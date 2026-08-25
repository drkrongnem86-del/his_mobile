// VpnBenhVienScreen v3.0.93 - Native OpenVPN client (ics-openvpn)
// Quáº£n lÃ½: Connect/Disconnect, Account input (default áº©n pass), Auto-disconnect 5p khi background
// v3.0.93:
//   - TÃ i khoáº£n máº·c Ä‘á»‹nh: áº©n password (khÃ´ng cho xem, khÃ´ng edit)
//   - Má»¥c "TÃ i khoáº£n khÃ¡c" riÃªng Ä‘á»ƒ nháº­p user + pass
//   - Bá» dÃ²ng "Máº·c Ä‘á»‹nh: ..." (lá»™ pass)
//   - ThÃ´ng tin káº¿t ná»‘i gá»n láº¡i
//   - Auto-disconnect 5 phÃºt khi thoÃ¡t/thu gá»n app
// v3.0.96: Comment sáº¡ch - khÃ´ng lá»™ username/password
//   - WidgetsBindingObserver Ä‘á»ƒ track app lifecycle
import 'package:flutter/material.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';

import 'package:his_mobile/core/security/credentials.dart';
class VpnBenhVienScreen extends StatefulWidget {
  const VpnBenhVienScreen({super.key});

  @override
  State<VpnBenhVienScreen> createState() => _VpnBenhVienScreenState();
}

