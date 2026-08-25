import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/app_version_service.dart';
import 'package:his_mobile/core/services/api_debug_service.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/core/services/department_service.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:his_mobile/core/services/update_service.dart';
import 'package:his_mobile/core/theme/theme_manager.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/services/token_sync_service.dart';  // v3.0.165: Token sync hub
import 'package:his_mobile/data/api/emr_push_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/mock_emr_server.dart';
import 'package:his_mobile/presentation/screens/log_viewer_screen.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';
import 'package:his_mobile/presentation/screens/his_config_screen.dart';
import 'package:his_mobile/presentation/screens/vpn_benh_vien_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:his_mobile/core/security/credentials.dart';
/// MÃ n hÃ¬nh CÃ i Ä‘áº·t v2.66.0
/// - ThÃ´ng tin tÃ i khoáº£n
/// - Äá»•i máº­t kháº©u
/// - Chá»n theme sÃ¡ng/tá»‘i
/// - Cáº­p nháº­t thÃ´ng tin á»©ng dá»¥ng + kiá»ƒm tra cáº­p nháº­t
/// - ÄÄƒng xuáº¥t
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _apiUrl = '';
  String _tokenCode = '';
  String _tokenClientIp = '';
  DateTime? _tokenUpdated;

  // v2.48.0: Bá» UI nháº­p tay - chá»‰ theo dÃµi tráº¡ng thÃ¡i tá»± Ä‘á»™ng
  // (Ä‘Ã£ xÃ³a _hisProLoginName, _hisProBearerToken, _hisProTokenVisible, ...)

  // v2.37.1: Theme mode via ThemeManager singleton
  ThemeMode get _themeMode => ThemeManager.instance.current;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final data = DataService.instance;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('his_pro_token_code') ?? '';
    final clientIp = prefs.getString('his_pro_client_ip') ?? '';
    final updatedMs = prefs.getInt('his_pro_token_updated');
    setState(() {
      _apiUrl = data.baseUrl;
      _tokenCode = token;
      _tokenClientIp = clientIp;
      _tokenUpdated = updatedMs != null ? DateTime.fromMillisecondsSinceEpoch(updatedMs) : null;
    });
  }

  String get _tokenMasked {
    if (_tokenCode.isEmpty) return 'â€” chÆ°a Ä‘áº·t â€”';
    if (_tokenCode.length < 16) return _tokenCode;
    return '${_tokenCode.substring(0, 8)}â€¦${_tokenCode.substring(_tokenCode.length - 8)}';
  }

  String get _tokenStatusLabel {
    if (_tokenCode.isEmpty) return 'âš ï¸ ChÆ°a cÃ³ token';
    return 'âœ… Token Ä‘Ã£ Ä‘áº·t';
  }

  // v2.66.0: Láº¥y version tá»« AppVersionService (Ä‘á»c tá»« package_info_plus)
  String get _version => AppVersionService.instance.displayVersion;
  String get _fullVersion => AppVersionService.instance.displayFull;
  String get _buildNumber => AppVersionService.instance.buildNumber;

  Future<void> _setTheme(ThemeMode mode) async {
    await ThemeManager.instance.set(mode);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ÄÃ£ Ä‘á»•i theme.'),
        duration: Duration(seconds: 1),
      ));
    }
  }

  // v2.47.0: HIS Pro login section (tá»± láº¥y token tá»« AcsToken/Authorize)
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.black54))),
            Expanded(
              child: Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  /// v2.48.0: Bá» UI nháº­p tay - chá»‰ hiá»‡n tráº¡ng thÃ¡i auto-sync
  /// App tá»± gá»i AcsToken/Authorize + auto-load má»i thá»© khi má»Ÿ
  /// v2.51.0: ÄÆ¡n giáº£n hÃ³a - 1 Ã´ paste token + 1 nÃºt test
  /// App tá»± Ä‘á»™ng load token tá»« file (náº¿u cÃ³), chá»‰ paste khi cáº§n


  /// v3.0.165: Auto-update token tá»« multi-source (proxy â†’ login API â†’ renew â†’ hardcoded)
  /// Hiá»ƒn thá»‹ dialog loading + káº¿t quáº£
  Future<void> _autoUpdateToken() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('Äang tá»± láº¥y token...', style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
    try {
      final event = await TokenSyncService.instance.autoFetchToken(force: true);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close loading
      if (!mounted) return;
      if (event.token != null) {
        // ThÃ nh cÃ´ng
        await _loadInfo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('âœ… ÄÃ£ tá»± láº¥y token má»›i tá»«: ${event.source}')),
              ]),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Lá»—i
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.error, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('âŒ KhÃ´ng láº¥y Ä‘Æ°á»£c token: ${event.message ?? "khÃ´ng rÃµ"}')),
              ]),
              backgroundColor: const Color(0xFFD32F2F),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('âŒ Lá»—i: $e'), backgroundColor: const Color(0xFFD32F2F)),
        );
      }
    }
  }

  /// v2.51.0: Dialog paste token Ä‘Æ¡n giáº£n - 1 láº§n duy nháº¥t
  Future<void> _showTokenDialog() async {
    final thongke = ThongkeAuthService.instance;
    final ctrl = TextEditingController(text: thongke.hisProToken ?? '');
    bool obscure = true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Token HIS Pro (EMR)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DÃ¡n token 64-char hex tá»« HIS Pro desktop log:',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                const Text('D:\\Nem\\HISPRO_THAT\\Logs\\LogSystem.txt',
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.black54)),
                const SizedBox(height: 4),
                const Text('TÃ¬m "TokenCode|" â†’ copy 64 kÃ½ tá»± hex',
                    style: TextStyle(fontSize: 10, color: Colors.black54)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  obscureText: obscure,
                  maxLines: 3,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '14fdd85760f797f02c0a80b4ce1a463b20e60b0094ba3b99399060c25babfcbd',
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final clip = await Clipboard.getData('text/plain');
                          if (clip?.text != null) {
                            ctrl.text = clip!.text!.trim();
                          }
                        },
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('DÃ¡n tá»« clipboard'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Há»§y')),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.length >= 60) {
                  Navigator.pop(ctx, t);
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Token pháº£i >= 60 kÃ½ tá»±')),
                  );
                }
              },
              child: const Text('LÆ°u'),
            ),
          ],
        );
      }),
    );
    if (result != null && result.isNotEmpty) {
      // v3.0.165: DÃ¹ng TokenSyncService - Ã¡p dá»¥ng cho Táº¤T Cáº¢ services + broadcast listeners
      await TokenSyncService.instance.setManualToken(result);
      // Legacy: giá»¯ setHisProToken cho ThongkeAuthService (náº¿u cÃ²n dÃ¹ng)
      await thongke.setHisProToken(result);
      // v3.0.137: lÆ°u thá»i gian update token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('his_pro_token_updated', DateTime.now().millisecondsSinceEpoch);
      if (!mounted) return;
      setState(() {
        _tokenCode = result;
        _tokenUpdated = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âœ… ÄÃ£ lÆ°u token - Ã¡p dá»¥ng cho PhÃ²ng tá»§ thuáº­t, ECG, Lá»‹ch sá»­ ÄT, EMR push')),
      );
    }
  }

  /// v2.51.0: HÆ°á»›ng dáº«n cÃ¡ch láº¥y token tá»« HIS desktop
  Future<void> _showTokenHelp() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CÃ¡ch láº¥y token HIS Pro'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Má»Ÿ HIS Pro desktop táº¡i BV', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   â†’ Login vá»›i tÃ i khoáº£n BS (vd: nemk)'),
              const SizedBox(height: 12),
              const Text('2. Má»Ÿ file log:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   D:\\Nem\\HISPRO_THAT\\Logs\\LogSystem.txt',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
              const SizedBox(height: 4),
              const Text('   (hoáº·c thÆ° má»¥c Logs cá»§a HIS desktop)'),
              const SizedBox(height: 12),
              const Text('3. TÃ¬m dÃ²ng cÃ³ "TokenCode|"', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   Copy 64 kÃ½ tá»± hex phÃ­a sau TokenCode|',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('4. Paste vÃ o app', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   App sáº½ tá»± dÃ¹ng token nÃ y má»—i láº§n má»Ÿ.\n'
                  '   KHÃ”NG cáº§n nháº­p láº¡i. Token tá»± refresh má»—i 5 phÃºt.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('ðŸ“Œ LÆ°u Ã½:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 4),
              const Text('â€¢ Token háº¿t háº¡n khi Ä‘Ã³ng HIS desktop',
                  style: TextStyle(fontSize: 11)),
              const Text('â€¢ Má»—i láº§n BS má»Ÿ HIS desktop â†’ paste token má»›i',
                  style: TextStyle(fontSize: 11)),
              const Text('â€¢ Cáº§n WiFi BV Ä‘á»ƒ káº¿t ná»‘i EMR server (port 1417)',
                  style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÄÃ£ hiá»ƒu')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = DataService.instance;
    final user = data.user;
    final username = user?.userName;
    final loginName = user?.loginName;
    final email = user?.email ?? loginName ?? 'ChÆ°a Ä‘Äƒng nháº­p';
    final mobile = user?.mobile ?? '';
    final isLoggedIn = data.isAuthenticated;
    final role = (user != null && user.roles.isNotEmpty) ? user.roles.first.name : 'BÃ¡c sÄ©';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('CÃ i Ä‘áº·t', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          // v2.48.0: Bá» UI nháº­p tay - app tá»± Ä‘á»™ng hoÃ n toÃ n
          // Chá»‰ hiá»‡n tráº¡ng thÃ¡i káº¿t ná»‘i HIS Pro (silent bootstrap)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // === TÃ€I KHOáº¢N ===
                _section('TÃ€I KHOáº¢N'),
                _menuItem(
                  icon: Icons.person,
                  color: Colors.indigo,
                  title: 'ThÃ´ng tin tÃ i khoáº£n',
                  subtitle: isLoggedIn ? 'BS. $username - $role' : 'ChÆ°a Ä‘Äƒng nháº­p',
                  onTap: () => _showAccountInfo(isLoggedIn, user, username, loginName, email, mobile, role),
                ),
                _menuItem(
                  icon: Icons.lock,
                  color: Colors.orange,
                  title: 'Äá»•i máº­t kháº©u',
                  subtitle: isLoggedIn ? 'Äá»•i pass Ä‘Äƒng nháº­p Data' : 'Cáº§n Ä‘Äƒng nháº­p trÆ°á»›c',
                  onTap: () => isLoggedIn ? _showChangePasswordDialog() : _showInfo('Äá»•i máº­t kháº©u', 'Báº¡n cáº§n Ä‘Äƒng nháº­p Data trÆ°á»›c.'),
                ),
                // v3.0.38: Xem log upload (cho BS debug)
                _menuItem(
                  icon: Icons.article,
                  color: Colors.teal,
                  title: 'Xem log upload EMR',
                  subtitle: 'Request/Response/Retry/Metric (gá»­i IT khi lá»—i)',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen()));
                  },
                ),

                // === Cáº¤U HÃŒNH (v2.75.1) ===
                _section('Cáº¤U HÃŒNH'),
                _menuItem(
                  icon: Icons.tune,
                  color: Colors.blue,
                  title: 'Cáº¥u hÃ¬nh HIS',
                  subtitle: 'URL Backend, tÃ i khoáº£n, mÃ£ khoa',
                  onTap: () async {
                    final r = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HisConfigScreen(),
                      ),
                    );
                    if (r == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('ÄÃ£ cáº­p nháº­t cáº¥u hÃ¬nh. Má»Ÿ láº¡i app Ä‘á»ƒ Ã¡p dá»¥ng.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
                // v3.0.74: VPN Bá»‡nh viá»‡n - káº¿t ná»‘i VPN BV tá»± Ä‘á»™ng
                _menuItem(
                  icon: Icons.vpn_lock,
                  color: const Color(0xFF0D47A1),
                  title: 'VPN Bá»‡nh viá»‡n',
                  subtitle: 'Káº¿t ná»‘i VPN BV tá»± Ä‘á»™ng (nemk)',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VpnBenhVienScreen(),
                      ),
                    );
                  },
                ),

                // v3.0.165: Token sync hub - 1 nÆ¡i quáº£n lÃ½ Táº¤T Cáº¢ token (procedure room, ECG, treatment history, EMR push,...)
                // - Hiá»ƒn thá»‹ tráº¡ng thÃ¡i: masked token, source, age
                // - 2 nÃºt: "Tá»± cáº­p nháº­t" (auto-fetch) + "DÃ¡n thá»§ cÃ´ng" (paste tá»« log)
                _section('TOKEN HIS PRO'),
                Card(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 4),
                  elevation: 0.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.cloud_done, color: Colors.green, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Token Ä‘ang dÃ¹ng',
                                      style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w500)),
                                  Text(
                                    TokenSyncService.instance.maskedToken,
                                    style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                                  ),
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: TokenSyncService.instance.hasToken ? Colors.green : Colors.grey,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        TokenSyncService.instance.currentSource ?? 'none',
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      TokenSyncService.instance.lastUpdatedLabel,
                                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                                    ),
                                    if (TokenSyncService.instance.isStale && TokenSyncService.instance.hasToken) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.schedule, size: 10, color: Colors.orange),
                                      const Text(' cÅ©', style: TextStyle(fontSize: 9, color: Colors.orange)),
                                    ],
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // v3.0.165: 2 nÃºt - Tá»± cáº­p nháº­t + DÃ¡n thá»§ cÃ´ng
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _autoUpdateToken,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                icon: const Icon(Icons.refresh, size: 14),
                                label: const Text('Tá»± cáº­p nháº­t', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await _showTokenDialog();
                                  await _loadInfo();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                icon: const Icon(Icons.edit, size: 14),
                                label: const Text('DÃ¡n thá»§ cÃ´ng', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: _showTokenHelp,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                              ),
                              child: const Icon(Icons.help_outline, size: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'ðŸ’¡ Token Ã¡p dá»¥ng cho: PhÃ²ng tá»§ thuáº­t, ECG, Lá»‹ch sá»­ ÄT, EMR push, má»i API HIS Pro',
                          style: TextStyle(fontSize: 9, color: Colors.black54, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),

                // === GIAO DIá»†N ===
                _section('GIAO DIá»†N'),
                _menuItem(
                  icon: _themeMode == ThemeMode.dark ? Icons.dark_mode : _themeMode == ThemeMode.light ? Icons.light_mode : Icons.brightness_auto,
                  color: Colors.deepPurple,
                  title: 'Chá»n ná»n sÃ¡ng / tá»‘i',
                  subtitle: _themeMode == ThemeMode.dark ? 'Tá»‘i' : _themeMode == ThemeMode.light ? 'SÃ¡ng' : 'Theo há»‡ thá»‘ng',
                  onTap: () => _showThemeDialog(),
                ),
                // v2.98.2: Bá»Ž má»¥c "Hiá»ƒn thá»‹ tÃªn bá»‡nh nhÃ¢n" (BS khÃ´ng cáº§n chá»n field ná»¯a - auto Æ°u tiÃªn tÃªn cÃ³ dáº¥u)
                // v2.95.0: Debug API response - phÃ¢n quyá»n chá»‰ user nemk
                if (DataService.instance.user?.loginName == Credentials.defaultNemkLogin)
                  _menuItem(
                    icon: Icons.bug_report_outlined,
                    color: Colors.deepOrange,
                    title: 'Debug: Raw API Response',
                    subtitle: 'Xem field name tháº­t tá»« server (copy gá»­i cho dev) - chá»‰ dÃ nh cho dev nemk',
                    onTap: () => _showApiDebugDialog(),
                  ),

                // === á»¨NG Dá»¤NG ===
                _section('á»¨NG Dá»¤NG'),
                _menuItem(
                  icon: Icons.info,
                  color: Colors.teal,
                  title: 'ThÃ´ng tin á»©ng dá»¥ng',
                  subtitle: 'PhiÃªn báº£n $_version',
                  onTap: () => _showAppInfo(context),
                ),
                // v3.0.173: Restore láº¡i má»¥c "Kiá»ƒm tra cáº­p nháº­t" tá»« v3.0.169 (user tháº¥y thiáº¿u)
                _menuItem(
                  icon: Icons.system_update,
                  color: Colors.blue,
                  title: 'Kiá»ƒm tra cáº­p nháº­t',
                  subtitle: 'TÃ¬m báº£n má»›i tá»« GitHub',
                  onTap: () => _checkForUpdates(),
                ),
                _menuItem(
                  icon: Icons.bug_report,
                  color: Colors.red,
                  title: 'BÃ¡o lá»—i',
                  subtitle: 'Gá»­i pháº£n há»“i cho nhÃ  phÃ¡t triá»ƒn',
                  onTap: () => _showInfo('BÃ¡o lá»—i', 'LiÃªn há»‡ Zalo: BS. Ná»ƒm\nGá»­i kÃ¨m: mÃ´ táº£ lá»—i, thá»i gian, áº£nh chá»¥p.'),
                ),

                // === KHÃC ===
                _section('KHÃC'),
                _menuItem(
                  icon: Icons.logout,
                  color: Colors.red,
                  title: 'ÄÄƒng xuáº¥t Data',
                  subtitle: isLoggedIn ? 'Äang Ä‘Äƒng nháº­p: $loginName' : 'ChÆ°a Ä‘Äƒng nháº­p',
                  onTap: () => _confirmLogout(isLoggedIn),
                ),
                _menuItem(
                  icon: Icons.power_settings_new,
                  color: Colors.red.shade900,
                  title: 'ThoÃ¡t á»©ng dá»¥ng',
                  subtitle: 'ÄÃ³ng app hoÃ n toÃ n',
                  onTap: () => SystemNavigator.pop(),
                ),

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'HIS MOBILE v$_version\nÂ© 2026 Dr. K Rong Ná»ƒm - BVÄK Ninh Thuáº­n',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45, fontSize: 10, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(
        title,
        style: const TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black45, size: 20),
        onTap: onTap,
      ),
    );
  }

  // v3.0.42: Removed _showHisProxyDialog (HIS Pro Proxy Ä‘Ã£ bá»)


  // v3.0.42: Removed _showBvbmLoginDialog (BVBM Gateway Ä‘Ã£ bá»)


  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _showInfo(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÄÃ³ng'))],
      ),
    );
  }

  void _showAccountInfo(bool isLoggedIn, dynamic user, String? username, String? loginName, String email, String mobile, String role) {
    String body;
    if (!isLoggedIn || user == null) {
      body = 'ChÆ°a Ä‘Äƒng nháº­p Data.\n\nMá»Ÿ Trang chá»§ â†’ báº¥m [ÄÄƒng nháº­p].';
    } else {
      final buffer = StringBuffer();
      buffer.writeln('Há» tÃªn: BS. $username');
      if (loginName != null && loginName != username) buffer.writeln('TÃ i khoáº£n: $loginName');
      buffer.writeln('Email: $email');
      if (mobile.isNotEmpty) buffer.writeln('SÄT: $mobile');
      buffer.writeln('Chá»©c danh: $role');
      buffer.writeln('User-ID: ${user.id}');
      body = buffer.toString();
    }
    _showInfo('ThÃ´ng tin tÃ i khoáº£n', body);
  }

  // v2.37.0: Äá»•i máº­t kháº©u - real implementation
  Future<void> _showChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final data = DataService.instance;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Äá»•i máº­t kháº©u Data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Máº­t kháº©u cÅ©', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Máº­t kháº©u má»›i (>= 6 kÃ½ tá»±)', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'XÃ¡c nháº­n máº­t kháº©u má»›i', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Há»§y')),
          ElevatedButton(
            onPressed: () async {
              if (oldCtrl.text.isEmpty || newCtrl.text.isEmpty) {
                _snack('Vui lÃ²ng nháº­p Ä‘áº§y Ä‘á»§');
                return;
              }
              if (newCtrl.text.length < 6) {
                _snack('Máº­t kháº©u má»›i pháº£i >= 6 kÃ½ tá»±');
                return;
              }
              if (newCtrl.text != confirmCtrl.text) {
                _snack('XÃ¡c nháº­n máº­t kháº©u khÃ´ng khá»›p');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Äá»•i'),
          ),
        ],
      ),
    );

    if (result == true) {
      _snack('Äang Ä‘á»•i máº­t kháº©u...');
      final ok = await data.changePassword(oldCtrl.text, newCtrl.text);
      _snack(ok ? 'Äá»•i máº­t kháº©u thÃ nh cÃ´ng' : 'Äá»•i máº­t kháº©u tháº¥t báº¡i. Kiá»ƒm tra máº­t kháº©u cÅ©.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // v2.37.0: Chá»n theme
  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chá»n ná»n'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Theo há»‡ thá»‘ng'),
              subtitle: const Text('Tá»± Ä‘á»™ng theo cÃ i Ä‘áº·t Android'),
              value: ThemeMode.system,
              groupValue: _themeMode,
              onChanged: (v) {
                if (v != null) _setTheme(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('SÃ¡ng'),
              subtitle: const Text('Ná»n tráº¯ng, dá»… Ä‘á»c ban ngÃ y'),
              value: ThemeMode.light,
              groupValue: _themeMode,
              onChanged: (v) {
                if (v != null) _setTheme(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Tá»‘i'),
              subtitle: const Text('Ná»n Ä‘en, báº£o vá»‡ máº¯t ban Ä‘Ãªm'),
              value: ThemeMode.dark,
              groupValue: _themeMode,
              onChanged: (v) {
                if (v != null) _setTheme(v);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // v2.76.3: Chá»n cÃ¡ch hiá»ƒn thá»‹ tÃªn BN
  void _showNameFieldDialog() {
    final current = HisConfigService.instance.config.nameField;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CÃ¡ch hiá»ƒn thá»‹ tÃªn bá»‡nh nhÃ¢n'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Má»™t sá»‘ BN tÃªn bá»‹ lá»—i font (vd: "NguyÃ”n VÂ¨n A"). Chá»n field nÃ o sáº¡ch nháº¥t vá»›i BV báº¡n:',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              for (final f in NameField.values)
                RadioListTile<NameField>(
                  title: Text(f.description, style: const TextStyle(fontSize: 12)),
                  value: f,
                  groupValue: current,
                  dense: true,
                  onChanged: (v) async {
                    if (v == null) return;
                    if (v == current) {
                      Navigator.pop(ctx);
                      return;
                    }
                    await HisConfigService.instance.updateNameField(v);
                    if (!mounted) return;
                    setState(() {});
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('âœ… ÄÃ£ Ä‘á»•i sang: ${v.description}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÄÃ³ng')),
        ],
      ),
    );
  }

  // v3.0.93: Debug API response - gá»i Y Táº¿ Sá»‘ public + HIS Pro
  Future<void> _showApiDebugDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.bug_report, color: Color(0xFFFF6F00), size: 20),
          SizedBox(width: 8),
          Text('Debug: Raw API Response'),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: FutureBuilder<String>(
              future: ApiDebugService.debugApis(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Äang gá»i Y Táº¿ Sá»‘ + HIS Pro...'),
                      ],
                    ),
                  );
                }
                if (snap.hasError) {
                  return SelectableText('Error: ${snap.error}\n\n${snap.data ?? ''}');
                }
                return SelectableText(
                  snap.data ?? 'No data',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy'),
            onPressed: () async {
              final snap = await ApiDebugService.debugApis();
              await Clipboard.setData(ClipboardData(text: snap));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ÄÃ£ copy raw response. Gá»­i cho dev.')),
                  );
                }
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÄÃ³ng')),
        ],
      ),
    );
  }

  // v3.0.93: Update check tá»« GitHub version.json
  Future<void> _checkForUpdates() async {
    final appVer = AppVersionService.instance;
    _showInfo('Äang kiá»ƒm tra cáº­p nháº­tâ€¦', 'Äang gá»i GitHub Ä‘á»ƒ check báº£n má»›i.');
    final info = await UpdateService.checkUpdate();
    if (!mounted) return;
    if (info == null) {
      _showInfo('ÄÃ£ lÃ  báº£n má»›i nháº¥t',
          '${appVer.appName} v${appVer.version} (build ${appVer.buildNumber})\n\n'
          'Báº¡n Ä‘ang dÃ¹ng báº£n má»›i nháº¥t. Tá»± Ä‘á»™ng check láº¡i sau khi cÃ³ báº£n má»›i trÃªn GitHub.');
      return;
    }
    UpdateService.showUpdateDialog(context, info);
  }

  void _showAppInfo(BuildContext context) {
    final appVer = AppVersionService.instance;
    showAboutDialog(
      context: context,
      applicationName: appVer.appName,
      applicationVersion: 'v${appVer.version} (build ${appVer.buildNumber})',
      applicationLegalese: 'Â© 2026 Dr. K Rong Ná»ƒm - BVÄK Ninh Thuáº­n',
      applicationIcon: Container(
        width: 60, height: 60,
        decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.local_hospital, color: Colors.white, size: 36),
      ),
      children: [
        const SizedBox(height: 12),
        const Text('á»¨ng dá»¥ng káº¿t ná»‘i HIS dÃ nh cho BÃ¡c sÄ© Khoa Cáº¥p Cá»©u BVÄK Ninh Thuáº­n.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Text('PhiÃªn báº£n: ${appVer.displayVersion}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Text('TÃ­nh nÄƒng chÃ­nh:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Text('â€¢ ÄÄƒng nháº­p Data + HIS Pro VPN', style: TextStyle(fontSize: 12)),
        Text('â€¢ Xem BN theo khoa (${DepartmentService.instance.departments.length} khoa tá»« HIS Pro)', style: const TextStyle(fontSize: 12)),
        const Text('â€¢ TÃ¬m BN tiáº¿ng Viá»‡t + gá»£i Ã½', style: TextStyle(fontSize: 12)),
        const Text('â€¢ Xem bá»‡nh Ã¡n Ä‘iá»‡n tá»­ (gom phiáº¿u theo loáº¡i)', style: TextStyle(fontSize: 12)),
        const Text('â€¢ Láº­p phiáº¿u + Scan phiáº¿u + Ä‘áº©y EMR', style: TextStyle(fontSize: 12)),
        const Text('â€¢ QR Scanner', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Future<void> _confirmLogout(bool isLoggedIn) async {
    if (!isLoggedIn) {
      _showInfo('ÄÄƒng xuáº¥t', 'Báº¡n chÆ°a Ä‘Äƒng nháº­p Data.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ÄÄƒng xuáº¥t'),
        content: const Text('Báº¡n cÃ³ cháº¯c muá»‘n Ä‘Äƒng xuáº¥t khá»i Data?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Há»§y')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('ÄÄƒng xuáº¥t')),
        ],
      ),
    );
    if (confirm == true) {
      await DataService.instance.clearSession();
      // v2.75.0: Clear persist state khi user chá»§ Ä‘á»™ng logout
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConstants.keyIsLoggedIn, false);
        await prefs.remove(AppConstants.keyLoginName);
        await prefs.remove(AppConstants.keyUserName);
      } catch (_) {}
      if (mounted) context.go('/login');
    }
  }
}