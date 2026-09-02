// KcbEmrPushService v2.76.0
// Đẩy file lên EMR qua Cục KCB gateway (Bộ Y tế) - giống app Y tế số (v0.3.0)
//
// Flow từ log app Y tế số (C:\1\log.txt):
//   1. POST {baseUrl}prod/v1/tai-lieu-bn/create
//      Body: { MADT, TEN_TAI_LIEU, EMR_DOCUMENT_TYPE: 20, TRANG_THAI_GUI: 0, fileBase64 }
//      → trả { id: uuid, filePath }
//   2. PUT {baseUrl}prod/v1/tai-lieu-bn/{uuid}
//      Body: { TRANG_THAI_GUI: 1, signature: base64 (optional) }
//      → trả { emrDocumentCode, emrDocumentId, filePath: .signed.pdf }
//
// Default baseUrl: https://prod.kcb.vn (Cục Khám chữa bệnh - Bộ Y tế)
// User có thể override qua Cấu hình HIS → "Cục KCB"
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:his_mobile/core/services/his_config_service.dart';

class KcbPushResult {
  final bool success;
  final String message;
  final String? uuid;          // từ POST create
  final String? emrDocumentCode;
  final int? emrDocumentId;
  final String? filePath;
  final String? errorDetail;

  KcbPushResult({
    required this.success,
    required this.message,
    this.uuid,
    this.emrDocumentCode,
    this.emrDocumentId,
    this.filePath,
    this.errorDetail,
  });
}

class KcbEmrPushService {
  KcbEmrPushService._();
  static final KcbEmrPushService instance = KcbEmrPushService._();

  /// Base URL mặc định (Cục KCB - Bộ Y tế)
  /// v2.76.1: URL thật là https://kcb.vn (sau khi test DNS) với path /api/v1/...
  /// App Y tế số dùng /prod/v1/... nhưng đó là internal path, server thật là /api/v1/...
  static const String defaultBaseUrl = 'https://kcb.vn';
  static const String defaultApiPath = 'api/v1'; // KHÔNG có /prod
  static const String defaultHospitalCode = 'bvdkninhthuan';

  /// Lấy base URL từ config (nếu có), không thì dùng default
  String get baseUrl {
    final cfg = HisConfigService.instance.config.kcbBaseUrl;
    if (cfg.isEmpty) return defaultBaseUrl;
    return cfg.endsWith('/') ? cfg : '$cfg/';
  }

  /// Bearer token từ config (optional - 1 số BV không cần)
  String? get bearerToken {
    final t = HisConfigService.instance.config.kcbToken.trim();
    return t.isEmpty ? null : t;
  }

  /// Hospital code (vd: "bvdkninhthuan")
  String get hospitalCode {
    final c = HisConfigService.instance.config.kcbHospitalCode;
    return c.isEmpty ? defaultHospitalCode : c;
  }

  /// v2.76.0: Tạo tài liệu (POST create)
  /// Trả uuid để bước sau PUT ký
  Future<KcbPushResult> createDocument({
    required String madt,           // Mã điều trị (12 số, vd "000002116314")
    required String tenTaiLieu,     // Tên file (vd "giải thích bệnh.pdf")
    required int emrDocumentType,   // 20 = Phiếu khác
    required String fileBase64,     // PDF đã encode base64
  }) async {
    try {
      final url = Uri.parse('${baseUrl}api/v1/tai-lieu-bn/create');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final token = bearerToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final body = <String, dynamic>{
        'MADT': madt,
        'TEN_TAI_LIEU': tenTaiLieu,
        'EMR_DOCUMENT_TYPE': emrDocumentType,
        'TRANG_THAI_GUI': 0, // 0 = chưa ký
        'fileBase64': fileBase64,
      };

      debugPrint('📤 [KCB] POST $url');
      debugPrint('   MADT=$madt, TEN=$tenTaiLieu, TYPE=$emrDocumentType');

      final r = await http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      debugPrint('   Status: ${r.statusCode}');
      debugPrint('   Body: ${r.body.substring(0, r.body.length > 200 ? 200 : r.body.length)}');

      if (r.statusCode != 200 && r.statusCode != 201) {
        return KcbPushResult(
          success: false,
          message: 'Cục KCB HTTP ${r.statusCode}',
          errorDetail: r.body,
        );
      }

      // v2.76.2: Body rỗng + 200 = server OK nhưng cần auth (Bearer token)
      if (r.body.trim().isEmpty) {
        return KcbPushResult(
          success: false,
          message: 'Cục KCB trả 200 nhưng body rỗng - cần Bearer token thật',
          errorDetail: 'Response body is empty. Server yêu cầu xác thực.\n'
              'Cách lấy token: Mở app Y tế số → copy Authorization header từ localStorage.',
        );
      }

      try {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final uuid = data['id']?.toString();
        if (uuid == null || uuid.isEmpty) {
          return KcbPushResult(
            success: false,
            message: 'Cục KCB không trả về id (response thiếu field id)',
            errorDetail: r.body.length > 500 ? r.body.substring(0, 500) : r.body,
          );
        }
        return KcbPushResult(
          success: true,
          message: 'Tạo tài liệu Cục KCB OK',
          uuid: uuid,
          filePath: data['filePath']?.toString(),
        );
      } catch (e) {
        return KcbPushResult(
          success: false,
          message: 'Cục KCB trả về body không phải JSON',
          errorDetail: r.body.length > 500 ? r.body.substring(0, 500) : r.body,
        );
      }
    } catch (e) {
      return KcbPushResult(
        success: false,
        message: 'Cục KCB lỗi: ${e.toString().split("\n").first}',
        errorDetail: e.toString(),
      );
    }
  }

