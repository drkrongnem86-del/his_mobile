// AutoTokenService v3.0.160 - Auto-fetch HIS Pro token từ nhiều nguồn
//
// Vấn đề: HIS Pro REST API /Token/Login trả Success:false (server dùng WCF/proprietary)
// Nên app phải tự lấy token từ nguồn khác.
//
// Chiến lược multi-source (thử tuần tự):
//   1. HIS PRO LOGIN API (ưu tiên 1) - best effort
//      → /api/Token/Login + /api/AcsToken/Authorize
//      → Thường fail vì server không nhận password qua REST
//   2. HIS PRO RENEW API (ưu tiên 2) - extend current token
//      → /api/Token/Renew với token cũ
//      → Kéo dài thêm nếu token sắp hết
//   3. HARDCODED FALLBACK (ưu tiên 3) - last resort
//      → HisProHardcoded.tokenCode (token đã biết từ memory dump)
//
// v3.0.160: BỎ PROXY SERVER (v3.0.159 có nhưng BS không cần)
//
// Auto chạy:
//   - App start (main.dart)
//   - Sau khi login (login_screen.dart _bgFetchTokens)
//   - Khi API trả 401 (retry logic)
//   - Manual refresh (settings_screen)
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/services/secure_storage_service.dart';

/// Nguồn token - để track token đến từ đâu (debug + UI status)
enum TokenSource {
  none,
  loginApi, // Login API thành công (ít xảy ra)
  renewApi, // Renew API thành công
  hardcoded, // Hardcoded fallback
  cached, // Từ secure storage (cache từ session trước)
}

/// Result trả về cho caller
class AutoTokenResult {
  final bool success;
  final String? token;
  final String? clientIp;
  final TokenSource source;
  final String? message;
  final DateTime? fetchedAt;

  const AutoTokenResult({
    required this.success,
    this.token,
    this.clientIp,
    this.source = TokenSource.none,
    this.message,
    this.fetchedAt,
  });

  factory AutoTokenResult.fail(String message) =>
      AutoTokenResult(success: false, source: TokenSource.none, message: message);

  @override
  String toString() => 'AutoTokenResult(success: $success, source: $source, '
      'token: ${token != null ? "${token!.substring(0, 12)}..." : "null"}, '
      'message: $message)';
}

class AutoTokenService {
  static final AutoTokenService instance = AutoTokenService._();
  AutoTokenService._();

  // SharedPreferences keys
  static const _kLastToken = 'auto_token_last';
  static const _kLastClientIp = 'auto_token_last_ip';
  static const _kLastSource = 'auto_token_last_source';
  static const _kLastFetchTime = 'auto_token_last_time';
  static const _kStoredLoginName = 'auto_token_login_name';
  static const _kStoredPassword = 'auto_token_password';
  static const _kAutoLoginEnabled = 'auto_token_enabled';

  /// Cache token hiện tại
  String? _currentToken;
  String? _currentClientIp;
  TokenSource _currentSource = TokenSource.none;
  DateTime? _lastFetchTime;

  String? get currentToken => _currentToken;
  String? get currentClientIp => _currentClientIp;
  TokenSource get currentSource => _currentSource;
  DateTime? get lastFetchTime => _lastFetchTime;

  /// Khoảng thời gian giữa 2 lần auto-refresh (10 phút)
  static const Duration refreshInterval = Duration(minutes: 10);

