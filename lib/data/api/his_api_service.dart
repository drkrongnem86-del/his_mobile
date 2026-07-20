import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';

/// HIS Pro API Service - v1.4.1
/// Server: 117.2.25.67 (qua VPN BV)
class HisApiService {
  late final Dio _dio;

  HisApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: AppConstants.connectionTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
  }

  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Tạo param base64 theo format HIS Pro
  String _encodeParam(Map<String, dynamic> apiData, [int limit = 100]) {
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

  /// Login qua ACS server - thử CẢ HAI server (fallback)
  Future<LoginResult> login(String loginName, String password) async {
    final param = _encodeParam({
      'LOGIN_NAME': loginName,
      'PASSWORD': password,
      'APPLICATION_CODE': 'HIS',
      'APP_VERSION': AppConstants.appVersion,
      'IS_ACTIVE': 1,
    });

    String? lastError;
    
    // Thử cả 2 server URLs
    for (final baseUrl in ConnectionService.instance.acsUrlCandidates) {
      try {
        print('🔐 Trying: $baseUrl');

        final response = await _dio.get(
          '${baseUrl}api/AcsToken/Authorize',
          queryParameters: {'param': param},
          options: Options(
            headers: {'Content-Type': 'application/json'},
            receiveTimeout: Duration(seconds: 15),
            sendTimeout: Duration(seconds: 15),
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          print('   HTTP ${response.statusCode} - thử server tiếp');
          continue;
        }

        Map<String, dynamic> data = {};
        if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try { data = jsonDecode(response.data); } catch (e) {}
        }

        // Sai tài khoản → trả về ngay
        if (data['Success'] == false) {
          String msg = 'Sai tài khoản hoặc mật khẩu';
          if (data['Param'] is Map) {
            final p = data['Param'];
            if (p is Map && p['Messages'] is List && (p['Messages'] as List).isNotEmpty) {
              msg = (p['Messages'] as List).first.toString();
            }
          }
          return LoginResult(success: false, message: msg);
        }

        if (data['Success'] == true) {
          final tokenData = data['Data'];
          String token = '';
          if (tokenData is Map) {
            token = tokenData['TOKEN']?.toString() ?? 
                    tokenData['Token']?.toString() ?? '';
          } else if (tokenData is String) {
            token = tokenData;
          }
          print('   ✅ Login OK!');
          return LoginResult(success: true, token: token, userData: tokenData);
        }

        lastError = 'Phản hồi không xác định';
      } catch (e) {
        lastError = '${e.toString().substring(0, 60)}';
        print('   ❌ Error: $lastError - thử server tiếp');
        continue;
      }
    }

    return LoginResult(
      success: false, 
      message: lastError?.contains('Timeout') == true 
        ? '⏱️ Timeout - Bật VPN?' 
        : '❌ $lastError'
    );
  }

  /// Lấy danh sách yêu cầu dịch vụ (ExecuteRoom)
  Future<HisResult> getServiceRequests({
    int executeRoomId = AppConstants.ROOM_ID_KHAM_CAP_CUU,
    DateTime? date,
    int limit = 100,
  }) async {
    try {
      final d = date ?? DateTime.now();
      final dateLong = d.year * 10000000000 +
                        d.month * 100000000 +
                        d.day * 1000000;

      // Filter thực tế từ log HIS Pro
      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2],
        'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
        'TDL_PATIENT_TYPE_IDs': [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
        'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
        'EXECUTE_ROOM_ID': executeRoomId,
        'INTRUCTION_DATE__EQUAL': dateLong,
        'HAS_EXECUTE': true,
        'IS_NOT_KSK_REQURIED_APROVAL__OR__IS_KSK_APPROVE': true,
        'ORDER_FIELD': 'INTRUCTION_DATE',
        'ORDER_DIRECTION': 'DESC',
        'ORDER_FIELD1': 'SERVICE_REQ_STT_ID',
        'ORDER_DIRECTION1': 'ASC',
        'ORDER_FIELD2': 'PRIORITY',
        'ORDER_DIRECTION2': 'DESC',
        'ORDER_FIELD3': 'NUM_ORDER',
        'ORDER_DIRECTION3': 'ASC',
      };

      final param = _encodeParam(apiData, limit);

      print('📡 MCH GetLView: ${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView');

      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy danh sách yêu cầu dịch vụ theo EXECUTE_ROOM_ID (phòng khám)
  Future<HisResult> getServiceRequestsByRoom(int executeRoomId, {int limit = 100}) async {
    try {
      final d = DateTime.now();
      final dateLong = d.year * 10000000000 +
                       d.month * 100000000 +
                       d.day * 1000000;

      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2],
        'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
        'TDL_PATIENT_TYPE_IDs': [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
        'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
        'EXECUTE_ROOM_ID': executeRoomId,
        'INTRUCTION_DATE__EQUAL': dateLong,
        'HAS_EXECUTE': true,
        'IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE': true,
        'ORDER_FIELD': 'INTRUCTION_DATE',
        'ORDER_DIRECTION': 'DESC',
        'ORDER_FIELD1': 'SERVICE_REQ_STT_ID',
        'ORDER_DIRECTION1': 'ASC',
        'ORDER_FIELD2': 'PRIORITY',
        'ORDER_DIRECTION2': 'DESC',
        'ORDER_FIELD3': 'NUM_ORDER',
        'ORDER_DIRECTION3': 'ASC',
      };

      final param = _encodeParam(apiData, limit);

      print('📡 MCH GetLView (RoomID=$executeRoomId): ${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView');

      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy danh sách yêu cầu dịch vụ theo DEPARTMENT_ID
  /// Strategy: filter bằng REQUEST_DEPARTMENT_ID (nếu API hỗ trợ)
  /// Nếu rỗng → fallback: lấy all + filter client-side bằng mapping room→dept
  Future<HisResult> getServiceRequestsByDepartment(int departmentId, {int limit = 100}) async {
    try {
      final d = DateTime.now();
      final dateLong = d.year * 10000000000 +
                       d.month * 100000000 +
                       d.day * 1000000;

      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2],
        'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
        'TDL_PATIENT_TYPE_IDs': [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
        'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
        'REQUEST_DEPARTMENT_ID': departmentId,
        'INTRUCTION_DATE__EQUAL': dateLong,
        'HAS_EXECUTE': true,
        'IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE': true,
        'ORDER_FIELD': 'INTRUCTION_DATE',
        'ORDER_DIRECTION': 'DESC',
        'ORDER_FIELD1': 'SERVICE_REQ_STT_ID',
        'ORDER_DIRECTION1': 'ASC',
        'ORDER_FIELD2': 'PRIORITY',
        'ORDER_DIRECTION2': 'DESC',
        'ORDER_FIELD3': 'NUM_ORDER',
        'ORDER_DIRECTION3': 'ASC',
      };

      final param = _encodeParam(apiData, limit);

      print('📡 MCH GetLView (DeptID=$departmentId): ${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView');

      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        // Nếu rỗng → thử fallback: lấy all hôm nay + filter client-side
        Map<String, dynamic> data = {};
        if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        }
        final innerData = data['Data'];
        if (innerData is List && innerData.isEmpty) {
          print('⚠️ Dept filter rỗng → fallback lấy all + filter client-side');
          return await _fallbackFilterByDepartment(departmentId, dateLong, limit);
        }
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Fallback: lấy tất cả BN hôm nay, filter client-side theo department
  Future<HisResult> _fallbackFilterByDepartment(int departmentId, int dateLong, int limit) async {
    try {
      // 1. Lấy tất cả phòng
      final roomsRes = await getRooms();
      final allRooms = <int, int>{}; // roomId -> deptId
      if (roomsRes.success && roomsRes.data is Map) {
        final d = roomsRes.data as Map;
        if (d['Success'] == true && d['Data'] is List) {
          for (final r in (d['Data'] as List)) {
            if (r is Map) {
              final rid = r['ID'];
              final did = r['DEPARTMENT_ID'];
              if (rid != null && did != null) {
                allRooms[rid] = did;
              }
            }
          }
        }
      }

      // 2. Lấy tất cả service req hôm nay (KHÔNG filter room)
      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2],
        'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
        'TDL_PATIENT_TYPE_IDs': [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
        'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
        'INTRUCTION_DATE__EQUAL': dateLong,
        'HAS_EXECUTE': true,
        'IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE': true,
        'ORDER_FIELD': 'INTRUCTION_DATE',
        'ORDER_DIRECTION': 'DESC',
        'ORDER_FIELD1': 'SERVICE_REQ_STT_ID',
        'ORDER_DIRECTION1': 'ASC',
        'ORDER_FIELD2': 'PRIORITY',
        'ORDER_DIRECTION2': 'DESC',
        'ORDER_FIELD3': 'NUM_ORDER',
        'ORDER_DIRECTION3': 'ASC',
      };

      final param = _encodeParam(apiData, 500); // Lấy nhiều hơn để filter
      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode != 200) {
        return HisResult(success: false, message: 'HTTP ${response.statusCode}');
      }

      // 3. Filter client-side
      final data = response.data;
      if (data is Map && data['Data'] is List) {
        final filtered = (data['Data'] as List).where((item) {
          if (item is! Map) return false;
          // Check REQUEST_DEPARTMENT_ID (BS yêu cầu từ khoa nào)
          if (item['REQUEST_DEPARTMENT_ID'] == departmentId) return true;
          // Fallback: check EXECUTE_ROOM_ID's department
          final execRoom = item['EXECUTE_ROOM_ID'];
          if (execRoom != null && allRooms[execRoom] == departmentId) return true;
          return false;
        }).toList();
        return HisResult(
          success: true,
          data: {
            'Success': true,
            'Data': filtered,
            'Count': filtered.length,
            'Description': 'Filtered client-side (${filtered.length} BN)',
          },
        );
      }
      return HisResult(success: true, data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy tất cả yêu cầu dịch vụ hôm nay (không filter)
  Future<HisResult> getServiceRequestsToday({int limit = 500}) async {
    try {
      final d = DateTime.now();
      final dateLong = d.year * 10000000000 +
                       d.month * 100000000 +
                       d.day * 1000000;

      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2],
        'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
        'TDL_PATIENT_TYPE_IDs': [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
        'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
        'INTRUCTION_DATE__EQUAL': dateLong,
        'HAS_EXECUTE': true,
        'IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE': true,
        'ORDER_FIELD': 'INTRUCTION_DATE',
        'ORDER_DIRECTION': 'DESC',
        'ORDER_FIELD1': 'SERVICE_REQ_STT_ID',
        'ORDER_DIRECTION1': 'ASC',
        'ORDER_FIELD2': 'PRIORITY',
        'ORDER_DIRECTION2': 'DESC',
        'ORDER_FIELD3': 'NUM_ORDER',
        'ORDER_DIRECTION3': 'ASC',
      };

      final param = _encodeParam(apiData, limit);

      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy tất cả phòng từ HIS Pro
  Future<HisResult> getRooms() async {
    try {
      final param = _encodeParam({});
      final response = await _dio.get(
        '${ConnectionService.instance.mosUrl}api/HisRoom/GetView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = {};
        if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try { data = jsonDecode(response.data); } catch (e) {}
        }
        return HisResult(success: true, data: data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  // ===================================================================
  // THONGKE SERVER (thongke.benhvienninhthuan.vn:8080) - Data BN thật
  // ===================================================================

  String? _csrfToken;
  Map<String, String> _sessionCookies = {};
  String? _tokenCode;
  String? _cmdLn;

  /// Login to thongke server (cookie-based session)
  /// Lưu cookies vào SharedPreferences để giữ session khi restart app
  /// Thực ra dùng HIS Pro API token (LOGIN_NAME only, không cần password)
  Future<HisResult> thongkeLogin(String username, String password) async {
    try {
      print('🔐 HIS Pro token login: $username');

      // Bước 1: Gọi api/AcsToken/Authorize với LOGIN_NAME only
      // Token được cache ở client, không cần password trong API call
      final apiData = {
        'LOGIN_NAME': username,
        'APPLICATION_CODE': 'HIS',
        'APP_VERSION': '2.405.0',
      };

      final param = _encodeParam(apiData);
      final r1 = await _dio.get(
        '${ConnectionService.instance.acsUrl}api/AcsToken/Authorize',
        queryParameters: {'param': param},
        options: Options(
          headers: {
            'User-Agent': 'HIS Mobile 2.405.0',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      print('📡 Token response: ${r1.statusCode}');

      if (r1.statusCode != 200) {
        return HisResult(success: false, message: 'Cannot get token: HTTP ${r1.statusCode}');
      }

      // Parse token from response
      String? tokenCode;
      if (r1.data is Map) {
        final m = r1.data as Map;
        if (m['Data'] is String) {
          tokenCode = m['Data'] as String;
        } else if (m['Data'] is Map) {
          tokenCode = m['Data']['TokenCode'] ?? m['Data']['token'];
        }
        // Also check direct fields
        tokenCode ??= m['TokenCode'] ?? m['token'];
      } else if (r1.data is String) {
        tokenCode = r1.data;
      }

      if (tokenCode == null || tokenCode.isEmpty) {
        // Try extract from raw response
        final raw = r1.data?.toString() ?? '';
        final tkm = RegExp(r'"TokenCode"\s*:\s*"([^"]+)"').firstMatch(raw);
        if (tkm != null) tokenCode = tkm.group(1);
      }

      print('🔑 TokenCode: ${tokenCode?.substring(0, tokenCode.length > 20 ? 20 : tokenCode.length)}...');

      if (tokenCode == null || tokenCode.isEmpty) {
        return HisResult(success: false, message: 'No TokenCode in response');
      }

      _tokenCode = tokenCode;

      // Build cmdLn string
      _cmdLn = '|AcsBaseUri|${ConnectionService.instance.acsUrl}'
          '|SdaBaseUri|http://172.16.9.6:1410/'
          '|SarBaseUri|http://172.16.9.6:1409/'
          '|MosBaseUri|http://172.16.9.6:1408/'
          '|ApplicationCode|HIS'
          '|TokenCode|$tokenCode'
          '|CacheType|1'
          '|RedisSaveType|0';

      // Lưu token vào SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hispro_user', username);
      await prefs.setString('hispro_token', tokenCode);
      await prefs.setString('hispro_cmdLn', _cmdLn!);
      print('💾 Saved HIS Pro session to SharedPreferences');

      return HisResult(success: true, data: {'tokenCode': tokenCode, 'cmdLn': _cmdLn});
    } catch (e) {
      print('❌ Login error: $e');
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Restore HIS Pro token từ SharedPreferences
  Future<void> thongkeRestoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _tokenCode = prefs.getString('hispro_token');
      _cmdLn = prefs.getString('hispro_cmdLn');
      if (_tokenCode != null && _cmdLn != null) {
        final len = _tokenCode!.length > 20 ? 20 : _tokenCode!.length;
        print('🔄 Restored HIS Pro token: ${_tokenCode!.substring(0, len)}...');
      }
    } catch (e) {
      print('❌ Restore error: $e');
    }
  }

  Future<void> thongkeLogout() async {
    _tokenCode = null;
    _cmdLn = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hispro_user');
    await prefs.remove('hispro_token');
    await prefs.remove('hispro_cmdLn');
  }

  /// Restore cookies từ SharedPreferences (gọi khi app start)
  Future<void> thongkeRestoreSessionLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookies = prefs.getStringList('thongke_cookies') ?? [];
      _csrfToken = prefs.getString('thongke_csrf');
      _sessionCookies.clear();
      for (final c in cookies) {
        final pair = c.split('=');
        if (pair.length >= 2) {
          _sessionCookies[pair[0].trim()] = pair[1].trim();
        }
      }
      if (_sessionCookies.isNotEmpty) {
        print('🔄 Restored ${_sessionCookies.length} thongke cookies');
      }
    } catch (e) {
      print('❌ Restore session error: $e');
    }
  }

  /// Re-login khi 401 + retry
  Future<HisResult> _retryWithRelogin<T>(
    Future<HisResult> Function() originalCall,
    String username,
    String password,
  ) async {
    // Try original first
    final first = await originalCall();
    if (first.success) return first;

    // If 401/403/302 → re-login then retry
    final msg = first.message ?? '';
    if (msg.contains('401') || msg.contains('403') || msg.contains('302')) {
      print('🔄 Got $msg → re-login thongke...');
      final relogin = await thongkeLogin(username, password);
      if (relogin.success) {
        return await originalCall();
      }
    }
    return first;
  }

  /// Get list of EMR treatments (patients with visits today)
  /// URL: /emr/index/get-list-emr-treatment?dateType=in&date_from=YYYY-MM-DD&...
  /// Dùng Thongke cookies (CookieManager tự gửi). Nếu session hết → trả empty data.
  Future<HisResult> thongkeGetPatients({
    DateTime? date,
    String? treatmentCode,
    String? department,
    int start = 0,
    int length = 500,
  }) async {
    return await _thongkeGetPatientsRaw(date, treatmentCode, department, start, length);
  }

  Future<HisResult> _thongkeGetPatientsRaw(
    DateTime? date,
    String? treatmentCode,
    String? department,
    int start,
    int length,
  ) async {
    try {
      final d = date ?? DateTime.now();
      final dateStr = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      // Gọi Thongke API với COOKIES (CookieManager tự gửi XSRF-TOKEN + qlbv_session)
      // Endpoint: /emr/index/get-list-emr-treatment
      // Response: {draw, recordsTotal, recordsFiltered, data: [...]}
      // Filter server-side: chỉ filter theo dateType + date_from/to
      // Filter client-side: theo department_code field trong data
      final params = <String, String>{
        'dateType': 'in',
        'date_from': dateStr,
        'date_to': dateStr,
        'length': '500',  // Lấy tối đa 500 BN để filter
        'start': '$start',
      };

      if (treatmentCode != null && treatmentCode.isNotEmpty) {
        params['treatment_code'] = treatmentCode;
      }

      print('🌐 Thongke get-list-emr-treatment: date=$dateStr, dept=$department');

      final r = await _dio.get(
        '${ConnectionService.instance.acsUrl}/emr/index/get-list-emr-treatment',
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '${ConnectionService.instance.acsUrl}/home',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      print('📡 Response: ${r.statusCode}, content-type: ${r.headers.value("content-type")}');

      // Response có thể là HTML (nếu session hết hạn) hoặc JSON
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        if (m['data'] is List) {
          var list = List<Map<String, dynamic>>.from(m['data'] as List);

          // Filter client-side theo department_code
          if (department != null && department.isNotEmpty) {
            list = list.where((p) {
              final dept = p['department_code']?.toString() ?? '';
              return dept == department;
            }).toList();
            print('✅ Got ${list.length} BN in dept $department (filtered from ${m["recordsTotal"]} total)');
          } else {
            print('✅ Got ${list.length} BN (total: ${m["recordsTotal"]})');
          }
          return HisResult(success: true, data: list);
        }
        return HisResult(success: false, message: m['message']?.toString() ?? 'Data: No data');
      }
      return HisResult(success: false, message: 'HTTP ${r.statusCode}', data: r.data);
    } catch (e) {
      print('❌ Get patients error: $e');
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Get patient by treatment code
  Future<HisResult> thongkeGetPatientByTreatment(String treatmentCode) async {
    return thongkeGetPatients(treatmentCode: treatmentCode, length: 1);
  }

  // ===================================================================
  // DASHBOARD SERVER (172.16.212.213:5173) - Data BN thật
  // ===================================================================

  /// Tìm bệnh nhân từ Dashboard server (BVĐK Ninh Thuận)
  /// API: GET /api/search-patient?name={query}&exact=0
  /// Dashboard JS: H.get('/api/search-patient', {params: {name: Gm, exact: Ym ? '1' : '0'}})
  Future<HisResult> dashboardSearchPatient({String? name, String? khoa, int exact = 0}) async {
    try {
      // Endpoint yêu cầu 'name' - nếu rỗng sẽ trả all
      final searchName = (name != null && name.isNotEmpty) ? name : '';
      final params = <String, dynamic>{
        'name': searchName,
        'exact': exact.toString(),
      };

      print('🌐 Dashboard search-patient: name="$searchName" exact=$exact');

      final response = await _dio.get(
        '${ConnectionService.instance.acsUrl}/search-patient',
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Accept-Charset': 'utf-8',
          },
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      print('📡 Response: status=${response.statusCode}, type=${response.data.runtimeType}');

      if (response.statusCode == 200) {
        // Response có thể là array trực tiếp hoặc {data: [...]}
        List<dynamic> data = [];
        if (response.data is List) {
          data = response.data;
        } else if (response.data is Map) {
          final m = response.data as Map;
          if (m['data'] is List) data = m['data'];
          else if (m['Data'] is List) data = m['Data'];
          else if (m['patients'] is List) data = m['patients'];
          else if (m['result'] is List) data = m['result'];
        }
        print('✅ Dashboard returned ${data.length} patients');
        if (data.isNotEmpty) {
          print('📋 First item keys: ${(data.first as Map).keys.take(10).join(", ")}');
        }
        return HisResult(success: true, data: List<Map<String, dynamic>>.from(data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      print('❌ Search error: $e');
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Loại bỏ dấu tiếng Việt để search thêm nếu name có dấu
  String _removeDiacritics(String str) {
    const withDiacritics = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const withoutDiacritics = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    String result = str;
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result;
  }

  /// Lấy tất cả BN đang điều trị (gọi với name="" - trả về all)
  Future<HisResult> dashboardGetAllPatients() async {
    return dashboardSearchPatient(name: '');
  }

  /// Lấy BN theo khoa từ dashboard
  Future<HisResult> dashboardGetPatientsByKhoa(String khoaCode) async {
    return dashboardSearchPatient(khoa: khoaCode);
  }

  /// Lấy BN nguy kịch
  Future<HisResult> dashboardGetCriticalPatients() async {
    try {
      final response = await _dio.get(
        '${ConnectionService.instance.acsUrl}/his/critical-patients',
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy kết quả CLS theo khoa (cho Báo cáo)
  Future<HisResult> dashboardGetDepartmentResults({String? khoaCode}) async {
    try {
      final params = <String, dynamic>{};
      if (khoaCode != null && khoaCode.isNotEmpty) params['khoa'] = khoaCode;

      final response = await _dio.get(
        '${ConnectionService.instance.acsUrl}/department-results',
        queryParameters: params,
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy thông tin lâm sàng (cho Báo cáo)
  Future<HisResult> dashboardGetClinicalInfo() async {
    try {
      final response = await _dio.get(
        '${ConnectionService.instance.acsUrl}/clinical-info',
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy sử dụng giường (cho Báo cáo)
  Future<HisResult> dashboardGetBedUtilization() async {
    try {
      final response = await _dio.get(
        '${ConnectionService.instance.acsUrl}/bed-utilization-detail',
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Lấy danh sách phòng user được phân công
  /// Từ log HIS Pro: api/HisUserRoom/GetView
  Future<HisResult> getUserRooms(String loginName) async {
    try {
      final param = _encodeParam({
        'IS_ACTIVE': 1,
        'LOGINNAME__EXACT': loginName,
      });

      final response = await _dio.get(
        '${ConnectionService.instance.mosUrl}api/HisUserRoom/GetView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = {};
        if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try { data = jsonDecode(response.data); } catch (e) {}
        }
        return HisResult(success: true, data: data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: e.toString().substring(0, e.toString().length.clamp(0, 100)));
    }
  }

  /// Lấy danh sách nhân viên để biết DEPARTMENT_ID (optional)
  Future<HisResult> getEmployee(String loginName) async {
    try {
      final param = _encodeParam({
        'LOGINNAME__EXACT': loginName,
        'IS_ACTIVE': 1,
      });

      final response = await _dio.get(
        '${ConnectionService.instance.mosUrl}api/HisEmployee/GetView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = {};
        if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try { data = jsonDecode(response.data); } catch (e) {}
        }
        return HisResult(success: true, data: data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      return HisResult(success: false, message: e.toString().substring(0, e.toString().length.clamp(0, 100)));
    }
  }

  /// Test kết nối
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get(
        ConnectionService.instance.acsUrl,
        options: Options(receiveTimeout: Duration(seconds: 10)),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// v2.97.0: Test URL cụ thể (cho ReportsScreen check Dashboard)
  Future<bool> testUrlReachable(String url, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
      );
      return response.statusCode != null && response.statusCode! < 500;
    } catch (e) {
      // Try GET if HEAD fails
      try {
        final response = await _dio.get(
          url,
          options: Options(
            receiveTimeout: timeout,
            sendTimeout: timeout,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        return response.statusCode != null;
      } catch (_) {
        return false;
      }
    }
  }

  String _handleError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '⏱️ Timeout - Kiểm tra VPN';
        case DioExceptionType.connectionError:
          return '❌ Không kết nối server\n📌 VPN chưa bật?';
        case DioExceptionType.badResponse:
          final s = e.response?.statusCode;
          if (s == 401) return '🔐 Sai tài khoản';
          if (s == 403) return '🚫 Không quyền';
          if (s == 404) return '🔍 Không tìm thấy';
          if (s == 500) return '🖥️ Lỗi server HIS';
          return '❗ HTTP $s';
        default:
          return '⚠️ ${e.message}';
      }
    }
    return '⚠️ Lỗi: ${e.toString().substring(0, 80)}';
  }
}

/// Login Result
class LoginResult {
  final bool success;
  final String? token;
  final dynamic userData;
  final String? message;
  LoginResult({required this.success, this.token, this.userData, this.message});
}

/// HIS API Result
class HisResult {
  final bool success;
  final dynamic data;
  final String? message;
  HisResult({required this.success, this.data, this.message});
}

/// Connection Test Result
class ConnectionTest {
  final bool success;
  final Map<String, bool> services;
  ConnectionTest({required this.success, required this.services});
}
