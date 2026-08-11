#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
his_proxy_server.py - HIS Pro Proxy + Auto Token Fetcher
v3.0.82: Chạy trên PC BV, listen port 9999. Cung cấp:
  1. /get-his-token       - Đọc log HIS.exe, extract Bearer token từ DTI
  2. /get-his-token-status - Trả về {token, age_seconds, source_file, valid}
  3. /proxy/{path:.*}     - Forward HTTP request tới HIS Pro server (172.16.9.6:*)
                            + auto-inject Bearer token nếu thiếu
  4. /                    - Status page (HTML đơn giản)

Chạy:
  python his_proxy_server.py

Yêu cầu:
  - Python 3.6+ (stdlib only - không cần pip install)
  - HIS Pro install: D:\\Soft\\HISPRO_THAT\\
  - Cùng WiFi/LAN với phone
  - Port 9999 mở (hoặc đổi PORT = 9999)

Test:
  curl http://localhost:9999/get-his-token-status
"""

import http.server
import urllib.request
import urllib.parse
import urllib.error
import json
import re
import os
import sys
import time
import socket
import threading
from datetime import datetime

# ==================== CONFIG ====================
PORT = 9999
HIS_PROXY_HOST = "0.0.0.0"  # Listen trên tất cả interface
HIS_LOG_DIR = r"D:\Soft\HISPRO_THAT\Logs"
HIS_LOG_FILE = os.path.join(HIS_LOG_DIR, "LogSystem.txt")
HIS_HLS_LOG_FILE = os.path.join(HIS_LOG_DIR, "HLSLogSystem.txt")

# HIS Pro servers (LAN) - phone không tới được trực tiếp, cần proxy
HIS_LAN_HOSTS = {
    1401: "172.16.9.6",   # AcsBaseUri
    1408: "172.16.9.6",   # MosBaseUri (HIS Pro APIs - Get/GetLView/GetView)
    1409: "172.16.9.6",   # SarBaseUri
    1410: "172.16.9.6",   # SdaBaseUri
    1417: "172.16.9.6",   # EmrBaseUri (EmrDocument CreateByTdo/GetView)
    1429: "172.16.9.6",   # MosBaseUri (cũ - empty)
    1405: "172.16.9.6",   # FssBaseUri
}
DEFAULT_LAN_HOST = "172.16.9.6"

# Public thongke (phone tới được qua internet)
PUBLIC_HOSTS = {
    "thongke": "http://113.163.187.3:8080",
    "vpn_mos": "http://117.2.25.67:1429",
}

# Bearer token cache (in-memory, single source of truth)
_token_cache = {
    "token": None,
    "source": None,
    "found_at": None,
    "log_file": None,
}
_token_lock = threading.Lock()


# ==================== TOKEN EXTRACTION ====================

DTI_PATTERN = re.compile(
    rb'___dti:"([^"]+)"',
    re.MULTILINE
)
TOKEN_PATTERN = re.compile(r'^[a-f0-9]{64}$', re.IGNORECASE)


def extract_token_from_log(log_path):
    """Đọc file log HIS.exe, extract Bearer token từ DTI line mới nhất.

    Returns: (token, found_at_iso, log_size) hoặc (None, None, 0) nếu không tìm thấy
    """
    if not os.path.exists(log_path):
        return None, None, 0

    try:
        # Đọc 5MB cuối (HIS log có thể rất lớn)
        size = os.path.getsize(log_path)
        with open(log_path, 'rb') as f:
            if size > 5 * 1024 * 1024:
                f.seek(-5 * 1024 * 1024, os.SEEK_END)
                # Skip đến newline đầu tiên
                f.readline()
            data = f.read()

        # Tìm DTI line cuối cùng (mới nhất)
        matches = list(DTI_PATTERN.finditer(data))
        if not matches:
            return None, None, size

        last = matches[-1]
        dti_str = last.group(1).decode('utf-8', errors='replace').strip()

        # DTI format: URL1|URL2|URL3|TOKEN|USERNAME|FULLNAME|
        # Ví dụ: http://172.16.9.6:1401/|http://172.16.9.6:1417|http://172.16.9.6:1405/|d856...|nemk|K Rong Nểm|
        parts = dti_str.split('|')
        if len(parts) < 4:
            return None, None, size

        token_candidate = parts[3].strip()
        if not TOKEN_PATTERN.match(token_candidate):
            return None, None, size

        # Tìm thời gian của line này trong log (line ngay trước)
        line_start = last.start()
        # Tìm newline trước đó
        prev_nl = data.rfind(b'\n', 0, line_start)
        if prev_nl < 0:
            prev_nl = 0
        prev_line = data[prev_nl:line_start].decode('utf-8', errors='replace').strip()
        # Format: "DEBUG 2026-08-10 11:18:07,262 ..."
        time_match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', prev_line)
        found_at = time_match.group(1) if time_match else datetime.now().isoformat(timespec='seconds')

        return token_candidate, found_at, size

    except Exception as e:
        print(f'[ERROR] extract_token_from_log: {e}', file=sys.stderr)
        return None, None, 0


def get_fresh_token():
    """Lấy token mới từ log file, có cache trong 30s."""
    with _token_lock:
        now = time.time()
        # Cache 30s
        if _token_cache.get('token') and _token_cache.get('found_at_epoch', 0) > now - 30:
            return _token_cache['token'], _token_cache

        # Thử LogSystem.txt trước (HIS desktop log)
        token, found_at, size = extract_token_from_log(HIS_LOG_FILE)
        source = HIS_LOG_FILE

        # Nếu không có, thử HLSLogSystem.txt
        if not token and os.path.exists(HIS_HLS_LOG_FILE):
            token, found_at, size = extract_token_from_log(HIS_HLS_LOG_FILE)
            source = HIS_HLS_LOG_FILE

        if token:
            _token_cache.update({
                'token': token,
                'source': 'dti',
                'source_file': source,
                'found_at': found_at,
                'found_at_epoch': now,
                'log_size': size,
            })
        return token, _token_cache.copy()


# ==================== HTTP HANDLERS ====================

class Handler(http.server.BaseHTTPRequestHandler):
    """HTTP request handler cho proxy + token fetcher."""

    # Tắt log mặc định (verbose)
    def log_message(self, format, *args):
        sys.stderr.write(f"[{self.log_date_time_string()}] {self.address_string()} - {format % args}\n")
        sys.stderr.flush()

    def _send_json(self, code, data):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _send_json_ascii(self, code, data):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode('ascii', errors='replace')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, code, html):
        body = html.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == '/' or path == '/index.html':
            self._send_html(200, self._index_html())
            return

        if path == '/get-his-token':
            token, info = get_fresh_token()
            if token:
                self._send_json(200, {
                    'success': True,
                    'token': token,
                    'source': info.get('source'),
                    'source_file': info.get('source_file'),
                    'found_at': info.get('found_at'),
                    'log_size': info.get('log_size'),
                })
            else:
                self._send_json(404, {
                    'success': False,
                    'error': 'Không tìm thấy token trong log HIS.exe',
                    'hint': f'Hãy mở HIS Pro desktop và đăng nhập để tạo token. Log: {HIS_LOG_FILE}',
                })
            return

        if path == '/get-his-token-status':
            token, info = get_fresh_token()
            now = datetime.now().isoformat(timespec='seconds')
            if token and info.get('found_at'):
                try:
                    found = datetime.fromisoformat(info['found_at'])
                    age = int((datetime.now() - found).total_seconds())
                except Exception:
                    age = -1
            else:
                age = -1
            self._send_json(200, {
                'success': bool(token),
                'has_token': bool(token),
                'token_length': len(token) if token else 0,
                'token_preview': (token[:8] + '...' + token[-4:]) if token else None,
                'source': info.get('source'),
                'source_file': info.get('source_file'),
                'found_at': info.get('found_at'),
                'age_seconds': age,
                'now': now,
                'log_file_exists': os.path.exists(HIS_LOG_FILE),
                'log_file_size': os.path.getsize(HIS_LOG_FILE) if os.path.exists(HIS_LOG_FILE) else 0,
            })
            return

        if path == '/ping':
            self._send_json(200, {'pong': True, 'ts': time.time()})
            return

        if path.startswith('/proxy/'):
            # Forward to HIS Pro LAN server
            self._handle_proxy(path[len('/proxy/'):], parsed.query, None)
            return

        self._send_json(404, {'error': 'Not found', 'path': path})

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path.startswith('/proxy/'):
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length else b''
            self._handle_proxy(path[len('/proxy/'):], parsed.query, body)
            return

        self._send_json(404, {'error': 'POST not supported', 'path': path})

    def do_OPTIONS(self):
        # CORS preflight
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def _handle_proxy(self, sub_path, query, body):
        """Forward request tới HIS Pro LAN server, auto-inject Bearer token."""
        # Parse path: "{port}/{api_path}" hoặc "{api_path}" (default port 1408)
        if '/' in sub_path:
            port_str, api_path = sub_path.split('/', 1)
            try:
                port = int(port_str)
            except ValueError:
                port = 1408  # default
                api_path = sub_path
        else:
            port = 1408
            api_path = sub_path

        host = HIS_LAN_HOSTS.get(port, DEFAULT_LAN_HOST)
        url = f"http://{host}:{port}/{api_path}"
        if query:
            url += '?' + query

        # Build headers
        req_headers = dict(self.headers)
        # Auto-inject Bearer token
        if 'authorization' not in {k.lower() for k in req_headers}:
            token, _ = get_fresh_token()
            if token:
                req_headers['Authorization'] = f'Bearer {token}'

        # Forward request
        try:
            req = urllib.request.Request(url, data=body, headers=req_headers, method='POST' if body else 'GET')
            with urllib.request.urlopen(req, timeout=30) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ('transfer-encoding', 'connection', 'server'):
                        self.send_header(k, v)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Content-Type', e.headers.get('Content-Type', 'application/json'))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self._send_json(502, {'error': f'Proxy error: {e}', 'url': url})

    def _index_html(self):
        token, info = get_fresh_token()
        token_info = f'<p>Token: <code>{(token[:20] + "...") if token else "NOT FOUND"}</code></p>' if token else '<p style="color:red">No token found in log</p>'
        return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>HIS Proxy Server</title>
<style>
body {{ font-family: -apple-system, sans-serif; max-width: 800px; margin: 20px auto; padding: 20px; background: #f5f5f5; }}
h1 {{ color: #1565C0; }}
.card {{ background: white; padding: 16px; margin: 12px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
code {{ background: #ECEFF1; padding: 2px 6px; border-radius: 3px; font-family: monospace; }}
.endpoint {{ background: #E3F2FD; padding: 2px 6px; border-radius: 3px; font-family: monospace; color: #0D47A1; }}
a {{ color: #1565C0; text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
.ok {{ color: #2E7D32; font-weight: bold; }}
.err {{ color: #C62828; font-weight: bold; }}
</style></head><body>
<h1>HIS Pro Proxy Server</h1>
<p>Status: <span class="ok">RUNNING</span> on port {PORT}</p>
<p>PC IP: <code>{socket.gethostbyname(socket.gethostname())}</code></p>

<div class="card">
<h3>Token Status</h3>
{token_info}
<p>Source: <code>{info.get('source_file', 'N/A')}</code></p>
<p>Found at: <code>{info.get('found_at', 'N/A')}</code></p>
</div>

<div class="card">
<h3>Endpoints (goi tu app)</h3>
<p><span class="endpoint">GET /get-his-token</span> - Tra ve Bearer token moi nhat tu log HIS.exe</p>
<p><span class="endpoint">GET /get-his-token-status</span> - Tra ve thong tin token (age, source, length)</p>
<p><span class="endpoint">GET /ping</span> - Health check</p>
<p><span class="endpoint">GET /proxy/{{port}}/{{api_path}}</span> - Forward request toi HIS Pro LAN (auto-inject Bearer)</p>
<p><span class="endpoint">POST /proxy/{{port}}/{{api_path}}</span> - Forward POST request</p>
</div>

<div class="card">
<h3>HIS Pro LAN Servers (mac dinh)</h3>
<ul>
<li>1401: AcsBaseUri (auth)</li>
<li>1408: MosBaseUri (HisTreatment/GetLView, HisDepartmentTran/GetView, etc.)</li>
<li>1417: EmrBaseUri (EmrDocument/CreateByTdo, GetView)</li>
<li>1405: FssBaseUri (file upload)</li>
</ul>
</div>

<div class="card">
<h3>Cau hinh App (phone)</h3>
<p>URL: <code>http://{{PC_IP}}:{PORT}</code></p>
<p>App se tu goi <code>http://{{PC_IP}}:{PORT}/get-his-token</code> khi can token moi</p>
<p>Neu proxy khong reachable, app fallback ve paste token thu cong</p>
</div>

<p><small>v3.0.82 - Python {sys.version_info.major}.{sys.version_info.minor} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</small></p>
</body></html>"""