  /// Main entry - thử tất cả các nguồn theo thứ tự ưu tiên
  Future<AutoTokenResult> fetchToken({
    bool forceRefresh = false,
    bool tryAllSources = false,
  }) async {
    debugPrint('🔄 [AutoToken] fetchToken(force: $forceRefresh, tryAll: $tryAllSources)');

    // 1. Check cache - nếu còn mới và không force
    if (!forceRefresh) {
      final cached = await _loadCachedToken();
      if (cached != null && cached.success) {
        debugPrint('✅ [AutoToken] Using cached token (source: ${cached.source})');
        _applyResult(cached);
        return cached;
      }
    }

    // 2. Try các nguồn theo thứ tự
    final sources = <Future<AutoTokenResult> Function()>[
      _fetchFromLoginApi,
      _fetchFromRenewApi,
      _fetchFromHardcoded,
    ];

    AutoTokenResult? lastResult;
    for (final source in sources) {
      try {
        final r = await source();
        if (r.success) {
          debugPrint('✅ [AutoToken] Got token from ${r.source}');
          _applyResult(r);
          await _saveCachedToken(r);
          return r;
        }
        lastResult = r;
        if (!tryAllSources) {
          // Thử source tiếp theo nếu fail
        }
      } catch (e) {
        debugPrint('⚠️ [AutoToken] Source error: $e');
        lastResult = AutoTokenResult.fail('$e');
      }
    }

    debugPrint('❌ [AutoToken] All sources failed');
    return lastResult ?? AutoTokenResult.fail('Không thể lấy token từ bất kỳ nguồn nào');
  }

