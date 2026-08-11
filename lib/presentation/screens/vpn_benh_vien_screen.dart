// VpnBenhVienScreen v3.0.76 - Native OpenVPN client (ics-openvpn)
// Quản lý: Connect/Disconnect, Account input, Status thật từ openvpn_flutter
// Mặc định: nemk / Cnttbvnt@321 (password mask kiểu ***** trên UI)
import 'package:flutter/material.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';

class VpnBenhVienScreen extends StatefulWidget {
  const VpnBenhVienScreen({super.key});

  @override
  State<VpnBenhVienScreen> createState() => _VpnBenhVienScreenState();
}

class _VpnBenhVienScreenState extends State<VpnBenhVienScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    VpnBenhVienService.instance.addListener(_onVpnChanged);
  }

  @override
  void dispose() {
    VpnBenhVienService.instance.removeListener(_onVpnChanged);
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _onVpnChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInitial() async {
    await VpnBenhVienService.instance.init();
    final vpn = VpnBenhVienService.instance;
    _userCtrl.text = vpn.currentUser;
    _passCtrl.text = vpn.currentPass;
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() => _busy = true);
    final vpn = VpnBenhVienService.instance;
    // Lưu credentials trước (nếu user đổi)
    await vpn.setCredentials(_userCtrl.text.trim(), _passCtrl.text);
    final ok = await vpn.connect();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔐 Đang yêu cầu kết nối VPN...'),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = vpn.lastError ?? 'Lỗi không xác định';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $err'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    VpnBenhVienService.instance.disconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Đã ngắt kết nối VPN'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = VpnBenhVienService.instance;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.vpn_lock, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('VPN Bệnh viện', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card - real status
            _buildStatusCard(vpn),
            const SizedBox(height: 16),
            // Account form - default nemk + masked password
            _buildAccountForm(),
            const SizedBox(height: 16),
            // Action buttons
            _buildActionButtons(vpn),
            const SizedBox(height: 16),
            // Info card
            _buildConfigInfo(vpn),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(VpnBenhVienService vpn) {
    Color color;
    IconData icon;
    String statusText;
    if (vpn.isConnected) {
      color = Colors.green;
      icon = Icons.verified;
      statusText = 'Đã kết nối VPN';
    } else if (vpn.isConnecting) {
      color = Colors.orange;
      icon = Icons.sync;
      statusText = 'Đang kết nối...';
    } else if (vpn.isError) {
      color = Colors.red;
      icon = Icons.error_outline;
      statusText = 'Lỗi VPN';
    } else {
      color = Colors.grey;
      icon = Icons.vpn_lock_outlined;
      statusText = 'Chưa kết nối';
    }

    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trạng thái VPN',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(statusText,
                    style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (vpn.isConnected)
                    const Text('Tới 113.176.81.193:8443 (qua internet)',
                      style: TextStyle(color: Colors.black54, fontSize: 11)),
                  if (vpn.lastError != null && vpn.isError)
                    Text('Lỗi: ${vpn.lastError}',
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (vpn.isConnecting)
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.account_circle, size: 18, color: Color(0xFF0D47A1)),
                SizedBox(width: 6),
                Text('Tài khoản VPN',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(
                labelText: 'Tên đăng nhập',
                hintText: 'nemk',
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                hintText: '•••••••••••',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Mặc định: nemk / Cnttbvnt@321 (có thể đổi cho user khác)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(VpnBenhVienService vpn) {
    final isOn = vpn.isConnected || vpn.isConnecting;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (_busy || isOn) ? null : _connect,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('KẾT NỐI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (_busy || !vpn.isConnected) ? null : _disconnect,
            icon: const Icon(Icons.power_off),
            label: const Text('NGẮT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigInfo(VpnBenhVienService vpn) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thông tin kết nối',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _infoRow('Engine', 'openvpn_flutter 1.3.4 (ics-openvpn)'),
            _infoRow('Config', 'sslvpn-nemk-client-config.ovpn'),
            _infoRow('Server', '113.176.81.193:8443 (TCP)'),
            _infoRow('Account mặc định', 'nemk'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF0D47A1)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'v3.0.76: VPN đã được tích hợp sẵn trong app, không cần OpenVPN Connect bên ngoài. Khi kết nối, hệ thống sẽ hiện 1 popup xin quyền VPN (chỉ hiện lần đầu).',
                      style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$label:',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
