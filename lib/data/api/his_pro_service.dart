// HIS Pro Online Sync Service - v2.17
// Gọi HIS Pro backend thật qua VPN (server 117.2.25.67 hoặc 172.16.9.6).
// Khi user bấm nút "Đồng bộ từ HIS Pro":
//  1. Login qua ACS → lấy token
//  2. Gọi MCH GetLView với REQUEST_DEPARTMENT_ID
//  3. (Tuỳ chọn) Lấy chi tiết BN qua HisTreatment/HIS_treatment
//  4. (Tuỳ chọn) Đồng bộ notes local lên HIS Pro qua Create service_req
//  3. Parse response → trả về List<Map> format PatientCard hiểu được.
//
// Yêu cầu: Điện thoại phải kết nối OpenVPN BV trước.
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/services/connection_service.dart';

/// Kết quả trả về từ HIS Pro sync
class HisProSyncResult {
  final bool success;
  final String message;
  final List<Map<String, dynamic>> patients;
  final String? token;
  final String? rawEndpoint;
  final int? httpStatus;

  HisProSyncResult({
    required this.success,
    required this.message,
    required this.patients,
    this.token,
    this.rawEndpoint,
    this.httpStatus,
  });
}

class HisProService {
  static final HisProService instance = HisProService._();
  HisProService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  String? _token;
  String? _loginName;
  String? _password; // v2.38.7: lưu pass để dùng Basic Auth cho data APIs
  DateTime? _tokenExpiry;

  bool get isLoggedIn => _token != null;
  String? get loggedInUser => _loginName;

  void clearSession() {
    _token = null;
    _loginName = null;
    _password = null;
    _tokenExpiry = null;
  }