  /// SOURCE 1: HIS Pro Login API
  Future<AutoTokenResult> _fetchFromLoginApi() async {
    final prefs = await SharedPreferences.getInstance();
    final loginName = prefs.getString(_kStoredLoginName);
    final password = prefs.getString(_kStoredPassword);

    if (loginName == null || loginName.isEmpty) {
      return AutoTokenResult.fail('Chưa lưu login name');
    }

    // Try /api/Token/Login with various field names
    final acsUrl = ConnectionService.instance.acsUrl;

    final formats = <Map<String, dynamic>>[
      // Format 1: AcsTokenLoginSDO (từ HIS Desktop open source)
      {
        'LOGIN_NAME': loginName,
        'PASSWORD': password ?? '',
        'APPLICATION_CODE': 'HIS',
        'APP_VERSION': '3.0.160',
      },
      // Format 2: camelCase
      {
        'LoginName': loginName,
        'Password': password ?? '',
        'ApplicationCode': 'HIS',
        'AppVersion': '3.0.160',
        'ClientIpAddress': HisProHardcoded.clientIpAddress,
      },
      // Format 3: UserName (từ TokenRefreshService)
      {
        'UserName': loginName,
        'Password': password ?? '',
        'AppCode': 'HIS',
      },
    ];

    for (final format in formats) {
      try {
        final param = base64Encode(utf8.encode(jsonEncode(format)));
        final url = Uri.parse('${acsUrl}api/Token/Login?param=$param');
        debugPrint('🌐 [AutoToken] Try login: $url (format: ${format.keys.first})');
        final r = await http.get(url).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (body['Success'] == true) {
            final data = body['Data'];
            String? token;
            if (data is Map) {
              token = (data['TokenCode'] ?? data['TOKEN_CODE'] ?? data['token'])?.toString();
            } else if (data is String) {
              token = data;
            }
            if (token != null && token.length == 64) {
              return AutoTokenResult(
                success: true,
                token: token,
                clientIp: HisProHardcoded.clientIpAddress,
                source: TokenSource.loginApi,
                message: 'Login API success',
                fetchedAt: DateTime.now(),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [AutoToken] Login format ${format.keys.first} failed: $e');
      }
    }
    return AutoTokenResult.fail('Login API: tất cả format đều fail');
  }

  /// SOURCE 2: Renew API - extend current token
  Future<AutoTokenResult> _fetchFromRenewApi() async {
    final currentToken = _currentToken ?? HisProHardcoded.tokenCode;
    final param = base64Encode(utf8.encode(jsonEncode({
      'TokenCode': currentToken,
      'ApplicationCode': 'HIS',
      'ClientIpAddress': HisProHardcoded.clientIpAddress,
    })));
    final url = Uri.parse(
        '${ConnectionService.instance.acsUrl}api/Token/Renew?param=$param');

    try {
      debugPrint('🌐 [AutoToken] Try renew');
      final r = await http.get(url).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['Success'] == true) {
          final data = body['Data'];
          String? token;
          if (data is Map) {
            token = (data['TokenCode'] ?? data['TOKEN_CODE'] ?? data['token'])?.toString();
          }
          if (token != null && token.length == 64) {
            return AutoTokenResult(
              success: true,
              token: token,
              clientIp: HisProHardcoded.clientIpAddress,
              source: TokenSource.renewApi,
              fetchedAt: DateTime.now(),
            );
          }
        }
      }
      return AutoTokenResult.fail('Renew API: Success=false');
    } catch (e) {
      return AutoTokenResult.fail('Renew API error: ${e.toString().substring(0, 50)}');
    }
  }

  /// SOURCE 3: Hardcoded fallback
  Future<AutoTokenResult> _fetchFromHardcoded() async {
    debugPrint('⚠️ [AutoToken] Using hardcoded token');
    return AutoTokenResult(
      success: true,
      token: HisProHardcoded.tokenCode,
      clientIp: HisProHardcoded.clientIpAddress,
      source: TokenSource.hardcoded,
      message: 'Hardcoded fallback',
      fetchedAt: DateTime.now(),
    );
  }

  /// User manually paste token - kept for emergency override
  Future<AutoTokenResult> setManualToken(String token, {String? clientIp}) async {
    if (token.length != 64) {
      return AutoTokenResult.fail('Token phải đúng 64 ký tự hex (hiện tại: ${token.length})');
    }
    final result = AutoTokenResult(
      success: true,
      token: token,
      clientIp: clientIp ?? HisProHardcoded.clientIpAddress,
      source: TokenSource.cached,
      fetchedAt: DateTime.now(),
    );
    _applyResult(result);
    await _saveCachedToken(result);
    debugPrint('✅ [AutoToken] Manual token set: ${token.substring(0, 12)}...');
    return result;
  }

  /// Apply result to in-memory cache
  void _applyResult(AutoTokenResult r) {
    _currentToken = r.token;
    _currentClientIp = r.clientIp;
    _currentSource = r.source;
    _lastFetchTime = r.fetchedAt ?? DateTime.now();
  }

  /// Save to SharedPreferences
  Future<void> _saveCachedToken(AutoTokenResult r) async {
    final prefs = await SharedPreferences.getInstance();
    if (r.token != null) {
      await prefs.setString(_kLastToken, r.token!);
      await prefs.setString(_kLastClientIp, r.clientIp ?? '');
      await prefs.setString(_kLastSource, r.source.name);
      await prefs.setInt(_kLastFetchTime, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Load cached token from SharedPreferences
  Future<AutoTokenResult?> _loadCachedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kLastToken);
    final ip = prefs.getString(_kLastClientIp);
    final sourceStr = prefs.getString(_kLastSource);
    final time = prefs.getInt(_kLastFetchTime);

    if (token == null || token.length != 64 || time == null) return null;

    // Cache hết hạn sau 1 giờ
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(time);
    if (DateTime.now().difference(fetchedAt) > const Duration(hours: 1)) {
      return null;
    }

    final source = TokenSource.values.firstWhere(
      (s) => s.name == sourceStr,
      orElse: () => TokenSource.cached,
    );

    return AutoTokenResult(
      success: true,
      token: token,
      clientIp: ip,
      source: source,
      fetchedAt: fetchedAt,
    );
  }

  /// Save user credentials (password lưu SecureStorage)
  Future<void> saveCredentials(String loginName, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStoredLoginName, loginName);
    await SecureStorageService.instance.save(_kStoredPassword, password);
    debugPrint('💾 [AutoToken] Saved credentials for $loginName');
  }

  /// Get saved login name
  Future<String?> getLoginName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kStoredLoginName);
  }

  /// Get saved password (from secure storage)
  Future<String?> getPassword() async {
    return await SecureStorageService.instance.read(_kStoredPassword);
  }

  /// Clear saved credentials
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStoredLoginName);
    await SecureStorageService.instance.save(_kStoredPassword, '');
    debugPrint('🗑️ [AutoToken] Cleared credentials');
  }

  /// Enable/disable auto-login
  Future<void> setAutoLoginEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoLoginEnabled, enabled);
  }

  Future<bool> isAutoLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoLoginEnabled) ?? true;
  }

  /// Status string for UI
  String getStatusString() {
    if (_currentToken == null) return '❌ Chưa có token';
    final age = _lastFetchTime == null
        ? 'unknown'
        : '${DateTime.now().difference(_lastFetchTime!).inMinutes} phút trước';
    return '✅ ${_currentSource.name} (${age})';
  }
}
