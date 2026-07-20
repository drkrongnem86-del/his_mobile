import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/services/his_pro_api_service.dart';
import 'package:his_mobile/data/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Events
abstract class AuthEvent {}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String loginName;
  final String password;

  AuthLoginRequested({required this.loginName, required this.password});
}

class AuthLogoutRequested extends AuthEvent {}

// States
abstract class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final String userId;
  final String userName;
  final String loginName;
  final String? departmentName;

  AuthAuthenticated({
    required this.userId,
    required this.userName,
    required this.loginName,
    this.departmentName,
  });
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  AuthError(this.message);
}

// Auth BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final HisApiService _apiService;
  final SharedPreferences _prefs;

  AuthBloc({required SharedPreferences prefs})
      : _prefs = prefs,
        _apiService = HisApiService(),
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    await Future.delayed(const Duration(milliseconds: 500));

    final isLoggedIn = _prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
    if (isLoggedIn) {
      // v3.0.42: Auto sync Token EMR HIS Pro khi restore session
      unawaited(_autoSyncEmrToken());
      emit(AuthAuthenticated(
        userId: _prefs.getString(AppConstants.keyUserId) ?? '',
        userName: _prefs.getString(AppConstants.keyUserName) ?? '',
        loginName: _prefs.getString(AppConstants.keyLoginName) ?? '',
        departmentName: _prefs.getString(AppConstants.keyDepartmentName),
      ));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      // Goi API login HIS Pro
      final result = await _apiService.login(event.loginName, event.password);

      if (result.success) {
        final token = result.token;
        if (token != null) {
          _apiService.setAuthToken(token);
        }

        // Đồng thời login vào Thongke server để có session cookie cho BN
        try {
          final thongkeResult = await _apiService.thongkeLogin(event.loginName, event.password);
          print('🌐 Thongke login: ${thongkeResult.success}');
        } catch (e) {
          print('⚠️ Thongke login failed (non-fatal): $e');
        }

        // Luu session
        await _prefs.setBool(AppConstants.keyIsLoggedIn, true);
        await _prefs.setString(AppConstants.keyLoginName, event.loginName);
        if (result.token != null) {
          await _prefs.setString(AppConstants.keyAccessToken, result.token!);
        }

        // v3.0.42: Auto sync Token EMR HIS Pro ngay sau khi login
        unawaited(_autoSyncEmrToken());

        emit(AuthAuthenticated(
          userId: '1',
          userName: result.userData?['USERNAME'] ?? event.loginName,
          loginName: event.loginName,
          departmentName: 'Khoa Cap Cuu',
        ));
      } else {
        emit(AuthError(result.message ?? 'Dang nhap that bai'));
      }
    } catch (e) {
      emit(AuthError('Loi ket noi: $e'));
    }
  }

  /// v3.0.59: FORCE hardcode token mới nhất (bỏ SecureStorage/SharedPreferences cache)
  /// - v3.0.57 dùng af89403b... → giờ giữ nguyên (verified work 20/7)
  /// - v3.0.59: IP đổi 171.15.128.5 → 171.15.0.9 (BS thay đổi IP máy BV)
  /// - Lý do: v3.0.45 dùng ??= chỉ fallback khi rỗng
  ///   Nếu SecureStorage đã lưu token cũ (cb35...) thì KHÔNG override → fail
  /// - Fix: hardcode mới nhất là source of truth, LUÔN ghi đè
  Future<void> _autoSyncEmrToken() async {
    try {
      const String latestToken = 'af89403b7f001cd27ca9defa6c987a4f9e7bbd564525b8bc6287a693bf674c4d';
      const String latestIp = '171.15.0.9';  // v3.0.59: IP mới
      // v3.0.49: Check override từ Settings (nếu BS muốn dùng token khác)
      final String? overrideToken = _prefs.getString('his_pro_token_override');
      final String? overrideIp = _prefs.getString('his_pro_ip_override');
      final String token = (overrideToken != null && overrideToken.isNotEmpty) ? overrideToken : latestToken;
      final String ip = (overrideIp != null && overrideIp.isNotEmpty) ? overrideIp : latestIp;
      // v3.0.49: LUÔN ghi đè cache với hardcode mới nhất
      HisProApiService.instance.setTokenCode(token: token, clientIp: ip);
      await SecureStorageService.instance.save('his_pro_token_code', token);
      await SecureStorageService.instance.save('his_pro_client_ip', ip);
      await _prefs.setString('his_pro_token_code', token);
      await _prefs.setString('his_pro_client_ip', ip);
      print('🔑 [v3.0.59] Force EMR Token: ${token.substring(0, 8)}… IP=$ip');
    } catch (e) {
      print('⚠️ Auto sync Token EMR failed: $e');
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    _apiService.clearAuthToken();
    await _prefs.setBool(AppConstants.keyIsLoggedIn, false);
    await _prefs.remove(AppConstants.keyAccessToken);
    await _prefs.remove(AppConstants.keyRefreshToken);
    emit(AuthUnauthenticated());
  }
}
