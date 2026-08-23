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
import 'package:his_mobile/data/api/his_pro_api_service.dart' as his_pro_api;  // v3.0.159: class CHÍNH (EMR push)
import 'package:his_mobile/data/services/his_pro_api_service.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/services/auto_token_service.dart';  // v3.0.159: Auto-token multi-source
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
  // v3.0.159: Auto-login với stored credentials
  // v3.0.169: Mặc định FALSE - user phải chủ động bật (an toàn hơn, tránh lưu password nhầm)
  bool _rememberCredentials = false;
  bool _autoLoginBusy = false;
  String _autoLoginStatus = '';

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

    // v3.0.159: Lưu credentials cho auto-login (nếu user chọn)
    if (_rememberCredentials) {
      await AutoTokenService.instance.saveCredentials(email, pass);
    }

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
            // v3.0.159: dùng class CHÍNH (his_pro_api) cho login flow cũ
            final r = await his_pro_api.HisProApiService.instance.login(email);
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

  /// v3.0.159: Auto-fetch HIS Pro token từ nhiều nguồn
  /// Thứ tự: proxy → login API → renew → hardcoded
  /// Nếu user chưa nhập credentials, dùng hardcoded token ngay
  Future<void> _handleAutoFetchToken() async {
    setState(() {
      _autoLoginBusy = true;
      _autoLoginStatus = '🔄 Đang thử tất cả nguồn...';
    });
    try {
      // Lưu credentials nếu user đã nhập
      if (_rememberCredentials) {
        final email = _loginNameController.text.trim();
        final pass = _passwordController.text;
        if (email.isNotEmpty && pass.isNotEmpty) {
          await AutoTokenService.instance.saveCredentials(email, pass);
        }
      }

      final result = await AutoTokenService.instance.fetchToken(forceRefresh: true, tryAllSources: true);
      if (result.success && result.token != null) {
        // Apply token ngay vào cả 2 class
        try {
          await his_pro_api.HisProApiService.instance.clearCustomBearer();
        } catch (_) {}
        await his_pro_api.HisProApiService.instance.setCustomBearer(result.token!);
        HisProApiService.instance.setTokenCode(token: result.token!, clientIp: result.clientIp ?? '');

        setState(() {
          _autoLoginStatus = '✅ Token: ${result.token!.substring(0, 12)}...\n'
              '📡 Nguồn: ${result.source.name}\n'
              '🕐 Lúc: ${result.fetchedAt?.toString().substring(0, 19) ?? "?"}';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Đã lấy token từ ${result.source.name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(() {
          _autoLoginStatus = '❌ Thất bại: ${result.message ?? "unknown"}';
        });
      }
    } catch (e) {
      setState(() {
        _autoLoginStatus = '❌ Lỗi: $e';
      });
    } finally {
      if (mounted) setState(() => _autoLoginBusy = false);
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
                    const SizedBox(height: 8),
                    // v3.0.169: Checkbox lưu credentials - default FALSE, có dialog cảnh báo khi bật
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Lưu thông tin để tự lấy token HIS Pro', style: TextStyle(fontSize: 13)),
                      subtitle: const Text('Auto-fetch token mỗi lần mở app (mật khẩu lưu SecureStorage)', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      value: _rememberCredentials,
                      onChanged: (v) async {
                        if (v == true) {
                          // v3.0.169: Hiện dialog cảnh báo trước khi bật
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Row(children: [
                                Icon(Icons.shield, color: Colors.orange),
                                SizedBox(width: 8),
                                Text('Lưu thông tin đăng nhập?'),
                              ]),
                              content: const Text(
                                'Mật khẩu sẽ được lưu trong Android Keystore (mã hóa AES).\n\n'
                                'App sẽ tự động lấy token HIS Pro mỗi lần mở - bạn không cần đăng nhập lại.\n\n'
                                'Bạn có thể tắt tính năng này bất kỳ lúc nào trong Cài đặt.',
                                style: TextStyle(fontSize: 13),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Hủy'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Đồng ý'),
                                ),
                              ],
                            ),
                          );
                          if (!mounted) return;
                          setState(() => _rememberCredentials = confirmed ?? false);
                        } else {
                          setState(() => _rememberCredentials = false);
                          // v3.0.169: Nếu tắt → xóa credentials đã lưu
                          await AutoTokenService.instance.clearCredentials();
                        }
                      },
                    ),
                  ],
                ),
              ),
              // v3.0.159: Nút Auto-fetch token (multi-source)
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_outlined, size: 18, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Auto-fetch Token (v3.0.159)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                          ),
                        ),
                        if (_autoLoginBusy)
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Thử login API → renew → hardcoded. '
                      'Chỉ cần bấm nút - không cần paste token tay.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _autoLoginBusy ? null : _handleAutoFetchToken,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('🔄 Lấy token tự động ngay', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    if (_autoLoginStatus.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _autoLoginStatus,
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
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
