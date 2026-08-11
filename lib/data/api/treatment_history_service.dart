// v3.0.79: TreatmentHistoryService — Lịch sử điều trị từ HIS Pro (port 1408)
// v3.0.79: Trả về TreatmentHistoryResult { data, errorCode, errorMessage } thay vì List
//   để caller biết 401 (token hết hạn) / timeout / 0 data để hiển thị UI chính xác.
//
// API flow đã verify qua log HIS.exe ngày 10/08/2026 08:32-08:35 + 10:22-10:24:
//   1. List các lần khám:    GET /api/HisTreatment/GetLView          filter: {PATIENT_CODE__EXACT, ORDER_FIELD: MODIFY_TIME, DESC, Limit: 50}
//   2. Khoa điều trị:        GET /api/HisDepartmentTran/GetView     filter: {TREATMENT_ID, ORDER_FIELD: DEPARTMENT_IN_TIME, ASC}
//   3. Y lệnh theo treatment: GET /api/HisServiceReq/Get            filter: {TREATMENT_ID}
//   4. Dịch vụ + thuốc:      GET /api/HisSereServ/GetDHisSereServ2  filter: {TREATMENT_ID, INTRUCTION_DATE}
//   5. Sample times:         GET /api/HisServiceReq/GetDynamic      filter: {IDs, ColumnParams: [ID, SAMPLE_TIME, RECEIVE_SAMPLE_TIME]}
//
// v3.0.79: Đổi port 1429 → 1408 (1429 trả 404, 1408 trả 200 - verify ngày 10/08/2026 10:52)

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/his_proxy_token_service.dart';

/// Mã lỗi cố định để UI biết phản ứng
class THistoryErr {
  static const none = '';
  static const noToken = 'NO_TOKEN';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const timeout = 'TIMEOUT';
  static const noConnection = 'NO_CONNECTION';
  static const httpError = 'HTTP_ERROR';
  static const unknown = 'UNKNOWN';
}

class TreatmentHistoryResult {
  final List<Map<String, dynamic>> data;
  final String errorCode;
  final String errorMessage;
  final int? httpStatus;

  const TreatmentHistoryResult({
    required this.data,
    this.errorCode = THistoryErr.none,
    this.errorMessage = '',
    this.httpStatus,
  });

  bool get isEmpty => data.isEmpty;
  bool get isOk => errorCode == THistoryErr.none;
  bool get isAuthError => errorCode == THistoryErr.tokenExpired || errorCode == THistoryErr.noToken;
}

class TreatmentHistoryService {
  static final TreatmentHistoryService instance = TreatmentHistoryService._();
  TreatmentHistoryService._();

  ThongkeAuthService get _thongke => ThongkeAuthService.instance;

  /// v3.0.79: Dùng hisProBaseUrl (port 1408) thay vì mosUrl (port 1429)
  /// vì GetLView chỉ có ở port 1408 (verify bằng test 1429→404, 1408→200).
  String get _baseUrl => ThongkeAuthService.hisProBaseUrl;

  /// v3.0.79: Chuẩn hóa mã BN thành 10 chữ số (string với leading zeros)
  /// vì HIS Pro filter `PATIENT_CODE__EXACT` yêu cầu đúng format
  /// (vd: "0000475806", không phải "475806").
  String _normalizePatientCode(String code) {
    final digits = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return digits.padLeft(10, '0');
  }