  /// v2.76.0: Ký tài liệu (PUT update) → trả về emrDocumentCode, emrDocumentId
  Future<KcbPushResult> signDocument({
    required String uuid,
    String? signatureBase64, // optional - ảnh chữ ký
  }) async {
    try {
      final url = Uri.parse('${baseUrl}api/v1/tai-lieu-bn/$uuid');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final token = bearerToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final body = <String, dynamic>{
        'TRANG_THAI_GUI': 1, // 1 = đã ký
      };
      if (signatureBase64 != null && signatureBase64.isNotEmpty) {
        body['signature'] = signatureBase64;
      }

      debugPrint('✍ [KCB] PUT $url');

      final r = await http
          .put(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      debugPrint('   Status: ${r.statusCode}');

      if (r.statusCode != 200 && r.statusCode != 201) {
        return KcbPushResult(
          success: false,
          message: 'Cục KCB ký HTTP ${r.statusCode}',
          uuid: uuid,
          errorDetail: r.body,
        );
      }

      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return KcbPushResult(
        success: true,
        message: 'Ký Cục KCB OK',
        uuid: uuid,
        emrDocumentCode: data['emrDocumentCode']?.toString(),
        emrDocumentId: data['emrDocumentId'] as int?,
        filePath: data['filePath']?.toString(),
      );
    } catch (e) {
      return KcbPushResult(
        success: false,
        message: 'Cục KCB ký lỗi: ${e.toString().split("\n").first}',
        uuid: uuid,
        errorDetail: e.toString(),
      );
    }
  }

  /// v2.76.0: Full flow - tạo + ký (gọi 1 lần)
  /// Trả về emrDocumentCode + emrDocumentId nếu thành công
  Future<KcbPushResult> pushFullFlow({
    required String madt,
    required String tenTaiLieu,
    required int emrDocumentType,
    required String fileBase64,
    String? signatureBase64,
  }) async {
    // Bước 1: Tạo
    final create = await createDocument(
      madt: madt,
      tenTaiLieu: tenTaiLieu,
      emrDocumentType: emrDocumentType,
      fileBase64: fileBase64,
    );
    if (!create.success || create.uuid == null) {
      return create;
    }
    // Bước 2: Ký
    final sign = await signDocument(
      uuid: create.uuid!,
      signatureBase64: signatureBase64,
    );
    if (!sign.success) {
      return KcbPushResult(
        success: false,
        message: 'Tạo OK (${create.uuid}) nhưng ký lỗi: ${sign.message}',
        uuid: create.uuid,
        errorDetail: sign.errorDetail,
      );
    }
    return sign;
  }

  /// v2.76.0: Test kết nối Cục KCB
  Future<KcbPushResult> testConnection() async {
    try {
      // Test bằng cách GET danh sách tài liệu của 1 MADT test
      final url = Uri.parse('${baseUrl}api/v1/tai-lieu-bn/danh-sach-tai-lieu?page=1&limit=1&MADT=000002116314');
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      final token = bearerToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
      final r = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
      return KcbPushResult(
        success: r.statusCode == 200,
        message: 'HTTP ${r.statusCode}',
        errorDetail: r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      );
    } catch (e) {
      return KcbPushResult(
        success: false,
        message: 'Lỗi: ${e.toString().split("\n").first}',
      );
    }
  }
}

// Cần import debugPrint
// ignore: unused_element
void _unusedDebugPrint() {}
