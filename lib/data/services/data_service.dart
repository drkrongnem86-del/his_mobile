// Data API Service v2.35.7 - Học từ log Y Tế Số mobile của BS + test thật
// Base URL: http://113.163.187.3:3000 (public) hoặc http://172.16.1.12:3000 (LAN)
//
// ENDPOINTS ĐÃ TEST OK:
//   POST /v1/auth/login  body: {email, password} → {accessToken, refreshToken, endpoint}
//       → Decode JWT để lấy user-id (sub), loginName, userName
//   GET  /v1/health
//   GET  /v1/users/profile → {id, loginName, userName, mobile, roleDatas, ...}
//   GET  /v1/users/server-time
//   POST /v1/patient/danh-sach-khoa-quan-ly  body: {USERNAME} → list khoa/phòng quản lý
//   POST /v1/patient/buong-benh  body: {USERNAME, DEPARTMENT_ID} → list buồng bệnh trong khoa
//   POST /v1/patient/benh-nhan-buong-benh  body: {USERNAME, BED_ROOM_IDs} → list BN trong buồng
//   POST /v1/dieu-duong/danh-sach-dieu-duong  body: {USERNAME, departmentId} → list điều dưỡng
//   GET  /v1/medical-record/document-types?treatmentCode=X → list phiếu
//   GET  /v1/medical-record/document-type/download?documentId=X → {Base64Data: "JVBER..."}
//
// HEADERS (mỗi request cần auth):
//   Authorization: Bearer <accessToken>
//   user-id: <id UUID>
//   user-name: <loginName URL-encoded>
//   content-type: application/json; charset=utf-8
//   Start-Time: <iso8601>
//   date: <iso8601>
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/data/api/his_pro_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Models ─────────────────────────────────────────────────────────────────

class DataUser {
  final String id;        // UUID
  final String loginName; // "admin"
  final String userName;  // "admin"
  final String? mobile;
  final String? email;
  final List<DataRole> roles;
  final DateTime? expireTime;

  DataUser({
    required this.id,
    required this.loginName,
    required this.userName,
    this.mobile,
    this.email,
    this.roles = const [],
    this.expireTime,
  });
}

class DataRole {
  final String code; // "BS", "DD", "IT"
  final String name; // "Bác sĩ"
  DataRole(this.code, this.name);
}

class DataDepartment {
  final int id;
  final String code;
  final String name;
  DataDepartment({required this.id, required this.code, required this.name});
}

class DataRoom {
  final int id;             // 442
  final int roomId;         // 3322
  final String code;        // DTBNCV
  final String name;        // "Điều Trị Bệnh Nhân Covid"
  final int departmentId;
  final String departmentCode;
  final String departmentName;
  DataRoom({
    required this.id,
    required this.roomId,
    required this.code,
    required this.name,
    required this.departmentId,
    required this.departmentCode,
    required this.departmentName,
  });
}

class DataPatient {
  final String? id;
  final String? patientCode;     // 00000597000
  final String? treatmentCode;   // 000002112000
  final String? patientName;     // Nguyễn Văn A
  final int? gender;             // 1=Nam, 2=Nữ
  final int? yearOfBirth;        // 1940
  final String? icdCode;         // I10
  final String? icdName;         // Tăng huyết áp
  final String? bedCode;         // P.1
  final String? bedName;         // Phòng 1
  final String? heinCardNumber;  // BT00245000000000
  final String? departmentCode;  // HSCC
  final String? roomCode;        // DT_CC
  final String? admissionDate;   // 2026-07-06
  final bool isNewAdmit;
  final bool isReal;
  final int? treatmentId;

  DataPatient({
    this.id, this.patientCode, this.treatmentCode, this.patientName,
    this.gender, this.yearOfBirth, this.icdCode, this.icdName,
    this.bedCode, this.bedName, this.heinCardNumber,
    this.departmentCode, this.roomCode, this.admissionDate,
    this.isNewAdmit = false, this.isReal = true, this.treatmentId,
  });
}

