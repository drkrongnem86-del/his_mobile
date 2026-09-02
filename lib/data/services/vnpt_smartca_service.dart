// v3.0.24: Dart wrapper cho VNPT SmartCA Android SDK
//
// Workflow:
//   1. init(clientId) - khởi tạo SDK với partner ID của BV
//   2. signPdf(pdfBytes) - workflow chính:
//      a. Tính SHA-256 hash của PDF
//      b. Gọi API backend BV lấy tranId (POST /api/vnpt/smartca/transaction)
//      c. Mở app VNPT SmartCA qua MethodChannel → user xác nhận
//      d. Nhận signature từ VNPT SmartCA
//      e. Trả về PKCS#7 signature base64
//
// Docs: https://smartca.vnpt.vn/help/docs/sdks/deeplink/steps/android/
// SDK: com.github.VNPTSmartCA:android-sdk:1.0.4

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class VnptSignResult {
  final bool success;
  final String? signature;  // PKCS#7 base64
  final String? tranId;
  final int status;
  final String? message;
  final String? error;

  const VnptSignResult({
    required this.success,
    this.signature,
    this.tranId,
    this.status = -1,
    this.message,
    this.error,
  });

  @override
  String toString() => 'VnptSignResult(success=$success, status=$status, message=$message)';
}

class VnptSmartcaService {
  static final VnptSmartcaService instance = VnptSmartcaService._();
  VnptSmartcaService._();

  static const _channel = MethodChannel('com.drnem.ccdk.his_mobile/vnpt_smartca');
  bool _initialized = false;

  /// v3.0.24: Khởi tạo VNPT SmartCA SDK
  /// [clientId] = Mobile Code / Partner ID (VNPT gửi qua email khi đăng ký)
  /// [env] = "PRODUCTION" | "DEVELOPMENT" (mặc định PRODUCTION)
  Future<bool> init({required String clientId, String env = 'PRODUCTION'}) async {
    if (!Platform.isAndroid) {
      debugPrint('VNPT SmartCA chỉ hỗ trợ Android');
      return false;
    }
    try {
      final result = await _channel.invokeMethod('init', {
        'clientId': clientId,
        'env': env,
      });
      _initialized = result is Map && result['ok'] == true;
      debugPrint('VNPT SmartCA init: $result');
      return _initialized;
    } catch (e) {
      debugPrint('VNPT SmartCA init error: $e');
      _initialized = false;
      return false;
    }
  }

  /// v3.0.24: Ký PDF qua VNPT SmartCA Deeplink
  /// [pdfBytes] = PDF cần ký
  /// [transactionApiUrl] = URL backend BV trả tranId (vd: https://api.bvdk.ninhthuan.vn/api/vnpt/smartca/transaction)
  /// [transactionApiBody] = body JSON cho API (vd: {hash: "...", certSerial: "..."})
  /// Trả về VnptSignResult với signature PKCS#7 base64 (nếu thành công)
  Future<VnptSignResult> signPdf({
    required Uint8List pdfBytes,
    required String transactionApiUrl,
    required Map<String, dynamic> transactionApiBody,
  }) async {
    if (!_initialized) {
      return VnptSignResult(
        success: false,
        error: 'Chưa khởi tạo VNPT SmartCA (gọi init() trước)',
      );
    }
    try {
      // Bước 1: Tính SHA-256 hash
      final hash = sha256.convert(pdfBytes).toString();
      debugPrint('VNPT SmartCA PDF hash: $hash');

      // Bước 2: Gọi API backend BV lấy tranId
      final body = Map<String, dynamic>.from(transactionApiBody);
      body['hash'] = hash;
      body['hashAlgorithm'] = 'SHA-256';

      // Sử dụng HttpClient đơn giản (không phụ thuộc Dio)
      final httpResponse = await _postJson(transactionApiUrl, body);
      if (!httpResponse.success) {
        return VnptSignResult(
          success: false,
          error: 'API backend lỗi: ${httpResponse.error}',
        );
      }
      final tranId = httpResponse.data?['tranId'] as String?;
      if (tranId == null || tranId.isEmpty) {
        return VnptSignResult(
          success: false,
          error: 'API backend không trả tranId. Response: ${httpResponse.data}',
        );
      }
      debugPrint('VNPT SmartCA tranId: $tranId');

      // Bước 3: Mở app VNPT SmartCA qua Intent
      final result = await _channel.invokeMethod('requestSign', {
        'tranId': tranId,
      });
      debugPrint('VNPT SmartCA result: $result');
      if (result is Map) {
        return VnptSignResult(
          success: result['ok'] == true,
          signature: result['signature'] as String?,
          tranId: result['tranId'] as String? ?? tranId,
          status: (result['status'] as int?) ?? -1,
          message: result['message'] as String?,
        );
      }
      return VnptSignResult(
        success: false,
        error: 'Unexpected response from VNPT SmartCA: $result',
      );
    } catch (e) {
      debugPrint('VNPT SmartCA signPdf error: $e');
      return VnptSignResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<_HttpResponse> _postJson(String url, Map<String, dynamic> body) async {
    try {
      // Sử dụng package http (built-in qua flutter)
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final uri = Uri.parse(url);
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        return _HttpResponse(success: true, data: data);
      }
      return _HttpResponse(
        success: false,
        error: 'HTTP ${response.statusCode}: $responseBody',
      );
    } catch (e) {
      return _HttpResponse(success: false, error: e.toString());
    }
  }
}

class _HttpResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;
  _HttpResponse({required this.success, this.data, this.error});
}

/// v3.0.24: Helper nhúng PKCS#7 signature vào PDF
/// Dùng pdf package để add signature field/annotation
/// (Hiện tại: trả về PDF gốc + signature riêng - workflow EMR HIS Pro chỉ cần metadata IsFinishSign=true)
class VnptPdfEmbedder {
  /// Embed PKCS#7 signature vào PDF (placeholder - workflow EMR dùng metadata)
  /// Tham khảo: pdf package + pointycastle để parse PKCS#7 + tạo SigDict
  /// Hiện tại: trả về PDF gốc - server EMR check IsFinishSign=true là đủ
  static Uint8List embedSignaturePlaceholder(Uint8List pdfBytes) {
    // TODO: Embed PKCS#7 vào PDF (cần pkcs7 + pointycastle để tạo SigDict)
    return pdfBytes;
  }
}
