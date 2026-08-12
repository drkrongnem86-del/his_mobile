// EmrScanAppConfigScreen v3.0.93 - Cấu hình EmrScanApp Windows service
//
// Chức năng:
//   - Sửa URL service EmrScanApp (vd: http://172.16.200.109:18080)
//   - Ping /health để check service có chạy không
//   - GET /token để lấy token về dùng
//   - GET /login?user=X&pass=Y để force re-login
//   - Hiển thị token age + expire time
//
// Workflow:
//   1. User chạy EmrScanApp Windows service trên PC BV (port 18080)
//   2. Mở app HIS Mobile → Settings → EmrScanApp Token Service
//   3. Nhập IP PC BV (vd: 172.16.200.109) + port 18080
//   4. Bấm "Test kết nối" → ping /health
//   5. Bấm "Lấy token" → lưu vào ThongkeAuthService
//   6. Từ giờ mỗi lần vào Lịch sử điều trị có thể bấm nút 1 chạm ở header
//
// Khác HIS Proxy (port 9999, đọc log file):
//   - EmrScanApp gọi HISLoginTool.exe chuẩn HIS → auto refresh mỗi 5 phút
//   - HIS Proxy chỉ đọc log → có thể miss khi HIS restart

import 'package:flutter/material.dart';
import 'package:his_mobile/data/services/emr_scan_token_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';

class EmrScanConfigScreen extends StatefulWidget {
  const EmrScanConfigScreen({super.key});

  @override
  State<EmrScanConfigScreen> createState() => _EmrScanConfigScreenState();
}

