// Icd10WebViewScreen v2.98.4
// - Tra cứu ICD-10 online qua web app Firebase hosting
// - URL: https://tracuu-icd10.web.app/ (ICD-10 2026 TT06/QĐ1849, PL1-PL5)
// - Cho phép BS tra cứu mã ICD khi offline / không có data local
// - Có nút "Copy mã ICD" để chép về phiếu khám
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Icd10WebViewScreen extends StatefulWidget {
  /// Callback khi user chọn mã ICD từ web (optional - nếu web hỗ trợ callback)
  final ValueChanged<String?>? onCodeSelected;

  /// Nếu true: cho phép paste mã ICD vào ô input rồi bấm "Dùng mã này" → trả về qua onCodeSelected
  final bool allowReturnCode;

  const Icd10WebViewScreen({
    super.key,
    this.onCodeSelected,
    this.allowReturnCode = true,
  });

  @override
  State<Icd10WebViewScreen> createState() => _Icd10WebViewScreenState();
}

class _Icd10WebViewScreenState extends State<Icd10WebViewScreen> {
  late final WebViewController _controller;
  final _codeCtrl = TextEditingController();
  bool _loading = true;
  String _currentUrl = 'https://tracuu-icd10.web.app/';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 HIS Mobile/2.98.4')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _loading = false;
              _currentUrl = url;
            });
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
            setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://tracuu-icd10.web.app/'));
  }

  @override
  void dispose() {
    // WebViewController không có dispose() method - framework tự quản lý
    _codeCtrl.dispose();
    super.dispose();
  }

  void _useCode() {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    HapticFeedback.mediumImpact();
    if (widget.onCodeSelected != null) {
      widget.onCodeSelected!(code);
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
        title: const Text('Tra cứu ICD-10', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: () {
              _controller.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Sao chép URL',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _currentUrl));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã sao chép URL'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner thông báo URL
          Container(
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.cloud_done, size: 14, color: Color(0xFF1976D2)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ICD-10 2026 TT06/QĐ1849 (PL1-PL5, thuốc PL3) - Cập nhật từ Bộ Y tế',
                    style: TextStyle(color: Colors.blue.shade900, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
              ],
            ),
          ),
          // Nếu cho phép nhập mã ICD thủ công
          if (widget.allowReturnCode)
            Container(
              color: Colors.amber.shade50,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Color(0xFFFF8F00), size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Gõ mã ICD (VD: S01, I10, J18, R50...)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _useCode,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Dùng', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          // WebView
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  Container(
                    color: Colors.white.withValues(alpha: 0.7),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
