// v3.0.93: EmrScanTokenService - Tích hợp EmrScanApp Windows service
//
// EmrScanApp (project riêng của BS) chạy Python HTTP service trên port 18080
// tự động fetch + refresh HIS Pro token từ HISLoginTool.exe
//
// Workflow:
//   - Phone gọi http://<HIS-WINDOWS-IP>:18080/token
//   - Service trả về JSON {token, user, user_name, expire_time, last_refresh, ...}
//   - Phone tự lưu token vào ThongkeAuthService (giống HisProxyTokenService)
//
// Endpoints (từ windows-service/his_token_service.py):
//   GET /health          - health check
//   GET /token           - get current token (auto-refresh if needed)
//   GET /login?user=X&pass=Y - force re-login
//
// Khác với HisProxyTokenService (port 9999, đọc log file):
//   - EmrScanApp service: gọi HISLoginTool.exe chuẩn HIS
//   - HIS Mobile proxy: đọc log file từ HIS.exe (có thể bị mất khi HIS restart)

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';

class EmrScanTokenInfo {
  final bool reachable;
  final bool hasToken;
  final String? token;
  final String? user;
  final String? userName;
  final String? expireTime;
  final String? lastRefresh;
  final String? error;
  final String? pcUrl;

  /// Số giây còn lại trước khi expire
  /// Hỗ trợ format từ HIS: "M/d/yyyy h:m:s a" (vd: "8/15/2026 2:30:00 PM")
  /// hoặc ISO: "yyyy-MM-dd HH:mm:ss"
  int? get expiresInSeconds {
    if (expireTime == null) return null;
    final t = expireTime!.trim();
    DateTime? dt;
    // Thử ISO format trước (DateTime.parse hỗ trợ tốt)
    dt = DateTime.tryParse(t);
    // Nếu fail, thử format HIS "M/d/yyyy h:m:s a" (12h with AM/PM)
    if (dt == null) {
      try {
        final parts = t.split(' ');
        if (parts.length >= 3) {
          final dateParts = parts[0].split('/');
          final timeParts = parts[1].split(':');
          final ampm = parts[2].toUpperCase();
          int hour = int.parse(timeParts[0]);
          if (ampm == 'PM' && hour != 12) hour += 12;
          if (ampm == 'AM' && hour == 12) hour = 0;
          dt = DateTime(
            int.parse(dateParts[2]),
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            hour,
            int.parse(timeParts[1]),
            int.parse(timeParts[2]),
          );
        }
      } catch (_) {
        return null;
      }
    }
    if (dt == null) return null;
    return dt.difference(DateTime.now()).inSeconds;
  }

  const EmrScanTokenInfo({
    required this.reachable,
    this.hasToken = false,
    this.token,
    this.user,
    this.userName,
    this.expireTime,
    this.lastRefresh,
    this.error,
    this.pcUrl,
  });

  factory EmrScanTokenInfo.unreachable(String url, String error) =>
      EmrScanTokenInfo(reachable: false, pcUrl: url, error: error);
}

class EmrScanTokenService {
  static final EmrScanTokenService instance = EmrScanTokenService._();
  EmrScanTokenService._();

  static const String _kServiceUrlKey = 'emrscan_service_url';
  static const String _kLastFetchKey = 'emrscan_last_fetch';

  /// EmrScanApp service URL candidates (port 18080)
  static const List<String> defaultServiceUrls = [
    'http://172.16.200.109:18080',  // Default HIS Windows
    'http://172.16.1.12:18080',     // LAN server
    'http://localhost:18080',        // Localhost
  ];

