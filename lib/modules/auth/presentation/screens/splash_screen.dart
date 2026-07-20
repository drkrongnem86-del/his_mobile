import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      setState(() => _status = 'Đang khôi phục phiên...');

      // v2.75.0: Check keyIsLoggedIn trước (state persistence)
      // Tắt ngang/đóng app → mở lại vẫn giữ đăng nhập
      // Trừ khi user chủ động logout thì keyIsLoggedIn = false
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
      if (!isLoggedIn) {
        setState(() => _status = 'Vui lòng đăng nhập');
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) context.go('/login');
        return;
      }

      // 1. Khôi phục thongke session (Data path - 8080)
      final thongke = ThongkeAuthService();
      bool thongkeOk = false;
      try {
        thongkeOk = await thongke.restoreSession();
      } catch (_) {
        thongkeOk = false;
      }

      // Lấy username từ prefs
      final loginName = prefs.getString(AppConstants.keyLoginName) ?? '';
      final savedName = prefs.getString(AppConstants.keyUserName) ?? '';
      if (savedName.isNotEmpty) {
        _username = savedName;
      } else if (loginName.isNotEmpty) {
        _username = loginName;
      }

      if (thongkeOk && thongke.currentUsername != null) {
        _username = 'BS. ${thongke.currentUsername}';
      }

      // 2. v2.47.0: Auto-login HIS Pro (1417) bằng saved loginName
      //    AcsToken/Authorize chỉ cần LOGIN_NAME - KHÔNG cần password
      //    → mỗi lần mở app tự lấy TokenCode mới
      setState(() => _status = 'Đang kết nối HIS Pro...');
      try {
        final hisPro = HisProApiService.instance;
        final r = await hisPro.tryAutoLogin();
        if (r.success && r.session != null) {
          print('✅ HIS Pro auto-login OK: ${r.session!.loginName}');
        } else {
          print('ℹ HIS Pro auto-login skipped: ${r.message}');
        }
      } catch (e) {
        print('⚠ HIS Pro auto-login error: $e');
      }

      // v2.75.0: Đã có keyIsLoggedIn = true → vào home trực tiếp
      // Kể cả khi thongke restore fail, vẫn vào home (BN sẽ tự load lại khi cần)
      setState(() => _status = 'Chào mừng trở lại, $_username');
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Lỗi: $e');
        await Future.delayed(const Duration(milliseconds: 800));
        context.go('/login');
      }
    }
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