class DataDocument {
  final int id;
  final String documentCode;
  final String name;
  final String? documentTypeName;
  final String treatmentCode;
  final String? treatmentId;
  final String? requestUsername;
  final String? lastVersionUrl;
  final bool isSigned;
  final String? departmentCode;
  final String? patientCode;
  final String? patientName;
  final String? documentDate;
  // v3.0.147: Track creator để phân quyền xóa EMR
  final String? creator;
  final String? requestLoginname;

  const DataDocument({
    required this.id,
    required this.documentCode,
    required this.name,
    this.documentTypeName,
    required this.treatmentCode,
    this.treatmentId,
    this.requestUsername,
    this.lastVersionUrl,
    this.isSigned = false,
    this.departmentCode,
    this.patientCode,
    this.patientName,
    this.documentDate,
    this.creator,
    this.requestLoginname,
  });
}

class DataLoginResult {
  final bool success;
  final String message;
  final DataUser? user;
  final String? accessToken;
  final String? refreshToken;
  DataLoginResult(this.success, this.message, {this.user, this.accessToken, this.refreshToken});
}

// ─── Service ────────────────────────────────────────────────────────────────

class DataService {
  static final DataService instance = DataService._();
  DataService._();

  // Base URL mặc định (public). User có thể đổi qua Settings.
  static const String defaultBaseUrl = 'http://113.163.187.3:3000';
  static const String hospitalCode = 'bvdk.ninhthuan';

  String _baseUrl = defaultBaseUrl;
  String? _accessToken;
  String? _refreshToken;
  DataUser? _user;
  Dio? _dio;

  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  DataUser? get user => _user;
  bool get isAuthenticated => _accessToken != null && _user != null;
  String? get email => _user?.email;
  String? get loginName => _user?.loginName;
  String? get userName => _user?.userName;
  String? get userId => _user?.id;

