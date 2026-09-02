// v3.0.55: Workflow ký PDF bằng HIS Pro service (C# port 7654)
//
// Sử dụng workflow ký thật PKCS#7 của HIS Pro desktop:
//   1. App tạo PDF (form + nội dung)
//   2. App POST PDF base64 lên service C# (hispro_sign_server.exe port 7654)
//   3. Service gọi SignProcessorClient.SignExecute() qua WCF
//   4. WCF -> KyDienTu.dll -> USB Token (VNPT SmartCA cert) -> ký thật
//   5. Service trả về PDF đã ký (PKCS#7 detached embedded bằng iTextSharp)
//   6. App push PDF đã ký lên EMR HIS Pro (IsFinishSign=true)
//
// Yêu cầu: HIS Pro desktop + SignAdapter.exe chạy nền, service C# port 7654 chạy

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/services/vnpt_smartca_config.dart';
import 'package:his_mobile/data/services/vnpt_smartca_service.dart';

class VnptSignatureResult {
  final bool success;
  final Uint8List? signedPdfBytes;  // PDF đã ký (placeholder - hiện tại = PDF gốc)
  final String? pkcs7Signature;     // PKCS#7 signature base64
  final String? tranId;
  final String? error;

  const VnptSignatureResult({
    required this.success,
    this.signedPdfBytes,
    this.pkcs7Signature,
    this.tranId,
    this.error,
  });
}

class VnptSignatureService {
  static final VnptSignatureService instance = VnptSignatureService._();
  VnptSignatureService._();

  bool _initialized = false;

