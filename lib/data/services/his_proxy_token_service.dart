// v3.0.82: HisProxyTokenService - Auto-fetch Bearer token qua local proxy
//
// Workflow:
//   - Phone gọi http://{PC_IP}:9999/get-his-token
//   - Proxy (chạy trên PC) đọc D:\Soft\HISPRO_THAT\Logs\LogSystem.txt
//   - Extract Bearer token từ dòng ___dti:"...|<TOKEN>|..." mới nhất
//   - Trả về JSON {token, source_file, found_at, age_seconds}
//   - Phone tự động lưu token vào SharedPreferences (qua ThongkeAuthService)
//
// PC IP candidates (auto-detect):
//   - 172.16.200.109 (default proxy PC mode - port 9999)
//   - User có thể tự cấu hình qua Settings
//
// Setup:
//   - Trên PC: chạy python tools/his_proxy_server.py (port 9999)
//   - Phone cùng WiFi/LAN với PC

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';

class HisProxyTokenStatus {
  final bool reachable;
  final bool hasToken;
  final String? token;
  final String? tokenPreview;
  final int? tokenLength;
  final String? source;
  final String? sourceFile;
  final String? foundAt;
  final int? ageSeconds;
  final String? error;
  final String? pcUrl;

  const HisProxyTokenStatus({
    required this.reachable,
    this.hasToken = false,
    this.token,
    this.tokenPreview,
    this.tokenLength,
    this.source,
    this.sourceFile,
    this.foundAt,
    this.ageSeconds,
    this.error,
    this.pcUrl,
  });

  factory HisProxyTokenStatus.unreachable(String url, String error) =>
      HisProxyTokenStatus(reachable: false, pcUrl: url, error: error);
}

class HisProxyTokenService {
  static final HisProxyTokenService instance = HisProxyTokenService._();
  HisProxyTokenService._();

  static const String _kProxyUrlKey = 'his_proxy_url';
  static const String _kAutoFetchKey = 'his_proxy_auto_fetch';
  static const String _kLastFetchKey = 'his_proxy_last_fetch';

  /// PC IP candidates - thử lần lượt
  static const List<String> defaultPcUrls = [
    'http://172.16.200.109:9999',  // Default proxy PC mode
    'http://172.16.1.12:9999',     // LAN server (BV)
    'http://192.168.1.1:9999',     // Common home router
  ];

  /// Lấy URL proxy đã lưu hoặc trả về default đầu tiên
  Future<String> getProxyUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kProxyUrlKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return defaultPcUrls.first;
  }

  /// Set URL proxy (lưu vào SharedPreferences)
  Future<void> setProxyUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProxyUrlKey, url);
  }

  /// Auto-fetch on 401? (default true)
  Future<bool> get autoFetchEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoFetchKey) ?? true;
  }

  Future<void> setAutoFetchEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoFetchKey, enabled);
  }

  /// Ping proxy - check reachable
  Future<HisProxyTokenStatus> ping({String? url}) async {
    final pcUrl = url ?? await getProxyUrl();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final r = await dio.get('$pcUrl/ping');
      if (r.statusCode == 200) {
        debugPrint('✅ Proxy ping OK: $pcUrl');
        return HisProxyTokenStatus(reachable: true, pcUrl: pcUrl);
      }
      return HisProxyTokenStatus.unreachable(pcUrl, 'HTTP ${r.statusCode}');
    } on DioException catch (e) {
      debugPrint('❌ Proxy ping fail: $pcUrl (${e.type})');
      return HisProxyTokenStatus.unreachable(pcUrl, e.message ?? 'Connection failed');
    }
  }

  /// Lấy token status (info only, no save)
  Future<HisProxyTokenStatus> getStatus({String? url}) async {
    final pcUrl = url ?? await getProxyUrl();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final r = await dio.get('$pcUrl/get-his-token-status');
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        return HisProxyTokenStatus(
          reachable: true,
          hasToken: m['has_token'] == true,
          token: m['token']?.toString(),
          tokenPreview: m['token_preview']?.toString(),
          tokenLength: m['token_length'] as int?,
          source: m['source']?.toString(),
          sourceFile: m['source_file']?.toString(),
          foundAt: m['found_at']?.toString(),
          ageSeconds: m['age_seconds'] as int?,
          pcUrl: pcUrl,
        );
      }
      return HisProxyTokenStatus.unreachable(pcUrl, 'HTTP ${r.statusCode}');
    } on DioException catch (e) {
      return HisProxyTokenStatus.unreachable(pcUrl, e.message ?? 'Connection failed');
    }
  }

  /// Lấy token từ proxy và lưu vào ThongkeAuthService
  /// Returns: token string nếu OK, null nếu fail
  Future<String?> fetchAndSaveToken({String? url}) async {
    final pcUrl = url ?? await getProxyUrl();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final r = await dio.get('$pcUrl/get-his-token');
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        if (m['success'] == true && m['token'] is String) {
          final token = m['token'] as String;
          // Lưu token qua ThongkeAuthService (v3.0.93: đánh dấu source = hisproxy)
          await ThongkeAuthService.instance.setHisProToken(token, source: 'hisproxy');
          await ThongkeAuthService.instance.loadHisProToken();
          // Lưu thời gian fetch
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLastFetchKey, DateTime.now().toIso8601String());
          debugPrint('✅ Token fetched & saved (${token.length} chars) from $pcUrl');
          return token;
        }
      }
      debugPrint('❌ fetchAndSaveToken: bad response from $pcUrl');
      return null;
    } on DioException catch (e) {
      debugPrint('❌ fetchAndSaveToken: $pcUrl (${e.type}: ${e.message})');
      return null;
    }
  }

  /// Last fetch timestamp
  Future<DateTime?> getLastFetchTime() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kLastFetchKey);
    if (s == null) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }
}