  /// Encode param theo format HIS Pro (CommonParam + ApiData → base64)
  String _encodeParam(Map<String, dynamic> apiData, [int limit = 200]) {
    final dataJson = apiData.toString();
    // Convert Dart Map toString back to proper JSON
    final properJson = _dartToJson(apiData);
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
      'ApiData': properJson,
    });
    return base64Encode(utf8.encode(param));
  }

  /// Convert Map<String, dynamic> thành JSON string hợp lệ
  String _dartToJson(Map<String, dynamic> m) {
    return jsonEncode(m);
  }

  /// Login ACS - thử nhiều server
  Future<({bool success, String token, String message, String endpoint})> login(
    String loginName,
    String password,
  ) async {
    final apiData = {
      'LOGIN_NAME': loginName,
      'PASSWORD': password,
      'APPLICATION_CODE': 'HIS',
      'APP_VERSION': AppConstants.appVersion,
      'IS_ACTIVE': 1,
    };
    final param = _encodeParam(apiData, 10);

    // 3 endpoint để fallback
    final candidates = <String>[
      '${ConnectionService.instance.acsUrl}api/AcsToken/Authorize',
      'http://117.2.25.67:1401/api/AcsToken/Authorize',
      '${ConnectionService.instance.mosUrl}api/AcsToken/Authorize',
    ];

    for (final url in candidates) {
      try {
        print('🔐 Trying HIS Pro login: $url');
        final r = await _dio.get(
          url,
          queryParameters: {'param': param},
          options: Options(
            // v2.38.6: Giảm timeout 10→5s - qua VPN thì nhanh, không VPN thì fail nhanh để show error
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        if (r.statusCode != 200) {
          print('   HTTP ${r.statusCode} - try next');
          continue;
        }

        final data = r.data;
        if (data is Map && data['Success'] == true) {
          // v2.38.7: HIS Pro không trả Token field - chỉ trả role config
          // Login vẫn OK vì server xác nhận credentials đúng
          // Nhưng cần test thêm API mới biết có truy cập được patient data không
          print('   ⚠ Login OK nhưng KHÔNG có Token field - response chỉ có role config');
          _token = 'no-token-needed';  // marker
          _loginName = loginName;
          _password = password; // v2.38.7: lưu để Basic Auth
          _tokenExpiry = DateTime.now().add(const Duration(hours: 2));
          return (success: true, token: 'no-token-needed', message: 'Đăng nhập OK', endpoint: url);
        } else if (data is Map && data['Success'] == false) {
          final param2 = data['Param'];
          String msg = 'Sai tài khoản / mật khẩu';
          if (param2 is Map && param2['Messages'] is List && (param2['Messages'] as List).isNotEmpty) {
            msg = (param2['Messages'] as List).first.toString();
          }
          return (success: false, token: '', message: msg, endpoint: url);
        }
      } catch (e) {
        print('   ❌ ${e.toString().split("\n").first}');
        continue;
      }
    }

    return (
      success: false,
      token: '',
      message: 'Không kết nối được HIS Pro. Hãy bật OpenVPN trước.',
      endpoint: '',
    );
  }

  /// Gọi MCH GetLView lọc theo department - v2.37.0: lấy cả 3 loại BN (chưa tiếp nhận, đang khám, đã chuyển khoa)
  Future<HisProSyncResult> fetchPatientsByDepartment(int departmentId) async {
    if (_token == null) {
      return HisProSyncResult(
        success: false,
        message: 'Chưa login HIS Pro',
        patients: const [],
      );
    }

    // v2.37.0: Lấy trong khoảng 7 ngày gần nhất để bao gồm cả BN chuyển khoa gần đây
    final now = DateTime.now();
    final dateLong = now.year * 10000000000 + now.month * 100000000 + now.day * 1000000;
    final fromLong = now.subtract(const Duration(days: 7)).year * 10000000000 +
        now.subtract(const Duration(days: 7)).month * 100000000 +
        now.subtract(const Duration(days: 7)).day * 1000000;

    // v2.37.0: Gọi 2 lần để lấy đủ 3 loại
    // Lần 1: BN đang ở PK (status 1+2, hôm nay)
    // Lần 2: BN đã chuyển khoa (status 3+, type chuyển khoa, 7 ngày gần)
    final all = <Map<String, dynamic>>[];
    String? lastErr;

    // === Lần 1: BN đang ở PK (status 1 + 2) ===
    final apiData1 = {
      'SERVICE_REQ_STT_IDs': [1, 2, 3],
      'NOT_IN_SERVICE_REQ_TYPE_IDs': [6, 16, 15, 14, 7],
      'TDL_PATIENT_TYPE_IDs': [
        206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203,
        44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43, 1, 38,
      ],
      'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
      'REQUEST_DEPARTMENT_ID': departmentId,
      'INTRUCTION_DATE__EQUAL': dateLong,
      'IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE': true,
      'ORDER_FIELD': 'INTRUCTION_DATE',
      'ORDER_DIRECTION': 'DESC',
    };
    final r1 = await _callGetLView(apiData1, 'Lần 1 (đang ở PK)');
    if (r1.success) all.addAll(r1.patients);
    lastErr = r1.message;

    // === Lần 2: BN đã chuyển khoa (status 3,4,5 - hoàn thành, 7 ngày gần) ===
    final apiData2 = {
      'SERVICE_REQ_STT_IDs': [3, 4, 5, 6, 7],
      'SERVICE_REQ_TYPE_IDs': [16, 15, 14], // Loại y lệnh chuyển khoa
      'TDL_PATIENT_TYPE_IDs': [
        206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203,
        44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43, 1, 38,
      ],
      'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': '',
      'REQUEST_DEPARTMENT_ID': departmentId,
      'INTRUCTION_DATE__FROM': fromLong,
      'INTRUCTION_DATE__TO': dateLong,
      'ORDER_FIELD': 'INTRUCTION_DATE',
      'ORDER_DIRECTION': 'DESC',
    };
    final r2 = await _callGetLView(apiData2, 'Lần 2 (chuyển khoa)');
    if (r2.success) all.addAll(r2.patients);

    // De-dupe by treatment_code
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final p in all) {
      final code = (p['treatment_code'] ?? '').toString();
      if (code.isNotEmpty && !seen.contains(code)) {
        seen.add(code);
        deduped.add(p);
      }
    }

    print('✅ Loaded ${deduped.length} BN từ HIS Pro khoa $departmentId (${r1.patients.length} đang ở + ${r2.patients.length} chuyển khoa)');
    return HisProSyncResult(
      success: deduped.isNotEmpty || (r1.success || r2.success),
      message: 'OK ${deduped.length} BN (${r1.patients.length} đang ở + ${r2.patients.length} chuyển khoa)',
      patients: deduped,
      token: _token,
      rawEndpoint: 'HisServiceReq/GetLView (combined)',
      httpStatus: 200,
    );
  }

  /// v2.37.0: Helper gọi GetLView, trả về HisProSyncResult
  /// v2.38.7: Thử nhiều URL (MCH 1429 + MOS 1408) + Basic Auth fallback
  Future<HisProSyncResult> _callGetLView(Map<String, dynamic> apiData, String label) async {
    final param = _encodeParam(apiData, 500);
    // v2.38.7: Try MCH (1429) FIRST - đúng endpoint cho patient APIs
    final urls = <String>[
      '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView',   // 172.16.9.6:1429 (MCH)
      'http://172.16.9.6:1408/api/HisServiceReq/GetLView',      // 172.16.9.6:1408 (MOS)
    ];

    for (final url in urls) {
      try {
        print('📡 HIS Pro GetLView [$label]: $url');
        final r = await _dio.get(
          url,
          queryParameters: {'param': param},
          options: Options(
            // v2.38.7: KHÔNG gửi Authorization Bearer (HIS Pro không có token)
            // Dùng Basic Auth với username:password
            headers: {
              if (_loginName != null)
                'Authorization': 'Basic ${base64Encode(utf8.encode('$_loginName:$_password'))}',
            },
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        print('   Status: ${r.statusCode}');
        if (r.statusCode == 404) continue;  // endpoint không có → thử URL tiếp
        if (r.statusCode != 200) {
          return HisProSyncResult(success: false, message: 'HTTP ${r.statusCode} từ $url', patients: const [], rawEndpoint: url, httpStatus: r.statusCode);
        }
        final rawData = r.data;
        if (rawData is! Map || rawData['Success'] != true) {
          return HisProSyncResult(success: false, message: 'API không trả Success=true', patients: const [], rawEndpoint: url);
        }
        final list = rawData['Data'];
        if (list is! List) {
          return HisProSyncResult(success: false, message: 'Data không phải list', patients: const [], rawEndpoint: url);
        }
        final mapped = <Map<String, dynamic>>[];
        for (final item in list) {
          if (item is Map) {
            mapped.add(_mapHisServiceReqToPatient(Map<String, dynamic>.from(item)));
          }
        }
        if (mapped.isEmpty) {
          print('   ⚠ API trả 0 BN');
          continue;  // thử URL khác
        }
        print('   ✅ Got ${mapped.length} BN từ $url');
        return HisProSyncResult(success: true, message: 'OK ${mapped.length} BN từ ${url.split('/').last}', patients: mapped, token: _token, rawEndpoint: url, httpStatus: 200);
      } catch (e) {
        print('   ❌ ${e.toString().split("\n").first}');
        continue;
      }
    }
    return HisProSyncResult(
      success: false,
      message: 'Cả MCH (1429) và MOS (1408) đều không trả BN. Có thể:\n'
          '1. HIS Pro BV chưa cấu hình API mobile\n'
          '2. Cần VPN tới intranet (171.15.x.x) thay vì VPN BV\n'
          '3. Cần tài khoản admin (không phải user BS)',
      patients: const [],
    );
  }

  Map<String, dynamic> _mapHisServiceReqToPatient(Map<String, dynamic> his) {
    // v2.37.0: Phân loại BN theo SERVICE_REQ_STT_ID
    int sttId = 0;
    final sttIdVal = his['SERVICE_REQ_STT_ID'];
    if (sttIdVal is num) sttId = sttIdVal.toInt();
    String patientStatus;
    switch (sttId) {
      case 1:
        patientStatus = 'chua_tiep_nhan'; // Chưa tiếp nhận
        break;
      case 2:
        patientStatus = 'dang_kham'; // Đang khám
        break;
      case 3:
      case 4:
      case 5:
        patientStatus = 'da_chuyen'; // Đã chuyển khoa / hoàn thành
        break;
      default:
        patientStatus = 'khac';
    }

    return {
      'ID': his['ID'],
      'treatment_code': his['TREATMENT_CODE'] ?? '',
      'TDL_PATIENT_CODE': his['TDL_PATIENT_CODE'] ?? '',
      'TDL_PATIENT_UNSIGNED_NAME': his['TDL_PATIENT_UNSIGNED_NAME'] ?? '',
      'TDL_PATIENT_NAME': his['TDL_PATIENT_NAME'] ?? '',
      'TDL_PATIENT_GENDER_NAME': his['TDL_PATIENT_GENDER_NAME'] ?? 'Nam',
      'TDL_PATIENT_DOB': his['TDL_PATIENT_DOB']?.toString() ?? '',
      'TDL_PATIENT_ADDRESS': his['TDL_PATIENT_ADDRESS'] ?? 'Ninh Thuận',
      'TDL_HEIN_CARD_NUMBER': his['TDL_HEIN_CARD_NUMBER'] ?? '',
      'TDL_PATIENT_PHONE': his['TDL_PATIENT_PHONE'] ?? '',
      'TDL_PATIENT_RELATIVE_MOBILE': his['TDL_PATIENT_RELATIVE_MOBILE'] ?? '',
      'TREATMENT_TYPE_NAME': his['TREATMENT_TYPE_NAME'] ?? 'Điều trị nội trú',
      'PATIENT_TYPE_NAME': his['PATIENT_TYPE_NAME'] ?? 'BHYT',
      'IN_TIME': his['INTRUCTION_TIME']?.toString() ?? '',
      'OUT_TIME': his['FINISH_TIME']?.toString() ?? '',
      'ICD_NAME': his['ICD_NAME'] ?? his['SERVICE_REQ_NAME'] ?? '',
      'ICD_CODE': his['ICD_CODE'] ?? '',
      'DEPARTMENT_CODE': his['EXECUTE_DEPARTMENT_CODE'] ?? his['REQUEST_DEPARTMENT_CODE'] ?? '',
      'DEPARTMENT_NAME': his['EXECUTE_DEPARTMENT_NAME'] ?? his['REQUEST_DEPARTMENT_NAME'] ?? '',
      'EXE_ROOM_NAME': his['EXECUTE_ROOM_NAME'] ?? '',
      'BED_ROOM_NAME': (his['EXECUTE_ROOM_NAME'] ?? '') == ''
          ? ''
          : '${his['EXECUTE_ROOM_NAME']} - ${his['BED_NAME'] ?? '?'}',
      'IS_BHYT': (his['IS_BHYT'] ?? true) == true,
      'IS_PAUSE': false,
      'SERVICE_REQ_STT_ID': sttId,
      'PATIENT_STATUS': patientStatus, // v2.37.0
      '_DATA_SOURCE': 'HIS_PRO_LIVE',
    };
  }

  // ============================================================
  // v2.17: BN DETAIL + SYNC PHIẾU LÊN HIS PRO
  // ============================================================

  /// Lấy chi tiết 1 BN theo treatment_code: profile + ICD + CLS + CLS pending
  /// Endpoint: MCH GetViewById - GET /api/HisTreatment/GetView?treatmentCode=XXX
  Future<HisProSyncResult> fetchPatientDetail(String treatmentCode) async {
    if (_token == null) {
      return HisProSyncResult(success: false, message: 'Chưa login HIS Pro', patients: const []);
    }

    final apiData = {
      'TREATMENT_CODE': treatmentCode,
      'IS_ACTIVE': 1,
    };
    final param = _encodeParam(apiData, 100);
    final url = '${ConnectionService.instance.ocrUrl}api/HisTreatment/GetView';
    try {
      print('📡 HIS Pro GetTreatment: $url?code=$treatmentCode');
      final r = await _dio.get(
        url,
        queryParameters: {'param': param},
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (r.statusCode != 200) {
        return HisProSyncResult(success: false, message: 'HTTP ${r.statusCode}', patients: const [], httpStatus: r.statusCode);
      }

      // Trả nguyên data để UI xử lý (rawData có profile + ICD + CLS)
      final detail = <String, dynamic>{
        'data': r.data is Map ? Map<String, dynamic>.from(r.data as Map) : {},
        'patient': _extractFirstMap(r.data, ['Data', 'Patient', 'Treatment', 'Profile']),
        'icd': _extractList(r.data, ['ICDs', 'IcdList', 'ICD']),
        'cls': _extractList(r.data, ['CLSs', 'ServiceReqList', 'Cls', 'Services']),
        'medications': _extractList(r.data, ['Medications', 'Meds', 'Prescriptions']),
        'allergies': _extractList(r.data, ['Allergies', 'Allergy']),
        'treatment_history': _extractList(r.data, ['Treatments', 'History', 'Treatments']),
      };
      return HisProSyncResult(
        success: true,
        message: 'OK',
        patients: [detail],
        rawEndpoint: url,
        httpStatus: 200,
      );
    } catch (e) {
      return HisProSyncResult(
        success: false,
        message: e.toString().split('\n').first,
        patients: const [],
        rawEndpoint: url,
      );
    }
  }

  /// Lấy danh sách CLS (xét nghiệm, CĐHA) đã thực hiện của 1 BN
  /// Endpoint: GET /api/HisServiceReq/GetLView với filter TREATMENT_CODE
  Future<HisProSyncResult> fetchClsHistory(String treatmentCode) async {
    if (_token == null) {
      return HisProSyncResult(success: false, message: 'Chưa login HIS Pro', patients: const []);
    }
    final d = DateTime.now();
    final dateLong = d.year * 10000000000 + d.month * 100000000 + d.day * 1000000;

    final apiData = {
      'KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE': treatmentCode,
      'IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE': true,
      'INTRUCTION_DATE__GREATER_THAN_OR_EQUAL': 0, // lấy tất cả từ 1970
      'ORDER_FIELD': 'INTRUCTION_DATE',
      'ORDER_DIRECTION': 'DESC',
    };
    final param = _encodeParam(apiData, 500);
    final url = '${ConnectionService.instance.ocrUrl}api/HisServiceReq/GetLView';
    try {
      final r = await _dio.get(
        url,
        queryParameters: {'param': param},
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode != 200) {
        return HisProSyncResult(success: false, message: 'HTTP ${r.statusCode}', patients: const [], httpStatus: r.statusCode);
      }
      final data = r.data;
      if (data is! Map || data['Success'] != true) {
        return HisProSyncResult(success: false, message: 'API không thành công', patients: const []);
      }
      final list = data['Data'];
      if (list is! List) {
        return HisProSyncResult(success: false, message: 'Data không phải list', patients: const []);
      }
      return HisProSyncResult(success: true, message: 'OK ${list.length} CLS', patients: List<Map<String, dynamic>>.from(list), httpStatus: 200);
    } catch (e) {
      return HisProSyncResult(success: false, message: e.toString().split('\n').first, patients: const []);
    }
  }

  /// Đồng bộ 1 phiếu local lên HIS Pro qua API POST create
  /// Endpoint: POST /api/HisServiceReq/Create  (hoặc endpoint tương ứng theo từng service_req_type)
  ///
  /// Note: HIS Pro mỗi loại phiếu (y lệnh CLS, đơn thuốc, chăm sóc) có endpoint POST riêng.
  /// Em map đơn giản cho trường hợp thường gặp:
  ///  - vitalSigns         → POST /api/HisVitalSign/Create (theo dõi sinh hiệu)
  ///  - prescription       → POST /api/HisExpMest/Add (đơn thuốc)
  ///  - paraclinical       → POST /api/HisServiceReq/Create (y lệnh CLS)
  ///  - infusion           → POST /api/HisServiceReq/Create
  ///  - careSheet          → POST /api/HisCareSheet/Create
  ///  - treatment_sheet / handoff / consult → ghi chú (no POST, chỉ lưu local)
  Future<HisProSyncResult> syncNoteToHisPro({
    required String treatmentCode,
    required Map<String, dynamic> data,
    required String noteType,
  }) async {
    if (_token == null) {
      return HisProSyncResult(success: false, message: 'Chưa login HIS Pro', patients: const []);
    }

    // Map noteType → endpoint
    final endpoint = _endpointFor(noteType);
    if (endpoint == null) {
      return HisProSyncResult(
        success: false,
        message: 'Loại phiếu "$noteType" chưa được map tới endpoint HIS Pro',
        patients: const [],
      );
    }

    final url = '${ConnectionService.instance.ocrUrl}$endpoint';
    final body = {
      'TREATMENT_CODE': treatmentCode,
      ...data,
    };
    final param = _encodeParam(body, 10);

    try {
      print('📡 HIS Pro POST: $url');
      final r = await _dio.post(
        url,
        queryParameters: {'param': param},
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (r.statusCode == 401) {
        clearSession();
        return HisProSyncResult(success: false, message: 'Token hết hạn', patients: const [], httpStatus: 401);
      }

      // Nếu thành công → trả msg
      final data = r.data;
      if (data is Map) {
        if (data['Success'] == true) {
          return HisProSyncResult(success: true, message: 'Đã đồng bộ lên HIS Pro', patients: const [], httpStatus: 200);
        }
        // Trả message lỗi từ server
        final param = data['Param'];
        String msg = 'Server từ chối: ${data['ErrorCode'] ?? ''}';
        if (param is Map && param['Messages'] is List && (param['Messages'] as List).isNotEmpty) {
          msg = (param['Messages'] as List).first.toString();
        }
        return HisProSyncResult(success: false, message: msg, patients: const [], httpStatus: r.statusCode);
      }
      return HisProSyncResult(
        success: false,
        message: 'Không rõ phản hồi từ server (HTTP ${r.statusCode})',
        patients: const [],
        httpStatus: r.statusCode,
      );
    } catch (e) {
      return HisProSyncResult(success: false, message: e.toString().split('\n').first, patients: const []);
    }
  }

  /// Map từ noteType tới endpoint backend HIS Pro
  String? _endpointFor(String noteType) {
    switch (noteType) {
      case 'vitals':          return 'api/HisVitalSign/Create';      // Theo dõi sinh hiệu
      case 'prescription':    return 'api/HisExpMest/Add';           // Đơn thuốc
      case 'paraclinical':    return 'api/HisServiceReq/Create';     // Y lệnh CLS
      case 'infusion':        return 'api/HisServiceReq/Create';     // Y lệnh dịch truyền
      case 'care_sheet':      return 'api/HisCareSheet/Create';      // Phiếu chăm sóc
      case 'treatment_sheet': return null;  // Chỉ lưu local (HIS Pro không có endpoint POST tờ điều trị điện tử)
      case 'handoff':         return null;  // Chỉ local
      case 'consult':        return null;  // Chỉ local
      case 'order_exec':     return null;  // Chỉ local
      default:                return null;
    }
  }

  // Helper: extract 1 map từ nested response
  Map<String, dynamic> _extractFirstMap(dynamic root, List<String> keys) {
    if (root is! Map) return {};
    for (final k in keys) {
      final v = root[k];
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is List && v.isNotEmpty && v.first is Map) {
        return Map<String, dynamic>.from(v.first as Map);
      }
    }
    return {};
  }

  // Helper: extract list
  List<Map<String, dynamic>> _extractList(dynamic root, List<String> keys) {
    if (root is! Map) return <Map<String, dynamic>>[];
    for (final k in keys) {
      final v = root[k];
      if (v is List) {
        final mapped = <Map<String, dynamic>>[];
        for (final e in v) {
          if (e is Map) {
            mapped.add(Map<String, dynamic>.from(e));
          }
        }
        return mapped;
      }
    }
    return <Map<String, dynamic>>[];
  }
}

