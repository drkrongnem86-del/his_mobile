// HisProVpnService v2.35 - Gọi thẳng HIS Pro backend qua VPN
// Y Tế Số dùng endpoint này - bypass public thongke (bị lỗi FS)
// Endpoints (discover từ log HIS-Pro ngày 2026-07-06):
//   GET  /api/AcsToken/Authorize?param=<base64({LOGIN_NAME, APPLICATION_CODE:"HIS", APP_VERSION})>
//   POST /api/Token/UpdateWorkInfo
//   GET  /api/EmrDocument/Get?param=<base64({TREATMENT_CODE, LOGIN_NAME})>
//   POST /api/EmrDocument/DownloadFile  body: EmrDocumentViewFilter -> trả base64 PDF
// Headers bắt buộc:
//   ipAddress: <LAN IP thiết bị>  (vd 172.16.200.105)
//   Content-Type: application/json
//
// PHƯƠNG THỨC XÁC THỰC (học từ Y Tế Số):
//   Server KHÔNG trả token trong body. Response chỉ chứa Data.ModuleInRoles (quyền user).
//   Việc xác thực dựa trên:
//     - IP LAN (header ipAddress)
//     - LOGIN_NAME trong ApiData
//     - (PASSWORD kiểu Windows Auth có thể ở header NTLM, mobile không cần)
//   Sau khi AcsToken/Authorize trả 200 → session được xác nhận, loginName được lưu làm marker.
import 'dart:convert';
import 'dart:io' show InternetAddress, InternetAddressType, NetworkInterface;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

class HisProDocument {
  final int id;            // 33213087 (numeric ID)
  final String documentCode;  // 000033213723
  final String name;       // "Phiếu yêu cầu xét nghiệm"
  final String type;       // "Phiếu chỉ định"
  final String treatmentCode;  // 000002113225
  final int treatmentId;   // 2093221
  final String departmentCode;  // HSCC
  final String mediOrgCode;     // 58001
  final DateTime? documentDate;
  final String? lastVersionUrl;
  final bool isSigned;
  final String? requestUsername;

  const HisProDocument({
    required this.id,
    required this.documentCode,
    required this.name,
    required this.type,
    required this.treatmentCode,
    required this.treatmentId,
    required this.departmentCode,
    required this.mediOrgCode,
    this.documentDate,
    this.lastVersionUrl,
    this.isSigned = false,
    this.requestUsername,
  });
}

class HisProVpnService {
  static final HisProVpnService instance = HisProVpnService._();
  HisProVpnService._();

  // HIS Pro main API (use via OpenVPN BV profile)
  static const String baseUrl = 'http://172.16.9.6:1401';

  // Mark session - login OK nếu _loginName != null
  String? _loginName;
  String? _username;
  DateTime? _authorizedAt;
  Dio? _dio;

  /// Set cached session marker (no token needed in this model)
  Future<void> setCredentials({String? loginName, String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    if (loginName != null) {
      _loginName = loginName;
      await prefs.setString('hispro_login', loginName);
    }
    if (username != null) {
      _username = username;
      await prefs.setString('hispro_username', username);
    }
  }

  Future<void> loadCachedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _loginName = prefs.getString('hispro_login') ?? prefs.getString('hispro_loginname');
    _username = prefs.getString('hispro_username') ?? prefs.getString('hispro_email');
    final atStr = prefs.getString('hispro_authorized_at');
    if (atStr != null) {
      try { _authorizedAt = DateTime.parse(atStr); } catch (_) {}
    }
  }

  Future<void> clearCredentials() async {
    _loginName = _username = _authorizedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hispro_login');
    await prefs.remove('hispro_loginname');
    await prefs.remove('hispro_username');
    await prefs.remove('hispro_authorized_at');
  }

  bool get isAuthorized => _loginName != null;
  String? get loginName => _loginName;
  String? get username => _username;

