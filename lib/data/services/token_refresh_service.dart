// v3.0.59: Token Refresh Service
// Tự động refresh Token EMR khi sắp hết hạn
// - Lưu expires_in + last_refresh vào SharedPreferences
// - Trước mỗi API call quan trọng: check expiry → refresh nếu < 5 phút
// - Manual refresh: gọi refreshToken() trực tiếp (button "Làm mới Token" trong Settings)

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/services/secure_storage_service.dart';

class TokenInfo {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String loginName;

  TokenInfo({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.loginName,
  });

  bool get isExpiringSoon {
    final now = DateTime.now();
    return expiresAt.difference(now) < const Duration(minutes: 5);
  }

  bool get isExpired {
    return DateTime.now().isAfter(expiresAt);
  }

  Duration get timeToExpire => expiresAt.difference(DateTime.now());
}

class TokenRefreshService {
  static final TokenRefreshService instance = TokenRefreshService._();
  TokenRefreshService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  static const _kTokenExpiresAt = 'emr_token_expires_at';
  static const _kRefreshToken = 'emr_refresh_token';
  static const _kLastRefresh = 'emr_last_refresh';

  /// Login lấy token mới
  /// POST /api/Token/Login { UserName, Password, AppCode: "HIS" }
  /// Response: { access_token, refresh_token, expires_in (seconds) }
  Future<TokenInfo?> login({
    required String loginName,
    required String password,
    required String baseUrl,  // vd: http://171.15.0.9
  }) async {
    try {
      debugPrint('[TokenRefresh] Login to $baseUrl as $loginName ...');
      final response = await _dio.post(
        '$baseUrl/api/Token/Login',
        data: {
          'UserName': loginName,
          'Password': password,
          'AppCode': 'HIS',
        },
      );
      if (response.statusCode != 200) {
        debugPrint('[TokenRefresh] Login failed: HTTP ${response.statusCode}');
        return null;
      }
      final data = response.data is Map ? response.data as Map<String, dynamic> : null;
      if (data == null) {
        debugPrint('[TokenRefresh] Invalid response: ${response.data}');
        return null;
      }
      // Parse response (HIS Pro có thể trả {Data: {...}} hoặc trả thẳng)
      final Map<String, dynamic> tokenData = data['Data'] is Map ? data['Data'] as Map<String, dynamic> : data;
      final accessToken = tokenData['access_token']?.toString() ?? '';
      final refreshToken = tokenData['refresh_token']?.toString();
      final expiresIn = (tokenData['expires_in'] as num?)?.toInt() ?? 3600;  // Default 1h
      if (accessToken.isEmpty) {
        debugPrint('[TokenRefresh] No access_token in response');
        return null;
      }
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      debugPrint('[TokenRefresh] ✅ Login OK: token ${accessToken.substring(0, 8)}… expires at $expiresAt');
      // Lưu vào prefs + secure storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTokenExpiresAt, expiresAt.millisecondsSinceEpoch);
      if (refreshToken != null) {
        await prefs.setString(_kRefreshToken, refreshToken);
        await SecureStorageService.instance.save(_kRefreshToken, refreshToken);
      }
      await prefs.setInt(_kLastRefresh, DateTime.now().millisecondsSinceEpoch);
      return TokenInfo(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        loginName: loginName,
      );
    } catch (e) {
      debugPrint('[TokenRefresh] Login error: $e');
      return null;
    }
  }

  /// Refresh token bằng refresh_token
  /// POST /api/Token/Renew { refresh_token }
  Future<TokenInfo?> refresh(String refreshToken, String baseUrl) async {
    try {
      debugPrint('[TokenRefresh] Renewing token...');
      final response = await _dio.post(
        '$baseUrl/api/Token/Renew',
        data: {'refresh_token': refreshToken},
      );
      if (response.statusCode != 200) {
        debugPrint('[TokenRefresh] Renew failed: HTTP ${response.statusCode}');
        return null;
      }
      final data = response.data is Map ? response.data as Map<String, dynamic> : null;
      if (data == null) return null;
      final tokenData = data['Data'] is Map ? data['Data'] as Map<String, dynamic> : data;
      final accessToken = tokenData['access_token']?.toString() ?? '';
      final newRefreshToken = tokenData['refresh_token']?.toString() ?? refreshToken;
      final expiresIn = (tokenData['expires_in'] as num?)?.toInt() ?? 3600;
      if (accessToken.isEmpty) return null;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTokenExpiresAt, expiresAt.millisecondsSinceEpoch);
      await prefs.setString(_kRefreshToken, newRefreshToken);
      await prefs.setInt(_kLastRefresh, DateTime.now().millisecondsSinceEpoch);
      debugPrint('[TokenRefresh] ✅ Renew OK: token expires at $expiresAt');
      return TokenInfo(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
        expiresAt: expiresAt,
        loginName: '',
      );
    } catch (e) {
      debugPrint('[TokenRefresh] Renew error: $e');
      return null;
    }
  }

  /// Lấy thông tin token hiện tại từ cache
  Future<TokenInfo?> getCurrentToken() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenStr = prefs.getString('his_pro_token_code');
    final expiresAtMs = prefs.getInt(_kTokenExpiresAt);
    if (tokenStr == null || tokenStr.isEmpty) return null;
    return TokenInfo(
      accessToken: tokenStr,
      refreshToken: prefs.getString(_kRefreshToken),
      expiresAt: expiresAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
          : DateTime.now().add(const Duration(hours: 1)),
      loginName: '',
    );
  }

  /// Check xem token có sắp hết hạn không (dùng trước khi gọi API quan trọng)
  Future<bool> isExpiringSoon() async {
    final info = await getCurrentToken();
    return info?.isExpiringSoon ?? true;
  }
}
