// v3.0.84: YTeSoExtendedService - các API Y Tế Số bổ sung (ngoài xem bệnh án)
//
// Bao gồm 15+ endpoints đã khám phá từ log:
//   - Bệnh nhân: danh-sach-khoa-quan-ly, buong-benh, benh-nhan-buong-benh, info
//   - Y lệnh: y-lenh-can-lam-sang
//   - Điều dưỡng: dieu-duong/danh-sach-dieu-duong
//   - Vấn đề: van-de-chuyen-mon, van-de-luu-y
//   - Báo cáo: phieu-ban-giao, tai-lieu-bn, thiet-bi-y-te
//   - User: users/profile, users/server-time
//   - Work: chi-dinh/common/workInfo, dich-vu-ket-qua, medical-instruction
//   - Notifications: notification-status, update-device

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';

class YTeSoExtendedService {
  static final YTeSoExtendedService instance = YTeSoExtendedService._();

  YTeSoExtendedService._();

  /// v3.0.84: Helper - gọi POST/GET với auto-login
  Future<YTeSoApiResult> _call({
    required String method, // 'GET' | 'POST'
    required String path,
    Map<String, String>? queryParameters,
    dynamic body,
    Map<String, String>? extraHeaders,
  }) async {
    final svc = YTeSoService.instance;
    if (!svc.isLoggedIn) {
      final r = await svc.login();
      if (!r.success) {
        return YTeSoApiResult(
            success: false, message: 'Chưa đăng nhập Y Tế Số: ${r.message}');
      }
    }
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ));
      // Build common headers (giống YTeSoService._buildHeaders)
      final now = DateTime.now();
      final isoTime = now.toIso8601String();
      final dateStr =
          '${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")} '
          '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}'
              '.${now.microsecond.toString().padLeft(6, "0")}';
      final hdrs = <String, String>{
        'Authorization': 'Bearer ${svc.accessToken}',
        'user-id': YTeSoService.defaultUserId,
        'user-name': Uri.encodeComponent(YTeSoService.defaultUserName),
        'content-type': 'application/json; charset=utf-8',
        'Start-Time': isoTime,
        'date': dateStr,
        // v3.0.85: auto pass treatment-id từ query/body nếu có
        if (queryParameters?['TREATMENT_ID'] != null)
          'treatment-id': queryParameters!['TREATMENT_ID'].toString(),
        if (queryParameters?['TreatmentId'] != null)
          'treatment-id': queryParameters!['TreatmentId'].toString(),
        if (body is Map && body['TREATMENT_ID'] != null)
          'treatment-id': body['TREATMENT_ID'].toString(),
        if (body is Map && body['ID_DIEUTRI'] != null)
          'treatment-id': body['ID_DIEUTRI'].toString(),
        // room/department defaults
        'room-id': YTeSoService.defaultRoomId,
        'room-code': YTeSoService.defaultRoomCode,
        'department-id': YTeSoService.defaultDepartmentId,
        'department-code': YTeSoService.defaultDepartmentCode,
        ...?extraHeaders,
      };
      final url = '${svc.baseUrl}$path';
      Response resp;
      if (method == 'GET') {
        resp = await dio.get(url,
            queryParameters: queryParameters,
            options: Options(headers: hdrs));
      } else {
        resp = await dio.post(url,
            data: body == null ? null : jsonEncode(body),
            queryParameters: queryParameters,
            options: Options(headers: hdrs));
      }
      return YTeSoApiResult(
          success: true, data: resp.data, statusCode: resp.statusCode);
    } on DioException catch (e) {
      String msg;
      if (e.response?.statusCode == 401) {
        await svc.logout();
        final r = await svc.login();
        if (r.success) {
          return _call(
              method: method,
              path: path,
              queryParameters: queryParameters,
              body: body,
              extraHeaders: extraHeaders);
        }
        msg = 'Token hết hạn';
      } else {
        msg = 'Lỗi ${e.response?.statusCode}: ${e.message}';
      }
      return YTeSoApiResult(success: false, message: msg);
    } catch (e) {
      return YTeSoApiResult(success: false, message: 'Lỗi: $e');
    }
  }

  // ============ BỆNH NHÂN ============
  /// POST /v1/patient/danh-sach-khoa-quan-ly {USERNAME}
  /// Server yêu cầu USERNAME (KHÔNG phải DEPARTMENT_ID)
  Future<YTeSoApiResult> danhSachKhoaQuanLy(String username) {
    return _call(
        method: 'POST',
        path: '/v1/patient/danh-sach-khoa-quan-ly',
        body: {'USERNAME': username});
  }

  /// POST /v1/patient/buong-benh {USERNAME, DEPARTMENT_ID}
  /// Server yêu cầu cả USERNAME + DEPARTMENT_ID (string)
  Future<YTeSoApiResult> buongBenh(String username, String departmentId) {
    return _call(
        method: 'POST',
        path: '/v1/patient/buong-benh',
        body: {'USERNAME': username, 'DEPARTMENT_ID': departmentId});
  }

  /// POST /v1/patient/benh-nhan-buong-benh
  /// Body: {USERNAME, BED_ROOM_IDs, TREATMENT_IDs}
  Future<YTeSoApiResult> benhNhanBuongBenh({
    required String username,
    required List<int> bedRoomIds,
    List<int>? treatmentIds,
  }) {
    return _call(
        method: 'POST',
        path: '/v1/patient/benh-nhan-buong-benh',
        body: {
          'USERNAME': username,
          'BED_ROOM_IDs': bedRoomIds,
          if (treatmentIds != null) 'TREATMENT_IDs': treatmentIds,
        });
  }

  /// POST /v1/patient/benh-nhan-buong-benh-is-show
  /// Server yêu cầu TREATMENT_IDs (không được empty)
  Future<YTeSoApiResult> benhNhanBuongBenhIsShow({
    required String username,
    required List<int> bedRoomIds,
    List<int>? treatmentIds,
  }) {
    return _call(
        method: 'POST',
        path: '/v1/patient/benh-nhan-buong-benh-is-show',
        body: {
          'USERNAME': username,
          'BED_ROOM_IDs': bedRoomIds,
          if (treatmentIds != null) 'TREATMENT_IDs': treatmentIds,
        });
  }

  /// POST /v1/patient/info {MADT}
  /// Server yêu cầu MADT (KHÔNG phải USERNAME)
  Future<YTeSoApiResult> patientInfo(String maDt) {
    return _call(
        method: 'POST', path: '/v1/patient/info', body: {'MADT': maDt});
  }

  // ============ Y LỆNH ============
  /// GET /v1/y-lenh-can-lam-sang?TREATMENT_ID=...&STT_ID=...&TREATMENT_CODE=...
  Future<YTeSoApiResult> yLenhCanLamSang({
    required int treatmentId,
    required int sttId,
    required String treatmentCode,
  }) {
    return _call(
        method: 'GET',
        path: '/v1/y-lenh-can-lam-sang',
        queryParameters: {
          'TREATMENT_ID': treatmentId.toString(),
          'STT_ID': sttId.toString(),
          'TREATMENT_CODE': treatmentCode,
        });
  }

  /// GET /v1/y-lenh-can-lam-sang/{serviceReqId}
  Future<YTeSoApiResult> yLenhCanLamSangDetail(int serviceReqId) {
    return _call(method: 'GET', path: '/v1/y-lenh-can-lam-sang/$serviceReqId');
  }

  /// POST /v1/y-lenh-can-lam-sang/check-download
  Future<YTeSoApiResult> yLenhCheckDownload({
    required String treatmentCode,
    required String serviceReqCode,
  }) {
    return _call(
        method: 'POST',
        path: '/v1/y-lenh-can-lam-sang/check-download',
        body: {
          'TREATMENT_CODE': treatmentCode,
          'SERVICE_REQ_CODE': serviceReqCode,
          'ROOM_CODE': '',
          'DEPARTMENT_CODE': '',
        });
  }

  /// GET /v1/y-lenh-can-lam-sang/danh-sach-nhom-dich-vu-cls
  Future<YTeSoApiResult> yLenhNhomDichVuCls() {
    return _call(
        method: 'GET', path: '/v1/y-lenh-can-lam-sang/danh-sach-nhom-dich-vu-cls');
  }

  // ============ ĐIỀU DƯỠNG ============
  /// POST /v1/dieu-duong/danh-sach-dieu-duong
  /// v3.0.87: Body lowercase theo test curl thực tế (server validation)
  /// Note: API này trả về danh sách điều dưỡng (assignable), KHÔNG phải phiếu chăm sóc cho BN
  /// → Dùng để show "Danh sách điều dưỡng có thể phân công" thay vì "Phiếu chăm sóc"
  Future<YTeSoApiResult> danhSachDieuDuong({
    required String reportTypeCode,
    required String reportTemplateCode,
    required String idDieuTri,
    required String ngayYlenh,
    required String departmentId,
    required String departmentCode,
    String? departmentName,
    String? bedRoomCode,
    String? bedRoomName,
  }) {
    return _call(
        method: 'POST',
        path: '/v1/dieu-duong/danh-sach-dieu-duong',
        body: {
          'reportTypeCode': reportTypeCode,
          'reportTemplateCode': reportTemplateCode,
          'idDieuTri': idDieuTri,
          'ngayYlenh': ngayYlenh,
          'departmentId': departmentId,
          'departmentCode': departmentCode,
          if (departmentName != null) 'departmentName': departmentName,
          if (bedRoomCode != null) 'bedRoomCode': bedRoomCode,
          if (bedRoomName != null) 'bedRoomName': bedRoomName,
        });
  }

  // ============ VẤN ĐỀ ============
  /// GET /v1/van-de-chuyen-mon?TreatmentId=...&TuNgay=...&DenNgay=...&IS_DONE=...
  Future<YTeSoApiResult> vanDeChuyenMon({
    required int treatmentId,
    String? tuNgay,
    String? denNgay,
    String? isDone,
  }) {
    return _call(
        method: 'GET',
        path: '/v1/van-de-chuyen-mon',
        queryParameters: {
          'TreatmentId': treatmentId.toString(),
          if (tuNgay != null) 'TuNgay': tuNgay,
          if (denNgay != null) 'DenNgay': denNgay,
          if (isDone != null) 'IS_DONE': isDone,
        });
  }

  /// GET /v1/van-de-luu-y
  Future<YTeSoApiResult> vanDeLuuY({
    required int treatmentId,
    String? tuNgay,
    String? denNgay,
    String? isDone,
  }) {
    return _call(
        method: 'GET',
        path: '/v1/van-de-luu-y',
        queryParameters: {
          'TreatmentId': treatmentId.toString(),
          if (tuNgay != null) 'TuNgay': tuNgay,
          if (denNgay != null) 'DenNgay': denNgay,
          if (isDone != null) 'IS_DONE': isDone,
        });
  }

  // ============ BÁO CÁO ============
  /// GET /v1/phieu-ban-giao/danh-sach-phieu
  Future<YTeSoApiResult> phieuBanGiao({
    required String startDate,
    required String endDate,
    required String maDt,
    int type = 0,
    String? dieuDuongThucHienId,
    String? caThucHien,
    String? departmentCode,
  }) {
    return _call(
        method: 'GET',
        path: '/v1/phieu-ban-giao/danh-sach-phieu',
        queryParameters: {
          'StartDate': startDate,
          'EndDate': endDate,
          'MADT': maDt,
          'Type': type.toString(),
          if (dieuDuongThucHienId != null) 'DieuDuongThucHienId': dieuDuongThucHienId,
          if (caThucHien != null) 'CaThucHien': caThucHien,
          if (departmentCode != null) 'DepartmentCode': departmentCode,
        });
  }

  /// GET /v1/tai-lieu-bn/danh-sach-tai-lieu
  Future<YTeSoApiResult> taiLieuBn({
    required String maDt,
    int page = 1,
    int limit = 16,
  }) {
    return _call(
        method: 'GET',
        path: '/v1/tai-lieu-bn/danh-sach-tai-lieu',
        queryParameters: {
          'page': page.toString(),
          'limit': limit.toString(),
          'MADT': maDt,
        });
  }

  /// GET /v1/thiet-bi-y-te/count-thiet-bi-bn/{treatmentId}
  Future<YTeSoApiResult> countThietBi(int treatmentId) {
    return _call(
        method: 'GET', path: '/v1/thiet-bi-y-te/count-thiet-bi-bn/$treatmentId');
  }

  // ============ USER ============
  /// GET /v1/users/profile
  Future<YTeSoApiResult> userProfile() {
    return _call(method: 'GET', path: '/v1/users/profile');
  }

  /// GET /v1/users/server-time
  Future<YTeSoApiResult> serverTime() {
    return _call(method: 'GET', path: '/v1/users/server-time');
  }

  // ============ WORK ============
  /// GET /v1/chi-dinh/common/workInfo/{roomId}
  Future<YTeSoApiResult> workInfo(int roomId) {
    return _call(method: 'GET', path: '/v1/chi-dinh/common/workInfo/$roomId');
  }

  /// GET /v1/dich-vu-ket-qua
  Future<YTeSoApiResult> dichVuKetQua() {
    return _call(method: 'GET', path: '/v1/dich-vu-ket-qua');
  }

  /// GET /v1/medical-instruction
  Future<YTeSoApiResult> medicalInstruction() {
    return _call(method: 'GET', path: '/v1/medical-instruction');
  }
}

class YTeSoApiResult {
  final bool success;
  final String? message;
  final dynamic data;
  final int? statusCode;
  YTeSoApiResult({
    required this.success,
    this.message,
    this.data,
    this.statusCode,
  });
}
