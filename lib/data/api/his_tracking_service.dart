// HisTrackingService.dart v2.55.0
// Tự động tạo Tracking (theo dõi điều trị) sau khi khám
//
// HIS Tracking chứa:
// - TrackingTime (thời điểm)
// - Content (nội dung theo dõi - sinh hiệu)
// - TrackingType (loại: 1=Nhập viện, 2=Chuyển khoa, ...)
// - TreatmentId, DepartmentId, RoomId
// - Icd (chẩn đoán)
// - Care (sơ kết 24h)

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'thongke_auth_service.dart';

class TrackingInput {
  final int treatmentId;
  final int departmentId;
  final int roomId;
  final int trackingType;   // 1=NHẬP VIỆN, 2=...
  final String content;     // Nội dung theo dõi (sinh hiệu)
  final String icdCode;
  final String icdName;
  final DateTime trackingTime;
  // v2.55.0: Theo dõi sinh hiệu
  final double? pulsel;
  final double? pulselAvg;
  final double? temperature;
  final double? systolic;  // huyết áp tâm thu
  final double? diastolic; // huyết áp tâm trương
  final double? spo2;

  TrackingInput({
    required this.treatmentId,
    required this.departmentId,
    required this.roomId,
    required this.trackingType,
    required this.content,
    required this.icdCode,
    required this.icdName,
    required this.trackingTime,
    this.pulsel,
    this.pulselAvg,
    this.temperature,
    this.systolic,
    this.diastolic,
    this.spo2,
  });
}

class TrackingResult {
  final bool success;
  final int? id;
  final String? error;
  TrackingResult({required this.success, this.id, this.error});
}

class HisTrackingService {
  static final HisTrackingService instance = HisTrackingService._();
  HisTrackingService._();

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

  /// Tạo tracking mới (POST /Update endpoint, ID=null)
  Future<TrackingResult> createTracking(TrackingInput input) async {
    try {
      final token = ThongkeAuthService.instance.hisProToken;
      if ((token ?? '').isEmpty) {
        return TrackingResult(success: false, error: 'Thiếu HIS Pro token');
      }
      // HisTracking SDO schema (verified qua test live)
      final sdo = <String, dynamic>{
        'ID': null,
        'TREATMENT_ID': input.treatmentId,
        'DEPARTMENT_ID': input.departmentId,
        'ROOM_ID': input.roomId,
        'TRACKING_TYPE': input.trackingType,
        'TRACKING_TIME': input.trackingTime.millisecondsSinceEpoch,
        'CONTENT': input.content,
        'ICD_CODE': input.icdCode,
        'ICD_NAME': input.icdName,
        // Sinh hiệu
        if (input.pulsel != null) 'PULSEL': input.pulsel,
        if (input.pulselAvg != null) 'PULSE_AVG': input.pulselAvg,
        if (input.temperature != null) 'TEMPERATURE': input.temperature,
        if (input.systolic != null) 'BLOOD_PRESSURE_SYSTOLIC': input.systolic,
        if (input.diastolic != null) 'BLOOD_PRESSURE_DIASTOLIC': input.diastolic,
        if (input.spo2 != null) 'SPO2': input.spo2,
        'IS_ACTIVE': 1,
        'IS_DELETE': 0,
      };
      final body = {
        'CommonParam': {'LanguageCode': 'VI', 'Start': 0, 'Limit': 1, 'HasException': false},
        'ApiData': sdo,
      };
      final encoded = base64.encode(utf8.encode(json.encode(body)));
      final resp = await _dio.post(
        '$_base/api/HisTracking/Update?param=$encoded',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      debugPrint('HisTracking/Update POST status: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final d = resp.data;
        if (d is Map && d['Success'] == true) {
          final data = d['Data'];
          int? id;
          if (data is List && data.isNotEmpty) {
            id = (data[0]['ID'] as num?)?.toInt();
          } else if (data is Map) {
            id = (data['ID'] as num?)?.toInt();
          }
          debugPrint('✅ HisTracking created: ID=$id');
          return TrackingResult(success: true, id: id);
        }
        return TrackingResult(success: false, error: d.toString());
      }
      return TrackingResult(success: false, error: 'HTTP ${resp.statusCode}: ${resp.data}');
    } catch (e) {
      debugPrint('HisTracking/Update error: $e');
      return TrackingResult(success: false, error: e.toString());
    }
  }
}
