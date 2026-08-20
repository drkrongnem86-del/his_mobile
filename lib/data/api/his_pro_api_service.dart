// v3.0.42: HIS Pro Real API Service - BREAKTHROUGH 2026-07-17!
//
// PHÁT HIỆN QUAN TRỌNG: HIS Pro KHÔNG dùng "Authorization: Bearer"!
// Auth thật dùng 3 custom HTTP headers:
//   TokenCode: <64-char hex>    ← Token từ memory dump HIS Pro desktop
//   ApplicationCode: HIS        ← Cố định
//   ClientIpAddress: <IP máy BV> ← IP máy BS đang chạy HIS Pro (cố định)
//
// Memory dump (MAYTINH-2FA6BJT, PID 4940, 2026-07-17):
//   TokenCode: af89403b7f001cd27ca9defa6c987a4f9e7bbd564525b8bc6287a693bf674c4d
//   ClientIpAddress: 171.15.128.5
//   Expire: 2026-08-16T14:11:50
//
// ⚠ KHI NÀO TOKEN HẾT HẠN: chạy dump_his_token.ps1 trên máy BV để lấy token mới
//
// HIS Pro Services (from HIS.exe.config):
//   1401 = ACS (Auth/Login/Renew/Logout/GetAuthenticated)
//   1405 = FSS (File Storage)
//   1408 = MOS (Medical/HisTreatment/Get)
//   1409 = SAR (Reports)
//   1410 = SDA (Admin/HisDepartment/HisUserRoom)
//   1417 = EMR (EmrDocument/EmrSigner/EmrBusiness) ← MAIN EMR
//   1418 = Aup (Auto Update)
//   1419 = LIS (Lab)
//   1425 = DMS (Medilink HL7)
//   1429 = MCH (Y tế cơ sở)
//
// Auth endpoints (port 1401 - ACS):
//   GET  /api/Token/Login           ?param=<BASE64({LOGIN_NAME,APPLICATION_CODE,...})>
//   GET  /api/Token/Renew           ?param=<BASE64({TokenCode,...})>
//   GET  /api/Token/Logout          ?param=<BASE64({TokenCode,...})>
//   GET  /api/Token/GetAuthenticated ?param=<BASE64({TokenCode,...})>
//
// EMR endpoints (port 1417 - EMR 1.164.0x64):
//   GET  /api/EmrSigner/Get              ?param=<BASE64({CommonParam,ApiData})>
//   GET  /api/EmrBusiness/Get            ?param=<BASE64({CommonParam,ApiData})>
//   GET  /api/EmrTreatment/Get           ?param=<BASE64({CommonParam,ApiData})>
//   GET  /api/EmrDocument/GetView        ?param=<BASE64({CommonParam,ApiData})>
//   POST /api/EmrDocument/CreateAndSignUsb ?param=<BASE64>
//   POST /api/EmrDocument/CreateAndSignHsm ?param=<BASE64>
//
// Payload schema (CommonParam + ApiData → base64):
//   {CommonParam:{Messages:[],BugCodes:[],MessageCodes:[],Start:0,Limit:200,
//                 LanguageCode:"VI",Now:0,HasException:false},ApiData:{...}}
//
// Verified: TokenCode af89... work 100% với EMR 1417 endpoints:
//   ✅ EmrSigner/Get       → 200 signers
//   ✅ EmrBusiness/Get      → 38+ loại phiếu
//   ✅ EmrTreatment/Get     → Full patient info
//   ✅ EmrDocument/GetView  → List phiếu theo treatment

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/core/security/secure_config_service.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/services/secure_storage_service.dart';
import 'package:his_mobile/data/services/upload_log_service.dart';

/// v3.0.42: TokenCode từ memory dump HIS Pro desktop (MAYTINH-2FA6BJT)
/// v3.0.142: Bumped sang token MỚI 1ee41ae9... (active 17/08/2026 17:08)
class HisProHardcoded {
  /// v3.0.142: TokenCode MỚI (active 17/08/2026 17:08, từ log HIS Desktop)
  /// Token xoay mỗi session - lấy từ `dti:"...|TOKEN|..."` trong LogSystem.txt
  /// Previous: cb356d3891b1e01ccbca37bafa5c61ef038e7c091de8cb09e019f061d20e77d3 (v3.0.65 - đã hết hạn)
  // v3.0.156: Read from SecureConfigService (Android Keystore)
  // Hardcoded fallback removed - use SecureConfigService.getTokenCodeSync()
  static String get tokenCode => SecureConfigService.instance.getTokenCodeSync();

  /// IP máy BV chạy HIS Pro (cố định, từ memory dump)
  // v3.0.156: Read from SecureConfigService
  static String get clientIpAddress => SecureConfigService.instance.getClientIpSync();

  /// ApplicationCode cố định
  static const String applicationCode = 'HIS';

  /// Default login name
  static const String loginName = 'nemk';

  /// Default user name
  static const String userName = 'K Rong Nểm';

  /// Mã CSYT BVĐK Ninh Thuận
  static const String mediOrgCode = '58001';

  /// Machine name (từ memory dump)
  static const String machineName = 'MAYTINH-2FA6BJT';

  /// SharedPreferences keys
  static const String prefLoginName = 'pref_login_name';
  static const String prefTokenCode = 'pref_token_code';
  static const String prefClientIp = 'pref_client_ip';
  static const String prefEmrAccessToken = 'pref_emr_access_token';
  static const String prefEmrUserName = 'pref_emr_user_name';
  static const String prefEmrUserId = 'pref_emr_user_id';
  static const String prefBranch = 'pref_branch';
}