  // JWT decode
  Map<String, dynamic>? _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1];
      // Add padding
      final pad = 4 - payload.length % 4;
      if (pad != 4) payload += '=' * pad;
      final json = utf8.decode(base64Url.decode(payload));
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('data_base_url', _baseUrl);
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    // v2.75.2: Ưu tiên URL từ HisConfigService (nếu user đã cấu hình)
    final cfgUrl = prefs.getString('cfg_bvbm_url');
    _baseUrl = prefs.getString('data_base_url')
        ?? cfgUrl
        ?? defaultBaseUrl;
    _accessToken = prefs.getString('data_access_token');
    _refreshToken = prefs.getString('data_refresh_token');
    final id = prefs.getString('data_user_id');
    if (id != null && _accessToken != null) {
      final loginName = prefs.getString('data_login_name') ?? 'user';
      final userName = prefs.getString('data_user_name') ?? loginName;
      _user = DataUser(id: id, loginName: loginName, userName: userName);
    } else {
      _user = null;
    }
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('data_access_token');
    await prefs.remove('data_refresh_token');
    await prefs.remove('data_user_id');
    await prefs.remove('data_login_name');
    await prefs.remove('data_user_name');
  }

  Map<String, dynamic> _authHeaders() {
    final h = <String, dynamic>{};
    if (_accessToken != null) h['Authorization'] = 'Bearer $_accessToken';
    if (_user?.id != null) h['user-id'] = _user!.id;
    if (_user?.loginName != null) {
      h['user-name'] = Uri.encodeComponent(_user!.loginName);
    }
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final iso = now.toIso8601String();
    h['Start-Time'] = iso;
    h['date'] = iso;
    return h;
  }

  Dio _makeDio({bool withAuth = true}) {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'User-Agent': 'HIS-Mobile-Data/2.35.9',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
    ));
    if (withAuth) {
      dio.options.headers.addAll(_authHeaders());
    }
    _dio = dio;
    return dio;
  }

  // ─── Test / Login ──────────────────────────────────────────────────────────

  Future<bool> isReachable() async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final r = await dio.get('/v1/health');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<DataLoginResult> login(String email, String password) async {
    final dio = _makeDio(withAuth: false);
    try {
      final r = await dio.post(
        '/v1/auth/login',
        data: {'email': email, 'password': password},
      );
      debugPrint('Data login: status=${r.statusCode}');
      if (r.statusCode == 201 || r.statusCode == 200) {
        final body = r.data is Map ? r.data as Map : jsonDecode(r.data as String);
        _accessToken = body['accessToken'] as String?;
        _refreshToken = body['refreshToken'] as String?;
        if (_accessToken == null) {
          final bodyStr = body.toString();
          return DataLoginResult(false, 'Response không có accessToken. Body: ${bodyStr.length > 200 ? bodyStr.substring(0, 200) : bodyStr}');
        }
        // Decode JWT để lấy user-id, loginName, userName
        final jwt = _decodeJwt(_accessToken!);
        final userId = jwt?['sub'] as String? ?? '';
        final loginName = jwt?['loginName'] as String? ?? email;
        final userName = jwt?['userName'] as String? ?? loginName;
        final mobile = jwt?['mobile'] as String?;
        // Tính expireTime
        final exp = jwt?['exp'] as int?;
        final expireTime = exp != null ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null;
        _user = DataUser(
          id: userId,
          loginName: loginName,
          userName: userName,
          mobile: mobile,
          expireTime: expireTime,
        );
        // Save
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('data_access_token', _accessToken!);
        if (_refreshToken != null) await prefs.setString('data_refresh_token', _refreshToken!);
        await prefs.setString('data_user_id', userId);
        await prefs.setString('data_login_name', loginName);
        await prefs.setString('data_user_name', userName);
        await prefs.setString('data_base_url', _baseUrl);

        // Fetch full profile for roles
        try {
          final prof = await getUserProfile();
          if (prof != null) {
            _user = DataUser(
              id: prof['id']?.toString() ?? userId,
              loginName: prof['loginName']?.toString() ?? loginName,
              userName: prof['userName']?.toString() ?? userName,
              mobile: prof['mobile']?.toString() ?? mobile,
              email: prof['email']?.toString(),
              expireTime: expireTime,
              roles: ((prof['roleDatas'] as List?) ?? []).map((r) {
                return DataRole(
                  (r['RoleCode'] ?? '').toString(),
                  (r['RoleName'] ?? '').toString(),
                );
              }).toList(),
            );
            await prefs.setString('data_user_name', _user!.userName);
          }
        } catch (_) {}

        return DataLoginResult(
          true,
          'Đăng nhập Data thành công\nUser: ${_user!.loginName} (${_user!.userName})\nHết hạn: ${expireTime?.toLocal().toString().substring(0, 16) ?? "?"}',
          user: _user,
          accessToken: _accessToken,
          refreshToken: _refreshToken,
        );
      } else if (r.statusCode == 401) {
        return DataLoginResult(false, 'Tên đăng nhập hoặc mật khẩu không chính xác (HTTP 401)');
      } else {
        final raw = r.data?.toString() ?? 'unknown';
        return DataLoginResult(false, 'Lỗi HTTP ${r.statusCode}: ${raw.length > 200 ? raw.substring(0, 200) : raw}');
      }
    } on DioException catch (e) {
      debugPrint('Data login DioException: ${e.message}');
      if (e.response?.statusCode == 401) {
        return DataLoginResult(false, 'Tên đăng nhập hoặc mật khẩu không chính xác');
      }
      return DataLoginResult(false, 'Lỗi mạng: ${e.message ?? e.toString()}');
    } catch (e) {
      return DataLoginResult(false, 'Lỗi: $e');
    }
  }

  // ─── Profile ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getUserProfile() async {
    if (!isAuthenticated) return null;
    final dio = _makeDio();
    try {
      final r = await dio.get('/v1/users/profile');
      if (r.statusCode == 200 && r.data is Map) {
        return r.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// v2.37.0: Đổi mật khẩu Data
  /// POST /v1/users/change-password  body: {oldPassword, newPassword}
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (!isAuthenticated) {
      await loadSession();
      if (!isAuthenticated) return false;
    }
    final dio = _makeDio();
    try {
      final r = await dio.post('/v1/users/change-password', data: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      });
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (e) {
      debugPrint('changePassword error: $e');
      return false;
    }
  }

  // ─── Departments / Rooms / Patients ───────────────────────────────────────

  /// Lấy danh sách khoa user được quản lý
  /// POST /v1/patient/danh-sach-khoa-quan-ly  body: {USERNAME}
  /// Response: [{DEPARTMENT_ID, DEPARTMENT_CODE, 'BUỒNGBỆNH'||DEPARTMENT_NAME, FLAG}, ...]
  Future<List<DataDepartment>> getDepartments() async {
    if (!isAuthenticated) {
      await loadSession();
      if (!isAuthenticated) return [];
    }
    final dio = _makeDio();
    try {
      final r = await dio.post(
        '/v1/patient/danh-sach-khoa-quan-ly',
        data: {'USERNAME': _user?.loginName},
      );
      debugPrint('getDepartments: status=${r.statusCode}');
      if (r.statusCode == 201 || r.statusCode == 200) {
        final list = r.data is List ? r.data as List : (r.data is Map ? (r.data['Data'] as List? ?? []) : []);
        return list.map((e) {
          final m = e as Map;
          final rawName = (m["'BUỒNGBỆNH'||DEPARTMENT_NAME"] ?? m['DEPARTMENT_NAME'] ?? '').toString();
          return DataDepartment(
            id: ((m['DEPARTMENT_ID'] as num?) ?? 0).toInt(),
            code: (m['DEPARTMENT_CODE'] ?? '').toString(),
            // v2.35.11: Fix mojibake + bỏ prefix "Buồng bệnh "
            name: fixVietnameseMojibake(rawName).replaceFirst('Buồng bệnh ', ''),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('getDepartments error: $e');
    }
    return [];
  }

  /// Lấy danh sách buồng bệnh theo khoa
  /// POST /v1/patient/buong-benh  body: {USERNAME, DEPARTMENT_ID (string)}
  Future<List<DataRoom>> getRoomsByDepartment(String departmentId) async {
    if (!isAuthenticated) {
      await loadSession();
      if (!isAuthenticated) return [];
    }
    final dio = _makeDio();
    try {
      final r = await dio.post(
        '/v1/patient/buong-benh',
        data: {'USERNAME': _user?.loginName, 'DEPARTMENT_ID': departmentId},
      );
      debugPrint('getRooms($departmentId): status=${r.statusCode}');
      if (r.statusCode == 201 || r.statusCode == 200) {
        final list = r.data is List ? r.data as List : [];
        return list.map((e) {
          final m = e as Map;
          return DataRoom(
            id: ((m['ID'] as num?) ?? 0).toInt(),
            roomId: ((m['ROOM_ID'] as num?) ?? 0).toInt(),
            code: (m['BED_ROOM_CODE'] ?? '').toString(),
            // v2.35.11: Fix mojibake
            name: fixVietnameseMojibake((m['BED_ROOM_NAME'] ?? '').toString()),
            departmentId: ((m['DEPARTMENT_ID'] as num?) ?? 0).toInt(),
            departmentCode: (m['DEPARTMENT_CODE'] ?? '').toString(),
            departmentName: fixVietnameseMojibake((m['DEPARTMENT_NAME'] ?? '').toString()),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('getRooms error: $e');
    }
    return [];
  }

  /// Lấy danh sách bệnh nhân trong các buồng
  /// POST /v1/patient/benh-nhan-buong-benh  body: {USERNAME, BED_ROOM_IDs: [...]}
  /// v2.35.13: BED_ROOM_IDs = ID field từ response buong-benh (KHÔNG phải ROOM_ID)
  ///   Ví dụ: response {"ID":28,"ROOM_ID":224,...} → truyền 28, không phải 224
  Future<List<DataPatient>> getPatientsInRooms(List<int> bedRoomIds) async {
    if (!isAuthenticated) {
      await loadSession();
      if (!isAuthenticated) return [];
    }
    final dio = _makeDio();
    try {
      final r = await dio.post(
        '/v1/patient/benh-nhan-buong-benh',
        data: {
          'USERNAME': _user?.loginName,
          'BED_ROOM_IDs': bedRoomIds,
        },
      );
      debugPrint('getPatientsInRooms: status=${r.statusCode} count=${bedRoomIds.length} ids=$bedRoomIds');
      if (r.statusCode == 201 || r.statusCode == 200) {
        final list = r.data is List ? r.data as List : [];
        debugPrint('  → got ${list.length} patients');
        return list.map((e) => _parsePatient(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('getPatients error: $e');
    }
    return [];
  }

  /// v2.37.1: Lấy tất cả BN theo DEPARTMENT_ID (không cần BED_ROOM_IDs)
  /// Thử nhiều endpoint - cover cả BN ngoại trú (PK)
  Future<List<DataPatient>> getPatientsByDepartment(int departmentId) async {
    if (!isAuthenticated) {
      await loadSession();
      if (!isAuthenticated) return [];
    }
    final dio = _makeDio();
    final endpoints = <String, Map<String, dynamic>>{
      '/v1/patient/benh-nhan-khoa': {'DEPARTMENT_ID': departmentId, 'IS_ACTIVE': 1},
      '/v1/patient/danh-sach-bn-khoa': {'DEPARTMENT_ID': departmentId, 'IS_ACTIVE': 1},
      '/v1/patient/all-by-department': {'DEPARTMENT_ID': departmentId},
      '/v1/patient/benh-nhan-buong-benh': {'DEPARTMENT_ID': departmentId, 'ALL_DEPT': true},
    };
    for (final entry in endpoints.entries) {
      try {
        final r = await dio.post(entry.key, data: {
          'USERNAME': _user?.loginName,
          ...entry.value,
        });
        debugPrint('getPatientsByDept[$entry.key]: status=${r.statusCode}');
        if (r.statusCode == 200 || r.statusCode == 201) {
          final list = r.data is List ? r.data : (r.data is Map ? (r.data['Data'] as List? ?? []) : []);
          if (list.isNotEmpty) {
            debugPrint('  → got ${list.length} BN from $entry.key');
            return list.map((e) => _parsePatient(e as Map)).toList();
          }
        }
      } catch (e) {
        debugPrint('getPatientsByDept[$entry.key] error: $e');
      }
    }
    return [];
  }

  DataPatient _parsePatient(Map m) {
    int? genderInt;
    final g = m['GIOITINH'] ?? m['GENDER_NAME'] ?? m['TDL_PATIENT_GENDER_ID']
        ?? m['TDL_PATIENT_GENDER_NAME'] ?? m['tdl_patient_gender_name'];
    if (g is num) genderInt = g.toInt();
    else if (g is String) {
      final gl = g.toLowerCase().trim();
      if (gl == '1' || gl == '01' || gl == 'nam' || gl == 'male' || gl == 'm') genderInt = 1;
      else if (gl == '2' || gl == '02' || gl == 'nữ' || gl == 'nu' || gl == 'female' || gl == 'f') genderInt = 2;
      else if (gl.contains('nam')) genderInt = 1;
      else if (gl.contains('nữ') || gl.contains('nu') || gl.contains('ữ')) genderInt = 2;
    }
    int? year;
    final dob = m['NGAYSINH'] ?? m['TDL_PATIENT_DOB'] ?? m['DOB'];
    if (dob is num) year = dob.toInt() ~/ 10000;
    else if (dob is String && dob.length >= 4) {
      year = int.tryParse(dob.substring(0, 4));
    }
    final isNew = (m['IS_NEW'] ?? m['MoiNhapVien'] ?? '').toString().toLowerCase().contains('mới')
        || m['MoiNhapVien'] == 'Mới nhập viện' || m['MoiNhapVien'] == 1;
    final isReal = (m['IS_REAL'] ?? m['That'] ?? 'Thật').toString().toLowerCase().contains('thật') || m['That'] == 'Thật' || m['That'] == 1;
    return DataPatient(
      id: m['id']?.toString() ?? m['ID']?.toString(),
      patientCode: (m['MABN'] ?? m['TDL_PATIENT_CODE'] ?? m['PATIENT_CODE'])?.toString(),
      treatmentCode: (m['MADT'] ?? m['TREATMENT_CODE'] ?? m['TREATMENT_CODE'])?.toString(),
      treatmentId: (m['TREATMENT_ID'] is num) ? (m['TREATMENT_ID'] as num).toInt() : null,
      // v2.35.11: Fix mojibake trong tên BN từ API (API trả về double-encoded UTF-8)
      patientName: _fixName(m['HOTENBN'] ?? m['VIR_PATIENT_NAME'] ?? m['TDL_PATIENT_UNSIGNED_NAME'] ?? m['TDL_PATIENT_NAME'] ?? m['tdl_patient_name'] ?? m['TEN_BENH_NHAN']),
      gender: genderInt,
      yearOfBirth: year,
      icdCode: (m['ICD_CODE'] ?? m['icd_code'])?.toString(),
      // Fix mojibake cho ICD name
      icdName: _fixName(m['ICD_NAME'] ?? m['ICD_TEXT'] ?? m['icd_name']),
      bedCode: (m['P'] ?? m['BED_CODE'] ?? m['MABUONGBENH'])?.toString(),
      bedName: _fixName(m['TENBUONGBENH'] ?? m['BED_NAME']),
      heinCardNumber: (m['BHYT'] ?? m['HEIN_CARD_NUMBER'])?.toString(),
      departmentCode: (m['DEPARTMENT_CODE'] ?? m['MAKHOA'])?.toString(),
      roomCode: (m['MABUONGBENH'] ?? m['ROOM_CODE'])?.toString(),
      admissionDate: (m['ADD_TIME'] ?? m['IN_DATE'] ?? m['IN_TIME'])?.toString(),
      isNewAdmit: isNew,
      isReal: isReal,
    );
  }

  /// Helper: fix mojibake trong string từ API
  String? _fixName(dynamic v) {
    if (v == null) return null;
    return fixVietnameseMojibake(v.toString().trim());
  }

  /// Lấy danh sách điều dưỡng trong khoa
  /// POST /v1/dieu-duong/danh-sach-dieu-duong  body: {USERNAME, departmentId}
  Future<List<Map<String, dynamic>>> getNursesByDepartment(String departmentId) async {
    if (!isAuthenticated) return [];
    final dio = _makeDio();
    try {
      final r = await dio.post(
        '/v1/dieu-duong/danh-sach-dieu-duong',
        data: {'USERNAME': _user?.loginName, 'departmentId': departmentId},
      );
      if (r.statusCode == 201 || r.statusCode == 200) {
        return (r.data is List ? r.data as List : []).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  // ─── Documents / PDF ───────────────────────────────────────────────────────

  /// Lấy danh sách phiếu cho 1 BN
  /// GET /v1/medical-record/document-types?treatmentCode={code}
  Future<List<DataDocument>?> getDocuments(String treatmentCode) async {
    if (!isAuthenticated) {
      await loadSession();
      if (!isAuthenticated) return null;
    }
    final dio = _makeDio();
    try {
      final r = await dio.get(
        '/v1/medical-record/document-types',
        queryParameters: {'treatmentCode': treatmentCode},
      );
      if (r.statusCode != 200 || r.data == null) return null;
      final body = r.data;
      List<dynamic> list;
      if (body is List) {
        list = body;
      } else if (body is Map) {
        list = (body['Data'] ?? body['data'] ?? body['items'] ?? []) as List;
      } else {
        return null;
      }
      // Mỗi element là {DOCUMENT_TYPE_CODE, DOCUMENT_TYPE_NAME, items: [...]}
      final out = <DataDocument>[];
      for (final typeGroup in list) {
        if (typeGroup is Map && typeGroup['items'] is List) {
          for (final item in typeGroup['items']) {
            if (item is! Map) continue;
            final signers = item['SIGNERS']?.toString() ?? '';
            final isSigned = signers.isNotEmpty;
            // v2.35.11: Fix mojibake trong document name
            final docName = fixVietnameseMojibake((item['DOCUMENT_NAME'] ?? 'Phiếu').toString());
            // Strip prefix like "PHIẾU THEO DÕI VÀ CHẸ SÓC_2607062489449" → "Phiếu theo dõi và chăm sóc"
            final typeNameFixed = fixVietnameseMojibake(typeGroup['DOCUMENT_TYPE_NAME']?.toString() ?? '');
            final displayName = _humanizeDocName(docName, typeNameFixed);
            out.add(DataDocument(
              id: ((item['ID'] as num?) ?? 0).toInt(),
              documentCode: (item['DOCUMENT_CODE'] ?? '').toString(),
              name: displayName,
              documentTypeName: typeGroup['DOCUMENT_TYPE_NAME']?.toString(),
              treatmentCode: (item['TREATMENT_CODE'] ?? treatmentCode).toString(),
              treatmentId: item['TREATMENT_ID']?.toString(),
              requestUsername: item['REQUEST_USERNAME']?.toString(),
              lastVersionUrl: item['LAST_VERSION_URL']?.toString(),
              isSigned: isSigned,
              departmentCode: item['DEPARTMENT_CODE']?.toString(),
              patientCode: item['PATIENT_CODE']?.toString(),
              patientName: item['VIR_PATIENT_NAME']?.toString(),
              documentDate: item['CREATE_DATE']?.toString(),
            ));
          }
        }
      }
      return out;
    } on DioException catch (e) {
      debugPrint('getDocuments DioException: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('getDocuments error: $e');
      return null;
    }
  }

  /// "PHIẾU THEO DÕI VÀ CHẸ SÓC_2607062489449" → "Phiếu theo dõi và chăm sóc"
  String _humanizeDocName(String full, String typeName) {
    final idx = full.indexOf('_');
    final raw = idx > 0 ? full.substring(0, idx) : full;
    if (raw.toUpperCase() == typeName.toUpperCase()) {
      // Trả về typeName dạng title case
      return _toTitleCase(typeName);
    }
    return _toTitleCase(raw);
  }

  String _toTitleCase(String s) {
    final words = s.toLowerCase().split(' ');
    return words.map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  /// Download PDF bytes
  /// GET /v1/medical-record/document-type/download?documentId=X
  /// Response: {Base64Data: "JVBER..."}
  Future<List<int>?> downloadDocument(int documentId) async {
    if (!isAuthenticated) return null;
    final dio = _makeDio();
    try {
      final r = await dio.get(
        '/v1/medical-record/document-type/download',
        queryParameters: {'documentId': documentId},
        options: Options(responseType: ResponseType.json, receiveTimeout: const Duration(seconds: 60)),
      );
      if (r.statusCode != 200 || r.data == null) return null;
      final data = r.data;
      String? b64;
      if (data is String) {
        b64 = data;
      } else if (data is Map) {
        b64 = (data['Base64Data'] ?? data['base64Data'] ?? data['base64'] ?? data['Base64']) as String?;
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
        return null;
      } catch (_) {
        return null;
      }
    } catch (e) {
      debugPrint('downloadDocument error: $e');
      return null;
    }
  }

  /// v3.0.116: Tra cứu nhanh BN theo mã điều trị (15 số)
  /// Dùng khi cả 3 API (HIS Pro/Data/Public) đều chết
  /// - Gọi Data 3000 `/v1/medical-record/document-types?treatmentCode=...` (works qua internet)
  /// - User nhập mã điều trị (15 số) từ HIS Desktop → xem BN + danh sách phiếu EMR
  /// - Trả về {patient: {...}, documents: [...], treatmentCode: ...}
  Future<Map<String, dynamic>?> quickLookupByTreatmentCode(String treatmentCode) async {
    try {
      if (!isAuthenticated) {
        return {'error': 'Chưa đăng nhập Data API'};
      }
      final dio = _makeDio();
      final r = await dio.get(
        '/v1/medical-record/document-types',
        queryParameters: {'treatmentCode': treatmentCode},
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      if (r.statusCode != 200) {
        return {'error': 'HTTP ${r.statusCode}'};
      }
      final data = r.data is Map ? r.data as Map : {};
      // Response structure: {patient: {...}, documents: [{name, type, isSigned, hisCode, serviceReqCode, ...}], treatmentCode}
      return {
        'patient': data['patient'] as Map<String, dynamic>?,
        'documents': (data['documents'] as List?) ?? [],
        'treatmentCode': treatmentCode,
      };
    } catch (e) {
      debugPrint('quickLookupByTreatmentCode error: $e');
      return {'error': e.toString()};
    }
  }
}