def main():
    # In config khi start
    print('=' * 60)
    print('[HIS] HIS Pro Proxy Server v3.0.82')
    print('=' * 60)
    print(f'Listen:  http://{HIS_PROXY_HOST}:{PORT}/')
    print(f'Log:     {HIS_LOG_FILE}')
    print(f'         exists={os.path.exists(HIS_LOG_FILE)}, size={os.path.getsize(HIS_LOG_FILE) if os.path.exists(HIS_LOG_FILE) else 0} bytes')
    print(f'PC IP:   {socket.gethostbyname(socket.gethostname())}')
    print('=' * 60)
    print('Endpoints:')
    print(f'  http://localhost:{PORT}/                          - Status page')
    print(f'  http://localhost:{PORT}/get-his-token            - Lay token moi')
    print(f'  http://localhost:{PORT}/get-his-token-status     - Trang thai token')
    print(f'  http://localhost:{PORT}/proxy/1408/api/HisTreatment/GetLView?...  - Proxy')
    print('=' * 60)
    print('Nhan Ctrl+C de dung.')
    print()

    # Warm up token cache
    token, _ = get_fresh_token()
    if token:
        print(f'[OK] Initial token loaded: {token[:12]}...{token[-4:]} (len={len(token)})')
    else:
        print(f'[!] Chua co token. Hay mo HIS Pro desktop va dang nhap de tao.')
    print()

    server = http.server.ThreadingHTTPServer((HIS_PROXY_HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopping...')
        server.shutdown()


if __name__ == '__main__':
    main()
