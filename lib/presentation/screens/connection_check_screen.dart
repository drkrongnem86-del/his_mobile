import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/presentation/navigation/safe_navigator.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';

class ConnectionCheckScreen extends StatefulWidget {
  const ConnectionCheckScreen({super.key});

  @override
  State<ConnectionCheckScreen> createState() => _ConnectionCheckScreenState();
}

class _ConnectionCheckScreenState extends State<ConnectionCheckScreen> {
  final HisApiService _api = HisApiService();
  bool _isTesting = false;
  bool? _connected;
  String _logText = '';

  @override
  void initState() {
    super.initState();
    _testConnection();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connected = null;
      _logText = '🔄 Đang kiểm tra...\nServer: ${ConnectionService.instance.acsUrl}\nVPN: ${AppConstants.vpnHost}:${AppConstants.vpnPort}\n---\n';
    });

    final result = await _api.testConnection();
    setState(() {
      _isTesting = false;
      _connected = result;
      if (result) {
        _logText += '✅ ACS server OK\n';
      } else {
        _logText += '❌ Không kết nối được\n📌 Bật VPN chưa?\n';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.safePop(),
          tooltip: 'Quay lại',
        ),
        title: const Text('Kiểm tra kết nối', style: TextStyle(fontSize: 15)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _testConnection),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hướng dẫn VPN
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.vpn_key, color: Colors.indigo[700]),
                      const SizedBox(width: 8),
                      const Text('Kết nối VPN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ]),
                    const Divider(),
                    _step('1', 'Mở OpenVPN Connect'),
                    _step('2', 'Chọn Profile'),
                    _step('3', 'Đăng nhập + Connect'),
                    _step('4', 'Đợi "Connected"'),
                    _step('5', 'Quay lại app thử lại'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Nút test
            ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isTesting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(_isTesting ? 'Đang kiểm tra...' : 'Test ngay', style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 8),
            // v2.37.0: Mở OpenVPN trực tiếp
            OutlinedButton.icon(
              onPressed: () => _openOpenVpn(),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.vpn_lock),
              label: const Text('Mở OpenVPN Connect', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 4),
            // Bật WiFi
            OutlinedButton.icon(
              onPressed: () => _openWifiSettings(),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.wifi),
              label: const Text('Bật/tắt WiFi', style: TextStyle(fontSize: 13)),
            ),

            const SizedBox(height: 16),

            // Kết quả
            if (_connected != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _connected! ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(_connected! ? Icons.check_circle : Icons.error, size: 32, color: _connected! ? Colors.green : Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_connected! ? '✅ Kết nối thành công!' : '❌ Không kết nối được server',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                              color: _connected! ? Colors.green.shade700 : Colors.red.shade700)),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Log
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              child: Text(_logText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.greenAccent)),
            ),

            const SizedBox(height: 24),

            // Back button cuối
            OutlinedButton.icon(
              onPressed: () => context.safePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Quay lại'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String n, String t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(color: Colors.indigo.shade100, shape: BoxShape.circle),
          child: Center(child: Text(n, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo.shade700))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  // v2.37.0: Mở OpenVPN Connect app
  Future<void> _openOpenVpn() async {
    final uri = Uri.parse('net.openvpn.openvpn://');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback: mở Play Store
      final store = Uri.parse('market://details?id=net.openvpn.openvpn');
      if (await canLaunchUrl(store)) {
        await launchUrl(store);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chưa cài OpenVPN Connect. Mở Play Store để tải.')),
          );
        }
      }
    }
  }

  // Mở cài đặt WiFi
  Future<void> _openWifiSettings() async {
    bool opened = false;
    // Thử nhiều intent scheme
    final candidates = [
      'android.settings.WIFI_SETTINGS',
      'android.settings.WIFI_IP_SETTINGS',
      'android.settings.SETTINGS',
      'package:com.android.settings',
    ];
    for (final scheme in candidates) {
      try {
        final uri = Uri.parse(scheme);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) {
          opened = true;
          break;
        }
      } catch (_) {}
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được cài đặt. Vuốt xuống thông báo + bấm WiFi')),
      );
    }
  }
}
