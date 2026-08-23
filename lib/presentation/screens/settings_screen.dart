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

/// Màn hình Cài đặt v2.66.0
/// - Thông tin tài khoản
/// - Đổi mật khẩu
/// - Chọn theme sáng/tối
/// - Cập nhật thông tin ứng dụng + kiểm tra cập nhật
/// - Đăng xuất
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

  // v2.48.0: Bỏ UI nhập tay - chỉ theo dõi trạng thái tự động
  // (đã xóa _hisProLoginName, _hisProBearerToken, _hisProTokenVisible, ...)

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
    if (_tokenCode.isEmpty) return '— chưa đặt —';
    if (_tokenCode.length < 16) return _tokenCode;
    return '${_tokenCode.substring(0, 8)}…${_tokenCode.substring(_tokenCode.length - 8)}';
  }

  String get _tokenStatusLabel {
    if (_tokenCode.isEmpty) return '⚠️ Chưa có token';
    return '✅ Token đã đặt';
  }

  // v2.66.0: Lấy version từ AppVersionService (đọc từ package_info_plus)
  String get _version => AppVersionService.instance.displayVersion;
  String get _fullVersion => AppVersionService.instance.displayFull;
  String get _buildNumber => AppVersionService.instance.buildNumber;

  Future<void> _setTheme(ThemeMode mode) async {
    await ThemeManager.instance.set(mode);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã đổi theme.'),
        duration: Duration(seconds: 1),
      ));
    }
  }

  // v2.47.0: HIS Pro login section (tự lấy token từ AcsToken/Authorize)
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

  /// v2.48.0: Bỏ UI nhập tay - chỉ hiện trạng thái auto-sync
  /// App tự gọi AcsToken/Authorize + auto-load mọi thứ khi mở
  /// v2.51.0: Đơn giản hóa - 1 ô paste token + 1 nút test
  /// App tự động load token từ file (nếu có), chỉ paste khi cần


  /// v3.0.165: Auto-update token từ multi-source (proxy → login API → renew → hardcoded)
  /// Hiển thị dialog loading + kết quả
  Future<void> _autoUpdateToken() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('Đang tự lấy token...', style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
    try {
      final event = await TokenSyncService.instance.autoFetchToken(force: true);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close loading
      if (!mounted) return;
      if (event.token != null) {
        // Thành công
        await _loadInfo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('✅ Đã tự lấy token mới từ: ${event.source}')),
              ]),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Lỗi
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.error, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('❌ Không lấy được token: ${event.message ?? "không rõ"}')),
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
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: const Color(0xFFD32F2F)),
        );
      }
    }
  }

  /// v2.51.0: Dialog paste token đơn giản - 1 lần duy nhất
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
                const Text('Dán token 64-char hex từ HIS Pro desktop log:',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                const Text('D:\\Nem\\HISPRO_THAT\\Logs\\LogSystem.txt',
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.black54)),
                const SizedBox(height: 4),
                const Text('Tìm "TokenCode|" → copy 64 ký tự hex',
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
                        label: const Text('Dán từ clipboard'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.length >= 60) {
                  Navigator.pop(ctx, t);
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Token phải >= 60 ký tự')),
                  );
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      }),
    );
    if (result != null && result.isNotEmpty) {
      // v3.0.165: Dùng TokenSyncService - áp dụng cho TẤT CẢ services + broadcast listeners
      await TokenSyncService.instance.setManualToken(result);
      // Legacy: giữ setHisProToken cho ThongkeAuthService (nếu còn dùng)
      await thongke.setHisProToken(result);
      // v3.0.137: lưu thời gian update token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('his_pro_token_updated', DateTime.now().millisecondsSinceEpoch);
      if (!mounted) return;
      setState(() {
        _tokenCode = result;
        _tokenUpdated = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Đã lưu token - áp dụng cho Phòng tủ thuật, ECG, Lịch sử ĐT, EMR push')),
      );
    }
  }

  /// v2.51.0: Hướng dẫn cách lấy token từ HIS desktop
  Future<void> _showTokenHelp() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cách lấy token HIS Pro'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Mở HIS Pro desktop tại BV', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   → Login với tài khoản BS (vd: nemk)'),
              const SizedBox(height: 12),
              const Text('2. Mở file log:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   D:\\Nem\\HISPRO_THAT\\Logs\\LogSystem.txt',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
              const SizedBox(height: 4),
              const Text('   (hoặc thư mục Logs của HIS desktop)'),
              const SizedBox(height: 12),
              const Text('3. Tìm dòng có "TokenCode|"', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   Copy 64 ký tự hex phía sau TokenCode|',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('4. Paste vào app', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('   App sẽ tự dùng token này mỗi lần mở.\n'
                  '   KHÔNG cần nhập lại. Token tự refresh mỗi 5 phút.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('📌 Lưu ý:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 4),
              const Text('• Token hết hạn khi đóng HIS desktop',
                  style: TextStyle(fontSize: 11)),
              const Text('• Mỗi lần BS mở HIS desktop → paste token mới',
                  style: TextStyle(fontSize: 11)),
              const Text('• Cần WiFi BV để kết nối EMR server (port 1417)',
                  style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
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
    final email = user?.email ?? loginName ?? 'Chưa đăng nhập';
    final mobile = user?.mobile ?? '';
    final isLoggedIn = data.isAuthenticated;
    final role = (user != null && user.roles.isNotEmpty) ? user.roles.first.name : 'Bác sĩ';

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
        title: const Text('Cài đặt', style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Column(
        children: [
          UserHeader.fromAuth(compact: true),
          // v2.48.0: Bỏ UI nhập tay - app tự động hoàn toàn
          // Chỉ hiện trạng thái kết nối HIS Pro (silent bootstrap)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // === TÀI KHOẢN ===
                _section('TÀI KHOẢN'),
                _menuItem(
                  icon: Icons.person,
                  color: Colors.indigo,
                  title: 'Thông tin tài khoản',
                  subtitle: isLoggedIn ? 'BS. $username - $role' : 'Chưa đăng nhập',
                  onTap: () => _showAccountInfo(isLoggedIn, user, username, loginName, email, mobile, role),
                ),
                _menuItem(
                  icon: Icons.lock,
                  color: Colors.orange,
                  title: 'Đổi mật khẩu',
                  subtitle: isLoggedIn ? 'Đổi pass đăng nhập Data' : 'Cần đăng nhập trước',
                  onTap: () => isLoggedIn ? _showChangePasswordDialog() : _showInfo('Đổi mật khẩu', 'Bạn cần đăng nhập Data trước.'),
                ),
                // v3.0.38: Xem log upload (cho BS debug)
                _menuItem(
                  icon: Icons.article,
                  color: Colors.teal,
                  title: 'Xem log upload EMR',
                  subtitle: 'Request/Response/Retry/Metric (gửi IT khi lỗi)',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen()));
                  },
                ),

                // === CẤU HÌNH (v2.75.1) ===
                _section('CẤU HÌNH'),
                _menuItem(
                  icon: Icons.tune,
                  color: Colors.blue,
                  title: 'Cấu hình HIS',
                  subtitle: 'URL Backend, tài khoản, mã khoa',
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
                          content: Text('Đã cập nhật cấu hình. Mở lại app để áp dụng.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
                // v3.0.74: VPN Bệnh viện - kết nối VPN BV tự động
                _menuItem(
                  icon: Icons.vpn_lock,
                  color: const Color(0xFF0D47A1),
                  title: 'VPN Bệnh viện',
                  subtitle: 'Kết nối VPN BV tự động (nemk)',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VpnBenhVienScreen(),
                      ),
                    );
                  },
                ),

                // v3.0.165: Token sync hub - 1 nơi quản lý TẤT CẢ token (procedure room, ECG, treatment history, EMR push,...)
                // - Hiển thị trạng thái: masked token, source, age
                // - 2 nút: "Tự cập nhật" (auto-fetch) + "Dán thủ công" (paste từ log)
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
                                  const Text('Token đang dùng',
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
                                      const Text(' cũ', style: TextStyle(fontSize: 9, color: Colors.orange)),
                                    ],
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // v3.0.165: 2 nút - Tự cập nhật + Dán thủ công
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
                                label: const Text('Tự cập nhật', style: TextStyle(fontSize: 12)),
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
                                label: const Text('Dán thủ công', style: TextStyle(fontSize: 12)),
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
                          '💡 Token áp dụng cho: Phòng tủ thuật, ECG, Lịch sử ĐT, EMR push, mọi API HIS Pro',
                          style: TextStyle(fontSize: 9, color: Colors.black54, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),

                // === GIAO DIỆN ===
                _section('GIAO DIỆN'),
                _menuItem(
                  icon: _themeMode == ThemeMode.dark ? Icons.dark_mode : _themeMode == ThemeMode.light ? Icons.light_mode : Icons.brightness_auto,
                  color: Colors.deepPurple,
                  title: 'Chọn nền sáng / tối',
                  subtitle: _themeMode == ThemeMode.dark ? 'Tối' : _themeMode == ThemeMode.light ? 'Sáng' : 'Theo hệ thống',
                  onTap: () => _showThemeDialog(),
                ),
                // v2.98.2: BỎ mục "Hiển thị tên bệnh nhân" (BS không cần chọn field nữa - auto ưu tiên tên có dấu)
                // v2.95.0: Debug API response - phân quyền chỉ user nemk
                if (DataService.instance.user?.loginName == 'nemk')
                  _menuItem(
                    icon: Icons.bug_report_outlined,
                    color: Colors.deepOrange,
                    title: 'Debug: Raw API Response',
                    subtitle: 'Xem field name thật từ server (copy gửi cho dev) - chỉ dành cho dev nemk',
                    onTap: () => _showApiDebugDialog(),
                  ),

                // === ỨNG DỤNG ===
                _section('ỨNG DỤNG'),
                _menuItem(
                  icon: Icons.info,
                  color: Colors.teal,
                  title: 'Thông tin ứng dụng',
                  subtitle: 'Phiên bản $_version',
                  onTap: () => _showAppInfo(context),
                ),
                // v3.0.171: Bỏ mục "Kiểm tra cập nhật" - user tự cài APK thủ công qua file manager
                _menuItem(
                  icon: Icons.bug_report,
                  color: Colors.red,
                  title: 'Báo lỗi',
                  subtitle: 'Gửi phản hồi cho nhà phát triển',
                  onTap: () => _showInfo('Báo lỗi', 'Liên hệ Zalo: BS. Nểm\nGửi kèm: mô tả lỗi, thời gian, ảnh chụp.'),
                ),

                // === KHÁC ===
                _section('KHÁC'),
                _menuItem(
                  icon: Icons.logout,
                  color: Colors.red,
                  title: 'Đăng xuất Data',
                  subtitle: isLoggedIn ? 'Đang đăng nhập: $loginName' : 'Chưa đăng nhập',
                  onTap: () => _confirmLogout(isLoggedIn),
                ),
                _menuItem(
                  icon: Icons.power_settings_new,
                  color: Colors.red.shade900,
                  title: 'Thoát ứng dụng',
                  subtitle: 'Đóng app hoàn toàn',
                  onTap: () => SystemNavigator.pop(),
                ),

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'HIS MOBILE v$_version\n© 2026 Dr. K Rong Nểm - BVĐK Ninh Thuận',
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

  // v3.0.42: Removed _showHisProxyDialog (HIS Pro Proxy đã bỏ)


  // v3.0.42: Removed _showBvbmLoginDialog (BVBM Gateway đã bỏ)


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
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  void _showAccountInfo(bool isLoggedIn, dynamic user, String? username, String? loginName, String email, String mobile, String role) {
    String body;
    if (!isLoggedIn || user == null) {
      body = 'Chưa đăng nhập Data.\n\nMở Trang chủ → bấm [Đăng nhập].';
    } else {
      final buffer = StringBuffer();
      buffer.writeln('Họ tên: BS. $username');
      if (loginName != null && loginName != username) buffer.writeln('Tài khoản: $loginName');
      buffer.writeln('Email: $email');
      if (mobile.isNotEmpty) buffer.writeln('SĐT: $mobile');
      buffer.writeln('Chức danh: $role');
      buffer.writeln('User-ID: ${user.id}');
      body = buffer.toString();
    }
    _showInfo('Thông tin tài khoản', body);
  }

  // v2.37.0: Đổi mật khẩu - real implementation
  Future<void> _showChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final data = DataService.instance;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi mật khẩu Data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu cũ', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu mới (>= 6 ký tự)', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Xác nhận mật khẩu mới', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (oldCtrl.text.isEmpty || newCtrl.text.isEmpty) {
                _snack('Vui lòng nhập đầy đủ');
                return;
              }
              if (newCtrl.text.length < 6) {
                _snack('Mật khẩu mới phải >= 6 ký tự');
                return;
              }
              if (newCtrl.text != confirmCtrl.text) {
                _snack('Xác nhận mật khẩu không khớp');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Đổi'),
          ),
        ],
      ),
    );

    if (result == true) {
      _snack('Đang đổi mật khẩu...');
      final ok = await data.changePassword(oldCtrl.text, newCtrl.text);
      _snack(ok ? 'Đổi mật khẩu thành công' : 'Đổi mật khẩu thất bại. Kiểm tra mật khẩu cũ.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // v2.37.0: Chọn theme
  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn nền'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Theo hệ thống'),
              subtitle: const Text('Tự động theo cài đặt Android'),
              value: ThemeMode.system,
              groupValue: _themeMode,
              onChanged: (v) {
                if (v != null) _setTheme(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Sáng'),
              subtitle: const Text('Nền trắng, dễ đọc ban ngày'),
              value: ThemeMode.light,
              groupValue: _themeMode,
              onChanged: (v) {
                if (v != null) _setTheme(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Tối'),
              subtitle: const Text('Nền đen, bảo vệ mắt ban đêm'),
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

  // v2.76.3: Chọn cách hiển thị tên BN
  void _showNameFieldDialog() {
    final current = HisConfigService.instance.config.nameField;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cách hiển thị tên bệnh nhân'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Một số BN tên bị lỗi font (vd: "NguyÔn V¨n A"). Chọn field nào sạch nhất với BV bạn:',
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
                        content: Text('✅ Đã đổi sang: ${v.description}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  // v3.0.93: Debug API response - gọi Y Tế Số public + HIS Pro
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
                        Text('Đang gọi Y Tế Số + HIS Pro...'),
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
                    const SnackBar(content: Text('Đã copy raw response. Gửi cho dev.')),
                  );
                }
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  // v3.0.93: Update check từ GitHub version.json
  Future<void> _checkForUpdates() async {
    final appVer = AppVersionService.instance;
    _showInfo('Đang kiểm tra cập nhật…', 'Đang gọi GitHub để check bản mới.');
    final info = await UpdateService.checkUpdate();
    if (!mounted) return;
    if (info == null) {
      _showInfo('Đã là bản mới nhất',
          '${appVer.appName} v${appVer.version} (build ${appVer.buildNumber})\n\n'
          'Bạn đang dùng bản mới nhất. Tự động check lại sau khi có bản mới trên GitHub.');
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
      applicationLegalese: '© 2026 Dr. K Rong Nểm - BVĐK Ninh Thuận',
      applicationIcon: Container(
        width: 60, height: 60,
        decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.local_hospital, color: Colors.white, size: 36),
      ),
      children: [
        const SizedBox(height: 12),
        const Text('Ứng dụng kết nối HIS dành cho Bác sĩ Khoa Cấp Cứu BVĐK Ninh Thuận.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Text('Phiên bản: ${appVer.displayVersion}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Text('Tính năng chính:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Text('• Đăng nhập Data + HIS Pro VPN', style: TextStyle(fontSize: 12)),
        Text('• Xem BN theo khoa (${DepartmentService.instance.departments.length} khoa từ HIS Pro)', style: const TextStyle(fontSize: 12)),
        const Text('• Tìm BN tiếng Việt + gợi ý', style: TextStyle(fontSize: 12)),
        const Text('• Xem bệnh án điện tử (gom phiếu theo loại)', style: TextStyle(fontSize: 12)),
        const Text('• Lập phiếu + Scan phiếu + đẩy EMR', style: TextStyle(fontSize: 12)),
        const Text('• QR Scanner', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Future<void> _confirmLogout(bool isLoggedIn) async {
    if (!isLoggedIn) {
      _showInfo('Đăng xuất', 'Bạn chưa đăng nhập Data.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi Data?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (confirm == true) {
      await DataService.instance.clearSession();
      // v2.75.0: Clear persist state khi user chủ động logout
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