  /// Get device's LAN IP for ipAddress header
  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Dio _makeDio(String ip) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'User-Agent': 'HIS-Mobile/2.35.0',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'ipAddress': ip,
      },
    ));
    _dio = dio;
    return dio;
  }

  /// Authorize với HIS Pro.
  /// Logic: HTTP 200 = server xác nhận user OK (qua IP + loginName).
  /// Response body KHÔNG chứa token (chỉ có Data.ModuleInRoles ~882 entries).
  Future<bool> authorize({
    required String loginName,
    String appVersion = '2.405.0',
  }) async {
    final ip = await _getLocalIp();
    final dio = _makeDio(ip);
    try {
      final param = base64Encode(utf8.encode(jsonEncode({
        'CommonParam': {
          'Messages': [], 'BugCodes': [], 'MessageCodes': [],
          'LanguageCode': 'VI', 'Now': 0, 'HasException': false,
        },
        'ApiData': {
          'LOGIN_NAME': loginName,
          'APPLICATION_CODE': 'HIS',
          'APP_VERSION': appVersion,
        },
      })));
      final r = await dio.get('/api/AcsToken/Authorize',
        queryParameters: {'param': param},
      );
      if (r.statusCode == 200) {
        await setCredentials(loginName: loginName);
        _authorizedAt = DateTime.now();
        return true;
      }
      debugPrint('Authorize failed: HTTP ${r.statusCode}');
      return false;
    } catch (e) {
      debugPrint('Authorize error: $e');
      return false;
    }
  }

  /// Lấy danh sách phiếu (signed forms) cho 1 BN
  Future<List<HisProDocument>?> getDocuments(String treatmentCode) async {
    if (_loginName == null) {
      await loadCachedCredentials();
      if (_loginName == null) return null;
    }
    final ip = await _getLocalIp();
    final dio = _makeDio(ip);

    try {
      final param = base64Encode(utf8.encode(jsonEncode({
        'CommonParam': {
          'Messages': [], 'BugCodes': [], 'MessageCodes': [],
          'Start': null, 'Limit': 50, 'Count': null,
          'LanguageCode': 'VI', 'Now': 0, 'HasException': false,
        },
        'ApiData': {
          'LOGIN_NAME': _loginName,
          'TREATMENT_CODE': treatmentCode,
        },
      })));
      final r = await dio.get('/api/EmrDocument/Get',
        queryParameters: {'param': param},
      );
      if (r.statusCode != 200 || r.data == null) {
        debugPrint('getDocuments HTTP ${r.statusCode}');
        return null;
      }

      final data = r.data is String ? jsonDecode(r.data) : r.data;
      if (data is! Map) return null;
      final list = data['Data'];
      if (list is! List) {
        debugPrint('getDocuments: data.Data is not List (got ${list.runtimeType})');
        return null;
      }

      return list.map<HisProDocument>((e) {
        final m = e as Map;
        // Multi-case key lookup (HIS Pro trả uppercase, JSON flexible)
        T g<T>(String k1, [String? k2, String? k3]) {
          for (final k in [k1, k2, k3].whereType<String>()) {
            if (m.containsKey(k) && m[k] != null) return m[k] as T;
          }
          return null as T;
        }

        final name = (g<String>('DOCUMENT_NAME', 'DocumentName') ?? 'Phiếu');
        final type = (g<String>('DOCUMENT_TYPE_NAME', 'DocumentTypeName') ?? '');
        // detect date
        DateTime? date;
        final ts = g<num>('DOCUMENT_TIME');
        if (ts != null) {
          final s = ts.toString();
          if (s.length >= 14) {
            try {
              date = DateTime(
                int.parse(s.substring(0, 4)),
                int.parse(s.substring(4, 6)),
                int.parse(s.substring(6, 8)),
                int.parse(s.substring(8, 10)),
                int.parse(s.substring(10, 12)),
                int.parse(s.substring(12, 14)),
              );
            } catch (_) {}
          }
        }
        return HisProDocument(
          id: (g<num>('ID') ?? 0).toInt(),
          documentCode: (g<String>('DOCUMENT_CODE', 'DocumentCode') ?? ''),
          name: name,
          type: type,
          treatmentCode: (g<String>('TREATMENT_CODE', 'TreatmentCode') ?? treatmentCode),
          treatmentId: (g<num>('TREATMENT_ID', 'TreatmentId') ?? 0).toInt(),
          departmentCode: (g<String>('DEPARTMENT_CODE', 'DepartmentCode') ?? ''),
          mediOrgCode: (g<String>('MEDI_ORG_CODE', 'MediOrgCode') ?? ''),
          documentDate: date,
          lastVersionUrl: g<String>('LAST_VERSION_URL', 'LastVersionUrl'),
          isSigned: (() {
            final s = g<String>('SIGNERS');
            return s != null && s.isNotEmpty;
          })(),
          requestUsername: g<String>('REQUEST_USERNAME', 'RequestUsername'),
        );
      }).toList();
    } catch (e) {
      debugPrint('getDocuments error: $e');
      return null;
    }
  }

  /// Download PDF as bytes
  /// Returns null on error
  Future<Uint8List?> downloadDocument(int documentId, {
    bool showWatermark = false,
    bool isSigned = false,
  }) async {
    if (_loginName == null) {
      await loadCachedCredentials();
      if (_loginName == null) return null;
    }
    final ip = await _getLocalIp();
    final dio = _makeDio(ip);

    try {
      // Format y hệt Y Tế Số: EmrDocumentViewFilter wrapper
      final body = {
        'CommonParam': {
          'Messages': [], 'BugCodes': [], 'MessageCodes': [],
          'Start': null, 'Limit': null, 'Count': null,
          'LanguageCode': 'VI', 'Now': 0, 'HasException': false,
        },
        'ApiData': {
          'LOGIN_NAME': _loginName,
          'ID': documentId,
          'IS_SIGNED': isSigned,
          'IS_MANDATORY_SIGNED': isSigned,
          'ShowWatermark': showWatermark,
          'DocumentName': '',
        },
      };
      final r = await dio.post('/api/EmrDocument/DownloadFile', data: body,
        options: Options(responseType: ResponseType.json, receiveTimeout: const Duration(seconds: 60)),
      );
      if (r.statusCode != 200 || r.data == null) {
        debugPrint('downloadDocument HTTP ${r.statusCode}');
        return null;
      }

      final data = r.data;
      String? b64;
      if (data is String) {
        b64 = data;
      } else if (data is Map) {
        if (data['Data'] is String) {
          b64 = data['Data'];
        } else if (data['Data'] is Map) {
          b64 = (data['Data'] as Map)['Base64Data'] as String?
              ?? (data['Data'] as Map)['Data'] as String?
              ?? (data['Data'] as Map)['FileBase64'] as String?
              ?? (data['Data'] as Map)['Base64File'] as String?;
        } else if (data['Base64Data'] is String) {
          b64 = data['Base64Data'];
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
          return Uint8List.fromList(bytes);
        }
        debugPrint('downloadDocument: not PDF magic (first4: ${bytes.take(4).toList()})');
        return null;
      } catch (e) {
        debugPrint('downloadDocument base64 error: $e');
        return null;
      }
    } catch (e) {
      debugPrint('downloadDocument error: $e');
      return null;
    }
  }

  /// Test if HIS Pro VPN is reachable
  Future<bool> isReachable() async {
    try {
      final ip = await _getLocalIp();
      final dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'ipAddress': ip},
      ));
      final r = await dio.get('/api/SdaConfig/Get?param=test');
      return r.statusCode != null;
    } catch (_) {
      return false;
    }
  }
}
