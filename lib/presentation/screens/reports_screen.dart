import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/presentation/screens/his_webview_screen.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'dart:async';

/// Màn hình Báo cáo - mở Dashboard server (172.16.212.213:5173) trong WebView.
/// v2.97.0: Tự động load khi có VPN (kết nối server OK), báo cần VPN khi ngoài mạng
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// Dashboard URL
  static const String dashboardUrl = 'http://172.16.212.213:5173/';

  // v2.97.0: Connection state
  bool _checking = true;
  bool _connected = false;
  String _connectionInfo = '';
  Timer? _autoOpenTimer;
  final HisApiService _api = HisApiService.instance;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  @override
  void dispose() {
    _autoOpenTimer?.cancel();
    super.dispose();
  }

  /// v2.97.0: Check connection tới server Dashboard BV
  Future<void> _checkConnection() async {
    setState(() {
      _checking = true;
      _connectionInfo = 'Đang kiểm tra kết nối...';
    });

    final ok = await _api.testUrlReachable(dashboardUrl, timeout: const Duration(seconds: 5));
    if (!mounted) return;
    setState(() {
      _checking = false;
      _connected = ok;
      _connectionInfo = ok
          ? '✓ Kết nối server OK - có thể mở Dashboard'
          : '✗ Không kết nối được Dashboard server';
    });

    // v2.97.0: Auto-open Dashboard nếu connected
    if (ok) {
      _autoOpenTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted && _connected) {
          _openDashboard(showWarning: false);
        }
      });
    }
  }

  Future<void> _openDashboard({bool showWarning = true}) async {
    if (showWarning && !_connected) {
      // v2.97.0: Nếu chưa có kết nối, hiện cảnh báo
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.vpn_lock, color: Colors.amber, size: 26),
              SizedBox(width: 8),
              Text('Cảnh báo: cần bật VPN',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Trang báo cáo Dashboard nằm trong mạng LAN bệnh viện.\n\n'
            'Bạn cần bật OpenVPN Profile BV trước khi mở.\n\n'
            'Nếu chưa bật VPN, trang sẽ không tải được.',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('Mở báo cáo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HisWebviewScreen(
          patient: {},
          department: {'name': 'Báo cáo Dashboard', 'code': 'REPORT', 'icon': '📊'},
          customUrl: dashboardUrl,
          screenTitle: 'Báo cáo - Dashboard BV',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Quay lại Trang chủ',
          onPressed: () {
            if (Navigator.canPop(context)) {
              context.safePop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Báo cáo', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.bar_chart, size: 80, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text(
                'Báo cáo Dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dashboard thống kê, báo cáo hoạt động bệnh viện',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 24),

              // v2.97.0: Connection status card (auto-check)
              _buildConnectionCard(),

              const SizedBox(height: 16),

              // v2.97.0: Big button to open dashboard
              ElevatedButton.icon(
                onPressed: _checking ? null : () => _openDashboard(),
                icon: _checking
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.open_in_browser, size: 22),
                label: Text(
                  _checking
                      ? 'Đang kiểm tra kết nối...'
                      : (_connected ? 'Mở Dashboard (đã kết nối)' : 'Mở Dashboard (cần VPN)'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _connected ? Colors.green.shade700 : Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // v2.97.0: Nút test lại
              OutlinedButton.icon(
                onPressed: _checking ? null : _checkConnection,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Test lại kết nối'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                dashboardUrl,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black45, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // v2.97.0: Connection status card
  Widget _buildConnectionCard() {
    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String text;

    if (_checking) {
      bgColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade300;
      textColor = Colors.blue.shade900;
      icon = Icons.hourglass_top;
      text = 'Đang kiểm tra kết nối...';
    } else if (_connected) {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      textColor = Colors.green.shade900;
      icon = Icons.check_circle;
      text = 'Kết nối server OK - có thể mở Dashboard';
    } else {
      bgColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      textColor = Colors.red.shade900;
      icon = Icons.error;
      text = 'Không kết nối được Dashboard server';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          if (_checking)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: textColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