class _VpnBenhVienScreenState extends State<VpnBenhVienScreen>
    with WidgetsBindingObserver {
  final _otherUserCtrl = TextEditingController();
  final _otherPassCtrl = TextEditingController();
  bool _showOtherPass = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    VpnBenhVienService.instance.addListener(_onVpnChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    VpnBenhVienService.instance.removeListener(_onVpnChanged);
    WidgetsBinding.instance.removeObserver(this);
    _otherUserCtrl.dispose();
    _otherPassCtrl.dispose();
    super.dispose();
  }

  // v3.0.93: App lifecycle - auto-disconnect khi background quÃ¡ 5 phÃºt
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vpn = VpnBenhVienService.instance;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      vpn.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      vpn.onAppResumed();
    }
  }

  void _onVpnChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInitial() async {
    await VpnBenhVienService.instance.init();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _connect() async {
    if (_busy) return;
    final vpn = VpnBenhVienService.instance;
    // Náº¿u Ä‘ang dÃ¹ng "TÃ i khoáº£n khÃ¡c" â†’ set credentials trÆ°á»›c
    if (!vpn.isUsingDefaultAccount) {
      final user = _otherUserCtrl.text.trim();
      final pass = _otherPassCtrl.text;
      if (user.isEmpty || pass.isEmpty) {
        _snack('Nháº­p tÃ i khoáº£n + máº­t kháº©u', ok: false);
        return;
      }
      await vpn.setCredentials(user, pass);
    } else {
      // Reset vá» default náº¿u cached credentials khÃ¡c default
      // (an toÃ n: náº¿u user Ä‘Ã£ thá»­ setCredentials vá»›i user khÃ¡c)
      // Cá»: náº¿u currentUser lÃ  rá»—ng (do toggleAccount setCredentials('', ''))
      if (vpn.currentUser.isEmpty) {
        await vpn.resetToDefault();
      }
    }
    setState(() => _busy = true);
    final ok = await vpn.connect();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _snack('ðŸ” Äang yÃªu cáº§u káº¿t ná»‘i VPN...');
    } else {
      _snack('âŒ ${vpn.lastError ?? "Lá»—i khÃ´ng xÃ¡c Ä‘á»‹nh"}', ok: false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    VpnBenhVienService.instance.disconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('âš ï¸ ÄÃ£ ngáº¯t káº¿t ná»‘i VPN');
  }

  void _snack(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.blue : Colors.red,
        duration: Duration(seconds: ok ? 2 : 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = VpnBenhVienService.instance;
    final remaining = vpn.remainingAutoDisconnectSeconds;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.vpn_lock, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('VPN Bá»‡nh viá»‡n', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner auto-disconnect (náº¿u Ä‘ang Ä‘áº¿m)
            if (remaining != null) _buildAutoDisconnectBanner(remaining),
            if (remaining != null) const SizedBox(height: 12),

            // Status Card
            _buildStatusCard(vpn),
            const SizedBox(height: 16),
            // Account form
            _buildAccountForm(vpn),
            const SizedBox(height: 16),
            // Action buttons
            _buildActionButtons(vpn),
            const SizedBox(height: 16),
            // Config info (gá»n)
            _buildConfigInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoDisconnectBanner(int remainingSeconds) {
    final mins = (remainingSeconds ~/ 60).toString().padLeft(1, '0');
    final secs = (remainingSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE0B2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF6F00)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Color(0xFFE65100), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'â³ Sáº½ tá»± ngáº¯t VPN sau khi thoÃ¡t app',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE65100)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Má»Ÿ láº¡i app trong $mins:$secs Ä‘á»ƒ há»§y',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6D4C41)),
                ),
              ],
            ),
          ),
        ],
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
      statusText = 'ÄÃ£ káº¿t ná»‘i VPN';
    } else if (vpn.isConnecting) {
      color = Colors.orange;
      icon = Icons.sync;
      statusText = 'Äang káº¿t ná»‘i...';
    } else if (vpn.isError) {
      color = Colors.red;
      icon = Icons.error_outline;
      statusText = 'Lá»—i VPN';
    } else {
      color = Colors.grey;
      icon = Icons.vpn_lock_outlined;
      statusText = 'ChÆ°a káº¿t ná»‘i';
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
                  Text('Tráº¡ng thÃ¡i VPN',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(statusText,
                    style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (vpn.isConnected)
                    const Text('Tá»›i 113.176.81.193:8443 (qua internet)',
                      style: TextStyle(color: Colors.black54, fontSize: 11)),
                  if (vpn.lastError != null && vpn.isError)
                    Text('Lá»—i: ${vpn.lastError}',
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

  /// v3.0.93: Form tÃ i khoáº£n
  /// - Náº¿u dÃ¹ng default nemk: hiá»ƒn thá»‹ username, áº©n password (khÃ´ng cho xem)
  /// - Náº¿u dÃ¹ng "TÃ i khoáº£n khÃ¡c": hiá»ƒn thá»‹ form riÃªng Ä‘á»ƒ nháº­p
  Widget _buildAccountForm(VpnBenhVienService vpn) {
    final isDefault = vpn.isUsingDefaultAccount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_circle, size: 18, color: Color(0xFF0D47A1)),
                SizedBox(width: 6),
                Text('TÃ i khoáº£n VPN',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (isDefault) _buildDefaultAccountRow() else _buildOtherAccountRow(),
            const SizedBox(height: 6),
            TextButton.icon(
              icon: Icon(
                isDefault ? Icons.person_add : Icons.refresh,
                size: 16,
              ),
              label: Text(isDefault ? 'DÃ¹ng tÃ i khoáº£n khÃ¡c' : 'Quay láº¡i tÃ i khoáº£n máº·c Ä‘á»‹nh'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0D47A1),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () => _toggleAccount(vpn),
            ),
          ],
        ),
      ),
    );
  }

  /// Row tÃ i khoáº£n máº·c Ä‘á»‹nh: hiá»‡n username, áº©n password hoÃ n toÃ n
  Widget _buildDefaultAccountRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Color(0xFF0D47A1), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(Credentials.defaultNemkLogin,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                Text('TÃ i khoáº£n BS máº·c Ä‘á»‹nh (pass Ä‘Ã£ lÆ°u sáºµn)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Máº·c Ä‘á»‹nh',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Form nháº­p tÃ i khoáº£n khÃ¡c
  Widget _buildOtherAccountRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _otherUserCtrl,
          decoration: const InputDecoration(
            labelText: 'TÃªn Ä‘Äƒng nháº­p',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _otherPassCtrl,
          obscureText: !_showOtherPass,
          decoration: InputDecoration(
            labelText: 'Máº­t kháº©u',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_showOtherPass ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showOtherPass = !_showOtherPass),
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _toggleAccount(VpnBenhVienService vpn) async {
    final wantOther = vpn.isUsingDefaultAccount;
    if (wantOther) {
      // Chuyá»ƒn sang "TÃ i khoáº£n khÃ¡c"
      setState(() {
        _otherUserCtrl.text = '';
        _otherPassCtrl.text = '';
        _showOtherPass = false;
      });
      // ÄÃ¡nh dáº¥u: báº±ng cÃ¡ch lÆ°u user rá»—ng
      await vpn.setCredentials('', '');
    } else {
      // Quay láº¡i default
      await vpn.resetToDefault();
      _otherUserCtrl.clear();
      _otherPassCtrl.clear();
    }
    if (mounted) setState(() {});
  }

  Widget _buildActionButtons(VpnBenhVienService vpn) {
    final isOn = vpn.isConnected || vpn.isConnecting;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (_busy || isOn) ? null : _connect,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('Káº¾T Ná»I'),
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
            label: const Text('NGáº®T'),
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

  /// v3.0.93: ThÃ´ng tin káº¿t ná»‘i gá»n
  Widget _buildConfigInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline, color: Color(0xFF0D47A1), size: 18),
                SizedBox(width: 6),
                Text('ThÃ´ng tin káº¿t ná»‘i',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'â€¢ VPN tá»›i mÃ¡y chá»§ BV Ninh Thuáº­n (qua internet)\n'
              'â€¢ Sau khi káº¿t ná»‘i: truy cáº­p HIS Pro 172.16.9.6 ná»™i bá»™\n'
              'â€¢ Auto-disconnect 5 phÃºt khi thoÃ¡t/thu gá»n app\n'
              'â€¢ TÃ­ch há»£p sáºµn (openvpn_flutter), khÃ´ng cáº§n OpenVPN Connect',
              style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