  Future<String> getServiceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kServiceUrlKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return defaultServiceUrls.first;
  }

  Future<void> setServiceUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServiceUrlKey, url);
  }

  Future<DateTime?> getLastFetchTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kLastFetchKey);
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Ping service health
  Future<EmrScanTokenInfo> ping({String? url}) async {
    final svcUrl = url ?? await getServiceUrl();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final r = await dio.get('$svcUrl/health');
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        return EmrScanTokenInfo(
          reachable: true,
          hasToken: m['token_available'] == true,
          user: m['user']?.toString(),
          expireTime: m['expire_time']?.toString(),
          lastRefresh: m['last_refresh']?.toString(),
          pcUrl: svcUrl,
        );
      }
      return EmrScanTokenInfo.unreachable(svcUrl, 'HTTP ${r.statusCode}');
    } on DioException catch (e) {
      debugPrint('❌ EmrScanApp ping fail: $svcUrl (${e.type})');
      return EmrScanTokenInfo.unreachable(svcUrl, e.message ?? 'Connection failed');
    }
  }

  /// Lấy token từ EmrScanApp service (auto-refresh nếu expired)
  /// Lưu vào ThongkeAuthService nếu thành công
  Future<EmrScanTokenInfo> fetchAndSaveToken({String? url, bool forceLogin = false}) async {
    final svcUrl = url ?? await getServiceUrl();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      String endpoint = forceLogin ? '$svcUrl/login' : '$svcUrl/token';
      final r = await dio.get(endpoint);
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        final info = EmrScanTokenInfo(
          reachable: true,
          hasToken: m['token'] is String,
          token: m['token']?.toString(),
          user: m['user']?.toString(),
          userName: m['user_name']?.toString(),
          expireTime: m['expire_time']?.toString(),
          lastRefresh: m['last_refresh']?.toString(),
          pcUrl: svcUrl,
        );
        if (info.hasToken && info.token != null) {
          // Lưu token qua ThongkeAuthService (v3.0.93: source = emrscan)
          await ThongkeAuthService.instance.setHisProToken(info.token!, source: 'emrscan');
          await ThongkeAuthService.instance.loadHisProToken();
          // Lưu thời gian fetch
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLastFetchKey, DateTime.now().toIso8601String());
          debugPrint('✅ EmrScanApp token fetched & saved (${info.token!.length} chars) from $svcUrl');
        }
        return info;
      }
      if (r.statusCode == 503) {
        return EmrScanTokenInfo.unreachable(
            svcUrl, 'Service has no active token. Try /login?user=X&pass=Y');
      }
      return EmrScanTokenInfo.unreachable(svcUrl, 'HTTP ${r.statusCode}');
    } on DioException catch (e) {
      debugPrint('❌ EmrScanApp fetchToken fail: $svcUrl (${e.type}: ${e.message})');
      return EmrScanTokenInfo.unreachable(svcUrl, e.message ?? 'Connection failed');
    }
  }

  /// Force re-login (gọi /login với user + pass từ main login)
  Future<EmrScanTokenInfo> forceLogin({
    required String username,
    required String password,
    String? url,
  }) async {
    final svcUrl = url ?? await getServiceUrl();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final r = await dio.get(
        '$svcUrl/login',
        queryParameters: {'user': username, 'pass': password},
      );
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        final info = EmrScanTokenInfo(
          reachable: true,
          hasToken: m['token'] is String,
          token: m['token']?.toString(),
          user: (m['user'] is Map)
              ? (m['user']['login_name']?.toString())
              : m['user']?.toString(),
          userName: m['user_name']?.toString(),
          expireTime: m['expire_time']?.toString(),
          lastRefresh: DateTime.now().toIso8601String(),
          pcUrl: svcUrl,
        );
        if (info.hasToken && info.token != null) {
          // v3.0.93: source = emrscan (force login cũng từ EmrScanApp)
          await ThongkeAuthService.instance.setHisProToken(info.token!, source: 'emrscan');
          await ThongkeAuthService.instance.loadHisProToken();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLastFetchKey, DateTime.now().toIso8601String());
        }
        return info;
      }
      final err = r.data is Map
          ? r.data['error']?.toString() ?? 'Login failed'
          : 'HTTP ${r.statusCode}';
      return EmrScanTokenInfo.unreachable(svcUrl, err);
    } on DioException catch (e) {
      return EmrScanTokenInfo.unreachable(svcUrl, e.message ?? 'Connection failed');
    }
  }
}
