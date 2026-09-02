// HisServiceReqService.dart v2.53.0
// Tạo phiếu khám / chỉ định DV qua HIS Pro thật (port 1408) + push EMR
//
// Workflow:
//   1. ICD đầu tiên (chẩn đoán chính) → gắn vào Treatment
//   2. List CLS (Service req) → POST api/HisServiceReq/Create
//   3. List thuốc (thường v2.54+, demo skeleton)
//   4. Auto-create EMR document + push PDF (qua emr_push_service)
//
// Input schema (1 service req):
//   {
//     'TREATMENT_ID': <int>,    // Required - BN's TREATMENT.ID
//     'SERVICE_ID': <int>,      // Required - HisService.ID
//     'SERVICE_REQ_STT_ID': 1,  // 1=Mới chỉ định
//     'REQUEST_LOGINNAME': <string>,  // User tạo
//     'REQUEST_USERNAME': <string>,
//     'REQUEST_ROOM_ID': <int>,
//     'AMOUNT': 1,
//     'INSTRUCTION_NOTE': <string>,  // Ghi chú
//     'ICDS': <json string>,  // ICD codes
//   }

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import 'thongke_auth_service.dart';
import 'his_catalog_service.dart';

class CreateServiceReqInput {
  final int treatmentId;
  final int serviceId;
  final String? note;
  final String requestLoginname;
  final String requestUsername;
  final int? requestRoomId;
  final int amount;
  final List<String> icdCodes;

  CreateServiceReqInput({
    required this.treatmentId,
    required this.serviceId,
    required this.requestLoginname,
    required this.requestUsername,
    this.requestRoomId,
    this.amount = 1,
    this.icdCodes = const [],
    this.note,
  });
}

class CreateServiceReqResult {
  final bool success;
  final int? serviceReqId;
  final String? serviceReqCode;
  final String? error;
  final List<String> errors = [];

  CreateServiceReqResult({
    required this.success,
    this.serviceReqId,
    this.serviceReqCode,
    this.error,
  });
}

class HisServiceReqService {
  static final HisServiceReqService instance = HisServiceReqService._();
  HisServiceReqService._();

  late Dio _dio;

  Future<void> init() async {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'HIS-Mobile/2.14.1',
        '___ipAddress': '127.0.0.1',
        'Content-Type': 'application/json',
      },
    ));
  }

  String get _base => ThongkeAuthService.hisProBaseUrl;

  Future<String?> _token() async => ThongkeAuthService.instance.hisProToken;

  /// v2.53.0: Tạo service req qua API `api/HisServiceReq/Update` (POST method)
  /// v2.53.1: HIS Pro dùng POST /Update cho cả Create (ID=null) + Update (ID=<id>)
  ///   - ID=null (default khi create) → tạo mới
  ///   - ID=integer → update existing
  ///   - SDO fields: TREATMENT_ID, SERVICE_ID, SERVICE_REQ_STT_ID, REQUEST_LOGINNAME, REQUEST_USERNAME, ...
  Future<CreateServiceReqResult> createServiceReq(CreateServiceReqInput input) async {
    try {
      final token = await _token();
      if ((token ?? '').isEmpty) {
        return CreateServiceReqResult(success: false, error: 'Không có token HIS Pro (vào Cài đặt → EMR Sync)');
      }

      // SDO (Service Data Object) - body cho HisServiceReq/Update
      // Schema reference: HIS_PRO HIS_SERVICE_REQ SDO (verified live)
      final sdo = <String, dynamic>{
        'ID': null,  // null = tạo mới
        'TREATMENT_ID': input.treatmentId,
        'SERVICE_ID': input.serviceId,
        'SERVICE_REQ_STT_ID': 1,  // 1=mới chỉ định, 2=đã duyệt
        'REQUEST_LOGINNAME': input.requestLoginname,
        'REQUEST_USERNAME': input.requestUsername,
        if (input.requestRoomId != null) 'REQUEST_ROOM_ID': input.requestRoomId,
        'AMOUNT': input.amount,
        if (input.note != null && input.note!.isNotEmpty) 'INSTRUCTION_NOTE': input.note,
        // ICD codes kèm theo
        if (input.icdCodes.isNotEmpty) 'ICD_CODES': input.icdCodes.join(','),
        'IS_NOT_REQUIRE_FEE': false,
        'IS_KIDNEY': false,
        'IS_NO_EXECUTE': false,
      };
      final body = {
        'CommonParam': {'LanguageCode': 'VI', 'Start': 0, 'Limit': 1, 'HasException': false},
        'ApiData': sdo,
      };
      final encoded = base64.encode(utf8.encode(json.encode(body)));

      // POST /Update (HIS Pro không có endpoint /Create - dùng POST /Update với ID=null)
      final resp = await _dio.post(
        '$_base/api/HisServiceReq/Update?param=$encoded',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      debugPrint('HisServiceReq/Update POST status: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final d = resp.data;
        if (d is Map) {
          if (d['Success'] == true) {
            // Response data có thể là list hay single
            final data = d['Data'];
            int? id;
            String? code;
            if (data is List && data.isNotEmpty) {
              id = (data[0]['ID'] as num?)?.toInt();
              code = data[0]['SERVICE_REQ_CODE']?.toString();
            } else if (data is Map) {
              id = (data['ID'] as num?)?.toInt();
              code = data['SERVICE_REQ_CODE']?.toString();
            }
            debugPrint('✅ HisServiceReq created: ID=$id CODE=$code');
            return CreateServiceReqResult(success: true, serviceReqId: id, serviceReqCode: code);
          }
          final errorMsg = d['Description'] ?? d['Message'] ?? d.toString();
          debugPrint('Update failed: $errorMsg');
          return CreateServiceReqResult(success: false, error: errorMsg.toString());
        }
      }
      return CreateServiceReqResult(success: false, error: 'HTTP ${resp.statusCode}: ${resp.data}');
    } catch (e) {
      debugPrint('HisServiceReq/Update error: $e');
      return CreateServiceReqResult(success: false, error: e.toString());
    }
  }

  /// Tạo nhiều service req trong 1 lần (gửi tuần tự hoặc batch)
  Future<List<CreateServiceReqResult>> batchCreate(
    List<CreateServiceReqInput> inputs,
  ) async {
    final results = <CreateServiceReqResult>[];
    for (final input in inputs) {
      final r = await createServiceReq(input);
      results.add(r);
      if (!r.success) break; // stop nếu fail
    }
    return results;
  }

  /// Helper: Tạo phiếu khám từ danh sách CatalogItem + ICD codes
  Future<List<CreateServiceReqResult>> createKhamPhieu({
    required int treatmentId,
    required String requestLoginname,
    required String requestUsername,
    int? requestRoomId,
    required List<CatalogItem> selectedServices,
    required List<String> primaryIcdCodes,
    String? instructionNote,
  }) async {
    final inputs = selectedServices.map((s) => CreateServiceReqInput(
      treatmentId: treatmentId,
      serviceId: s.id,
      requestLoginname: requestLoginname,
      requestUsername: requestUsername,
      requestRoomId: requestRoomId,
      icdCodes: primaryIcdCodes,
      note: instructionNote,
    )).toList();
    return batchCreate(inputs);
  }
}
