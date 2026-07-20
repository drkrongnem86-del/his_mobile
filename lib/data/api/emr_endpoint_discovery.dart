// EmrEndpointDiscovery v2.99.0 - Khám phá HIS Pro EMR endpoints
// Mục đích: Probe các endpoint tiềm năng để tìm SignWithCreateDoc, Update, ReplaceFile...
// Pattern: từ log app Y tế số, biết HIS Pro có ~50+ endpoint. Một số endpoint ký số có thể:
//   - POST /api/EmrDocument/SignWithCreateDoc (ký + tạo doc trong 1 step)
//   - POST /api/EmrDocument/SignDigital (ký số PDF đã upload)
//   - POST /api/EmrDocument/Update (cập nhật doc - gắn signed PDF)
//   - POST /api/EmrDocument/ReplaceFile (thay file PDF)
//   - POST /api/EmrDocument/Sign (ký 1 document đã tồn tại)
//
// Khi chạy probe: app gọi từng endpoint với body test, ghi log status + body.
// Endpoint nào trả 200/400 (không phải 404) → có khả năng tồn tại.
//
// BS có thể chạy từ app: Cài đặt → HIS Pro → "Khám phá EMR endpoints" (TODO nút)
//
// v2.99.0: Tạo file - workflow B+C (tìm API sign thay thế PFX local)

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/api/his_pro_api_service.dart';

class EndpointProbeResult {
  final String endpoint;
  final String method;     // 'GET' | 'POST'
  final int? statusCode;
  final String? bodySnippet;  // first 200 chars
  final bool exists;        // true nếu server trả != 404
  final String? error;

  EndpointProbeResult({
    required this.endpoint,
    required this.method,
    this.statusCode,
    this.bodySnippet,
    this.exists = false,
    this.error,
  });
}

class EmrEndpointDiscovery {
  static final EmrEndpointDiscovery instance = EmrEndpointDiscovery._();
  EmrEndpointDiscovery._();

  /// Danh sách endpoint EMR có thể tồn tại (dự đoán từ convention REST HIS Pro)
  /// BS có thể edit thêm khi phát hiện
  static const List<({String path, String method, String? sampleBody})>
      candidateEndpoints = [
    // ===== EMR Document Signing (mục tiêu chính) =====
    (path: '/api/EmrDocument/SignWithCreateDoc', method: 'POST',
        sampleBody: '{"ApiData":{"TreatmentCode":"TEST","SignerId":1}}'),
    (path: '/api/EmrDocument/SignDigital', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST","SignatureData":""}}'),
    (path: '/api/EmrDocument/Sign', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST"}}'),
    (path: '/api/EmrDocument/Update', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST"}}'),
    (path: '/api/EmrDocument/UpdateSign', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST"}}'),
    (path: '/api/EmrDocument/ReplaceFile', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST","Base64Data":""}}'),
    (path: '/api/EmrDocument/AttachSignature', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST"}}'),
    (path: '/api/EmrDocument/FinishSign', method: 'POST',
        sampleBody: '{"ApiData":{"DocumentCode":"TEST"}}'),

    // ===== EMR Document CRUD (tham khảo) =====
    (path: '/api/EmrDocument/Get', method: 'GET', sampleBody: null),
    (path: '/api/EmrDocument/GetView', method: 'GET', sampleBody: null),
    (path: '/api/EmrDocument/Create', method: 'POST', sampleBody: null),
    (path: '/api/EmrDocument/CreateByTdo', method: 'POST', sampleBody: null),
    (path: '/api/EmrDocument/Delete', method: 'POST', sampleBody: null),
    (path: '/api/EmrDocument/DownloadFile', method: 'POST', sampleBody: null),

    // ===== EMR Document Group =====
    (path: '/api/EmrDocumentGroup/Get', method: 'GET', sampleBody: null),
    (path: '/api/DocumentType/Get', method: 'GET', sampleBody: null),
  ];

  /// Probe tất cả endpoint, trả về list kết quả
  /// Timeout 5s mỗi endpoint, tổng ~90s
  Future<List<EndpointProbeResult>> probeAll({String? customBaseUrl}) async {
    final api = HisProApiService.instance;
    if (!api.isLoggedIn) {
      throw Exception('Chưa đăng nhập HIS Pro');
    }
    await api.refreshTokenIfNeeded();
    final base = customBaseUrl ?? api.getEmrBaseUrlSync();

    final results = <EndpointProbeResult>[];
    for (final ep in candidateEndpoints) {
      final r = await _probeOne(base, ep.path, ep.method, ep.sampleBody);
      results.add(r);
      debugPrint('PROBE ${ep.method} ${ep.path} -> ${r.statusCode} exists=${r.exists}');
    }
    return results;
  }

  /// Probe 1 endpoint, gọi thật (không cache)
  /// v3.0.42: Dùng TokenCode headers thay vì Authorization: Bearer
  Future<EndpointProbeResult> _probeOne(
    String base,
    String path,
    String method,
    String? sampleBody,
  ) async {
    final url = '$base$path';
    final headers = HisProApiService.instance.getEffectiveAuthHeaders();
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 6),
      headers: headers,
    ));
    try {
      Response r;
      if (method == 'GET') {
        r = await dio.get(url);
      } else {
        // POST với body test (parser reject nếu body sai schema)
        final body = sampleBody != null ? jsonDecode(sampleBody) : {};
        r = await dio.post(url, data: body);
      }
      final bodyStr = r.data?.toString() ?? '';
      return EndpointProbeResult(
        endpoint: path,
        method: method,
        statusCode: r.statusCode,
        bodySnippet: bodyStr.length > 200 ? '${bodyStr.substring(0, 200)}...' : bodyStr,
        exists: r.statusCode != 404,
      );
    } on DioException catch (e) {
      final respData = e.response?.data;
      return EndpointProbeResult(
        endpoint: path,
        method: method,
        statusCode: e.response?.statusCode,
        bodySnippet: respData != null ? respData.toString().substring(0, respData.toString().length < 200 ? respData.toString().length : 200) : null,
        exists: e.response?.statusCode != 404,
        error: e.message,
      );
    } catch (e) {
      return EndpointProbeResult(
        endpoint: path,
        method: method,
        statusCode: null,
        exists: false,
        error: e.toString(),
      );
    }
  }

  /// Probe nhanh 4 endpoint ưu tiên nhất (cho UI nhanh)
  Future<List<EndpointProbeResult>> probePriority() async {
    const priority = [
      '/api/EmrDocument/SignWithCreateDoc',
      '/api/EmrDocument/SignDigital',
      '/api/EmrDocument/Update',
      '/api/EmrDocument/ReplaceFile',
    ];
    final api = HisProApiService.instance;
    if (!api.isLoggedIn) {
      throw Exception('Chưa đăng nhập HIS Pro');
    }
    await api.refreshTokenIfNeeded();
    final base = api.getEmrBaseUrlSync();
    final results = <EndpointProbeResult>[];
    for (final path in priority) {
      final r = await _probeOne(base, path, 'POST', '{"ApiData":{}}');
      results.add(r);
    }
    return results;
  }
}