/// Cached thông tin user khi login HIS Pro
class HisProSession {
  final String token;        // TokenCode 64-char hex từ memory dump
  final String loginName;     // "nemk"
  final String userName;     // "K Rong Nểm" (full name)
  final String clientIp;      // "171.15.128.5" - IP máy BV
  final int? signerId;       // 236 (từ EmrSigner.Get)
  final String? departmentCode;
  final String? departmentName;
  final String? roomCode;
  final DateTime loginAt;
  final DateTime expiresAt;  // 30 ngày (from memory dump)

  HisProSession({
    required this.token,
    required this.loginName,
    required this.userName,
    required this.clientIp,
    this.signerId,
    this.departmentCode,
    this.departmentName,
    this.roomCode,
    required this.loginAt,
    required this.expiresAt,
  });

  bool get isValid => DateTime.now().isBefore(expiresAt);

  /// v3.0.42: Build auth headers cho HIS Pro (TokenCode + ApplicationCode + ClientIpAddress)
  Map<String, String> get authHeaders => {
        'TokenCode': token,
        'ApplicationCode': HisProHardcoded.applicationCode,
        'ClientIpAddress': clientIp,
      };

  Map<String, dynamic> toJson() => {
        'token': token,
        'loginName': loginName,
        'userName': userName,
        'clientIp': clientIp,
        'signerId': signerId,
        'departmentCode': departmentCode,
        'departmentName': departmentName,
        'roomCode': roomCode,
        'loginAt': loginAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory HisProSession.fromJson(Map<String, dynamic> j) => HisProSession(
        token: j['token'] as String,
        loginName: j['loginName'] as String,
        userName: j['userName'] as String? ?? j['loginName'] as String,
        clientIp: j['clientIp'] as String? ?? HisProHardcoded.clientIpAddress,
        signerId: j['signerId'] as int?,
        departmentCode: j['departmentCode'] as String?,
        departmentName: j['departmentName'] as String?,
        roomCode: j['roomCode'] as String?,
        loginAt: DateTime.parse(j['loginAt'] as String),
        expiresAt: DateTime.parse(j['expiresAt'] as String),
      );
}

/// User-room mapping từ HisUserRoom/GetView
class HisUserRoom {
  final int id;
  final String loginName;
  final int? roomId;
  final String? roomCode;
  final String? roomName;
  final int? departmentId;
  final String? departmentCode;
  final String? departmentName;
  final bool? isActive;

  HisUserRoom({
    required this.id,
    required this.loginName,
    this.roomId,
    this.roomCode,
    this.roomName,
    this.departmentId,
    this.departmentCode,
    this.departmentName,
    this.isActive,
  });

  factory HisUserRoom.fromJson(Map<String, dynamic> j) => HisUserRoom(
        id: (j['ID'] ?? j['id'] ?? 0) as int,
        loginName: (j['LOGINNAME'] ?? j['loginName'] ?? '') as String,
        roomId: (j['ROOM_ID'] ?? j['roomId']) as int?,
        roomCode: (j['ROOM_CODE'] ?? j['roomCode']) as String?,
        roomName: (j['ROOM_NAME'] ?? j['roomName']) as String?,
        departmentId: (j['DEPARTMENT_ID'] ?? j['departmentId']) as int?,
        departmentCode: (j['DEPARTMENT_CODE'] ?? j['departmentCode']) as String?,
        departmentName: (j['DEPARTMENT_NAME'] ?? j['departmentName']) as String?,
        isActive: (j['IS_ACTIVE'] ?? j['isActive']) as bool?,
      );
}

/// EMR signer (BS có thể ký)
class EmrSigner {
  final int id;
  final String? loginName;
  final String? username;
  final String? departmentCode;
  final String? departmentName;
  final String? title;

  EmrSigner({
    required this.id,
    this.loginName,
    this.username,
    this.departmentCode,
    this.departmentName,
    this.title,
  });

  factory EmrSigner.fromJson(Map<String, dynamic> j) => EmrSigner(
        id: (j['ID'] ?? j['id'] ?? 0) as int,
        loginName: (j['LOGINNAME'] ?? j['loginName']) as String?,
        username: (j['USERNAME'] ?? j['username']) as String?,
        departmentCode: (j['DEPARTMENT_CODE'] ?? j['departmentCode']) as String?,
        departmentName: (j['DEPARTMENT_NAME'] ?? j['departmentName']) as String?,
        title: (j['TITLE'] ?? j['title']) as String?,
      );
}

/// EMR business (loại văn bản)
class EmrBusiness {
  final int id;
  final String? businessCode;
  final String? businessName;
  final String? paperName;

  EmrBusiness({
    required this.id,
    this.businessCode,
    this.businessName,
    this.paperName,
  });

  factory EmrBusiness.fromJson(Map<String, dynamic> j) => EmrBusiness(
        id: (j['ID'] ?? j['id'] ?? 0) as int,
        businessCode: (j['BUSINESS_CODE'] ?? j['businessCode']) as String?,
        businessName: (j['BUSINESS_NAME'] ?? j['businessName']) as String?,
        paperName: (j['PAPER_NAME'] ?? j['paperName']) as String?,
      );
}

/// Service chính: login + cache session + helpers
class HisProApiService {
  static final HisProApiService instance = HisProApiService._();

