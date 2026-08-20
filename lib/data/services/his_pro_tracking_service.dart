/// HIS Pro Tracking Service (Legacy)
/// v3.0.156: Renamed from HisProApiService to HisProTrackingService to avoid
///   conflict with the main HisProApiService class in data/api/.
/// Original:
/// Kết nối tới HIS Pro backend (qua OpenVPN BV profile)
/// Base URL: http://172.16.9.6:1401 (LAN BV) hoặc http://117.2.25.67:1401
///
/// Pattern API từ log: api/{Module}/{Method}?param=BASE64(JSON)
///   - CommonParam: { Messages: [], BugCodes: [], MessageCodes: [], LanguageCode: "VI", Now: 0, HasException: false }
///   - ApiData: { ... theo từng method ... }
///
/// Ví dụ:
///   api/HisTracking/GetView?param=BASE64
///   api/EmrDocument/GetView?param=BASE64
///   api/HisTracking/GetData?param=BASE64
///   api/HisBedRoom/GetView?param=BASE64   ← v2.36.3: lấy cả PK + nội trú
///   api/HisTreatmentBedRoom/GetView?param=BASE64   ← BN trong buồng
///   api/Token/Login (POST body)   ← v2.36.3: JWT auth
library;
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class HisProTrackingService {
  static final HisProTrackingService instance = HisProTrackingService._();
  HisProTrackingService._();

  // Base URL mặc định (qua VPN)
  static const String defaultBaseUrl = 'http://172.16.9.6:1401';
  static const String fallbackBaseUrl = 'http://117.2.25.67:1401';

  String _baseUrl = defaultBaseUrl;
  String get baseUrl => _baseUrl;

  Dio? _dio;

  // v2.36.3: JWT auth state
  String? _jwtToken;
  DateTime? _tokenExpiry;
  String? _currentLoginName;

  // v3.0.42: TokenCode headers cho HIS Pro EMR 1417
  // (KHÔNG phải Bearer - HIS Pro dùng custom headers)
  String? _tokenCode;
  String? _clientIp;
  String? get tokenCode => _tokenCode;
  String? get clientIp => _clientIp;

  /// v3.0.42: Set TokenCode + ClientIp (load từ secure storage khi login)
  void setTokenCode({required String token, required String clientIp}) {
    _tokenCode = token;
    _clientIp = clientIp;
    debugPrint('HIS Pro TokenCode set, len=${token.length}, ip=$clientIp');
  }

  void clearTokenCode() {
    _tokenCode = null;
    _clientIp = null;
  }

  bool get isLoggedIn => _jwtToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!);
  String? get currentLoginName => _currentLoginName;

  /// Khởi tạo HTTP client
  Dio _makeDio({bool withAuth = true}) {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      // HIS Pro trả về text/plain với JSON - chấp nhận mọi status 2xx-4xx
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'User-Agent': 'HIS-Mobile-Flutter/2.36.3',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json; charset=utf-8',
        if (withAuth && _jwtToken != null) 'Authorization': 'Bearer $_jwtToken',
      },
    ));
    _dio = dio;
    return dio;
  }

  /// Đổi base URL (cho test LAN vs Internet)
  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    debugPrint('HIS Pro API base: $_baseUrl');
  }

  /// Ping server - check kết nối (không cần auth)
  Future<bool> ping() async {
    try {
      final dio = _makeDio(withAuth: false);
      final r = await dio.get('/home', options: Options(receiveTimeout: const Duration(seconds: 5)));
      return r.statusCode != null && r.statusCode! < 500;
    } catch (e) {
      return false;
    }
  }

  /// Build CommonParam cho mọi request (giống HIS Pro client)
  Map<String, dynamic> _commonParam() => {
    'Messages': <String>[],
    'BugCodes': <String>[],
    'MessageCodes': <String>[],
    'LanguageCode': 'VI',
    'Now': 0,
    'HasException': false,
  };

  /// Encode JSON param thành base64 (giống cách HIS Pro gửi)
  String _encodeParam(Map<String, dynamic> apiData) {
    final param = {
      'CommonParam': _commonParam(),
      'ApiData': apiData,
    };
    final json = jsonEncode(param);
    // HIS Pro dùng UTF-8 → base64
    return base64Encode(utf8.encode(json));
  }

  /// Decode response từ HIS Pro (thường là JSON object với Result/Data)
  Map<String, dynamic>? _parseResponse(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  /// Lấy list từ response (HIS Pro trả về {Result, Data: [...]})
  List<Map<String, dynamic>> _extractList(Map<String, dynamic>? resp) {
    if (resp == null) return [];
    final data = resp['Data'] ?? resp['data'] ?? resp['Result'] ?? resp['result'];
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// Gọi GET api/{module}/{method}?param=BASE64
  Future<Map<String, dynamic>?> get(String module, String method, Map<String, dynamic> apiData) async {
    try {
      final dio = _makeDio();
      final param = _encodeParam(apiData);
      final url = '/api/$module/$method?param=$param';
      debugPrint('HisPro GET: $url');
      final r = await dio.get(url);
      if (r.statusCode == 200) {
        return _parseResponse(r.data);
      }
      debugPrint('  → status ${r.statusCode}: ${r.data}');
      return null;
    } on DioException catch (e) {
      debugPrint('HisPro GET error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('HisPro GET exception: $e');
      return null;
    }
  }

  /// Gọi POST api/{module}/{method} với JSON body
  Future<Map<String, dynamic>?> post(String module, String method, Map<String, dynamic> body) async {
    try {
      final dio = _makeDio();
      final url = '/api/$module/$method';
      debugPrint('HisPro POST: $url');
      final r = await dio.post(url, data: jsonEncode(body));
      if (r.statusCode == 200) {
        return _parseResponse(r.data);
      }
      debugPrint('  → status ${r.statusCode}: ${r.data}');
      return null;
    } on DioException catch (e) {
      debugPrint('HisPro POST error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('HisPro POST exception: $e');
      return null;
    }
  }

  // ============================================================
  // v2.36.3: AUTH - Token/Login (lấy JWT)
  // ============================================================

  /// Login HIS Pro → lưu JWT token
  /// POST /api/Token/Login  body: {LoginName, Password, ...}
  /// Returns JWT token hoặc null nếu fail
  Future<HisProLoginResult> login(String loginName, String password) async {
    try {
      final dio = _makeDio(withAuth: false);
      // HIS Pro token endpoint không dùng CommonParam wrapper - body trực tiếp
      final body = {
        'LoginName': loginName,
        'Password': password,
        'LanguageCode': 'VI',
      };
      debugPrint('HisPro Login: $loginName');
      final r = await dio.post('/api/Token/Login', data: jsonEncode(body));
      debugPrint('  status: ${r.statusCode} body: ${r.data}');
      if (r.statusCode == 200) {
        final resp = _parseResponse(r.data);
        if (resp != null) {
          // Response có thể có nhiều format:
          // { token: "..." } / { Token: "..." } / { access_token: "..." } / { Result: { Token: "..." } }
          final token = resp['Token']
              ?? resp['token']
              ?? resp['AccessToken']
              ?? resp['access_token']
              ?? (resp['Result'] is Map ? (resp['Result']['Token'] ?? resp['Result']['token']) : null);
          if (token != null && token.toString().isNotEmpty) {
            _jwtToken = token.toString();
            _currentLoginName = loginName;
            // Token sống 8h (giống HIS Pro desktop)
            _tokenExpiry = DateTime.now().add(const Duration(hours: 8));
            debugPrint('  ✅ Login OK, token len=${_jwtToken!.length}');
            return HisProLoginResult(success: true, token: _jwtToken!);
          }
        }
        return HisProLoginResult(success: false, message: 'Không nhận được token từ HIS Pro');
      } else if (r.statusCode == 401) {
        return HisProLoginResult(success: false, message: 'Sai tên đăng nhập hoặc mật khẩu');
      } else {
        return HisProLoginResult(success: false, message: 'HTTP ${r.statusCode}: ${r.data}');
      }
    } on DioException catch (e) {
      debugPrint('HisPro Login DioException: ${e.type} - ${e.message}');
      return HisProLoginResult(
        success: false,
        message: e.type == DioExceptionType.connectionTimeout
            ? 'Timeout - không kết nối được HIS Pro (cần VPN BV?)'
            : 'Lỗi kết nối: ${e.message}',
      );
    } catch (e) {
      return HisProLoginResult(success: false, message: e.toString());
    }
  }

  /// Logout
  void logout() {
    _jwtToken = null;
    _tokenExpiry = null;
    _currentLoginName = null;
  }

  // ============================================================
  // v2.36.3: ROOMS - HisBedRoom/GetView (cả PK + nội trú)
  // ============================================================

  /// Lấy TẤT CẢ buồng bệnh theo khoa (gồm cả PK ngoại trú + nội trú)
  /// GET /api/HisBedRoom/GetView?param=BASE64
  /// Filter: DEPARTMENT_ID, IS_ACTIVE=1
  Future<List<Map<String, dynamic>>> getBedRoomsByDepartment(int departmentId) async {
    final resp = await get('HisBedRoom', 'GetView', {
      'DEPARTMENT_ID': departmentId,
      'IS_ACTIVE': 1,
    });
    final list = _extractList(resp);
    debugPrint('getBedRoomsByDepartment($departmentId): ${list.length} rooms');
    return list;
  }

  // ============================================================
  // v2.36.3: PATIENTS - HisTreatmentBedRoom/GetView
  // ============================================================

  /// Lấy BN đang nằm trong các buồng của khoa (kể cả PK)
  /// GET /api/HisTreatmentBedRoom/GetView?param=BASE64
  Future<List<Map<String, dynamic>>> getPatientsInRoomsByDept(int departmentId) async {
    final resp = await get('HisTreatmentBedRoom', 'GetView', {
      'DEPARTMENT_ID': departmentId,
      'IS_PAUSE': false,
      'IS_ACTIVE': 1,
    });
    final list = _extractList(resp);
    debugPrint('getPatientsInRoomsByDept($departmentId): ${list.length} BN');
    return list;
  }

  /// Lấy BN đang điều trị trong khoa (cả khám + nội trú, không filter phòng)
  /// GET /api/HisTreatment/GetView?param=BASE64
  Future<List<Map<String, dynamic>>> getTreatmentsByDepartment(int departmentId, {int limit = 200}) async {
    final resp = await get('HisTreatment', 'GetView', {
      'DEPARTMENT_ID': departmentId,
      'IS_PAUSE': false,
      'IS_ACTIVE': 1,
      'IS_OUT': false,
      'LIMIT': limit,
    });
    final list = _extractList(resp);
    debugPrint('getTreatmentsByDepartment($departmentId): ${list.length} BN');
    return list;
  }

  /// Tra cứu BN theo mã ĐT
  /// GET /api/HisTreatment/Get?param=BASE64
  /// v3.0.45: HIS Pro dùng `TREATMENT_CODE__EXACT` (không phải `TREATMENT_CODE`)
  /// (verified từ log HIS Pro desktop 18/7/2026 - cmdLn API call)
  Future<Map<String, dynamic>?> getTreatmentByCode(String treatmentCode) async {
    return get('HisTreatment', 'Get', {
      'TREATMENT_CODE__EXACT': treatmentCode,
      'IS_INCLUDED_DELETED': false,
    });
  }

  /// Tra cứu BN theo mã BN
  Future<Map<String, dynamic>?> getPatientByCode(String patientCode) async {
    return get('HisPatient', 'Get', {
      'PATIENT_CODE': patientCode,
      'IS_INCLUDED_DELETED': false,
    });
  }

  // ============================================================
  // EXISTING METHODS
  // ============================================================

  /// Get tracking list theo TREATMENT_ID
  Future<dynamic> getTrackingView(int treatmentId, {int start = 0, int limit = 50}) async {
    final body = {
      'TREATMENT_ID': treatmentId,
      'IS_INCLUDED_DELETED': false,
      'ORDER_FIELD': 'TRACKING_TIME',
      'ORDER_DIRECTION': 'DESC',
      'CREATE_TIME_TO': null,
      'DATA_DOMAIN_FILTER': false,
    };
    return get('HisTracking', 'GetView', body);
  }

  /// Get full tracking data (with materials, medi mats, services)
  Future<dynamic> getTrackingData(int treatmentId, {bool includeMaterial = true}) async {
    final body = {
      'TreatmentId': treatmentId,
      'IncludeMaterial': includeMaterial,
      'IncludeMoveBackMediMat': true,
      'IncludeBloodPres': false,
    };
    return get('HisTracking', 'GetData', body);
  }

  /// Check if document exists in EMR
  /// v3.0.45: HIS Pro dùng `TREATMENT_CODE__EXACT` cho EmrDocument queries
  Future<dynamic> getEmrDocumentView(String treatmentCode, int documentTypeId) async {
    final body = {
      'DOCUMENT_TYPE_ID': documentTypeId,
      'TREATMENT_CODE__EXACT': treatmentCode,
      'IS_DELETE': false,
      'IS_ACTIVE': 1,
    };
    return get('EmrDocument', 'GetView', body);
  }

  /// Save tracking (insert/update)
  Future<dynamic> saveTracking(Map<String, dynamic> trackingData) async {
    return post('HisTracking', 'Save', trackingData);
  }

  /// Save EMR document (save + ký + đẩy EMR portal)
  Future<dynamic> saveEmrDocument(Map<String, dynamic> documentData) async {
    return post('EmrDocument', 'Save', documentData);
  }

  /// Generate Mps template (preview/save)
  Future<dynamic> generateMpsTemplate(String mpsCode, Map<String, dynamic> data) async {
    return post(mpsCode, 'Generate', data);
  }

  /// Get template fields/structure
  Future<dynamic> getMpsTemplate(String mpsCode) async {
    return get(mpsCode, 'GetTemplate', {});
  }
}

class HisProLoginResult {
  final bool success;
  final String? token;
  final String? message;
  HisProLoginResult({required this.success, this.token, this.message});
}