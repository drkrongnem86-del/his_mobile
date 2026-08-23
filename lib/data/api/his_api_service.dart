import 'dart:convert';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show debugPrint;  // v3.0.168: for getAcsUsers
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/services/data_service.dart';

/// HIS Pro API Service - v1.4.1
/// Server: 117.2.25.67 (qua VPN BV) hoặc 172.16.9.6 (LAN)
/// v3.0.162: Fix HIS Pro auth - dùng TokenCode headers thay vì Bearer
/// v3.0.162: Fix response parsing - HIS Pro trả text/plain, cần jsonDecode
class HisApiService {
  late final Dio _dio;

  HisApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: AppConstants.connectionTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // v3.0.162: HIS Pro dùng TokenCode headers (KHÔNG Bearer)
        'TokenCode': '',
        'ApplicationCode': 'HIS',
        'ClientIpAddress': '172.16.200.101',
      },
    ));
  }

  void setAuthToken(String token) {
    // v3.0.162: Set cả 2 - Bearer (cho tương thích cũ) + TokenCode (HIS Pro chuẩn)
    _dio.options.headers['Authorization'] = 'Bearer $token';
    _dio.options.headers['TokenCode'] = token;
  }

  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
    _dio.options.headers.remove('TokenCode');
  }

  /// v3.0.162: Procedure room API thực tế ở port 1408 (MOS)
  /// (mosUrl = 1429 sai, chỉ dùng cho MCH service)
  /// ocrUrl = 1425 chỉ cho HisExecuteUser, KHÔNG có GetLView
  String get _procedureRoomUrl {
    final mos = ConnectionService.instance.mosUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse(mos);
    return '${uri.scheme}://${uri.host}:1408';
  }

  /// v3.0.162: Unwrap HIS Pro response
  /// HIS Pro trả Content-Type: text/plain nên Dio parse thành String
  /// → cần jsonDecode trước khi dùng
  dynamic _unwrap(dynamic data) {
    if (data is String && data.isNotEmpty) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
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
      // v3.1.14: Thêm status 3 (đã thực hiện) giống HIS Desktop - lấy đủ 87 BN
      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2, 3],
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
  /// v3.1.15: thêm serviceReqSttIds param - cho phép lọc theo status (mặc định {1,2,3})
  Future<HisResult> getServiceRequestsByRoom(int executeRoomId, {int limit = 100, Set<int>? serviceReqSttIds}) async {
    try {
      final d = DateTime.now();
      final dateLong = d.year * 10000000000 +
                       d.month * 100000000 +
                       d.day * 1000000;

      // v3.1.15: Dùng filter từ caller, mặc định {1,2,3} nếu không truyền
      final statuses = serviceReqSttIds?.toList() ?? [1, 2, 3];

      final apiData = {
        // v3.1.15: Status filter động từ UI (3 nút riêng biệt)
        'SERVICE_REQ_STT_IDs': statuses,
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

      // v3.0.162: Fix port - procedure room API ở port 1408 (MOS), KHÔNG phải 1425 (OCR)
      print('📡 ProcedureRoom GetLView (RoomID=$executeRoomId): $_procedureRoomUrl/api/HisServiceReq/GetLView');

      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200) {
        // v3.0.162: Unwrap String response (HIS Pro text/plain)
        final unwrapped = _unwrap(response.data);
        return HisResult(success: true, data: unwrapped);
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
        // v3.1.14: Thêm status 3 (đã thực hiện) giống HIS Desktop
        'SERVICE_REQ_STT_IDs': [1, 2, 3],
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
        // v3.1.14: Thêm status 3 (đã thực hiện) giống HIS Desktop
        'SERVICE_REQ_STT_IDs': [1, 2, 3],
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
        // v3.1.14: Thêm status 3 (đã thực hiện) giống HIS Desktop
        'SERVICE_REQ_STT_IDs': [1, 2, 3],
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

  // ===================================================================
  // v3.0.116: Phòng thủ thuật HSCC - 3 API sources
  // v3.1.13: Port từ v3.1.13 - thêm 3 methods + 1 finish method
  // ===================================================================

  /// Lấy danh sách yêu cầu dịch vụ theo room từ Data API 3000
  /// POST http://113.163.187.3:3000/v1/patient/benh-nhan-buong-benh
  /// v3.1.13: Trả về BN có BED_ROOM_ID trùng với executeRoomId (mapping ngược)
  /// - deptId: filter thêm theo DEPARTMENT_ID (nếu muốn giới hạn)
  /// v3.1.15: thêm serviceReqSttIds param - filter client-side theo status
  Future<HisResult> getServiceRequestsByRoomDataApi(int roomId, {int limit = 100, int? departmentId, Set<int>? serviceReqSttIds}) async {
    try {
      // Data 3000 API: POST /v1/patient/benh-nhan-buong-benh
      // Yêu cầu: Bearer token từ /v1/auth/login
      // Body: {USERNAME, BED_ROOM_IDs: [roomId]}
      // Map field names về chuẩn HIS Pro
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ));
      // Lấy token từ DataService (singleton)
      final token = DataService.instance.accessToken;
      if (token != null && token.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }
      final r = await dio.post(
        'http://113.163.187.3:3000/v1/patient/benh-nhan-buong-benh',
        data: {
          'USERNAME': DataService.instance.email ?? 'nemk',
          'BED_ROOM_IDs': [roomId],
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (r.statusCode != 200 && r.statusCode != 201) {
        return HisResult(success: false, message: 'Data 3000: HTTP ${r.statusCode}', data: r.data);
      }
      // Map response về chuẩn HIS Pro (giống các API khác)
      final items = r.data is List ? r.data as List : (r.data is Map ? r.data['data'] as List? : null) ?? [];
      final list = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is Map) {
          // v3.0.118: Fix tên BN thật từ Data 3000 (trước dùng 'patient_name' sai - thực tế là 'HOTENBN' / 'VIR_PATIENT_NAME' / 'tdl_patient_name')
          final patientName = (raw['HOTENBN'] ?? raw['hotenbn'] ?? raw['VIR_PATIENT_NAME'] ?? raw['vir_patient_name']
              ?? raw['TDL_PATIENT_NAME'] ?? raw['tdl_patient_name'] ?? raw['TEN_BENH_NHAN'] ?? raw['ten_benh_nhan'] ?? '').toString();
          final patientNameUnsigned = (raw['HOTENBN'] ?? raw['hotenbn'] ?? raw['TDL_PATIENT_UNSIGNED_NAME'] ?? raw['TEN_BENH_NHAN'] ?? '').toString();
          list.add({
            'ID': raw['treatment_code'] ?? raw['TREATMENT_CODE'] ?? raw['id'],
            'TDL_TREATMENT_CODE': raw['treatment_code'] ?? raw['TREATMENT_CODE'] ?? raw['MADT'],
            'TDL_PATIENT_CODE': raw['patient_code'] ?? raw['PATIENT_CODE'] ?? raw['tdl_patient_code'] ?? raw['MABN'],
            'TDL_PATIENT_UNSIGNED_NAME': patientNameUnsigned,
            'TDL_PATIENT_NAME': patientName,
            'TDL_PATIENT_DOB': raw['dob'] ?? raw['DOB'] ?? raw['tdl_patient_dob'] ?? raw['NGAYSINH'],
            'TDL_PATIENT_ADDRESS': raw['address'] ?? raw['ADDRESS'] ?? raw['tdl_patient_address'] ?? raw['DIACHI'],
            'TDL_PATIENT_PHONE': raw['phone'] ?? raw['PHONE'] ?? raw['tdl_patient_phone'],
            'TDL_HEIN_CARD_NUMBER': raw['hein_card_number'] ?? raw['HEIN_CARD_NUMBER'] ?? raw['BHYT'],
            'TREATMENT_TYPE_NAME': raw['treatment_type_name'] ?? raw['TREATMENT_TYPE_NAME'],
            'PATIENT_TYPE_NAME': raw['patient_type_name'] ?? raw['PATIENT_TYPE_NAME'],
            'IN_TIME': raw['in_time'] ?? raw['IN_TIME'] ?? raw['ADD_TIME'],
            'OUT_TIME': raw['out_time'] ?? raw['OUT_TIME'],
            'DEPARTMENT_NAME': raw['department_name'] ?? raw['DEPARTMENT_NAME'] ?? raw['last_department'] ?? raw['MAKHOA'],
            'IS_BHYT': (raw['patient_type_name'] ?? raw['PATIENT_TYPE_NAME'] ?? '').toString().contains('BHYT'),
            'BED_NAME': raw['bed_name'] ?? raw['BED_NAME'] ?? raw['TENBUONGBENH'],
            'SERVICE_REQ_CODE': raw['service_req_code'] ?? raw['SERVICE_REQ_CODE'],
            'SERVICE_NAME': raw['service_name'] ?? raw['SERVICE_NAME'],
            'SERVICE_REQ_STT_ID': raw['service_req_stt_id'] ?? raw['SERVICE_REQ_STT_ID'] ?? 1,
            'SERVICE_REQ_STT_NAME': raw['service_req_stt_name'] ?? raw['SERVICE_REQ_STT_NAME'] ?? '',
            'PRIORITY': raw['priority'] ?? raw['PRIORITY'] ?? 0,
            'ICD_CODE': raw['icd_code'] ?? raw['ICD_CODE'],
            'ICD_NAME': raw['icd_name'] ?? raw['ICD_NAME'] ?? raw['ICD_TEXT'],
            'INTRUCTION_TIME': raw['intruction_time'] ?? raw['INTRUCTION_TIME'],
            '_DATA_SOURCE': 'DATA_3000_BED_$roomId',
          });
        }
      }
      // v3.1.15: Filter theo status (client-side)
      final statuses = serviceReqSttIds ?? {1, 2, 3};
      final filtered = list.where((p) {
        final stt = (p['SERVICE_REQ_STT_ID'] ?? 1) as int;
        return statuses.contains(stt);
      }).toList();

      return HisResult(success: true, data: filtered);
    } catch (e) {
      return HisResult(success: false, message: 'Data 3000: ${_handleError(e)}');
    }
  }

  /// Lấy danh sách yêu cầu dịch vụ từ Public API 8080 (113.163.187.3:8080)
  /// GET /emr-checker/emr-checker-list?department_catalog={id}
  /// v3.1.13: Filter theo department_catalog (HSCC=22)
  /// v3.1.15: thêm serviceReqSttIds param (no-op for public API - nó không trả status)
  Future<HisResult> getServiceRequestsByRoomPublic(int roomId, {int limit = 100, int? departmentCatalogId, Set<int>? serviceReqSttIds}) async {
    try {
      // Public 8080 dùng login session cookie (CSRF) - cần auth trước
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ));
      final cookieJar = CookieJar();
      dio.interceptors.add(CookieManager(cookieJar));

      // Step 1: GET /login để lấy CSRF token
      final r1 = await dio.get('http://113.163.187.3:8080/login');
      String csrf = '';
      final m = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(r1.data?.toString() ?? '');
      if (m != null) csrf = m.group(1) ?? '';

      if (csrf.isEmpty) {
        return HisResult(success: false, message: 'Public 8080: no CSRF token');
      }

      // Step 2: POST /login với credentials
      final cookies1 = await cookieJar.loadForRequest(Uri.parse('http://113.163.187.3:8080/login'));
      final xsrf1 = cookies1.firstWhere((c) => c.name == 'XSRF-TOKEN', orElse: () => Cookie('XSRF-TOKEN', '')).value;

      final r2 = await dio.post('http://113.163.187.3:8080/login',
        data: {
          'email': 'nemk',
          'password': '1027',
          '_token': csrf,
        },
        options: Options(headers: {
          'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf1),
          'Referer': 'http://113.163.187.3:8080/login',
        }, validateStatus: (s) => s != null && s < 500));

      if (r2.statusCode != 302) {
        return HisResult(success: false, message: 'Public login failed: HTTP ${r2.statusCode}');
      }

      // Step 3: GET /emr-checker-list với filter
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      String fmtDt(DateTime dt) => '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';

      final params = {
        'date_from': fmtDt(DateTime(now.year, now.month, now.day)),
        'date_to': fmtDt(DateTime(now.year, now.month, now.day, 23, 59, 59)),
        'date_type': 'date_in',
        'length': '$limit',
        'start': '0',
        if (departmentCatalogId != null) 'department_catalog': '$departmentCatalogId',
      };
      final queryStr = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final fullUrl = 'http://113.163.187.3:8080/emr-checker/emr-checker-list?$queryStr';

      final cookies3 = await cookieJar.loadForRequest(Uri.parse('http://113.163.187.3:8080'));
      final xsrf3 = cookies3.firstWhere((c) => c.name == 'XSRF-TOKEN', orElse: () => Cookie('XSRF-TOKEN', '')).value;

      final r3 = await dio.get(fullUrl, options: Options(headers: {
        'Referer': 'http://113.163.187.3:8080/emr-checker/emr-checker-index',
        'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf3),
      }));
      if (r3.statusCode != 200) {
        return HisResult(success: false, message: 'Public fetch: HTTP ${r3.statusCode}');
      }
      final items = (r3.data is Map ? r3.data['data'] as List? : null) ?? [];
      final list = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is Map) {
          list.add({
            'ID': raw['treatment_code'],
            'TDL_TREATMENT_CODE': raw['treatment_code'],
            'TDL_PATIENT_CODE': raw['tdl_patient_code'],
            'TDL_PATIENT_UNSIGNED_NAME': raw['tdl_patient_name'] ?? '',
            'TDL_PATIENT_NAME': raw['tdl_patient_name'],
            'TDL_PATIENT_DOB': raw['tdl_patient_dob'],
            'TDL_PATIENT_ADDRESS': raw['tdl_patient_address'],
            'TDL_PATIENT_PHONE': raw['tdl_patient_phone'] ?? raw['tdl_patient_mobile'],
            'TDL_PATIENT_RELATIVE_MOBILE': raw['tdl_patient_relative_mobile'] ?? raw['tdl_patient_relative_phone'],
            'TDL_HEIN_CARD_NUMBER': raw['tdl_hein_card_number'],
            'TREATMENT_TYPE_NAME': raw['treatment_type_name'],
            'PATIENT_TYPE_NAME': raw['patient_type_name'],
            'IN_TIME': raw['in_time'],
            'OUT_TIME': raw['out_time'],
            'LAST_DEPARTMENT_RAW': raw['last_department'],
            'DEPARTMENT_NAME': raw['last_department'],
            'IS_BHYT': (raw['patient_type_name'] ?? '').toString().contains('BHYT'),
            'treatment_code': raw['treatment_code'],
            'tdl_patient_name': raw['tdl_patient_name'],
            '_DATA_SOURCE': 'PUBLIC_8080_DEPT_$departmentCatalogId',
          });
        }
      }
      return HisResult(success: true, data: list);
    } catch (e) {
      return HisResult(success: false, message: 'Public 8080: ${_handleError(e)}');
    }
  }

  /// Lấy TẤT CẢ service req của 1 BN theo TREATMENT_ID
  /// v3.1.13: Dùng khi 1 BN có nhiều service req (Khám + CĐHA + Thủ thuật)
  Future<HisResult> getServiceRequestsByTreatment(dynamic treatmentId) async {
    try {
      final d = DateTime.now();
      final dateLong = d.year * 10000000000 + d.month * 100000000 + d.day * 1000000;
      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2, 3, 4, 5],
        'TDL_TREATMENT_ID__EQUAL': int.tryParse(treatmentId.toString()) ?? 0,
        'INTRUCTION_DATE__EQUAL': dateLong,
        'ORDER_FIELD': 'INTRUCTION_TIME',
        'ORDER_DIRECTION': 'DESC',
      };
      final param = _encodeParam(apiData, 50);
      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',
        queryParameters: {'param': param},
        options: Options(headers: {'Content-Type': 'application/json'}, receiveTimeout: const Duration(seconds: 30), validateStatus: (s) => s != null && s < 500),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// Đánh dấu hoàn thành service req với start_time + end_time + note
  /// v3.1.13: Gọi api/HisServiceReq/FinishWithTime từ ECG form
  /// Trả về true nếu thành công
  Future<HisResult> finishServiceReqWithTime({
    required int serviceReqId,
    required DateTime startTime,
    required DateTime endTime,
    String resultNote = '',
  }) async {
    try {
      // Format DateTime → yyyyMMddHHmmss long
      String fmt(DateTime t) =>
        '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}'
        '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}${t.second.toString().padLeft(2, '0')}';

      final apiData = {
        'ID': serviceReqId,
        'START_TIME': fmt(startTime),
        'END_TIME': fmt(endTime),
        'RESULT_NOTE': resultNote,
        'IS_AUTO_FINISH': true,
      };
      final param = _encodeParam(apiData, 0);
      print('📡 MCH FinishWithTime (ID=$serviceReqId): ${ConnectionService.instance.ocrUrl}api/HisServiceReq/FinishWithTime');

      final response = await _dio.post(
        '${ConnectionService.instance.ocrUrl}api/HisServiceReq/FinishWithTime',
        queryParameters: {'param': param},
        options: Options(headers: {'Content-Type': 'application/json'}, receiveTimeout: const Duration(seconds: 60), validateStatus: (s) => s != null && s < 500),
      );

      if (response.statusCode == 200) {
        final data = response.data is Map ? response.data as Map : {};
        if (data['Success'] == true) {
          return HisResult(success: true, data: data['Data']);
        }
        return HisResult(success: false, message: data['Message']?.toString() ?? 'Finish failed', data: data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.116: Lấy danh sách user theo role + department (cho ServiceExecuteDetailScreen)
  /// GET /api/HisExecuteUser/GetView?param=BASE64({DEPARTMENT_ID, IS_ACTIVE, ...})
  Future<HisResult> getExecuteRoleUsers({int? departmentId, int limit = 200}) async {
    try {
      final apiData = {
        'IS_ACTIVE': 1,
        if (departmentId != null) 'DEPARTMENT_ID': departmentId,
        'ORDER_FIELD': 'LOGINNAME',
        'ORDER_DIRECTION': 'ASC',
      };
      final param = _encodeParam(apiData, limit);
      print('📡 MCH GetExecuteRoleUsers: ${ConnectionService.instance.ocrUrl}api/HisExecuteUser/GetView');
      final response = await _dio.get(
        '${ConnectionService.instance.ocrUrl}api/HisExecuteUser/GetView',
        queryParameters: {'param': param},
        options: Options(headers: {'Content-Type': 'application/json'}, receiveTimeout: const Duration(seconds: 30), validateStatus: (s) => s != null && s < 500),
      );
      if (response.statusCode == 200) {
        // v3.0.162: Unwrap String response (HIS Pro text/plain)
        final unwrapped = _unwrap(response.data);
        return HisResult(success: true, data: unwrapped);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.168: Lấy danh sách users từ AcsUser (port 1401) - cho dropdown PTV/TTV chính
  /// Returns: [{LOGINNAME, USERNAME (tên đầy đủ), EMAIL, MOBILE, G_CODE, DEPARTMENT_ID, ...}, ...]
  /// - LOGINNAME: tên đăng nhập (vd "dungntm") - dùng cho backend
  /// - USERNAME: tên đầy đủ (vd "Nguyễn Thị Mỹ Dung") - hiển thị cho user
  /// Sort theo USERNAME alphabetical
  Future<HisResult> getAcsUsers({int? departmentId, String? roleCode, int limit = 200}) async {
    try {
      final apiData = <String, dynamic>{
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'ORDER_FIELD': 'USERNAME',
        'ORDER_DIRECTION': 'ASC',
        'LIMIT': limit,
      };
      if (departmentId != null) apiData['DEPARTMENT_ID'] = departmentId;
      if (roleCode != null) apiData['G_CODE'] = roleCode;
      final param = _encodeParam(apiData, limit);
      final url = '${ConnectionService.instance.acsUrl}api/AcsUser/Get';
      debugPrint('📡 AcsUser/Get: $url');
      final response = await _dio.get(
        url,
        queryParameters: {'param': param},
        options: Options(headers: {'Content-Type': 'application/json'}, receiveTimeout: const Duration(seconds: 30), validateStatus: (s) => s != null && s < 500),
      );
      if (response.statusCode == 200) {
        final unwrapped = _unwrap(response.data);
        return HisResult(success: true, data: unwrapped);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.162: Lấy thông tin mở rộng của sere_serv (kết quả CLS, Xquang, mô tả, kết luận)
  /// API: HisSereServExt/Get filter SERE_SERV_ID (1-1 với SereServ)
  /// Returns: {CONCLUDE, DESCRIPTION, MACHINE_CODE, BEGIN_TIME, END_TIME, NOTE, NUMBER_OF_FILM, ...}
  Future<HisResult> getSereServExtResult(int sereServId) async {
    try {
      final param = _encodeParam({
        'SERE_SERV_ID': sereServId,
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
      }, 10);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisSereServExt/Get',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        final unwrapped = _unwrap(response.data);
        return HisResult(success: true, data: unwrapped);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.162: Lấy kết quả Xquang từ service_req (gọi GetSereServExt với từng sere_serv)
  Future<HisResult> getServiceReqResult(int serviceReqId) async {
    try {
      // Bước 1: Lấy danh sách sere_serv theo service_req
      final paramList = _encodeParam({
        'TDL_SERVICE_REQ_ID': serviceReqId,
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
      }, 50);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisSereServ/Get',
        queryParameters: {'param': paramList},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode != 200) {
        return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
      }
      final unwrapped = _unwrap(response.data);
      if (unwrapped is! Map || unwrapped['Data'] == null) {
        return HisResult(success: false, message: 'Invalid response');
      }
      // Bước 2: Lấy kết quả Xquang từ SereServExt cho mỗi sere_serv
      final results = <Map<String, dynamic>>[];
      for (final s in (unwrapped['Data'] as List)) {
        final sereServId = s['ID'] ?? s['id'];
        if (sereServId == null) continue;
        final extResult = await getSereServExtResult(sereServId as int);
        if (extResult.success && extResult.data != null) {
          final data = extResult.data;
          if (data is Map && data['Data'] is List) {
            for (final ext in (data['Data'] as List)) {
              results.add({
                'SERE_SERV': s,
                'SERE_SERV_EXT': ext,
              });
            }
          } else if (data is Map && data['Data'] is Map) {
            results.add({
              'SERE_SERV': s,
              'SERE_SERV_EXT': data['Data'],
            });
          }
        }
      }
      return HisResult(success: true, data: results);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.162: Lấy danh sách ECG/SereServ theo executeRoomId (Phòng tủ thuật)
  /// Reuses getServiceRequestsByRoom but with focus on service_type_id 4 (thủ thuật) + 3 (XN)
  Future<HisResult>   getRoomServiceReqsWithToken(
    int executeRoomId, {
    int? serviceTypeId,
    int limit = 50,
  }) async {
    return getServiceRequestsByRoom(
      executeRoomId,
      limit: limit,
      serviceReqSttIds: {1, 2, 3},
    );
  }

  /// v3.0.163: Lay danh sach may (HIS_MACHINE)
  /// 144 may (May tao Oxy di dong ID=29, May dien tim 3 kenh ID=12,...)
  Future<HisResult> getAllMachines({int limit = 200}) async {
    try {
      final param = _encodeParam({
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'LIMIT': limit,
      }, limit);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisMachine/Get',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.163: Lay may theo service_id (HIS_SERVICE_MACHINE)
  /// Cho ECG (service 3249) tra 3 may: 29 (May tao Oxy di dong), 302, ...
  Future<HisResult> getMachinesForService(int serviceId, {int limit = 50}) async {
    try {
      final param = _encodeParam({
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'SERVICE_ID': serviceId,
        'LIMIT': limit,
      }, limit);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisServiceMachine/Get',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.163: Lay chi tiet 1 service_req (MACHINE_NAMES, START_TIME, FINISH_TIME)
  Future<HisResult> getServiceReqView(int serviceReqId) async {
    try {
      final param = _encodeParam({
        'ID': serviceReqId,
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
      }, 5);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisServiceReq/GetView',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.163: Update HisSereServExt (luu may + ket qua khi thuc hien DV)
  Future<HisResult> updateSereServExt(Map<String, dynamic> data) async {
    try {
      final param = _encodeParam(data, 1);
      final response = await _dio.post(
        '$_procedureRoomUrl/api/HisSereServExt/Update',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.163: Update HisServiceReq (set MACHINE_ID + MACHINE_NAMES)
  Future<HisResult> updateServiceReq(Map<String, dynamic> data) async {
    try {
      final param = _encodeParam(data, 1);
      final response = await _dio.post(
        '$_procedureRoomUrl/api/HisServiceReq/Update',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  // ============================================================
  // v3.0.164: KẾT QUẢ CẬN LÂM SÀNG - Siêu âm, ECG, XN
  // ============================================================

  /// v3.0.164: Lấy kết quả Siêu âm từ SAR (Subclinical Analyze Report)
  /// SAR endpoint: `api/SarReport/Get` (port 1409) - chứa kết quả Siêu âm/Xquang
  /// Filter theo SERVICE_REQ_ID hoặc SERE_SERV_ID
  /// Trả về list các SAR_PRINT/result với: CONCLUDE, DESCRIPTION, NOTE
  Future<HisResult> getSarReportResult({
    int? serviceReqId,
    int? sereServId,
    int limit = 20,
  }) async {
    try {
      final sarBase = ConnectionService.instance.sarUrl.replaceAll(RegExp(r'/$'), '');
      final filterData = <String, dynamic>{
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'LIMIT': limit,
      };
      if (serviceReqId != null) filterData['SERVICE_REQ_ID'] = serviceReqId;
      if (sereServId != null) filterData['SERE_SERV_ID'] = sereServId;

      final param = _encodeParam(filterData, limit);
      final response = await _dio.get(
        '$sarBase/api/SarReport/Get',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.164: Lấy kết quả Xét nghiệm từ LIS (port 1419)
  /// LIS endpoint: `api/LisResult/Get` hoặc `api/LisSample/Get`
  /// Filter theo SERVICE_REQ_ID, có thể trả về nhiều test values
  Future<HisResult> getLisResult({
    int? serviceReqId,
    int? treatmentId,
    int? patientId,
    int limit = 50,
  }) async {
    try {
      final lisBase = ConnectionService.instance.lisUrl.replaceAll(RegExp(r'/$'), '');
      final filterData = <String, dynamic>{
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'LIMIT': limit,
      };
      if (serviceReqId != null) filterData['SERVICE_REQ_ID'] = serviceReqId;
      if (treatmentId != null) filterData['TDL_TREATMENT_ID'] = treatmentId;
      if (patientId != null) filterData['TDL_PATIENT_ID'] = patientId;

      // Thử nhiều endpoint (server này có thể không có SAR/LIS - 404 expected)
      final endpoints = [
        '$lisBase/api/LisResult/Get',
        '$lisBase/api/LisSample/Get',
        '$_procedureRoomUrl/api/HisLisSample/Get',
        '$_procedureRoomUrl/api/HisLisResult/Get',
      ];

      HisResult? lastResult;
      for (final url in endpoints) {
        try {
          final param = _encodeParam(filterData, limit);
          final response = await _dio.get(
            url,
            queryParameters: {'param': param},
            options: Options(
              headers: {'Content-Type': 'application/json'},
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (response.statusCode == 200) {
            return HisResult(success: true, data: _unwrap(response.data));
          }
          lastResult = HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
        } catch (e) {
          lastResult = HisResult(success: false, message: _handleError(e));
        }
      }
      return lastResult ?? HisResult(success: false, message: 'LIS không khả dụng');
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.164: Lấy kết quả CĐHA/Siêu âm từ SubclinicalResult
  /// Endpoint: `api/SubclinicalResult/Get` - kết quả siêu âm + nội soi + CĐHA khác
  Future<HisResult> getSubclinicalResult({
    int? serviceReqId,
    int? sereServId,
    int limit = 20,
  }) async {
    try {
      final filterData = <String, dynamic>{
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'LIMIT': limit,
      };
      if (serviceReqId != null) filterData['SERVICE_REQ_ID'] = serviceReqId;
      if (sereServId != null) filterData['SERE_SERV_ID'] = sereServId;

      final param = _encodeParam(filterData, limit);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/SubclinicalResult/Get',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        return HisResult(success: true, data: _unwrap(response.data));
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.166: Lấy kết quả tổng hợp CLS (Siêu âm/Xquang/XN) theo ServiceReq
  /// Auto-detect service type và gọi endpoint phù hợp.
  ///
  /// v3.0.166: REFACTOR - LUÔN thử `getServiceReqResult` (HisSereServExt) TRƯỚC vì:
  /// - v3.0.162 verified: work cho ECG/Xquang với HisSereServExt
  /// - SAR/LIS thường return 404 trên server này (chưa có module SAR/LIS)
  /// - Chỉ thử SAR/LIS khi HisSereServExt fail
  ///
  /// Returns: { serviceType, serviceTypeName, source, serviceName, results: List/Map }
  Future<HisResult> getServiceResultByType({
    required int serviceReqId,
    int? sereServId,
    int? serviceTypeId,
  }) async {
    try {
      // Step 1: Lấy thông tin service_req để biết SERVICE_TYPE_ID + SERVICE_NAME
      String? serviceName;
      if (serviceTypeId == null) {
        final srv = await getServiceReqView(serviceReqId);
        if (srv.success && srv.data is Map) {
          final data = srv.data as Map;
          if (data['Data'] is List && (data['Data'] as List).isNotEmpty) {
            final first = (data['Data'] as List).first;
            serviceTypeId = int.tryParse(
              (first['SERVICE_TYPE_ID'] ?? first['service_type_id'] ?? '0').toString(),
            );
            serviceName = (first['SERVICE_NAME'] ?? first['service_name'])?.toString();
          } else if (data['Data'] is Map) {
            serviceTypeId = int.tryParse(
              (data['Data']['SERVICE_TYPE_ID'] ?? data['Data']['service_type_id'] ?? '0').toString(),
            );
            serviceName = (data['Data']['SERVICE_NAME'] ?? data['Data']['service_name'])?.toString();
          }
        }
      }
      serviceTypeId ??= 0;
      serviceName ??= '';

      // Step 2: Detect service type từ SERVICE_NAME nếu type = 0
      // (một số CĐHA có type 0 trong GetView trên server này)
      if (serviceTypeId == 0) {
        final name = serviceName.toLowerCase();
        if (name.contains('siêu âm') || name.contains('sieu am') || name.contains('sa ')) {
          serviceTypeId = 4;
        } else if (name.contains('xquang') || name.contains('x-quang') || name.contains('xq')) {
          serviceTypeId = 4;
        } else if (name.contains('điện tim') || name.contains('dien tim') || name.contains('ecg')) {
          serviceTypeId = 4;
        } else if (name.contains('ct ') || name.contains('mri') || name.contains('cộng hưởng')) {
          serviceTypeId = 4;
        } else if (name.contains('xét nghiệm') || name.contains('xet nghiem') || name.contains('máu')) {
          serviceTypeId = 3;
        }
      }

      // Step 3: LUÔN thử HisSereServExt TRƯỚC - work cho ECG/Xquang/Siêu âm từ v3.0.162
      final extR = await getServiceReqResult(serviceReqId);
      if (extR.success) {
        final extData = extR.data;
        bool hasContent = false;
        if (extData is List) {
          hasContent = extData.isNotEmpty;
        } else if (extData is Map) {
          hasContent = extData['Data'] != null;
        }
        if (hasContent) {
          return HisResult(success: true, data: {
            'serviceType': serviceTypeId,
            'serviceTypeName': _serviceTypeName(serviceTypeId),
            'source': 'HisSereServExt',
            'serviceName': serviceName,
            'results': extData,
          });
        }
      }

      // Step 4: HisSereServExt fail → thử SAR (CĐHA) hoặc LIS (XN) làm bổ sung
      if (serviceTypeId == 3) {
        // XN - thử LIS
        final r = await getLisResult(serviceReqId: serviceReqId);
        if (r.success) {
          return HisResult(success: true, data: {
            'serviceType': 3,
            'serviceTypeName': 'Xét nghiệm',
            'source': 'LIS',
            'serviceName': serviceName,
            'results': r.data,
          });
        }
        // Fallback cuối: empty list, dialog sẽ hiển thị "Chưa có kết quả"
        return HisResult(success: true, data: {
          'serviceType': 3,
          'serviceTypeName': 'Xét nghiệm',
          'source': 'none',
          'serviceName': serviceName,
          'results': [],
        });
      } else if (serviceTypeId == 4 || serviceTypeId == 5) {
        // CĐHA / Thủ thuật - thử SAR
        final sarR = await getSarReportResult(serviceReqId: serviceReqId);
        if (sarR.success && sarR.data != null) {
          final sarData = sarR.data;
          bool hasContent = sarData is Map && sarData['Data'] is List && (sarData['Data'] as List).isNotEmpty;
          if (hasContent) {
            return HisResult(success: true, data: {
              'serviceType': serviceTypeId,
              'serviceTypeName': _serviceTypeName(serviceTypeId),
              'source': 'SAR',
              'serviceName': serviceName,
              'results': sarData,
            });
          }
        }
        // Fallback: SubclinicalResult
        final subR = await getSubclinicalResult(serviceReqId: serviceReqId);
        if (subR.success && subR.data != null) {
          return HisResult(success: true, data: {
            'serviceType': serviceTypeId,
            'serviceTypeName': _serviceTypeName(serviceTypeId),
            'source': 'SubclinicalResult',
            'serviceName': serviceName,
            'results': subR.data,
          });
        }
        // v3.0.166: Trước đây return "Không tìm thấy kết quả CĐHA" lỗi đỏ
        // Giờ return success + empty list → dialog "Chưa có kết quả" thay vì báo lỗi
        return HisResult(success: true, data: {
          'serviceType': serviceTypeId,
          'serviceTypeName': _serviceTypeName(serviceTypeId),
          'source': 'none',
          'serviceName': serviceName,
          'results': [],
        });
      } else {
        // Other types - đã thử getServiceReqResult ở Step 3
        return HisResult(success: true, data: {
          'serviceType': serviceTypeId,
          'serviceTypeName': 'Khác',
          'source': 'none',
          'serviceName': serviceName,
          'results': [],
        });
      }
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
  }

  /// v3.0.166: Helper - service type name
  String _serviceTypeName(int? typeId) {
    switch (typeId) {
      case 1: return 'Khám';
      case 2: return 'Ngừng';
      case 3: return 'Xét nghiệm';
      case 4: return 'CĐHA';
      case 5: return 'Thủ thuật';
      case 6: return 'Thuốc';
      case 7: return 'Máu';
      case 8: return 'Vật tư';
      case 9: return 'Giường';
      case 10: return 'Phẫu thuật';
      default: return 'Dịch vụ';
    }
  }

  /// v3.0.164: Lấy kết quả tổng hợp tất cả CLS của 1 treatment (theo treatment_id)
  /// Trả về: {sieuAm: [...], xquang: [...], xn: [...], ecg: [...], other: [...]}
  Future<HisResult> getAllClsByTreatment(int treatmentId, {int limit = 100}) async {
    try {
      // Lấy tất cả service_req theo treatment
      final param = _encodeParam({
        'TREATMENT_ID': treatmentId,
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
        'LIMIT': limit,
      }, limit);
      final response = await _dio.get(
        '$_procedureRoomUrl/api/HisServiceReq/Get',
        queryParameters: {'param': param},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode != 200) {
        return HisResult(success: false, message: 'HTTP ${response.statusCode}');
      }
      final unwrapped = _unwrap(response.data);
      if (unwrapped is! Map || unwrapped['Data'] is! List) {
        return HisResult(success: false, message: 'Invalid response');
      }
      final services = (unwrapped['Data'] as List).cast<Map<String, dynamic>>();
      // Group theo SERVICE_TYPE_ID
      final grouped = <String, List<Map<String, dynamic>>>{
        'sieuAm': [],
        'xquang': [],
        'xn': [],
        'ecg': [],
        'khac': [],
      };
      for (final s in services) {
        final typeId = int.tryParse((s['SERVICE_TYPE_ID'] ?? s['service_type_id'] ?? '0').toString()) ?? 0;
        final serviceName = (s['SERVICE_NAME'] ?? s['TDL_SERVICE_NAME'] ?? '').toString().toLowerCase();
        if (typeId == 3) {
          grouped['xn']!.add(s);
        } else if (typeId == 4) {
          if (serviceName.contains('siêu âm') || serviceName.contains('sieu am') || serviceName.contains('sa')) {
            grouped['sieuAm']!.add(s);
          } else if (serviceName.contains('xquang') || serviceName.contains('x-quang') || serviceName.contains('xq')) {
            grouped['xquang']!.add(s);
          } else {
            grouped['khac']!.add(s);
          }
        } else if (typeId == 5 && (serviceName.contains('điện tim') || serviceName.contains('ecg'))) {
          grouped['ecg']!.add(s);
        } else {
          grouped['khac']!.add(s);
        }
      }
      return HisResult(success: true, data: grouped);
    } catch (e) {
      return HisResult(success: false, message: _handleError(e));
    }
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
