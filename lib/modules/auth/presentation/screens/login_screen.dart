// LoginScreen v2.98.0
// - BỎ ô "Public VPN / LAN" toggle (v2.98.0 - BS yêu cầu)
// - Sửa mojibake: "TĂi khoản" → "tài khoản", "Lá»—i mạng" → "Lỗi mạng", "vĂ o" → "vào"
// - 4 endpoints test: 1401/Authorize, 1408/HisBranch/Get, 1410/SdaConfig/Get, 1401/Timer/Sync
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/core/theme/app_theme.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/presentation/screens/connection_check_screen.dart';
import 'package:his_mobile/presentation/screens/his_config_screen.dart';
import 'package:his_mobile/presentation/screens/vpn_benh_vien_screen.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  final _passwordFocus = FocusNode();
  bool _isExiting = false;

  @override
  void dispose() {
    _loginNameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _loginNameController.text.trim();
    final pass = _passwordController.text;
    if (email.isEmpty || pass.isEmpty) return;

    setState(() => _loading = true);

    final result = await DataService.instance.login(email, pass);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      // v2.75.0: Lưu state đăng nhập - để lần sau mở app vào thẳng home
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConstants.keyIsLoggedIn, true);
        await prefs.setString(AppConstants.keyLoginName, email);
        await prefs.setString(AppConstants.keyUserName, result.user?.userName ?? email);
      } catch (_) {}

      // v3.0.89: NAVIGATE NGAY để user thấy home → giảm perceived login time
      // Auto-fetch HIS Pro + Y Tế Số JWT chạy BACKGROUND (fire-and-forget)
      if (!mounted) return;
      context.go('/home');

      // Background auto-fetch (không block navigation)
      // Trước đây: Future.wait → tổng thời gian = max(t2, t3) ≈ 3-5s BLOCKING
      // Giờ: fire-and-forget → user vào home ngay, tokens sẵn sàng khi cần
      unawaited(_bgFetchTokens(email, pass));
    } else {
      final msg = _friendlyAuthMessage(result.message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _friendlyAuthMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('sai') ||
        lower.contains('không chính xác') ||
        lower.contains('invalid') ||
        lower.contains('401')) {
      return 'Tên đăng nhập hoặc mật khẩu không chính xác';
    }
    if (lower.contains('mạng') ||
        lower.contains('timeout') ||
        lower.contains('connection')) {
      return 'Lỗi mạng — kiểm tra kết nối và thử lại';
    }
    return 'Tên đăng nhập hoặc mật khẩu không chính xác';
  }

  /// v3.0.89: Background auto-fetch tokens (HIS Pro + Y Tế Số)
  /// Fire-and-forget - không block navigation
  /// Tokens sẽ có sẵn khi user mở Xem bệnh án / Y tế số screen
  Future<void> _bgFetchTokens(String email, String pass) async {
    try {
      // Chạy song song 2 luồng
      await Future.wait([
        () async {
          try {
            final r = await HisProApiService.instance.login(email);
            if (r.success && r.session != null) {
              debugPrint('✅ BG: Auto-fetched HIS Pro token: ${r.session!.token.length} chars');
            }
          } catch (e) {
            debugPrint('⚠️ BG: HIS Pro login error: $e');
          }
        }(),
        () async {
          try {
            final r = await YTeSoService.instance.login(email: email, password: pass);
            if (r.success) {
              debugPrint('✅ BG: Auto-fetched Y Tế Số JWT: ${YTeSoService.instance.accessToken?.length ?? 0} chars');
            } else {
              debugPrint('⚠️ BG: Y Tế Số login failed: ${r.message}');
            }
          } catch (e) {
            debugPrint('⚠️ BG: Y Tế Số login error: $e');
          }
        }(),
      ]);
    } catch (e) {
      debugPrint('⚠️ BG fetch tokens error: $e');
    }
  }

  /// v2.75.0: Test 4 endpoints
  Future<List<({String name, bool ok, String? info})>> _testEndpoints() async {
    final results = <({String name, bool ok, String? info})>[];
    // v2.75.4: Đảm bảo URL có trailing slash
    String _fix(String url) => url.endsWith('/') ? url : '$url/';
    final acsUrl = _fix(ConnectionService.instance.acsUrl);
    final mosUrl = _fix(ConnectionService.instance.mosUrl);
    final sdaUrl = _fix(ConnectionService.instance.sdaUrl);

    // 1. AcsToken/Authorize
    try {
      final r = await http
          .get(Uri.parse('${acsUrl}api/AcsToken/Authorize'))
          .timeout(const Duration(seconds: 5));
      results.add((
        name: '1401 AcsToken/Authorize',
        ok: r.statusCode == 200,
        info: '${r.statusCode}',
      ));
    } catch (e) {
      results.add((
        name: '1401 AcsToken/Authorize',
        ok: false,
        info: e.toString().split('\n').first,
      ));
    }

    // 2. HisBranch/Get
    try {
      final r = await http
          .get(Uri.parse('${mosUrl}api/HisBranch/Get'))
          .timeout(const Duration(seconds: 5));
      var info = '${r.statusCode}';
      if (r.statusCode == 200) {
        try {
          final data = jsonDecode(r.body);
          if (data is List && data.isNotEmpty) {
            info = '${data.length} branches (${data[0]['BRANCH_NAME'] ?? '?'})';
          }
        } catch (_) {}
      }
      results.add((name: '1408 HisBranch/Get', ok: r.statusCode == 200, info: info));
    } catch (e) {
      results.add((
        name: '1408 HisBranch/Get',
        ok: false,
        info: e.toString().split('\n').first,
      ));
    }

    // 3. SdaConfig/Get
    try {
      final r = await http
          .get(Uri.parse('${sdaUrl}api/SdaConfig/Get'))
          .timeout(const Duration(seconds: 5));
      results.add((
        name: '1410 SdaConfig/Get',
        ok: r.statusCode == 200,
        info: '${r.statusCode}',
      ));
    } catch (e) {
      results.add((
        name: '1410 SdaConfig/Get',
        ok: false,
        info: e.toString().split('\n').first,
      ));
    }

    // 4. Timer/Sync
    try {
      final r = await http
          .get(Uri.parse('${acsUrl}api/Timer/Sync'))
          .timeout(const Duration(seconds: 5));
      results.add((
        name: '1401 Timer/Sync',
        ok: r.statusCode == 200,
        info: '${r.statusCode} (${r.body.length}B)',
      ));
    } catch (e) {
      results.add((
        name: '1401 Timer/Sync',
        ok: false,
        info: e.toString().split('\n').first,
      ));
    }

    return results;
  }

  /// v2.75.2: Nứt Back ở góc phải trên cùng - thoát app thật
  Future<void> _handleBack() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.exit_to_app, color: AppTheme.errorColor),
            SizedBox(width: 8),
            Text('Thoát ứng dụng?'),
          ],
        ),
        content: const Text('Bạn muốn Đóng HIS Mobile?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hễy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Thoát', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (shouldExit == true) {
      // v2.75.2: Thoát app thật
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        // v2.75.0: Nứt Back ở góc phải trên cùng
        actions: [
          // v3.0.74: VPN status indicator
          _VpnStatusButton(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black54),
            tooltip: 'Đóng',
            onPressed: _handleBack,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.local_hospital, size: 56, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'HIS Mobile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              // v2.75.0: Tên BV đầy đủ
              const Text(
                AppConstants.hospitalFullName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 32),

              // v2.98.0: BỎ ô "Public VPN / LAN" toggle (BS yêu cầu - đơn giản hóa)
              // Auto-detect ở ConnectionService - không cần user chọn
              const SizedBox(height: 0),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _loginNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên đăng nhập (email)',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập tên đăng nhập';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleLogin(),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: _loading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Đăng nhập', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConnectionCheckScreen()),
                  );
                },
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Kiểm tra kết nối'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              // v2.75.1: Nứt mở cấu hình HIS (URLs + tài khoản)
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HisConfigScreen()),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Cấu hình HIS (URL, tài khoản, khoa)'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// v3.0.74: Nút hiển thị trạng thái VPN Bệnh viện ở AppBar
class _VpnStatusButton extends StatefulWidget {
  @override
  State<_VpnStatusButton> createState() => _VpnStatusButtonState();
}

class _VpnStatusButtonState extends State<_VpnStatusButton> {
  @override
  void initState() {
    super.initState();
    VpnBenhVienService.instance.init();
    VpnBenhVienService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    VpnBenhVienService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vpn = VpnBenhVienService.instance;
    final isConnected = vpn.isConnected;
    final isConnecting = vpn.isConnecting;
    Color color = Colors.grey;
    IconData icon = Icons.vpn_lock;
    String tooltip = 'VPN BV: Chưa kết nối';
    if (isConnected) {
      color = Colors.green;
      icon = Icons.verified;
      tooltip = 'VPN BV: Đã kết nối';
    } else if (isConnecting) {
      color = Colors.orange;
      icon = Icons.sync;
      tooltip = 'VPN BV: Đang kết nối...';
    }
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VpnBenhVienScreen()),
        );
      },
    );
  }
}
