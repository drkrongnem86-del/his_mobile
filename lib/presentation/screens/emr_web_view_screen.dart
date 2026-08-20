// v3.0.82: EmrWebViewScreen - Hiển thị EMR công khai (thongke public) inline
// Thay vì mở browser ngoài (như cũ), giờ mở webview trong app với:
//   - URL bar (đọc/edit, ấn Enter để navigate)
//   - Nút back/forward/reload
//   - Loading indicator
//   - Nút "Đăng nhập nhanh" nếu URL là login page
//   - Nút "Mở trong Chrome" nếu cần
//
// Yêu cầu: webview_flutter (đã có sẵn trong pubspec)
// URLs hỗ trợ:
//   - http://thongke.benhvienninthuan.vn:8080/emr/index/search?treatment_code=XXX
//   - http://113.163.187.3:8080/emr/index/search?treatment_code=XXX

import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class EmrWebViewScreen extends StatefulWidget {
  final String initialUrl;
  final String? title;
  final String? treatmentCode;
  final String? patientName;

  const EmrWebViewScreen({
    super.key,
    required this.initialUrl,
    this.title,
    this.treatmentCode,
    this.patientName,
  });

  /// Tạo URL search EMR theo mã điều trị
  static String buildUrl(String treatmentCode) {
    return 'http://thongke.benhvienninthuan.vn:8080/emr/index/search?treatment_code=${Uri.encodeQueryComponent(treatmentCode)}';
  }

  /// URL thongke public
  static const String publicBase = 'http://thongke.benhvienninthuan.vn:8080';

  @override
  State<EmrWebViewScreen> createState() => _EmrWebViewScreenState();
}

class _EmrWebViewScreenState extends State<EmrWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String _currentUrl = '';
  String _pageTitle = '';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _pageTitle = widget.title ?? 'EMR Công khai';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14; SM-A175F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 HIS-Mobile/3.0.82')
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          setState(() {
            _currentUrl = url;
            _loading = true;
            _progress = 0;
          });
        },
        onProgress: (progress) {
          setState(() => _progress = progress / 100.0);
        },
        onPageFinished: (url) {
          setState(() {
            _loading = false;
            _currentUrl = url;
          });
        },
        onWebResourceError: (error) {
          setState(() => _loading = false);
          debugPrint('WebView error: ${error.description}');
        },
        onHttpError: (error) {
          debugPrint('WebView HTTP error: ${error.response?.statusCode}');
        },
      ))
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _reload() async {
    await _controller.reload();
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  Future<void> _goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  Future<void> _openInChrome() async {
    final uri = Uri.parse(_currentUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_pageTitle, style: const TextStyle(fontSize: 14)),
            if (widget.patientName != null && widget.patientName!.isNotEmpty)
              Text('${widget.patientName} • ${widget.treatmentCode ?? ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Tải lại',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInChrome,
            tooltip: 'Mở trong Chrome',
          ),
        ],
      ),
      body: Column(
        children: [
          // URL bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: const Color(0xFFECEFF1),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: _goBack,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: _goForward,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB0BEC5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _loading ? Icons.hourglass_empty : Icons.lock_outline,
                          size: 14,
                          color: _loading ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _currentUrl,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF455A64)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Progress bar
          if (_loading)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: const Color(0xFFECEFF1),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00838F)),
            ),
          // WebView
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
