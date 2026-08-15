// v3.0.110: API source selector cho Phòng thủ thuật HSCC
// 3 nguồn: Public 8080 + HIS Pro 1408 + Y Tế Số 3000
// - Public: filter theo khoa HSCC + date_in → ~19 BN
// - HIS Pro: filter EXECUTE_ROOM_ID=36 + status [1,2,3] → 78 BN (cần LAN/VPN)
// - Y Tế Số: filter BED_ROOM_ID (mặc định 39) → BN trong phòng (cần login YTeSo)

import 'dart:async';
import 'dart:convert';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:his_mobile/core/security/credentials.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';

/// Enum các API source (v3.0.110: thêm Y Tế Số 3000)
enum PhongTTApiSource {
  public8080,        // ☁ Public thongke 8080
  hisPro1408,        // 🏥 HIS Pro LAN 1408
  yTeSo3000,         // 📊 Y Tế Số 3000
}

extension PhongTTApiSourceX on PhongTTApiSource {
  String get label {
    switch (this) {
      case PhongTTApiSource.public8080: return '☁ Public thongke :8080';
      case PhongTTApiSource.hisPro1408: return '🏥 HIS Pro LAN :1408';
      case PhongTTApiSource.yTeSo3000:  return '📊 Y Tế Số :3000';
    }
  }
  String get shortLabel {
    switch (this) {
      case PhongTTApiSource.public8080: return 'Public 8080';
      case PhongTTApiSource.hisPro1408: return 'HIS Pro 1408';
      case PhongTTApiSource.yTeSo3000:  return 'Y Tế Số 3000';
    }
  }
  String get hint {
    switch (this) {
      case PhongTTApiSource.public8080: return 'Internet BV (luôn chạy)';
      case PhongTTApiSource.hisPro1408: return 'LAN BV - ở BV hoặc VPN';
      case PhongTTApiSource.yTeSo3000:  return 'Y Tế Số - cần login';
    }
  }
}

/// Kết quả load BN từ 1 nguồn API
class PhongTTResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> patients;
  final String apiUrl;
  final DateTime loadedAt;
  const PhongTTResult({
    required this.success,
    this.message,
    required this.patients,
    required this.apiUrl,
    required this.loadedAt,
  });
}

/// Service gọi API lấy BN trong Phòng thủ thuật HSCC
/// v3.0.110:
/// - Public 8080: filter theo khoa HSCC (dept_catalog=22)
/// - HIS Pro 1408: filter EXECUTE_ROOM_ID=36 + status [1,2,3]
/// - Y Tế Số 3000: filter BED_ROOM_ID (mặc định 39)
class PhongTTApiService {
  PhongTTApiService._();
  static final PhongTTApiService instance = PhongTTApiService._();

  /// Load BN theo nguồn API
  Future<PhongTTResult> loadPatients({
    required PhongTTApiSource source,
    int executeRoomId = 36,    // v3.0.110: HIS Desktop filter = 36 (PKCC)
    int bedRoomId = 39,        // v3.0.110: BED_ROOM_ID cho Y Tế Số (mặc định PTTT_KCC)
    int deptCatalogId = 22,    // HSCC - Khoa Cấp Cứu
    DateTime? date,
    int limit = 200,
  }) async {
    switch (source) {
      case PhongTTApiSource.public8080:   return _loadFromPublic8080(deptCatalogId: deptCatalogId, date: date, limit: limit);
      case PhongTTApiSource.hisPro1408:   return _loadFromHisPro1408(executeRoomId: executeRoomId, date: date, limit: limit);
      case PhongTTApiSource.yTeSo3000:    return _loadFromYTeSo3000(bedRoomId: bedRoomId, date: date, limit: limit);
    }
  }