class _EmrScanConfigScreenState extends State<EmrScanConfigScreen> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'nemk');
  final _passCtrl = TextEditingController(text: '1027');
  bool _showPass = false;
  bool _busy = false;
  EmrScanTokenInfo? _info; // last /health result
  DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final url = await EmrScanTokenService.instance.getServiceUrl();
    final last = await EmrScanTokenService.instance.getLastFetchTime();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = url;
      _lastFetch = last;
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      _snack('URL không hợp lệ (phải bắt đầu bằng http://)', ok: false);
      return;
    }
    await EmrScanTokenService.instance.setServiceUrl(url);
    _snack('✅ Đã lưu URL: $url');
  }

  Future<void> _ping() async {
    if (_busy) return;
    setState(() => _busy = true);
    final info = await EmrScanTokenService.instance.ping();
    if (!mounted) return;
    setState(() {
      _info = info;
      _busy = false;
    });
    if (info.reachable && info.hasToken) {
      _snack('✅ Service hoạt động, có token sẵn');
    } else if (info.reachable) {
      _snack('⚠️ Service hoạt động nhưng CHƯA có token. Cần /login?user=X&pass=Y');
    } else {
      _snack('❌ Không kết nối được: ${info.error}', ok: false);
    }
  }

  Future<void> _fetchToken() async {
    if (_busy) return;
    setState(() => _busy = true);
    final info = await EmrScanTokenService.instance.fetchAndSaveToken();
    if (!mounted) return;
    setState(() {
      _info = info;
      _busy = false;
      _lastFetch = DateTime.now();
    });
    if (!info.reachable) {
      _snack('❌ ${info.error}', ok: false);
      return;
    }
    if (!info.hasToken) {
      _snack('⚠️ Service không có token. Bấm "Force login" để login lại.', ok: false);
      return;
    }
    final userInfo = info.userName ?? info.user ?? '?';
    _snack('✅ Đã lấy token ($userInfo, ${info.token!.length} ký tự)');
  }

  Future<void> _forceLogin() async {
    if (_busy) return;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _snack('Nhập user + password', ok: false);
      return;
    }
    setState(() => _busy = true);
    final info = await EmrScanTokenService.instance.forceLogin(
      username: user,
      password: pass,
    );
    if (!mounted) return;
    setState(() {
      _info = info;
      _busy = false;
      _lastFetch = DateTime.now();
    });
    if (!info.reachable || !info.hasToken) {
      _snack('❌ Force login fail: ${info.error}', ok: false);
      return;
    }
    _snack('✅ Force login OK, đã lưu token mới');
  }

  void _snack(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
        duration: Duration(seconds: ok ? 2 : 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
        title: const Text('EmrScanApp Token Service', style: TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // === GIỚI THIỆU ===
          Card(
            color: const Color(0xFFE0F7FA),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFF00838F), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(children: [
                    Icon(Icons.satellite_alt, color: Color(0xFF00838F), size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Tự động lấy HIS Pro token từ EmrScanApp',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF006064), fontSize: 13),
                    ),
                  ]),
                  SizedBox(height: 6),
                  Text(
                    'EmrScanApp là Windows service chạy trên máy BV, tự động login + refresh HIS Pro token mỗi 5 phút.\n'
                    'HIS Mobile kết nối tới service này để lấy token về dùng, không cần paste thủ công nữa.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF006064), height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // === CẤU HÌNH URL ===
          _section('CẤU HÌNH SERVICE'),
          Card(
            color: Colors.white,
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('URL Service (Windows service port 18080):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'http://172.16.200.109:18080',
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _saveUrl,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Lưu URL'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _ping,
                        icon: const Icon(Icons.network_check, size: 16),
                        label: const Text('Test kết nối'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00838F),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // === URL gợi ý ===
          Card(
            color: const Color(0xFFFAFAFA),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡 URL gợi ý (bấm để điền):',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 4),
                  ...EmrScanTokenService.defaultServiceUrls.map(
                    (u) => InkWell(
                      onTap: () => setState(() => _urlCtrl.text = u),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          u,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF1565C0)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // === LẤY TOKEN ===
          _section('LẤY TOKEN'),
          Card(
            color: Colors.white,
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nút lấy token
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _fetchToken,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Lấy token từ service'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Hoặc force re-login (nếu service chưa có token):',
                      style: TextStyle(fontSize: 11, color: Colors.black54)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passCtrl,
                    obscureText: !_showPass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _forceLogin,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Force login qua service'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00838F),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // === TRẠNG THÁI ===
          _section('TRẠNG THÁI'),
          _buildStatusCard(),
          const SizedBox(height: 12),

          // === HƯỚNG DẪN ===
          _section('HƯỚNG DẪN CÀI ĐẶT SERVICE'),
          Card(
            color: const Color(0xFFFFF8E1),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFFFB300)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('1️⃣ Build HISLoginTool.exe trên máy BV (Windows):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('   cd his-login-tool\n   build.bat',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87)),
                  SizedBox(height: 8),
                  Text('2️⃣ Chạy Python service (auto-refresh token mỗi 5 phút):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('   cd windows-service\n   python his_token_service.py',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87)),
                  SizedBox(height: 8),
                  Text('3️⃣ Hoặc cài auto-start khi Windows boot:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('   install.bat',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87)),
                  SizedBox(height: 8),
                  Text('4️⃣ Mở port 18080 trong Windows Firewall',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('   Service listen 0.0.0.0:18080',
                      style: TextStyle(fontSize: 11, color: Colors.black87)),
                  SizedBox(height: 8),
                  Text('5️⃣ Trên app, nhập IP máy BV + bấm "Lấy token"',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('   Ví dụ: http://172.16.200.109:18080',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        title,
        style: const TextStyle(color: Color(0xFF00838F), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildStatusCard() {
    final info = _info;
    final token = ThongkeAuthService.instance.hisProToken;
    return Card(
      color: Colors.white,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: info == null
              ? const Color(0xFFE0E0E0)
              : (info.reachable && info.hasToken
                  ? const Color(0xFF66BB6A)
                  : const Color(0xFFEF5350)),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trạng thái service
            Row(children: [
              Icon(
                info == null
                    ? Icons.help_outline
                    : (info.reachable
                        ? (info.hasToken ? Icons.check_circle : Icons.warning_amber)
                        : Icons.error),
                color: info == null
                    ? Colors.grey
                    : (info.reachable && info.hasToken
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828)),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info == null
                      ? 'Chưa test kết nối. Bấm "Test kết nối" ở trên.'
                      : (info.reachable
                          ? (info.hasToken
                              ? 'Service OK — có token sẵn'
                              : 'Service OK — CHƯA có token (cần /login)')
                          : 'Không kết nối được service'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (info != null) ...[
              _kv('URL', info.pcUrl ?? '—'),
              if (info.user != null) _kv('User', info.user!),
              if (info.userName != null) _kv('Tên', info.userName!),
              if (info.expireTime != null) _kv('Hết hạn', info.expireTime!),
              if (info.lastRefresh != null) _kv('Refresh lần cuối', info.lastRefresh!),
              if (info.expiresInSeconds != null) _kv('Còn lại', _formatRemaining(info.expiresInSeconds!)),
              if (info.error != null)
                _kv('Lỗi', info.error!, isError: true),
            ],
            if (_lastFetch != null)
              _kv('Lưu local lúc', _formatDateTime(_lastFetch!)),
            const Divider(height: 16),
            // Current token trong app
            Row(children: [
              const Icon(Icons.vpn_key, size: 16, color: Color(0xFF1565C0)),
              const SizedBox(width: 4),
              Text(
                token == null
                    ? 'App: chưa có token'
                    : 'App: có token (${token.length} ký tự)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: token == null ? Colors.grey : const Color(0xFF2E7D32),
                ),
              ),
            ]),
            if (token != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Source: ${_getSourceDisplay()}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF455A64)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isError ? const Color(0xFFC62828) : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRemaining(int seconds) {
    if (seconds <= 0) return 'Đã hết hạn';
    if (seconds < 60) return '$seconds giây';
    if (seconds < 3600) return '${(seconds / 60).floor()} phút';
    if (seconds < 86400) return '${(seconds / 3600).floor()} giờ ${((seconds % 3600) / 60).floor()} phút';
    return '${(seconds / 86400).floor()} ngày';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} ${dt.day}/${dt.month}/${dt.year}';
  }

  Future<String> _getSourceDisplay() async {
    final src = await ThongkeAuthService.instance.getTokenSource();
    final txt = await ThongkeAuthService.instance.getTokenSourceText();
    final icon = await ThongkeAuthService.instance.getTokenSourceIcon();
    return '$icon $txt ($src)';
  }
}
