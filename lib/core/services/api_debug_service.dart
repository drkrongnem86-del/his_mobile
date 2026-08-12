// ApiDebugService v3.0.93
// Debug: gọi API thật với auth đúng + xem field trong response
// Test 2 endpoints chính của app:
//   1. Y Tế Số public (113.163.187.3:3000) - login + medical-record/document-types
//   2. HIS Pro 1408 (172.16.9.6) - HisTreatment/GetView
//
// BS copy text này gửi cho dev
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';

class ApiDebugService {
  /// Gọi API Y Tế Số public + HIS Pro
  /// BS copy text này gửi cho dev
  static Future<String> debugApis() async {
    final buf = StringBuffer();
    buf.writeln('=== ApiDebugService v3.0.93 ===');
    buf.writeln('Time: ${DateTime.now()}');
    buf.writeln('App: ${HisConfigService.instance.config.mode}');
    buf.writeln('');

    // ========== 0. CONFIG ==========
    final cfg = HisConfigService.instance.config;
    buf.writeln('========== CONFIG ==========');
    buf.writeln('BVBM (Data public): ${cfg.bvbmUrl}');
    buf.writeln('HIS Pro EMR:        ${cfg.emrUrl}');
    buf.writeln('HIS Pro MOS (1408): ${cfg.mosUrl}');
    buf.writeln('Login:              ${cfg.loginName}');
    buf.writeln('');

    // ========== 1. Y Tế SỐ PUBLIC (Bộ Y tế) - 113.163.187.3:3000 ==========
    buf.writeln('========== Y TẾ SỐ PUBLIC (http://113.163.187.3:3000) ==========');
    final yTeBase = 'http://113.163.187.3:3000';
    final yTeDio = Dio(BaseOptions(
      baseUrl: yTeBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    // v3.0.93: Lấy email từ current user (BS nemk thì dùng K Rong Nểm)
    final yTeEmail = '${cfg.loginName}@krongnem.local';
    final yTePass = '1027'; // Default cho nemk
    String? yTeToken;
    try {
      buf.writeln('--- 1.1 POST /v1/auth/login (email=$yTeEmail) ---');
      final r = await yTeDio.post('/v1/auth/login', data: {
        'email': yTeEmail,
        'password': yTePass,
      });
      buf.writeln('status: ${r.statusCode}');
      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        yTeToken = m['token']?.toString() ?? m['access_token']?.toString();
        buf.writeln('token: ${yTeToken != null ? "${yTeToken.substring(0, 20)}…(${yTeToken.length} chars)" : "NULL"}');
        buf.writeln('user: ${m['user']}');
      } else {
        buf.writeln('body: ${r.data.toString().substring(0, r.data.toString().length.clamp(0, 500))}');
      }
    } catch (e) {
      buf.writeln('YTe login error: ${e.toString().split("\n").first}');
    }
    buf.writeln('');

    // Test document-types (nếu có token)
    if (yTeToken != null && yTeToken.isNotEmpty) {
      try {
        buf.writeln('--- 1.2 GET /v1/medical-record/document-types?treatmentCode=000002128160 ---');
        final r = await yTeDio.get(
          '/v1/medical-record/document-types',
          queryParameters: {'treatmentCode': '000002128160'},
          options: Options(headers: {'Authorization': 'Bearer $yTeToken'}),
        );
        buf.writeln('status: ${r.statusCode}');
        if (r.data is Map) {
          final m = r.data as Map;
          // YTeSoService parse response như: response.data['data'] = List các nhóm
          final groups = m['data'] ?? m['Data'];
          if (groups is List && groups.isNotEmpty) {
            buf.writeln('groups: ${groups.length}');
            buf.writeln('first group keys: ${(groups.first as Map).keys.toList()}');
            // Lấy items từ group đầu tiên
            final firstGroup = groups.first as Map;
            final items = firstGroup['items'] ?? firstGroup['documents'] ?? firstGroup['children'];
            if (items is List && items.isNotEmpty) {
              buf.writeln('first item keys: ${(items.first as Map).keys.toList()}');
              buf.writeln('--- first item (raw, max 1000 chars) ---');
              final s = jsonEncode(items.first);
              buf.writeln(s.length > 1000 ? '${s.substring(0, 1000)}…' : s);
              buf.writeln('--- end ---');
            }
          } else {
            buf.writeln('no groups / data: ${m.keys.toList()}');
          }
        }
      } catch (e) {
        buf.writeln('YTe doc-types error: ${e.toString().split("\n").first}');
      }
      buf.writeln('');
    }

    // ========== 2. HIS PRO MOS (1408) - Bearer token ==========
    final mosUrl = cfg.mosUrl;
    final hisProToken = ThongkeAuthService.instance.hisProToken;
    buf.writeln('========== HIS PRO MOS ($mosUrl) ==========');
    buf.writeln('token: ${hisProToken != null ? "${hisProToken.substring(0, 6)}…${hisProToken.substring(hisProToken.length - 4)} (${hisProToken.length} chars)" : "NULL"}');
    if (hisProToken != null && hisProToken.isNotEmpty) {
      final mosDio = Dio(BaseOptions(
        baseUrl: mosUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Authorization': 'Bearer $hisProToken'},
      ));
      try {
        buf.writeln('--- 2.1 GET /api/HisTreatment/GetView?param=BASE64 ---');
        final apiData = {
          'DEPARTMENT_ID': cfg.defaultDeptId,
          'IS_PAUSE': false,
          'IS_ACTIVE': 1,
          'LIMIT': 3,
        };
        final param = base64Encode(utf8.encode(jsonEncode(apiData)));
        final r = await mosDio.get('/api/HisTreatment/GetView?param=$param');
        buf.writeln('status: ${r.statusCode}');
        if (r.data is Map) {
          final m = r.data as Map;
          final data = m['Data'] ?? m['data'];
          if (data is List && data.isNotEmpty) {
            buf.writeln('count: ${data.length}');
            final first = data.first as Map;
            buf.writeln('--- keys (${first.keys.length}) ---');
            buf.writeln(first.keys.toList().join(', '));
            buf.writeln('');
            // Highlight name fields
            buf.writeln('--- name fields (first 2) ---');
            for (var i = 0; i < data.length && i < 2; i++) {
              final p = data[i] as Map;
              final nameFields = <String, dynamic>{};
              p.forEach((k, v) {
                final kl = k.toString().toLowerCase();
                if (kl.contains('name') || kl.contains('patient')) {
                  nameFields[k.toString()] = v;
                }
              });
              buf.writeln('Treatment #${i + 1}: $nameFields');
            }
            buf.writeln('');
            // Raw JSON (max 2000 chars)
            buf.writeln('--- first treatment (raw, max 2000 chars) ---');
            final s = jsonEncode(first);
            buf.writeln(s.length > 2000 ? '${s.substring(0, 2000)}…' : s);
            buf.writeln('--- end ---');
          } else {
            buf.writeln('no data / response keys: ${m.keys.toList()}');
          }
        } else {
          buf.writeln('non-map response: ${r.data.toString().substring(0, r.data.toString().length.clamp(0, 500))}');
        }
      } catch (e) {
        buf.writeln('HisTreatment error: ${e.toString().split("\n").first}');
      }
    } else {
      buf.writeln('--- SKIP (no HIS Pro token) ---');
      buf.writeln('Vào Settings → Cấu hình HIS → Bearer tùy chỉnh để paste token.');
    }
    buf.writeln('');

    return buf.toString();
  }
}
