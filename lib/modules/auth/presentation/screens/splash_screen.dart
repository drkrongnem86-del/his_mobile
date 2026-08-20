import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/core/services/vpn_benh_vien_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Đang khởi động...';
  String _username = 'BS. Nểm';

  @override
  void initState() {
    super.initState();
    // v3.0.76: Wrap toàn bộ bootstrap trong 1 timeout 8s
    // → tránh app treo ở splash khi không có VPN / API chậm
    _bootstrap().timeout(const Duration(seconds: 8), onTimeout: () {
      debugPrint('SplashScreen: bootstrap timeout 8s → force go /home');
    }).catchError((e) {
      debugPrint('SplashScreen: bootstrap error: $e');
    });
    // Vẫn fallback: nếu 8s vẫn chưa xong, ép về home
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        try {
          context.go('/home');
        } catch (_) {}
      }
    });
  }

  Future<void> _bootstrap() async {
    try {
      setState(() => _status = 'Đang khôi phục phiên...');

      // v2.75.0: Check keyIsLoggedIn trước (state persistence)
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
      if (!isLoggedIn) {
        setState(() => _status = 'Vui lòng đăng nhập');
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) context.go('/login');
        return;
      }

      // 0. v3.0.76: Init VPN service (không block, fire-and-forget)
      // → user có thể thấy VPN status indicator trên home/setting
      VpnBenhVienService.instance.init().catchError((e) {
        debugPrint('VpnBenhVienService init error: $e');
        return;
      });

      // Lấy username từ prefs (nhanh, local)
      final loginName = prefs.getString(AppConstants.keyLoginName) ?? '';
      final savedName = prefs.getString(AppConstants.keyUserName) ?? '';
      if (savedName.isNotEmpty) {
        _username = savedName;
      } else if (loginName.isNotEmpty) {
        _username = loginName;
      }

      // 1. v3.0.76: Thongke restore trong 3s max - không block splash
      setState(() => _status = 'Đang kết nối thongke...');
      final thongke = ThongkeAuthService();
      try {
        await thongke.restoreSession().timeout(const Duration(seconds: 3),
            onTimeout: () => false);
        if (thongke.currentUsername != null) {
          _username = 'BS. ${thongke.currentUsername}';
        }
      } catch (_) {}

      // 2. v3.0.76: Auto-login HIS Pro trong 4s max - KHÔNG block splash
      //    Nếu quá timeout → vẫn vào home, BN sẽ tự load lại khi cần
      setState(() => _status = 'Đang kết nối HIS Pro...');
      // Fire-and-forget - chạy nền, không await
      _tryHisProAutoLoginInBackground();

      // v3.0.76: Vào home ngay (không đợi HIS Pro)
      setState(() => _status = 'Chào mừng trở lại, $_username');
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Lỗi: $e');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) context.go('/home');  // v3.0.76: luôn về home (không về login)
      }
    }
  }

  /// v3.0.76: HIS Pro auto-login chạy nền (không block splash)
  void _tryHisProAutoLoginInBackground() {
    Future.microtask(() async {
      try {
        final hisPro = HisProApiService.instance;
        final r = await hisPro.tryAutoLogin()
            .timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('HIS Pro auto-login timeout 4s (no VPN?)');
          return (success: false, message: 'Timeout - kiểm tra VPN', session: null);
        });
        if (r.success && r.session != null) {
          debugPrint('✅ HIS Pro auto-login OK: ${r.session!.loginName}');
        } else {
          debugPrint('ℹ HIS Pro auto-login skipped: ${r.message}');
        }
      } catch (e) {
        debugPrint('HIS Pro auto-login error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.7),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.local_hospital,
                  size: 64,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'HIS Mobile',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppConstants.hospitalFullName,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _username,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 36),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
