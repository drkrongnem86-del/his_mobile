// ApiDebugService v2.76.5
// Debug: gọi API thật với auth đúng + xem field trong response
// + gọi HIS Pro thẳng (port 1408) để xem field uppercase TDL_PATIENT_UNSIGNED_NAME
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
class ApiDebugService {
  /// Gọi API Data (`113.163.187.3:3000`) + HIS Pro (`172.16.9.6:1408`)
  /// BS copy text này gửi cho dev
  static Future<String> debugPatientsInRooms({
    required String dataBaseUrl,   // http://113.163.187.3:3000
    required String hisProBaseUrl, // http://172.16.9.6:1401
    required String mosBaseUrl,    // http://172.16.9.6:1408 (MOS/HisTreatment)
    required String loginName,
    required String password,
    List<int>? bedRoomIds,
  }) async {
    bedRoomIds ??= [22, 23, 68, 71];
    final buf = StringBuffer();
    buf.writeln('=== ApiDebugService v3.0.12 (tăng timeout + skip AcsToken) ===');
    buf.writeln('Time: ${DateTime.now()}');
    buf.writeln('dataBaseUrl: $dataBaseUrl');
    buf.writeln('hisProBaseUrl: $hisProBaseUrl');
    buf.writeln('mosBaseUrl: $mosBaseUrl');
    buf.writeln('loginName: $loginName');
    buf.writeln('bedRoomIds: $bedRoomIds');
    buf.writeln('');

    // v3.0.12: Lấy Bearer từ HisProApiService (ưu tiên Custom → Hardcode)
    // Nếu có Bearer, skip AcsToken/Authorize (không cần VPN 1401)
    String? existingBearer;
    try {
      existingBearer = HisProApiService.instance.getEffectiveBearer();
      buf.writeln('🔑 Bearer available: ${existingBearer != null ? "${existingBearer.substring(0, 6)}…${existingBearer.substring(existingBearer.length - 4)} (${HisProApiService.instance.getEffectiveTokenSource()})" : "NULL"}');
    } catch (e) {
      buf.writeln('⚠ Không load được Bearer: $e');
    }
    buf.writeln('');

    // ========== 1. DATA API (113.163.187.3:3000) - v3.0.43 BỎ ==========
    // BVBM Gateway đã bỏ khỏi app. Chỉ ghi chú thông tin.
    buf.writeln('========== DATA API (${dataBaseUrl}) ==========');
    buf.writeln('v3.0.43: BVBM Gateway đã bỏ. App chỉ dùng HIS Pro 1417 (EMR).');
    buf.writeln('');

    // ========== 2. HIS PRO ACS (1401) - get token ==========
    // v3.0.12: Skip AcsToken/Authorize nếu đã có Bearer từ HisProApiService
    buf.writeln('========== HIS PRO ACS ($hisProBaseUrl) ==========');
    String? acsToken = existingBearer;  // v3.0.12: dùng Bearer có sẵn
    if (acsToken != null && acsToken.isNotEmpty) {
      buf.writeln('--- SKIP AcsToken/Authorize (đã có Bearer) ---');
      buf.writeln('token: ${acsToken.substring(0, 6)}…${acsToken.substring(acsToken.length - 4)} (${HisProApiService.instance.getEffectiveTokenSource()})');
    } else {
      buf.writeln('--- 2.1 GET /api/AcsToken/Authorize?param= ---');
      final acsDio = Dio(BaseOptions(
        baseUrl: hisProBaseUrl,
        connectTimeout: const Duration(seconds: 30),  // v3.0.12: tăng 8s → 30s
        receiveTimeout: const Duration(seconds: 30),
      ));
      try {
        final param = base64Encode(utf8.encode('{"appCode":"HISPRO","loginName":"$loginName","password":""}'));
        final r = await acsDio.get('/api/AcsToken/Authorize', queryParameters: {'param': param});
        buf.writeln('status: ${r.statusCode}');
        if (r.data != null) {
          acsToken = r.data.toString();
          buf.writeln('token: ${acsToken.length > 30 ? '${acsToken.substring(0, 30)}...' : acsToken}');
        }
      } catch (e) {
        buf.writeln('AcsToken error: ${e.toString().split("\n").first}');
        buf.writeln('→ Cần paste Bearer vào Settings → Cấu hình HIS → Bearer tùy chỉnh');
      }
    }
    buf.writeln('');

    // BN list qua HIS Pro 1408 (MOS)
    if (acsToken != null && acsToken.isNotEmpty && !acsToken.contains('error')) {
      try {
        buf.writeln('========== HIS PRO MOS ($mosBaseUrl) ==========');
        final mosDio = Dio(BaseOptions(
          baseUrl: mosBaseUrl,
          connectTimeout: const Duration(seconds: 30),  // v3.0.12: tăng 8s → 30s
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Authorization': 'Bearer $acsToken'},
        ));
        buf.writeln('--- 3.1 GET /api/HisTreatment/GetView?param=BASE64 ---');
        try {
          // v3.0.43: Endpoint là GET ?param=BASE64 (KHÔNG phải POST body)
          // Lấy DS điều trị theo khoa (filter theo departmentId 22 - HSCC)
          final apiData = {
            'DEPARTMENT_ID': 22,
            'IS_PAUSE': false,
            'IS_ACTIVE': 1,
            'LIMIT': 5,
          };
          final param = base64Encode(utf8.encode(jsonEncode(apiData)));
          final r = await mosDio.get('/api/HisTreatment/GetView?param=$param');
          buf.writeln('status: ${r.statusCode}');
          if (r.data is Map) {
            final data = r.data['Data'] ?? r.data['data'];
            if (data is List && data.isNotEmpty) {
              buf.writeln('count: ${data.length}');
              final first = data.first as Map;
              buf.writeln('first item keys: ${first.keys.toList()}');
              buf.writeln('--- first treatment (raw) ---');
              buf.writeln(jsonEncode(first).substring(0, jsonEncode(first).length > 2000 ? 2000 : jsonEncode(first).length));
              buf.writeln('--- end ---');

              buf.writeln('');
              buf.writeln('--- name-related fields (first 3) ---');
              for (var i = 0; i < data.length && i < 3; i++) {
                final p = data[i] as Map;
                final nameFields = <String, dynamic>{};
                p.forEach((k, v) {
                  final kl = k.toString().toLowerCase();
                  if (kl.contains('name') || kl.contains('patient_name')) {
                    nameFields[k.toString()] = v;
                  }
                });
                buf.writeln('Treatment #${i + 1}: $nameFields');
              }
            } else {
              buf.writeln('no data');
            }
          }
        } catch (e) {
          buf.writeln('HisTreatment error: ${e.toString().split("\n").first}');
        }
      } catch (e) {
        buf.writeln('HIS PRO outer error: ${e.toString().split("\n").first}');
      }
    }

    return buf.toString();
  }
}