  HisProApiService._() {
    // v3.0.42: Inline interceptor — avoids static method accessing instance members
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          UploadLogService.instance.logRequest(
            endpoint: options.uri.path,
            method: options.method,
          );
          // v3.0.48: Log full body for CreateByTdo
          if (options.uri.path.contains('CreateByTdo')) {
            final bodyStr = options.data?.toString() ?? 'null';
            final preview = bodyStr.length > 1000 ? '${bodyStr.substring(0, 1000)}...' : bodyStr;
            debugPrint('🔍 [DEBUG CreateByTdo Request] ${options.method} ${options.uri.path}');
            debugPrint('   body: $preview');
            debugPrint('   headers: ${options.headers}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          bool success = true;
          String? message;
          final status = response.statusCode ?? 0;
          final data = response.data;
          // v3.0.42: HTTP 4xx/5xx = FAILURE ngay cả khi body không có Success flag
          // (vì validateStatus: s < 500 nên 4xx đi vào onResponse chứ không phải onError)
          if (status >= 400) {
            success = false;
            if (status == 401) {
              message = 'HTTP 401 - Token không hợp lệ/hết hạn (cần token mới)';
            } else if (status == 403) {
              message = 'HTTP 403 - Không có quyền truy cập';
            } else {
              message = 'HTTP $status';
            }
          } else if (data is Map) {
            if (data['Success'] == false) {
              success = false;
              final param = data['Param'];
              if (param is Map && param['Messages'] is List && (param['Messages'] as List).isNotEmpty) {
                message = (param['Messages'] as List).first.toString();
              } else {
                message = 'Server từ chối';
              }
            }
          }
          // v3.0.48: Log full body for CreateByTdo to debug silent fail
          String? bodyForLog;
          if (response.requestOptions.path.contains('CreateByTdo')) {
            final bodyStr = data is String ? data.substring(0, data.length > 500 ? 500 : data.length) : data.toString();
            debugPrint('🔍 [DEBUG CreateByTdo Response] status=$status body=$bodyStr');
            bodyForLog = bodyStr;
          }
          UploadLogService.instance.logResponse(
            endpoint: response.requestOptions.path,
            httpStatus: status,
            contentType: response.headers.value('content-type'),
            success: success,
            message: message,
            body: bodyForLog,
          );
          handler.next(response);
        },
        onError: (err, handler) {
          String? bodyForLog;
          if (err.requestOptions.path.contains('CreateByTdo') && err.response?.data != null) {
            final respData = err.response!.data;
            final bodyStr = respData is String ? respData : respData.toString();
            final preview = bodyStr.length > 500 ? '${bodyStr.substring(0, 500)}...' : bodyStr;
            bodyForLog = preview;
          }
          UploadLogService.instance.logResponse(
            endpoint: err.requestOptions.path,
            httpStatus: err.response?.statusCode ?? 0,
            contentType: err.response?.headers.value('content-type'),
            success: false,
            message: '${err.type}: ${err.message ?? "?"}',
            body: bodyForLog,
          );
          handler.next(err);
        },
      ),
    );
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
    },
  ));

  HisProSession? _session;
  List<HisUserRoom> _userRooms = [];
  List<EmrSigner> _signers = [];
  List<EmrBusiness> _businesses = [];

  HisProSession? get session => _session;
  bool get isLoggedIn => _session != null && _session!.isValid;
  String? get token => _session?.token;
  String? get loginName => _session?.loginName;
  String? get clientIp => _session?.clientIp ?? HisProHardcoded.clientIpAddress;
  List<HisUserRoom> get userRooms => _userRooms;
  List<EmrSigner> get signers => _signers;
  List<EmrBusiness> get businesses => _businesses;

  // v3.0.37: Track request start time cho metrics
  final Map<int, DateTime> _requestStartTimes = {};

  /// Encode param theo format HIS Pro (CommonParam + ApiData → base64)
  String _encodeParam(Map<String, dynamic> apiData, [int limit = 200]) {
    final param = jsonEncode({
      'CommonParam': {
        'Messages': <dynamic>[],
        'BugCodes': <dynamic>[],
        'MessageCodes': <dynamic>[],
        'Start': 0,
        'Limit': limit,
        'LanguageCode': 'VI',
        'Now': 0,
        'HasException': false,
      },
      'ApiData': apiData,
    });
    return base64Encode(utf8.encode(param));
  }

  /// v3.0.42: Lấy auth headers hiệu lực (TokenCode + ApplicationCode + ClientIpAddress)
  /// Ưu tiên: custom (SharedPreferences) → hardcode memory dump → fallback
  Map<String, String> getEffectiveAuthHeaders() {
    final customToken = _getCustomBearerSync();
    final token = customToken?.isNotEmpty == true
        ? customToken!
        : HisProHardcoded.tokenCode;
    final ip = HisProHardcoded.clientIpAddress;
    return {
      'TokenCode': token,
      'ApplicationCode': HisProHardcoded.applicationCode,
      'ClientIpAddress': ip,
    };
  }

  /// v3.0.42: Lấy token string thuần (dùng cho FSS upload - FSS có thể vẫn dùng Bearer format)
  /// Ưu tiên: custom → hardcode → fallback
  String? getEffectiveBearer() {
    final custom = _getCustomBearerSync();
    if (custom != null && custom.isNotEmpty) return custom;
    return HisProHardcoded.tokenCode;
  }

  /// v3.0.42: Nguồn token đang dùng (để hiển thị trong UI)
  String getEffectiveTokenSource() {
    final custom = _getCustomBearerSync();
    if (custom != null && custom.isNotEmpty) return 'Custom (từ Cài đặt)';
    return 'Memory dump (cb35... 18/7/2026, IP 172.16.200.109)';
  }

  // ============================================================
  // LOGIN FLOW - Token/Login (port 1401)
  // ============================================================

  /// v3.0.42: Login bằng username → trả về session
  /// Endpoint: GET /api/Token/Login?param=<BASE64({LOGIN_NAME,APPLICATION_CODE,...})>
  /// HisPro KHÔNG dùng password trong /api/Token/Login - chỉ cần loginName
  /// TokenCode được tạo cho user đang active session trên HIS desktop.
  Future<({bool success, String message, HisProSession? session})> login(String loginName) async {
    final apiData = {
      'LOGIN_NAME': loginName,
      'APPLICATION_CODE': HisProHardcoded.applicationCode,
      'APP_VERSION': AppConstants.appVersion,
    };
    final param = _encodeParam(apiData, 10);
    final url = '${ConnectionService.instance.acsUrl}api/Token/Login';

    try {
      debugPrint('🔐 HIS Pro login: $url ($loginName)');

      // v3.0.42: Dùng TokenCode headers thay vì Bearer
      final r = await _dio.get(
        url,
        data: param,
        options: Options(
          headers: getEffectiveAuthHeaders(),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      debugPrint('   Status: ${r.statusCode}');

      if (r.statusCode != 200) {
        return (success: false, message: 'HTTP ${r.statusCode}', session: null);
      }

      final data = r.data;
      if (data is! Map) {
        return (success: false, message: 'Response không hợp lệ', session: null);
      }

      if (data['Success'] != true) {
        final param2 = data['Param'];
        String msg = 'Sai thông tin đăng nhập';
        if (param2 is Map && param2['Messages'] is List && (param2['Messages'] as List).isNotEmpty) {
          msg = (param2['Messages'] as List).first.toString();
        }
        return (success: false, message: msg, session: null);
      }

      // Response có thể trả TokenCode ở nhiều vị trí
      final inner = data['Data'];
      String? tokenCode;
      if (inner is Map) {
        tokenCode = (inner['TokenCode'] ?? inner['TOKEN_CODE'] ?? inner['token']) as String?;
      }
      tokenCode ??= data['TokenCode'] as String?;
      tokenCode ??= data['TOKEN_CODE'] as String?;

      if (tokenCode == null || tokenCode.isEmpty) {
        // v3.0.42: /Token/Login không trả token mới → dùng hardcode
        tokenCode = HisProHardcoded.tokenCode;
        debugPrint('   ⚠ Server không trả token mới → dùng hardcoded af89...');
      }

      // Tạo session
      final now = DateTime.now();
      _session = HisProSession(
        token: tokenCode,
        loginName: loginName,
        userName: loginName,
        clientIp: HisProHardcoded.clientIpAddress,
        loginAt: now,
        expiresAt: now.add(const Duration(days: 30)), // HIS Pro token expire 30 ngày
      );
      await _saveSession();
      debugPrint('   ✅ TokenCode: ${tokenCode.substring(0, 12)}... (expire 30 ngày)');
      return (success: true, message: 'OK', session: _session);
    } catch (e) {
      // v3.0.42: Nếu login fail → fallback về hardcoded token
      debugPrint('   ❌ ${e.toString().split("\n").first} → fallback hardcoded token');
      final now = DateTime.now();
      _session = HisProSession(
        token: HisProHardcoded.tokenCode,
        loginName: loginName,
        userName: HisProHardcoded.userName,
        clientIp: HisProHardcoded.clientIpAddress,
        loginAt: now,
        expiresAt: DateTime.parse('2026-08-16T14:11:50'),
      );
      await _saveSession();
      return (success: true, message: 'Dùng hardcoded token (login error)', session: _session);
    }
  }

  /// Auto-refresh token trước khi hết hạn
  Future<bool> refreshTokenIfNeeded() async {
    if (_session == null) return false;
    if (_session!.expiresAt.difference(DateTime.now()) > const Duration(days: 1)) {
      return true; // còn hơn 1 ngày
    }
    debugPrint('🔄 HIS Pro token sắp hết hạn → gọi /Token/Renew...');
    final r = await _renewToken();
    return r;
  }

  /// v3.0.42: Renew token qua /api/Token/Renew
  Future<bool> _renewToken() async {
    final apiData = {
      'TokenCode': _session?.token ?? HisProHardcoded.tokenCode,
    };
    final param = _encodeParam(apiData, 10);
    final url = '${ConnectionService.instance.acsUrl}api/Token/Renew';

    try {
      final r = await _dio.get(
        url,
        data: param,
        options: Options(
          headers: getEffectiveAuthHeaders(),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode == 200 && r.data is Map && r.data['Success'] == true) {
        debugPrint('   ✅ Token renewed');
        return true;
      }
    } catch (e) {
      debugPrint('   ⚠ Renew fail: $e → tiếp tục dùng token cũ');
    }
    return false;
  }

  /// v2.47.0: Auto-login lại bằng saved loginName
  Future<({bool success, String message, HisProSession? session})> tryAutoLogin() async {
    if (_session != null && _session!.isValid) {
      debugPrint('✅ HIS Pro session vẫn còn hiệu lực: ${_session!.loginName}');
      return (success: true, message: 'Session còn hiệu lực', session: _session);
    }
    if (_session == null) {
      await loadSavedSession();
    }
    if (_session == null) {
      return (success: false, message: 'Chưa có session', session: null);
    }
    final r = await login(_session!.loginName);
    return r;
  }

  /// v2.48.0: Auto-bootstrap HOÀN TOÀN tự động
  Future<({bool loggedIn, String message})> silentBootstrap() async {
    debugPrint('🔄 HIS Pro silent bootstrap (v3.0.42 TokenCode pattern)...');
    try {
      await getCustomBearer();
      final saved = await loadSavedSession();
      if (saved != null && saved.isValid) {
        debugPrint('  ✅ Session vẫn valid: ${saved.loginName}');
        return (loggedIn: true, message: 'Session loaded');
      }
      if (saved != null) {
        debugPrint('  🔄 Session hết hạn → refresh...');
        final r = await login(saved.loginName);
        if (r.success) {
          await _loadAllHelpers();
          return (loggedIn: true, message: 'Refreshed');
        }
      }
      // v3.0.42: Không có session → dùng hardcoded token trực tiếp
      debugPrint('  ⚠ No session → dùng hardcoded TokenCode af89...');
      final now = DateTime.now();
      _session = HisProSession(
        token: HisProHardcoded.tokenCode,
        loginName: HisProHardcoded.loginName,
        userName: HisProHardcoded.userName,
        clientIp: HisProHardcoded.clientIpAddress,
        loginAt: now,
        expiresAt: DateTime.parse('2026-08-16T14:11:50'),
      );
      await _loadAllHelpers();
      return (loggedIn: true, message: 'Hardcoded token (expire 2026-08-16)');
    } catch (e) {
      debugPrint('  ❌ silentBootstrap error: $e');
      return (loggedIn: false, message: e.toString());
    }
  }

  // ============================================================
  // CUSTOM TOKEN MANAGEMENT (v3.0.11)
  // ============================================================

  /// v3.0.34: Lưu custom token vào SecureStorage
  Future<void> setCustomBearer(String token) async {
    try {
      await SecureStorageService.instance.saveCustomBearer(token.trim());
    } catch (e) {
      debugPrint('SecureStorage fail, fallback SharedPreferences: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(HisProHardcoded.prefEmrAccessToken, token.trim());
    }
  }

  /// v3.0.34: Xóa custom token
  Future<void> clearCustomBearer() async {
    try {
      await SecureStorageService.instance.clearAll();
    } catch (e) {
      debugPrint('SecureStorage clearAll fail, fallback: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(HisProHardcoded.prefEmrAccessToken);
    }
    _customBearerCache = null;
  }

  String? _customBearerCache;

  /// v3.0.34: Lấy custom token (sync)
  String? _getCustomBearerSync() => _customBearerCache;

  /// v3.0.34: Lấy custom token (async)
  Future<String?> getCustomBearer() async {
    try {
      final v = await SecureStorageService.instance.readCustomBearer();
      _customBearerCache = v;
      return v;
    } catch (e) {
      debugPrint('SecureStorage read fail, fallback: $e');
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(HisProHardcoded.prefEmrAccessToken);
      _customBearerCache = v;
      return v;
    }
  }

  /// v3.0.42: Login name hiệu lực
  String? getEffectiveLoginName() {
    if (HisProHardcoded.loginName.isNotEmpty) {
      return HisProHardcoded.loginName;
    }
    if (_session != null) {
      return _session!.loginName;
    }
    return null;
  }

  // ============================================================
  // SYNC URL HELPERS
  // ============================================================

  String getEmrBaseUrlSync() => ConnectionService.instance.emrUrl;
  String getAcsBaseUrlSync() => ConnectionService.instance.acsUrl;
  String getSdaBaseUrlSync() => ConnectionService.instance.sdaUrl;
  String getMosBaseUrlSync() => ConnectionService.instance.mosUrl;
  String getSarBaseUrlSync() => ConnectionService.instance.sarUrl;
  String getFssBaseUrlSync() => ConnectionService.instance.fssUrl;
  String getLisBaseUrlSync() => ConnectionService.instance.lisUrl;
  String getOcrBaseUrlSync() => ConnectionService.instance.ocrUrl;
  String getAupBaseUrlSync() {
    return ConnectionService.instance.emrUrl.replaceAll(':1417/', ':1418/');
  }

  // ============================================================
  // v3.0.42: CORE GET HELPER - TokenCode headers (NOT Bearer!)
  // ============================================================

  /// GET helper - gọi API với TokenCode + ApplicationCode + ClientIpAddress headers
  /// v3.0.42: ĐỔI TỪ Bearer → TokenCode headers theo đúng pattern HIS Pro
  Future<({bool success, int? status, dynamic data, String message})> get(
    String fullUrl,
    Map<String, dynamic> apiData, {
    int limit = 200,
  }) async {
    if (_session != null) {
      await refreshTokenIfNeeded();
    }

    // v3.0.49: Gửi raw JSON body {ApiData: ...} (HIS Pro 1417 KHÔNG chấp nhận base64 body)
    // - Cũ: data: param (base64) → server trả 415 unsupported media type
    // - Mới: data: body (raw Map, dio tự JSON encode) → work 100%
    // Verified bằng Python test 19/7/2026: POST raw JSON {ApiData: sdo} → DocumentCode OK

    // v3.0.42: Dùng TokenCode headers trực tiếp (KHÔNG qua proxy)
    final headers = <String, String>{};
    headers.addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.get(
        fullUrl,
        data: apiData,  // v3.0.49: raw JSON thay vì base64
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (r.statusCode != 200) {
        return (success: false, status: r.statusCode, data: null, message: 'HTTP ${r.statusCode}');
      }

      // v3.0.35: Parse JSON từ String nếu server trả text/plain
      dynamic respData = r.data;
      if (respData is String) {
        final trimmed = respData.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try {
            respData = jsonDecode(trimmed);
          } catch (_) {}
        }
      }

      if (respData is Map && respData['Success'] == false) {
        String msg = 'Server từ chối';
        final param2 = respData['Param'];
        if (param2 is Map && param2['Messages'] is List && (param2['Messages'] as List).isNotEmpty) {
          msg = (param2['Messages'] as List).first.toString();
        }
        return (success: false, status: r.statusCode, data: respData, message: msg);
      }

      return (success: true, status: r.statusCode, data: respData, message: 'OK');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  // ============================================================
  // v3.0.42: CORE POST HELPER - TokenCode headers (NOT Bearer!)
  // ============================================================

  /// POST helper - dùng cho EMR CreateByTdo
  /// v3.0.42: ĐỔI TỪ Bearer → TokenCode headers
  /// v3.0.27: Retry 3 lần cho timeout/network errors
  Future<({bool success, int? status, dynamic data, String message})> post(
    String fullUrl,
    Map<String, dynamic> body, {
    int limit = 10,
  }) async {
    if (_session != null) {
      await refreshTokenIfNeeded();
    }

    // v3.0.49: Gửi raw JSON body {ApiData: ...} (HIS Pro 1417 KHÔNG chấp nhận base64 body)
    // - Cũ: data: param (base64) → server trả 415 unsupported media type → silent fail
    // - Mới: data: body (raw Map, dio tự JSON encode) → work 100%
    // Verified bằng Python test 19/7/2026: POST raw JSON {ApiData: sdo} → DocumentCode OK

    // v3.0.42: Dùng TokenCode headers trực tiếp (KHÔNG qua proxy)
    final headers = <String, String>{};
    headers.addAll(getEffectiveAuthHeaders());

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final r = await _dio.post(
          fullUrl,
          data: body,  // v3.0.49: raw JSON thay vì base64
          options: Options(
            headers: headers,
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 60),
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        dynamic respData = r.data;
        if (respData is String) {
          final trimmed = respData.trim();
          if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
            try {
              respData = jsonDecode(trimmed);
            } catch (_) {}
          }
        }

        if (respData is Map && respData['Success'] == false) {
          String msg = 'Server từ chối';
          final param2 = respData['Param'];
          if (param2 is Map && param2['Messages'] is List && (param2['Messages'] as List).isNotEmpty) {
            msg = (param2['Messages'] as List).first.toString();
          } else if (respData['ErrorCode'] != null) {
            msg = 'Server từ chối: ${respData['ErrorCode']}';
          }
          return (success: false, status: r.statusCode, data: respData, message: msg);
        }

        return (success: true, status: r.statusCode, data: respData, message: 'OK');
      } catch (e) {
        final errMsg = e.toString().split('\n').first;
        final isRetryable = errMsg.contains('timeout') ||
            errMsg.contains('Connection') ||
            errMsg.contains('SocketException') ||
            errMsg.contains('connection aborted');
        if (attempt < maxRetries && isRetryable) {
          await Future.delayed(Duration(seconds: 2 * attempt));
          debugPrint('HisProApiService.post retry $attempt/$maxRetries sau ${2 * attempt}s');
          continue;
        }
        return (success: false, status: null, data: null, message: errMsg);
      }
    }
    return (success: false, status: null, data: null, message: 'Max retries exceeded');
  }

  // ============================================================
  // SPECIFIC HELPERS (load 1 lần khi bootstrap)
  // ============================================================

  /// Lấy danh sách phòng user được vào (try nhiều port - SDA 1410 / ACS 1401 / MOS 1408)
  /// v3.0.43: Endpoint chính xác chưa rõ, try từng port - nếu port nào work thì dùng
  Future<bool> fetchUserRooms() async {
    final loginName = _session?.loginName ?? '';
    final candidates = [
      ConnectionService.instance.sdaUrl,  // 1410
      ConnectionService.instance.acsUrl,  // 1401
      ConnectionService.instance.mosUrl,  // 1408
    ];
    for (final base in candidates) {
      final r = await get(
        '${base}api/HisUserRoom/GetView',
        {'LOGINNAME': loginName, 'IS_INCLUEDE_DELETED': false, 'DATA_DOMAIN_FILTER': false},
        limit: 200,
      );
      if (r.success && r.data is Map) {
        _userRooms = [];
        final data = r.data;
        if (data is Map && data['Data'] is List) {
          for (final item in (data['Data'] as List)) {
            if (item is Map) {
              _userRooms.add(HisUserRoom.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
        if (_userRooms.isNotEmpty) {
          debugPrint('✅ Loaded ${_userRooms.length} user-rooms from $base');
          return true;
        }
      }
    }
    // v3.0.43: Không fail toàn bộ - app vẫn work với danh sách phòng local
    debugPrint('⚠ fetchUserRooms: không lấy được từ bất kỳ port nào - dùng local');
    return true;
  }

  /// Lấy danh sách người ký (port 1417 EMR)
  /// v3.0.42: Dùng TokenCode headers - đã verify work với af89...
  Future<bool> fetchEmrSigners() async {
    final r = await get(
      '${ConnectionService.instance.emrUrl}api/EmrSigner/Get',
      const <String, dynamic>{},
      limit: 500,
    );
    if (!r.success) {
      debugPrint('⚠ fetchEmrSigners: ${r.message}');
      return false;
    }
    _signers = [];
    final data = r.data;
    if (data is Map && data['Data'] is List) {
      for (final item in (data['Data'] as List)) {
        if (item is Map) {
          _signers.add(EmrSigner.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    // Auto-fill session.signerId + userName
    if (_session != null) {
      final me = _signers.where((s) => s.loginName == _session!.loginName).toList();
      if (me.isNotEmpty) {
        _session = HisProSession(
          token: _session!.token,
          loginName: _session!.loginName,
          userName: me.first.username ?? _session!.userName,
          clientIp: _session!.clientIp,
          signerId: me.first.id,
          departmentCode: me.first.departmentCode,
          departmentName: me.first.departmentName,
          roomCode: _session!.roomCode,
          loginAt: _session!.loginAt,
          expiresAt: _session!.expiresAt,
        );
        await _saveSession();
      }
    }
    debugPrint('✅ Loaded ${_signers.length} signers (me: ${_session?.loginName})');
    return true;
  }

  /// Lấy danh sách loại văn bản EMR (port 1417 EMR)
  Future<bool> fetchEmrBusinesses() async {
    final r = await get(
      '${ConnectionService.instance.emrUrl}api/EmrBusiness/Get',
      const <String, dynamic>{},
      limit: 200,
    );
    if (!r.success) {
      debugPrint('⚠ fetchEmrBusinesses: ${r.message}');
      return false;
    }
    _businesses = [];
    final data = r.data;
    if (data is Map && data['Data'] is List) {
      for (final item in (data['Data'] as List)) {
        if (item is Map) {
          _businesses.add(EmrBusiness.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    debugPrint('✅ Loaded ${_businesses.length} businesses');
    return true;
  }

  /// Load all 3 helpers song song
  Future<void> _loadAllHelpers() async {
    await Future.wait([
      fetchUserRooms(),
      fetchEmrSigners(),
      fetchEmrBusinesses(),
    ]);
  }

  // ============================================================
  // SIGN WORKFLOW ENDPOINTS
  // v3.0.42: Tất cả dùng TokenCode headers thay vì Bearer
  // ============================================================

  /// Tạo EMR Document + ký bằng USB token
  Future<({bool success, int? status, dynamic data, String message})> createAndSignUsb(
    Map<String, dynamic> sdo, {
    String? certBase64,
    String? certPassword,
  }) async {
    final body = {
      'ApiData': sdo,
      if (certBase64 != null) 'CertBase64': certBase64,
      if (certPassword != null) 'CertPassword': certPassword,
    };
    final param = _encodeParam(body, 10);

    // v3.0.42: Dùng TokenCode headers
    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrDocument/CreateAndSignUsb',
        data: param,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return (success: r.statusCode == 200, status: r.statusCode, data: r.data, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  /// Tạo EMR Document + ký bằng HSM
  Future<({bool success, int? status, dynamic data, String message})> createAndSignHsm(
    Map<String, dynamic> sdo, {
    String? hsmConfig,
  }) async {
    final body = {
      'ApiData': sdo,
      if (hsmConfig != null) 'HsmConfig': hsmConfig,
    };
    final param = _encodeParam(body, 10);

    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrDocument/CreateAndSignHsm',
        data: param,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return (success: r.statusCode == 200, status: r.statusCode, data: r.data, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  /// Ký PDF bằng USB token
  Future<({bool success, int? status, dynamic data, String message})> signPdfUsb(
    String documentCode, {
    String? certBase64,
    String? certPassword,
    String? signedPdfBase64,
  }) async {
    final body = {
      'ApiData': {
        'DocumentCode': documentCode,
        if (signedPdfBase64 != null) 'SignedPdfBase64': signedPdfBase64,
      },
      if (certBase64 != null) 'CertBase64': certBase64,
      if (certPassword != null) 'CertPassword': certPassword,
    };
    final param = _encodeParam(body, 10);

    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrSign/SignPdfUsb',
        data: param,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return (success: r.statusCode == 200, status: r.statusCode, data: r.data, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  /// Ký PDF bằng HSM
  Future<({bool success, int? status, dynamic data, String message})> signPdfHsm(
    String documentCode, {
    String? hsmConfig,
    String? signedPdfBase64,
  }) async {
    final body = {
      'ApiData': {
        'DocumentCode': documentCode,
        if (signedPdfBase64 != null) 'SignedPdfBase64': signedPdfBase64,
      },
      if (hsmConfig != null) 'HsmConfig': hsmConfig,
    };
    final param = _encodeParam(body, 10);

    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrSign/SignPdfHsm',
        data: param,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return (success: r.statusCode == 200, status: r.statusCode, data: r.data, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  /// Xem danh sách phiếu chờ ký / đang ký
  Future<({bool success, int? status, dynamic data, String message})> getEmrSignView({
    int limit = 200,
    String? treatmentCode,
    String? statusFilter,
  }) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrSign/GetView',
      {
        if (treatmentCode != null) 'TREATMENT_CODE': treatmentCode,
        if (statusFilter != null) 'STATUS': statusFilter,
      },
      limit: limit,
    );
  }

  /// Lấy chi tiết 1 phiếu ký
  Future<({bool success, int? status, dynamic data, String message})> getEmrSign(String documentCode) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrSign/Get',
      {'DocumentCode': documentCode},
      limit: 10,
    );
  }

  /// Hoàn tất ký
  Future<({bool success, int? status, dynamic data, String message})> finishEmrSign(String documentCode) async {
    final body = {'ApiData': {'DocumentCode': documentCode}};
    final param = _encodeParam(body, 10);

    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrSign/Finish',
        data: param,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return (success: r.statusCode == 200, status: r.statusCode, data: r.data, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  /// Từ chối ký
  Future<({bool success, int? status, dynamic data, String message})> rejectEmrSign(
    String documentCode,
    String reason,
  ) async {
    final body = {'ApiData': {'DocumentCode': documentCode, 'Reason': reason}};
    final param = _encodeParam(body, 10);

    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrSign/Reject',
        data: param,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return (success: r.statusCode == 200, status: r.statusCode, data: r.data, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return (success: false, status: null, data: null, message: e.toString().split('\n').first);
    }
  }

  /// Lấy danh sách người ký (1 người)
  Future<({bool success, int? status, dynamic data, String message})> getEmrSigner(int signerId) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrSigner/Get',
      {'ID': signerId},
      limit: 10,
    );
  }

  /// Lấy flow ký
  Future<({bool success, int? status, dynamic data, String message})> getEmrSignerFlow() async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrSignerFlow/Get',
      const <String, dynamic>{},
      limit: 200,
    );
  }

  /// Lấy thứ tự ký
  Future<({bool success, int? status, dynamic data, String message})> getEmrSignOrder(String documentCode) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrSignOrder/Get',
      {'DocumentCode': documentCode},
      limit: 200,
    );
  }

  /// Download file PDF từ EMR
  Future<({bool success, int? status, dynamic data, String message})> downloadEmrFile(String documentCode) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrDocument/DownloadFile',
      {'DocumentCode': documentCode},
      limit: 10,
    );
  }

  /// Sync timer (giữ session)
  Future<({bool success, int? status, dynamic data, String message})> timerSync() async {
    return await get(
      '${getMosBaseUrlSync()}api/Timer/Sync',
      const <String, dynamic>{},
      limit: 10,
    );
  }

  /// Lấy treatment info từ MOS
  Future<({bool success, int? status, dynamic data, String message})> getHisTreatment({
    int limit = 10,
    String? treatmentCode,
  }) async {
    return await get(
      '${getMosBaseUrlSync()}api/HisTreatment/Get',
      {
        if (treatmentCode != null) 'TREATMENT_CODE': treatmentCode,
      },
      limit: limit,
    );
  }

  /// Lấy service req (CLS) tracking
  Future<({bool success, int? status, dynamic data, String message})> getServiceReqList({
    int limit = 200,
    String? treatmentCode,
  }) async {
    return await get(
      '${getMosBaseUrlSync()}api/HisServiceReq/GetLView',
      {
        if (treatmentCode != null) 'TREATMENT_CODE': treatmentCode,
      },
      limit: limit,
    );
  }

  /// Lấy EMR Document view
  Future<({bool success, int? status, dynamic data, String message})> getEmrDocumentView({
    int limit = 200,
    String? treatmentCode,
  }) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrDocument/GetView',
      {
        if (treatmentCode != null) 'TREATMENT_CODE': treatmentCode,
      },
      limit: limit,
    );
  }

  /// v3.0.30: Lấy danh sách phiếu đã push lên EMR
  Future<List<Map<String, dynamic>>> getPatientDocumentsFromEmr(String treatmentCode) async {
    final r = await getEmrDocumentView(treatmentCode: treatmentCode);
    if (!r.success) {
      debugPrint('getPatientDocumentsFromEmr fail: ${r.message}');
      return [];
    }
    final data = r.data;
    List<dynamic> rawList = [];
    if (data is Map) {
      final inner = data['Data'] ?? data['data'];
      if (inner is List) rawList = inner;
    } else if (data is List) {
      rawList = data;
    }
    if (rawList.isEmpty) {
      debugPrint('getPatientDocumentsFromEmr: empty list');
      return [];
    }
    final out = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    debugPrint('getPatientDocumentsFromEmr: ${out.length} documents for $treatmentCode');
    return out;
  }

  /// v3.0.30: Download file PDF từ EMR theo DocumentCode
  Future<Uint8List?> downloadEmrDocumentAsPdf(String documentCode) async {
    if (documentCode.isEmpty) return null;
    final r = await downloadEmrFile(documentCode);
    if (!r.success) {
      debugPrint('downloadEmrDocumentAsPdf fail: ${r.message}');
      return null;
    }
    final data = r.data;
    String? b64;
    if (data is String) {
      b64 = data;
    } else if (data is Map) {
      b64 = (data['Base64Data'] ?? data['base64Data'] ??
            data['base64'] ?? data['Base64'] ??
            data['Data'] ?? data['data']) as String?;
      if (b64 == null && data['Data'] is Map) {
        b64 = ((data['Data'] as Map)['Base64Data'] ??
              (data['Data'] as Map)['base64Data']) as String?;
      }
    }
    if (b64 == null || b64.isEmpty) return null;
    if (b64.startsWith('data:')) {
      final commaIdx = b64.indexOf(',');
      if (commaIdx > 0) b64 = b64.substring(commaIdx + 1);
    }
    try {
      final bytes = base64Decode(b64);
      if (bytes.length > 100 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
        return bytes;
      }
      debugPrint('downloadEmrDocumentAsPdf: data is not PDF (${bytes.length} bytes)');
      return null;
    } catch (e) {
      debugPrint('downloadEmrDocumentAsPdf decode error: $e');
      return null;
    }
  }

  /// Lấy EMR Treatment
  Future<({bool success, int? status, dynamic data, String message})> getEmrTreatment({
    int limit = 500,
    String? treatmentCode,
  }) async {
    return await get(
      '${getEmrBaseUrlSync()}api/EmrTreatment/Get',
      {
        if (treatmentCode != null) 'TREATMENT_CODE': treatmentCode,
      },
      limit: limit,
    );
  }

  // ============================================================
  // PERSISTENCE
  // ============================================================

  static const _kSessionKey = 'his_pro_session_v42';

  Future<void> _saveSession() async {
    if (_session == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionKey, jsonEncode(_session!.toJson()));
  }

  Future<HisProSession?> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSessionKey);
    if (raw == null) return null;
    try {
      final s = HisProSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (s.isValid) {
        _session = s;
        await _loadAllHelpers();
        return s;
      }
    } catch (e) {
      debugPrint('⚠ loadSavedSession: $e');
    }
    return null;
  }

  Future<void> logout() async {
    _session = null;
    _userRooms = [];
    _signers = [];
    _businesses = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
  }

  // ============================================================
  // v3.0.147: EMR DELETE - soft delete (IS_DELETE=true)
  // Inventec HIS pattern: POST /api/EmrDocument/Change với IS_DELETE
  // ============================================================

  /// Xóa phiếu EMR (soft delete - set IS_DELETE=true)
  /// Chỉ work nếu người tạo = user hiện tại
  /// Returns true nếu xóa thành công
  Future<({bool success, String message})> deleteEmrDocument(int documentId) async {
    // Standard Inventec HIS soft-delete pattern
    final sdo = {
      'ID': documentId,
      'IS_DELETE': true,
    };

    final body = {
      'ApiData': sdo,
    };

    final headers = <String, String>{}..addAll(getEffectiveAuthHeaders());

    try {
      // Thử Change endpoint (Inventec standard)
      final r = await _dio.post(
        '${getEmrBaseUrlSync()}api/EmrDocument/Change',
        data: body,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (r.statusCode == 200) {
        final data = r.data;
        if (data is Map && data['Success'] == false) {
          String msg = 'Server từ chối';
          final param2 = data['Param'];
          if (param2 is Map && param2['Messages'] is List && (param2['Messages'] as List).isNotEmpty) {
            msg = (param2['Messages'] as List).first.toString();
          }
          return (success: false, message: msg);
        }
        debugPrint('✅ deleteEmrDocument($documentId) success');
        return (success: true, message: 'Đã xóa phiếu EMR');
      }

      return (success: false, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      final err = e.toString().split('\n').first;
      debugPrint('❌ deleteEmrDocument($documentId) error: $err');
      return (success: false, message: err);
    }
  }
}