  // v3.0.56: Timeout ngắn để fail nhanh nếu service C# không chạy
  // - Trước đó 15s/60s/60s → user đợi lâu, app tưởng crash
  // - Bây giờ 3s/5s/5s → fail trong ~3s với message thân thiện
  // - User vẫn dùng được 2 nút Lưu/Lưu ký bình thường
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 5),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  /// v3.0.24: Khởi tạo (gọi 1 lần khi app start) - DEPRECATED ở v3.0.55
  /// (workflow không cần VNPT SmartCA SDK native nữa, gọi HTTP trực tiếp)
  Future<bool> initOnce() async {
    if (_initialized) return true;
    // v3.0.55: Vẫn init SDK để giữ tương thích nếu cần dùng app VNPT SmartCA sau
    _initialized = await VnptSmartcaService.instance.init(
      clientId: VnptSmartcaConfig.clientId,
      env: VnptSmartcaConfig.environment,
    );
    return _initialized;
  }

  /// v3.0.55: Ký PDF qua HIS Pro workflow thật (C# service port 7654)
  /// - Tính SHA-256 hash
  /// - POST lên service C# (HISPro Sign Server) với base64 PDF
  /// - Service gọi WCF SignProcessorClient.SignExecute() -> KyDienTu.dll -> USB Token
  /// - Service trả về PDF đã ký (PKCS#7 detached embedded) + signature base64
  /// - Workflow verified 19/7/2026: PDF có iTextSharp + Adobe.PPKLite + VNPT SmartCA cert
  ///
  /// v3.0.56: Fail nhanh +3s nếu service C# không chạy (thay vì đợi 60s)
  /// - App vẫn dùng được 2 nút Lưu/Lưu ký bình thường
  /// - User bấm "Ký VNPT SmartCA" sẽ thấy message thân thiện, không crash
  ///
  /// [pdfBytes] = PDF cần ký
  /// Trả về VnptSignatureResult với:
  ///   - success: true nếu ký OK
  ///   - signedPdfBytes: PDF đã ký (binary thật, có PKCS#7 embedded)
  ///   - pkcs7Signature: PKCS#7 base64 (cho audit, có thể lấy từ PDF)
  ///
  /// v3.0.29: Detect URL placeholder -> return sớm với error rõ ràng "Cần backend URL"
  Future<VnptSignatureResult> signPdf(Uint8List pdfBytes) async {
    // v3.0.29: Check URL backend trước - nếu chưa config thật -> return sớm
    final url = VnptSmartcaConfig.transactionApiUrl;
    if (_isPlaceholderUrl(url)) {
      return VnptSignatureResult(
        success: false,
        error: 'Chưa cấu hình backend BV để ký HIS Pro thật.\n'
               'URL: $url\n'
               'Cần: chạy hispro_sign_server.exe trên PC BV port 7654.',
      );
    }
    // v3.0.55: Gọi thẳng service C# (bypass VNPT SmartCA SDK native)
    try {
      final base64Pdf = base64Encode(pdfBytes);
      final requestBody = {
        'pdfBase64': base64Pdf,
        'certSerial': VnptSmartcaConfig.certSerial,
        'userName': _getCurrentUserName(),
        'documentName': 'signed_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'treatmentCode': '',
        'TokenCode': _getCurrentTokenCode(),
        'ClientIpAddress': _getCurrentClientIp(),
      };
      debugPrint('[signPdf v3.0.56] POST $url (${pdfBytes.length} bytes)');

      final response = await _dio.post(url, data: requestBody);
      final responseBody = response.data is String ? response.data : (response.data?.toString() ?? '');

      debugPrint('[signPdf v3.0.56] Response: ${response.statusCode}');

      if (response.statusCode != 200) {
        return VnptSignatureResult(
          success: false,
          error: 'Service trả về HTTP ${response.statusCode}: ${responseBody.substring(0, responseBody.length.clamp(0, 300))}',
        );
      }

      final responseJson = response.data is Map
          ? response.data as Map<String, dynamic>
          : jsonDecode(responseBody) as Map<String, dynamic>;
      final success = responseJson['success'] == true;
      if (!success) {
        final err = responseJson['error']?.toString() ?? 'Unknown error';
        return VnptSignatureResult(
          success: false,
          error: 'Service báo lỗi: $err',
        );
      }

      // Lấy PDF đã ký (base64) + signature
      final signedPdfBase64 = responseJson['signedPdfBase64'] as String?;
      final signature = responseJson['signature'] as String?;
      if (signedPdfBase64 == null || signedPdfBase64.isEmpty) {
        return VnptSignatureResult(
          success: false,
          error: 'Service không trả về PDF đã ký. Response: ${responseJson.keys}',
        );
      }

      final signedPdfBytes = base64Decode(signedPdfBase64);
      debugPrint('[signPdf v3.0.56] Signed PDF: ${signedPdfBytes.length} bytes, signature: ${signature?.length ?? 0} chars');

      return VnptSignatureResult(
        success: true,
        signedPdfBytes: signedPdfBytes,  // PDF thật đã ký (có PKCS#7)
        pkcs7Signature: signature,
        tranId: 'real_sign_${DateTime.now().millisecondsSinceEpoch}',
      );
    } on DioException catch (e) {
      // v3.0.56: Fail nhanh + message thân thiện khi service không chạy
      debugPrint('[signPdf v3.0.56] DioException: ${e.type} ${e.message}');
      final errMsg = e.type == DioExceptionType.connectionTimeout
          ? 'Service ký chưa sẵn sàng (timeout 3s).\n\n'
          : e.type == DioExceptionType.connectionError
              ? 'Không kết nối được service ký (192.168.1.101:7654).\n\n'
              : 'Lỗi service: ${e.type}\n\n';
      return VnptSignatureResult(
        success: false,
        error: '${errMsg}'
               'Workflow ký số qua HIS Pro desktop chưa được cấu hình đầy đủ.\n'
               'Vui lòng ký trên HIS Pro desktop hoặc liên hệ IT.\n\n'
               'Lưu/Lưu ký vẫn dùng được bình thường.',
      );
    } catch (e) {
      debugPrint('[signPdf v3.0.56] Error: $e');
      return VnptSignatureResult(
        success: false,
        error: 'Lỗi không xác định: $e\n\n'
               'Vui lòng ký trên HIS Pro desktop hoặc liên hệ IT.',
      );
    }
  }

  /// v3.0.29: Check URL có phải placeholder không
  /// - Chứa "YOUR_BV_SERVER" / "TODO" / "example.com" → placeholder
  /// - Domain "api.bvdk.ninhthuan.vn" không có thật (verified 2026-07-16) → cũng coi như placeholder
  /// - Cần BS cung cấp URL thật
  bool _isPlaceholderUrl(String url) {
    final u = url.toLowerCase();
    if (u.isEmpty) return true;
    if (u.contains('your_bv_server')) return true;
    if (u.contains('your-server')) return true;
    if (u.contains('todo')) return true;
    if (u.contains('example.com')) return true;
    // v3.0.52: localhost OK vì Python bridge có thể chạy trên cùng máy test
    // (BS sẽ thay bằng IP PC thật khi deploy)
    // if (u.contains('localhost')) return true;
    // v3.0.29: Domain BV cũ (từ v3.0.24-3.0.27) không tồn tại trên internet
    if (u.contains('api.bvdk.ninhthuan.vn')) return true;
    if (u.contains('bvdk.ninhthuan.vn')) return true;
    return false;
  }

  /// v3.0.52: Lấy URL backend VNPT SmartCA (override từ Settings nếu có)
  String _getBackendUrl() {
    try {
      // Có thể override qua SharedPreferences key 'vnpt_smartca_url'
      // (BS có thể nhập URL khác trong Settings)
      return VnptSmartcaConfig.transactionApiUrl;
    } catch (_) {
      return VnptSmartcaConfig.transactionApiUrl;
    }
  }

  /// v3.0.28: Lấy username cho API backend BV (format phù hợp API)
  String _getCurrentUserName() {
    try {
      final api = HisProApiService.instance;
      return api.loginName ?? HisProHardcoded.loginName;
    } catch (_) {
      return HisProHardcoded.loginName;
    }
  }

  /// v3.0.51: Lấy TokenCode HIS Pro hiện tại (cho backend VNPT SmartCA auth)
  String _getCurrentTokenCode() {
    try {
      return HisProApiService.instance.token
          ?? HisProHardcoded.tokenCode;
    } catch (_) {
      return HisProHardcoded.tokenCode;
    }
  }

  /// v3.0.51: Lấy ClientIpAddress HIS Pro hiện tại
  String _getCurrentClientIp() {
    try {
      return HisProApiService.instance.clientIp
          ?? HisProHardcoded.clientIpAddress;
    } catch (_) {
      return HisProHardcoded.clientIpAddress;
    }
  }
}
