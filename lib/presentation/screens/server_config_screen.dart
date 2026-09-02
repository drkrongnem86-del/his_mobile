// ServerConfigScreen v2.75.1
// Màn hình "Cài đặt Server" - giống app v0.3.0 (team BS)
// - 4 base URL riêng: ACS / MOS / SAR / SDA
// - Nút TEST ACS + RESET + LƯU & ĐÓNG
import 'package:flutter/material.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:http/http.dart' as http;

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  late TextEditingController _acsCtrl;
  late TextEditingController _mosCtrl;
  late TextEditingController _sarCtrl;
  late TextEditingController _sdaCtrl;

  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final c = HisConfigService.instance.config;
    _acsCtrl = TextEditingController(text: c.acsUrl);
    _mosCtrl = TextEditingController(text: c.mosUrl);
    _sarCtrl = TextEditingController(text: c.sarUrl);
    _sdaCtrl = TextEditingController(text: c.sdaUrl);
  }

  @override
  void dispose() {
    _acsCtrl.dispose();
    _mosCtrl.dispose();
    _sarCtrl.dispose();
    _sdaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = HisConfigService.instance.config.copyWith(
      acsUrl: _acsCtrl.text.trim(),
      mosUrl: _mosCtrl.text.trim(),
      sarUrl: _sarCtrl.text.trim(),
      sdaUrl: _sdaCtrl.text.trim(),
    );
    await HisConfigService.instance.save(c);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Đã lưu cấu hình Server'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pop(context, true);
    });
  }

  void _reset() {
    setState(() {
      _acsCtrl.text = 'http://172.16.9.6:1401';
      _mosCtrl.text = 'http://172.16.9.6:1408';
      _sarCtrl.text = 'http://172.16.9.6:1409';
      _sdaCtrl.text = 'http://172.16.9.6:1410';
    });
  }

  Future<void> _testAcs() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final url = _acsCtrl.text.trim();
    try {
      final r = await http
          .get(Uri.parse('${url}api/AcsToken/Authorize'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = 'ACS ${r.statusCode} ✅ (${r.body.length}B)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = 'ACS ❌ ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        title: const Text('Cài đặt Server', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Hộp thoại giải thích
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF1976D2)),
                      SizedBox(width: 8),
                      Text(
                        'Mỗi nhóm API dùng port riêng',
                        style: TextStyle(
                          color: Color(0xFF1976D2),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('• ACS (Auth): /api/AcsToken, /api/Timer',
                      style: TextStyle(fontSize: 13)),
                  Text('• MOS (Data): /api/His*, /api/EmrDocument',
                      style: TextStyle(fontSize: 13)),
                  Text('• SAR (Reports): /api/Sar*',
                      style: TextStyle(fontSize: 13)),
                  Text('• SDA (System): /api/Sda*',
                      style: TextStyle(fontSize: 13)),
                  SizedBox(height: 8),
                  Text(
                    'Mặc định: ACS=1401, MOS=1408, SAR=1409, SDA=1410',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4 ô input
            _urlField(label: 'ACS / Auth Base URL', controller: _acsCtrl, icon: Icons.security),
            const SizedBox(height: 12),
            _urlField(label: 'MOS / Data Base URL', controller: _mosCtrl, icon: Icons.storage),
            const SizedBox(height: 12),
            _urlField(label: 'SAR / Reports Base URL', controller: _sarCtrl, icon: Icons.bar_chart),
            const SizedBox(height: 12),
            _urlField(label: 'SDA / System Base URL', controller: _sdaCtrl, icon: Icons.settings),

            // Test result
            if (_testResult != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _testResult!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(height: 16),

            // TEST ACS + RESET
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testAcs,
                    icon: _testing
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_testing ? 'Testing...' : 'TEST ACS'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1976D2),
                      side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('RESET'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1976D2),
                      side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // LƯU & ĐÓNG
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('LƯU & ĐÓNG',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _urlField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1976D2)),
        border: const OutlineInputBorder(),
        fillColor: Colors.white,
        filled: true,
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
    );
  }
}