  Dio _buildDio() {
    final token = _thongke.hisProToken ?? '';
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Authorization': 'Bearer $token',
        '___ipAddress': '127.0.0.1',
        'Accept': 'application/json',
      },
    ));
  }

  Map<String, dynamic> _commonParam({int start = 0, int limit = 50}) => {
        'Messages': [],
        'BugCodes': [],
        'MessageCodes': [],
        'Start': start,
        'Limit': limit,
        'LanguageCode': 'VI',
        'Now': 0,
        'HasException': false,
      };

  /// Parse response từ HIS Pro (extract list từ Data field)
  TreatmentHistoryResult _parseResponse(
    Response<dynamic> r,
    String endpoint,
    Map<String, dynamic> apiData,
  ) {
    final data = r.data;
    if (data is Map && data['Success'] == true) {
      final list = data['Data'];
      if (list is List) {
        return TreatmentHistoryResult(
          data: list.cast<Map<String, dynamic>>(),
        );
      }
      return const TreatmentHistoryResult(data: []);
    }
    return const TreatmentHistoryResult(data: []);
  }

  Future<TreatmentHistoryResult> _get(
    String endpoint,
    Map<String, dynamic> apiData,
  ) async {
    if (!(_thongke.hasHisProToken)) {
      await _thongke.loadHisProToken();
    }
    if (!(_thongke.hasHisProToken)) {
      return const TreatmentHistoryResult(
        data: [],
        errorCode: THistoryErr.noToken,
        errorMessage: 'Chưa có HIS Pro token. Vào Cài đặt → EMR Sync để nhập token.',
      );
    }
    try {
      final paramData = {'CommonParam': _commonParam(), 'ApiData': apiData};
      final param = base64Encode(utf8.encode(jsonEncode(paramData)));
      final dio = _buildDio();
      final r = await dio.get(
        '$_baseUrl$endpoint',
        queryParameters: {'param': param},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (r.statusCode == 401) {
        // v3.0.82: Auto-fetch token mới qua local proxy (nếu bật autoFetch)
        final autoFetch = await HisProxyTokenService.instance.autoFetchEnabled;
        if (autoFetch) {
          debugPrint('🔄 401 detected, trying auto-fetch token from proxy...');
          final newToken = await HisProxyTokenService.instance.fetchAndSaveToken();
          if (newToken != null) {
            // Retry 1 lần với token mới
            final dio2 = _buildDio();
            final r2 = await dio2.get(
              '$_baseUrl$endpoint',
              queryParameters: {'param': param},
              options: Options(validateStatus: (s) => s != null && s < 500),
            );
            if (r2.statusCode == 200) {
              debugPrint('✅ Auto-fetched token works!');
              return _parseResponse(r2, endpoint, apiData);
            }
            debugPrint('❌ Auto-fetched token still returns ${r2.statusCode}');
          } else {
            debugPrint('❌ Auto-fetch failed (proxy not reachable?)');
          }
        }
        return const TreatmentHistoryResult(
          data: [],
          errorCode: THistoryErr.tokenExpired,
          errorMessage: 'Token hết hạn. Vào Cài đặt → EMR Sync để cập nhật token mới.',
          httpStatus: 401,
        );
      }
      if (r.statusCode != 200) {
        return TreatmentHistoryResult(
          data: [],
          errorCode: THistoryErr.httpError,
          errorMessage: 'API trả về HTTP ${r.statusCode}',
          httpStatus: r.statusCode,
        );
      }
      return _parseResponse(r, endpoint, apiData);
    } on DioException catch (e) {
      debugPrint('❌ $endpoint DioException: ${e.message}');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return const TreatmentHistoryResult(
          data: [],
          errorCode: THistoryErr.timeout,
          errorMessage: 'Quá thời gian chờ. Kiểm tra mạng/VPN.',
        );
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return const TreatmentHistoryResult(
          data: [],
          errorCode: THistoryErr.noConnection,
          errorMessage: 'Không kết nối được HIS Pro (kiểm tra VPN).',
        );
      }
      if (e.response?.statusCode == 401) {
        return const TreatmentHistoryResult(
          data: [],
          errorCode: THistoryErr.tokenExpired,
          errorMessage: 'Token hết hạn. Vào Cài đặt → EMR Sync để cập nhật.',
          httpStatus: 401,
        );
      }
      return TreatmentHistoryResult(
        data: [],
        errorCode: THistoryErr.unknown,
        errorMessage: 'Lỗi: ${e.message}',
      );
    } catch (e) {
      debugPrint('❌ $endpoint error: $e');
      return TreatmentHistoryResult(
        data: [],
        errorCode: THistoryErr.unknown,
        errorMessage: 'Lỗi: $e',
      );
    }
  }

  /// 1. Lấy danh sách TẤT CẢ các lần điều trị của 1 bệnh nhân
  /// - patientCode: mã BN (vd: "0000003080")
  /// - limit: số lượng tối đa (mặc định 50, sắp xếp MODIFY_TIME DESC)
  /// - Returns: TreatmentHistoryResult.data là List<Map> với TREATMENT_ID, TREATMENT_CODE,
  ///   IN_TIME, OUT_TIME, ICD_CODE, ICD_NAME, TDL_PATIENT_NAME, TREATMENT_DAY_COUNT, ...
  /// - errorCode: THistoryErr.* (noToken/tokenExpired/timeout/noConnection/httpError/none)
  Future<TreatmentHistoryResult> getTreatmentHistory(
    String patientCode, {
    int limit = 50,
  }) async {
    final normalized = _normalizePatientCode(patientCode);
    if (normalized.isEmpty) {
      return const TreatmentHistoryResult(
        data: [],
        errorCode: THistoryErr.unknown,
        errorMessage: 'Mã BN rỗng hoặc không hợp lệ',
      );
    }
    if (!(_thongke.hasHisProToken)) {
      await _thongke.loadHisProToken();
    }
    if (!(_thongke.hasHisProToken)) {
      return const TreatmentHistoryResult(
        data: [],
        errorCode: THistoryErr.noToken,
        errorMessage: 'Chưa có HIS Pro token. Vào Cài đặt → EMR Sync → paste token (lấy từ log HIS.exe: ___dti:"...|<TOKEN>|...").',
      );
    }

    debugPrint('🔍 getTreatmentHistory: code=$normalized, baseUrl=$_baseUrl, tokenLen=${_thongke.hisProToken?.length ?? 0}');

    // Thử PATIENT_CODE__EXACT trước (đúng format HIS Desktop dùng)
    var result = await _get('/api/HisTreatment/GetLView', {
      'ORDER_FIELD': 'MODIFY_TIME',
      'ORDER_DIRECTION': 'DESC',
      'PATIENT_CODE__EXACT': normalized,
    });
    if (result.isAuthError) {
      // Token hết hạn → trả luôn, không thử tiếp
      return result;
    }
    if (result.isOk && result.data.isEmpty) {
      // Fallback: thử với TDL_PATIENT_CODE__EXACT (HIS Pro cũ)
      debugPrint('ℹ PATIENT_CODE__EXACT rỗng, thử TDL_PATIENT_CODE__EXACT...');
      result = await _get('/api/HisTreatment/GetLView', {
        'ORDER_FIELD': 'MODIFY_TIME',
        'ORDER_DIRECTION': 'DESC',
        'TDL_PATIENT_CODE__EXACT': normalized,
      });
    }
    return result;
  }

  /// 2. Lấy danh sách khoa điều trị của 1 lần khám
  Future<TreatmentHistoryResult> getDepartmentTrans(int treatmentId) async {
    return _get('/api/HisDepartmentTran/GetView', {
      'TREATMENT_ID': treatmentId,
      'IS_INCLUDE_DELETED': false,
      'ORDER_FIELD': 'DEPARTMENT_IN_TIME',
      'ORDER_DIRECTION': 'ASC',
      'DATA_DOMAIN_FILTER': false,
    });
  }

  /// 3. Lấy y lệnh (service requests) theo treatment
  Future<TreatmentHistoryResult> getServiceReqs(int treatmentId) async {
    return _get('/api/HisServiceReq/Get', {
      'TREATMENT_ID': treatmentId,
      'IS_INCLUDE_DELETED': false,
      'DATA_DOMAIN_FILTER': false,
    });
  }

  /// 4. Lấy tất cả dịch vụ + thuốc đã dùng theo treatment + ngày chỉ định
  Future<TreatmentHistoryResult> getSereServs(
    int treatmentId, {
    int intructionDate = 0,
  }) async {
    final apiData = <String, dynamic>{
      'TREATMENT_ID': treatmentId,
    };
    if (intructionDate > 0) {
      apiData['INTRUCTION_DATE'] = intructionDate;
    }
    return _get('/api/HisSereServ/GetDHisSereServ2', apiData);
  }

  /// 5. Lấy SAMPLE_TIME, RECEIVE_SAMPLE_TIME cho danh sách service req IDs
  Future<TreatmentHistoryResult> getServiceReqDynamic(List<int> ids) async {
    if (ids.isEmpty) return const TreatmentHistoryResult(data: []);
    return _get('/api/HisServiceReq/GetDynamic', {
      'IS_INCLUDE_DELETED': false,
      'DATA_DOMAIN_FILTER': false,
      'IDs': ids,
      'ColumnParams': ['ID', 'SAMPLE_TIME', 'RECEIVE_SAMPLE_TIME'],
    });
  }
}
