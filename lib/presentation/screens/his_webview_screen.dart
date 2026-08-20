// HisWebviewScreen - "Bệnh án điện tử" như Y Tế Số.
// Wrap HIS Pro EMR web frontend (http://thongke.benhvienninhthuan.vn:8080/emr/...)
// trong WebView của app. BS không cần login lại vì cookie web cached.
// v3.0.96: Auto-fill credentials từ Credentials (XOR-encoded) - không có plaintext
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/core/security/credentials.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/local/clinical_notes_service.dart';
import 'package:his_mobile/presentation/widgets/patient_header.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HisWebviewScreen extends StatefulWidget {
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? department;

  /// URL tùy chỉnh cho tile cụ thể. Nếu null thì dùng URL mặc định từ
  /// SharedPreferences('his_web_url') hoặc fallback Data public.
  /// Ví dụ:
  ///   customUrl: 'http://thongke.benhvienninhthuan.vn:8080/emr/index'
  ///   customUrl: 'http://thongke.benhvienninhthuan.vn:8080/emr/index/search?treatment_code={code}'
  final String? customUrl;

  /// Tiêu đề hiển thị trên AppBar (mặc định 'Bệnh án điện tử').
  final String? screenTitle;

  const HisWebviewScreen({
    super.key,
    this.patient,
    this.department,
    this.customUrl,
    this.screenTitle,
  });

  @override
  State<HisWebviewScreen> createState() => _HisWebviewScreenState();
}

class _HisWebviewScreenState extends State<HisWebviewScreen> {
  late WebViewController _controller;
  bool _loading = true;
  String _error = '';
  String _currentUrl = '';
  String _webUrl = '';

  String _g(String k1, [String? k2, String? k3]) {
    final p = widget.patient;
    if (p == null) return '';
    return (p[k1] ?? p[k2 ?? ''] ?? p[k3 ?? ''] ?? '').toString();
  }

  String get _treatmentCode {
    final c = _g('TDL_TREATMENT_CODE', 'treatment_code');
    return c.isNotEmpty ? c : _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  }