  // ===================================================================
  // 1. Public thongke 8080
  // ===================================================================
  Future<PhongTTResult> _loadFromPublic8080({
    required int deptCatalogId,
    DateTime? date,
    int limit = 200,
  }) async {
    const baseUrl = 'http://113.163.187.3:8080/emr-checker/emr-checker-list';
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ));
      final cookieJar = CookieJar();
      dio.interceptors.add(CookieManager(cookieJar));

      final r1 = await dio.get('http://113.163.187.3:8080/login');
      String csrf = '';
      final m = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(r1.data ?? '');
      if (m != null) csrf = m.group(1) ?? '';
      if (csrf.isEmpty) {
        return PhongTTResult(success: false, message: 'Public: no CSRF token', patients: [], apiUrl: baseUrl, loadedAt: DateTime.now());
      }

      final cookies1 = await cookieJar.loadForRequest(Uri.parse('http://113.163.187.3:8080/login'));
      final xsrf1 = cookies1.firstWhere((c) => c.name == 'XSRF-TOKEN', orElse: () => Cookie('XSRF-TOKEN', '')).value;
      final email = Credentials.thongkeDefaultEmail;
      final pwd = Credentials.thongkeDefaultPassword;

      final r2 = await dio.post('http://113.163.187.3:8080/login',
        data: {'email': email, 'password': pwd, '_token': csrf},
        options: Options(headers: {
          'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf1),
          'Referer': 'http://113.163.187.3:8080/login',
        }, validateStatus: (s) => s != null && s < 500));
      if (r2.statusCode != 302) {
        return PhongTTResult(success: false, message: 'Public login failed: ${r2.statusCode} (email=$email)', patients: [], apiUrl: baseUrl, loadedAt: DateTime.now());
      }

      final now = date ?? DateTime.now();
      final fromDt = DateTime(now.year, now.month, now.day);
      final toDt = DateTime(now.year, now.month, now.day, 23, 59, 59);
      String two(int n) => n.toString().padLeft(2, '0');
      String fmtDt(DateTime dt) => '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';

      final params = {
        'date_from': fmtDt(fromDt),
        'date_to': fmtDt(toDt),
        'date_type': 'date_in',
        'length': '$limit',
        'start': '0',
        'department_catalog': '$deptCatalogId',
      };
      final queryStr = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final fullUrl = '$baseUrl?$queryStr';

      final cookies3 = await cookieJar.loadForRequest(Uri.parse('http://113.163.187.3:8080'));
      final xsrf3 = cookies3.firstWhere((c) => c.name == 'XSRF-TOKEN', orElse: () => Cookie('XSRF-TOKEN', '')).value;

      final r3 = await dio.get(fullUrl, options: Options(headers: {
        'Referer': 'http://113.163.187.3:8080/emr-checker/emr-checker-index',
        'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf3),
      }));
      if (r3.statusCode != 200) {
        return PhongTTResult(success: false, message: 'Public fetch: HTTP ${r3.statusCode}', patients: [], apiUrl: fullUrl, loadedAt: DateTime.now());
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
            '_DATA_SOURCE': 'PUBLIC_8080',
          });
        }
      }
      return PhongTTResult(success: true, patients: list, apiUrl: fullUrl, loadedAt: DateTime.now());
    } catch (e) {
      return PhongTTResult(success: false, message: 'Public: $e', patients: [], apiUrl: baseUrl, loadedAt: DateTime.now());
    }
  }

  // ===================================================================
  // 2. HIS Pro LAN 1408 - v3.0.110: filter EXECUTE_ROOM_ID=36 + status [1,2,3]
  // (HIS Desktop thật: 78 BN trong PTTT_KCC, status 1=CHỜ 2=ĐANG 3=XONG)
  // ===================================================================
  Future<PhongTTResult> _loadFromHisPro1408({
    required int executeRoomId,
    DateTime? date,
    int limit = 200,
  }) async {
    const baseUrl = 'http://172.16.9.6:1408';
    final url = '$baseUrl/api/HisServiceReq/GetLView';
    try {
      final d = date ?? DateTime.now();
      final dateLong = d.year * 10000000000 + d.month * 100000000 + d.day * 1000000;

      // v3.0.110: Filter đúng theo HIS Desktop
      // - EXECUTE_ROOM_ID = 36 (PKCC - phòng khám cấp cứu)
      // - SERVICE_REQ_STT_IDs = [1, 2, 3] (CHỜ + ĐANG + XONG - tất cả status)
      final apiData = {
        'SERVICE_REQ_STT_IDs': [1, 2, 3],
        'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
        'TDL_PATIENT_TYPE_IDs': [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 302, 282, 222, 142, 143, 209, 208, 207, 42, 43],
        'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
        'EXECUTE_ROOM_ID': executeRoomId,
        'INTRUCTION_DATE__EQUAL': dateLong,
        'HAS_EXECUTE': true,
        'IS_NOT_KSK_REQURIED_APROVAL__OR__IS_KSK_APPROVE': true,
        'ORDER_FIELD': 'INTRUCTION_TIME',
        'ORDER_DIRECTION': 'DESC',
        'ORDER_FIELD1': 'SERVICE_REQ_STT_ID',
        'ORDER_DIRECTION1': 'ASC',
        'ORDER_FIELD2': 'PRIORITY',
        'ORDER_DIRECTION2': 'DESC',
        'ORDER_FIELD3': 'NUM_ORDER',
        'ORDER_DIRECTION3': 'ASC',
      };
      final param = base64Encode(utf8.encode(jsonEncode(apiData)));

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final r = await dio.get(url, queryParameters: {'param': param},
        options: Options(headers: {'Content-Type': 'application/json'}, validateStatus: (s) => s != null && s < 500));
      if (r.statusCode != 200) {
        return PhongTTResult(success: false, message: 'HIS_PRO_1408: HTTP ${r.statusCode}', patients: [], apiUrl: url, loadedAt: DateTime.now());
      }
      final data = r.data is Map ? r.data['Data'] as List? : null;
      final list = <Map<String, dynamic>>[];
      for (final raw in (data ?? [])) {
        if (raw is Map) {
          final p = Map<String, dynamic>.from(raw);
          p['_DATA_SOURCE'] = 'HIS_PRO_1408_EXE_$executeRoomId';
          list.add(p);
        }
      }
      return PhongTTResult(success: true, patients: list, apiUrl: url, loadedAt: DateTime.now());
    } catch (e) {
      return PhongTTResult(success: false, message: 'HIS_PRO_1408: $e', patients: [], apiUrl: url, loadedAt: DateTime.now());
    }
  }

  // ===================================================================
  // 3. Y Tế Số 3000 - DataService (POST /v1/patient/benh-nhan-buong-benh)
  // v3.0.110: cần BED_ROOM_ID, user nhập trong UI
  // ===================================================================
  Future<PhongTTResult> _loadFromYTeSo3000({
    required int bedRoomId,
    DateTime? date,
    int limit = 200,
  }) async {
    final url = 'http://113.163.187.3:3000/v1/patient/benh-nhan-buong-benh';
    try {
      final yTeSo = YTeSoService.instance;
      // Login nếu chưa
      if (!yTeSo.isLoggedIn) {
        final loginRes = await yTeSo.login();
        if (!loginRes.success) {
          return PhongTTResult(success: false, message: 'YTeSo: login fail (${loginRes.message})', patients: [], apiUrl: url, loadedAt: DateTime.now());
        }
      }
      // Lấy buồng bệnh theo khoa HSCC (22) trước để tìm đúng BED_ROOM_ID
      // Sau đó gọi benhNhanBuongBenh với BED_ROOM_IDs
      // Hoặc gọi thẳng nếu biết BED_ROOM_ID
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${yTeSo.accessToken}',
        },
      ));

      // Step 1: Lấy rooms by dept để tìm BED_ROOM_ID
      // Nếu bedRoomId = 0 → query tất cả
      List<int> bedRoomIds = [];
      if (bedRoomId > 0) {
        bedRoomIds = [bedRoomId];
      } else {
        // Query rooms by dept
        try {
          final roomsRes = await dio.post(
            'http://113.163.187.3:3000/v1/patient/buong-benh',
            data: {'USERNAME': yTeSo.email, 'DEPARTMENT_ID': '22'},
            options: Options(validateStatus: (s) => s != null && s < 500),
          );
          if (roomsRes.statusCode == 200 && roomsRes.data is List) {
            for (final r in roomsRes.data) {
              if (r is Map && r['ID'] != null) {
                bedRoomIds.add(int.tryParse(r['ID'].toString()) ?? 0);
              }
            }
          }
        } catch (_) {}
      }

      if (bedRoomIds.isEmpty) {
        return PhongTTResult(success: false, message: 'YTeSo: no BED_ROOM_IDs', patients: [], apiUrl: url, loadedAt: DateTime.now());
      }

      // Step 2: Gọi benhNhanBuongBenh
      final r = await dio.post(url, data: {
        'USERNAME': yTeSo.email,
        'BED_ROOM_IDs': bedRoomIds,
      }, options: Options(validateStatus: (s) => s != null && s < 500));

      if (r.statusCode != 200 && r.statusCode != 201) {
        return PhongTTResult(success: false, message: 'YTeSo fetch: HTTP ${r.statusCode}: ${r.data}', patients: [], apiUrl: url, loadedAt: DateTime.now());
      }
      final items = r.data is List ? r.data as List : (r.data is Map ? r.data['data'] as List? : null) ?? [];
      final list = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is Map) {
          // Map field về chuẩn HIS Pro
          list.add({
            'ID': raw['treatment_code'] ?? raw['TREATMENT_CODE'] ?? raw['id'],
            'TDL_TREATMENT_CODE': raw['treatment_code'] ?? raw['TREATMENT_CODE'],
            'TDL_PATIENT_CODE': raw['patient_code'] ?? raw['PATIENT_CODE'] ?? raw['tdl_patient_code'],
            'TDL_PATIENT_UNSIGNED_NAME': raw['patient_name_unsigned'] ?? raw['PATIENT_NAME_UNSIGNED'] ?? '',
            'TDL_PATIENT_NAME': raw['patient_name'] ?? raw['PATIENT_NAME'] ?? raw['tdl_patient_name'],
            'TDL_PATIENT_DOB': raw['dob'] ?? raw['DOB'] ?? raw['tdl_patient_dob'],
            'TDL_PATIENT_ADDRESS': raw['address'] ?? raw['ADDRESS'] ?? raw['tdl_patient_address'],
            'TDL_PATIENT_PHONE': raw['phone'] ?? raw['PHONE'] ?? raw['tdl_patient_phone'],
            'TDL_HEIN_CARD_NUMBER': raw['hein_card_number'] ?? raw['HEIN_CARD_NUMBER'] ?? raw['tdl_hein_card_number'],
            'TREATMENT_TYPE_NAME': raw['treatment_type_name'] ?? raw['TREATMENT_TYPE_NAME'],
            'PATIENT_TYPE_NAME': raw['patient_type_name'] ?? raw['PATIENT_TYPE_NAME'],
            'IN_TIME': raw['in_time'] ?? raw['IN_TIME'],
            'OUT_TIME': raw['out_time'] ?? raw['OUT_TIME'],
            'DEPARTMENT_NAME': raw['department_name'] ?? raw['DEPARTMENT_NAME'] ?? raw['last_department'],
            'IS_BHYT': (raw['patient_type_name'] ?? raw['PATIENT_TYPE_NAME'] ?? '').toString().contains('BHYT'),
            'BED_ROOM_ID': raw['bed_room_id'] ?? raw['BED_ROOM_ID'],
            'treatment_code': raw['treatment_code'] ?? raw['TREATMENT_CODE'],
            'tdl_patient_name': raw['patient_name'] ?? raw['tdl_patient_name'],
            '_DATA_SOURCE': 'YTE_SO_3000_BED_$bedRoomId',
          });
        }
      }
      return PhongTTResult(success: true, patients: list, apiUrl: url, loadedAt: DateTime.now());
    } catch (e) {
      return PhongTTResult(success: false, message: 'YTeSo: $e', patients: [], apiUrl: url, loadedAt: DateTime.now());
    }
  }
}