  /// URL template bệnh án điện tử - BS có thể tuỳ chỉnh
  /// mặc định (list chung): /emr/index (Data public, không cần code)
  /// Chi tiết 1 BN: /emr/index/search?treatment_code={code} (Data public)
  /// VPN nội bộ: /emr/treatment-detail?code={code} (HIS Pro)
  String _buildWebUrl() {
    final base = _webUrl;
    if (base.isEmpty) return '';
    // Thay thế placeholder {code} bằng treatment_code
    return base.replaceAll('{code}', _treatmentCode).replaceAll('{patient_name}', _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME'));
  }

  Future<void> _loadConfigAndWebView() async {
    String newDefault;
    if (widget.customUrl != null && widget.customUrl!.isNotEmpty) {
      // Tile cụ thể truyền URL theo BN → ưu tiên
      _webUrl = widget.customUrl!;
    } else {
      final prefs = await SharedPreferences.getInstance();
      // v2.19.1: chuyển EMR từ HIS Pro VPN (172.16.9.6) → Data server (thongke public)
      // URL mặc định dùng /emr/index (không cần code) — đây là trang List EMR chung
      // ngoài BV (không cần VPN). Tile 'Xem bệnh án' tự động trỏ sang /emr/index/search
      // với treatment_code pre-fill.
      newDefault = 'http://thongke.benhvienninhthuan.vn:8080/emr/index';
      final saved = prefs.getString('his_web_url');
      // Migrate: URL cũ chứa 172.16.9.6 (HIS Pro VPN) hoặc /emr/treatment-detail (404) → đổi
      if (saved != null && saved.contains('thongke.benhvienninthuan.vn')) {
        await prefs.setString('his_web_url', newDefault);
        _webUrl = newDefault;
      } else {
        _webUrl = saved ?? newDefault;
      }
    }

    final url = _buildWebUrl();
    if (url.isEmpty) {
      setState(() {
        _error = 'Chưa cấu hình URL HIS Pro web';
        _loading = false;
      });
      return;
    }

    final user = _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME');
    setState(() => _currentUrl = url);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1565C0))
      ..setUserAgent('Mozilla/5.0 (HIS-Mobile/2.20.0) Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36')
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (p == 100) {
              setState(() {
                _loading = false;
                _error = '';
              });
            }
          },
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _loading = false;
              _currentUrl = url;
            });
            // v2.35.11: Auto-fill login form for thongke Laravel
            if (url.contains('thongke.benhvienninhthuan.vn:8080') &&
                (url.contains('/login') || url == 'http://thongke.benhvienninhthuan.vn:8080/login')) {
              await _autoLoginThongke();
            }
          },
          onWebResourceError: (err) {
            setState(() {
              _error = 'Lỗi: ${err.description ?? "không rõ"}';
              _loading = false;
            });
          },
          onHttpError: (err) {
            setState(() {
              _error = 'HTTP ${err.response?.statusCode ?? "?"} - URL không khả dụng';
              _loading = false;
            });
          },
          onNavigationRequest: (req) {
            debugPrint('🔗 WebView nav: ${req.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(url), headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml',
        'X-Patient': user,
        'X-Treatment-Code': _treatmentCode,
      });

    if (mounted) setState(() {});
  }

  /// v3.0.96: Auto-fill email/password từ Credentials (XOR-encoded) trên trang login Thongke Laravel
  /// rồi tự động submit form.
  Future<void> _autoLoginThongke() async {
    // Chờ form render xong (1.5s)
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final autoEmail = Credentials.thongkeDefaultEmail;
    final autoPass = Credentials.thongkeDefaultPassword;
    final js = '''
      (function() {
        // Tìm input email/username
        var emailInput = document.querySelector('input[name="email"]') ||
                         document.querySelector('input[type="email"]') ||
                         document.querySelector('input[name="username"]') ||
                         document.querySelector('input[id*="email" i]') ||
                         document.querySelector('input[id*="user" i]');
        // Tìm input password
        var passInput = document.querySelector('input[name="password"]') ||
                        document.querySelector('input[type="password"]');
        if (emailInput && passInput) {
          // Set value qua native setter (React/Vue có thể override)
          var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
          nativeInputValueSetter.call(emailInput, '$autoEmail');
          emailInput.dispatchEvent(new Event('input', { bubbles: true }));
          nativeInputValueSetter.call(passInput, '$autoPass');
          passInput.dispatchEvent(new Event('input', { bubbles: true }));
          // Submit form
          setTimeout(function() {
            var form = emailInput.closest('form') || passInput.closest('form');
            if (form) {
              form.submit();
            } else {
              // Fallback: tìm button submit
              var btn = document.querySelector('button[type="submit"]') ||
                        document.querySelector('input[type="submit"]') ||
                        document.querySelector('button.btn-primary');
              if (btn) btn.click();
            }
          }, 500);
          return 'OK - auto login submitted';
        }
        return 'NO FORM FOUND - retry in 1s';
      })();
    ''';
    try {
      final result = await _controller.runJavaScriptReturningResult(js);
      debugPrint('🔐 Auto-login result: $result');
      // Nếu chưa có form, thử lại sau 1s
      if (result.toString().contains('NO FORM FOUND')) {
        await Future.delayed(const Duration(milliseconds: 1000));
        if (!mounted) return;
        await _controller.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('❌ Auto-login error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadConfigAndWebView();
  }

  Future<void> _showUrlConfig() async {
    final ctrl = TextEditingController(text: _webUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cấu hình URL Web HIS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL pattern để load bệnh án điện tử.\nDùng {code} làm placeholder cho treatment code:',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'http://thongke.benhvienninhthuan.vn:8080/emr/index/search?treatment_code={code}',
              ),
            ),
            const SizedBox(height: 6),
            const Text('Preset:',
                style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 4, runSpacing: 4,
              children: [
                // v2.19: bỏ các preset HIS Pro VPN - giờ Data public là URL mặc định
                _presetChip('Data list EMR', 'http://thongke.benhvienninhthuan.vn:8080/emr/index'),
                _presetChip('Data search EMR', 'http://thongke.benhvienninhthuan.vn:8080/emr/index/search?treatment_code={code}'),
                _presetChip('HIS Pro detail', 'http://172.16.9.6/emr/treatment-detail?code={code}'),
                _presetChip('Data home', 'http://thongke.benhvienninhthuan.vn:8080/home'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('his_web_url', result);
      setState(() {
        _webUrl = result;
        _loading = true;
        _error = '';
      });
      _loadConfigAndWebView();
    }
  }

  Widget _presetChip(String label, String url) {
    return GestureDetector(
      onTap: () {
        // Pass URL up so host dialog can pick it up; or simply show snackbar.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Đã chọn preset: $url'),
          duration: const Duration(seconds: 2),
        ));
        setState(() => _webUrl = url);
        _loadConfigAndWebView();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.shade200),
        ),
        child: Text(label, style: TextStyle(color: Colors.indigo.shade700, fontSize: 10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: Text(widget.screenTitle ?? 'Bệnh án điện tử',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.settings), tooltip: 'Cấu hình URL', onPressed: _showUrlConfig),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: () {
              _loadConfigAndWebView();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(department: widget.department?['name']?.toString()),
          if (widget.patient != null && widget.department != null)
            PatientHeader(patient: widget.patient!, department: widget.department!, accent: const Color(0xFF1565C0)),
          // v2.35.11: Thanh compact - chỉ nút Load, không hiện URL
          Container(
            color: const Color(0xFFF0F4FF),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: _loading ? Colors.amber.shade700 : Colors.green.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_loading ? 'Đang tải...' : 'Sẵn sàng',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                // Nút Load (reload)
                TextButton.icon(
                  onPressed: () {
                    _loadConfigAndWebView();
                  },
                  icon: const Icon(Icons.refresh, size: 14, color: Colors.indigo),
                  label: const Text('Load', style: TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty)
            Container(
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error, style: TextStyle(color: Colors.red.shade900, fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: _showUrlConfig,
                    child: const Text('Đổi URL'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading && _error.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
