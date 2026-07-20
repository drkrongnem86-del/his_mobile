// EmrPushService v3.0.42 - LẤY HẾT từ app Y tế số thật v0.3.3
// Flow theo EmrScanApp:
//   1. HIS Pro dùng TokenCode headers (NOT Bearer!):
//      TokenCode: <64-char hex>, ApplicationCode: HIS, ClientIpAddress: <IP máy BV>
//   2. FSS Upload (port 1405) -> POST /api/File/Upload voi imageFile -> tra ve URL
//   3. EMR Create (port 1417) -> POST /api/EmrDocument/CreateByTdo voi body day du
//      v3.0.6: HOẶC CreateAndSignUsb (workflow A có ký PFX) / CreateAndSignHsm
//
// v2.62.0: DocumentTypeId/DocumentGroupId mapping - 37 loại phiếu THẬT từ HIS Pro EMR
// (lấy từ log app Y tế số tại BV Ninh Thuận, ngày 2026-07-09, PLogger Body response)
// DocumentGroupId = null theo body log (HIS Pro không dùng groupId cho EMR Document)
//
// Auth v3.0.42: TokenCode headers thay vì Bearer
// SDO fields: full theo log thật từ HIS desktop (signs, workingDept, mediOrgCode...)
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as pathJoin;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/core/services/his_config_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/api/kcb_emr_push_service.dart';
import 'package:his_mobile/data/services/emr_push_api_source.dart';
import 'package:his_mobile/data/services/mock_emr_server.dart';
import 'package:his_mobile/data/services/upload_log_service.dart';

/// v2.62.0: 37 loại phiếu THẬT từ HIS Pro EMR (ID + Code + Name)
/// Mỗi entry có ID (int) = DocumentTypeId, CODE (string), NAME (tiếng Việt)
class EmrDocTypeInfo {
  final int id;
  final String code;
  final String name;
  final int numOrder;

  const EmrDocTypeInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.numOrder,
  });

  factory EmrDocTypeInfo.fromJson(Map<String, dynamic> json) {
    return EmrDocTypeInfo(
      id: (json['ID'] as num?)?.toInt() ?? 0,
      code: (json['DOCUMENT_TYPE_CODE'] ?? '').toString(),
      name: (json['DOCUMENT_TYPE_NAME'] ?? '').toString(),
      numOrder: (json['NUM_ORDER'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'ID': id,
        'DOCUMENT_TYPE_CODE': code,
        'DOCUMENT_TYPE_NAME': name,
        'NUM_ORDER': numOrder,
      };
}

/// v2.62.0: Enum với ID thật (KHÔNG dùng docGroupId vì HIS Pro log trả null)
enum EmrDocumentKind {
  voBenhAnHanhChinh('Vỏ bệnh án hành chính', 1, '01'),
  phieuKhamVaoVien('Phiếu khám vào viện', 2, '02'),
  chungNhanPTTT('Chứng nhận PTTT', 4, '04'),
  soKet15NgayDT('Sơ kết 15 ngày điều trị', 5, '05'),
  toDieuTri('Tờ điều trị', 7, '07'),
  phieuChamSoc('Phiếu chăm sóc', 8, '08'),
  phieuTruyenDich('Phiếu truyền dịch', 9, '09'),
  phieuTheoDoi('Phiếu theo dõi', 10, '10'),
  phieuPhanUngThuoc('Phiếu phản ứng thuốc', 11, '11'),
  bienBanHoiChan('Biên bản hội chẩn', 17, '17'),
  phieuChiDinh('Phiếu chỉ định', 21, '21'),
  phieuKetQua('Phiếu kết quả', 22, '22'),
  voBenhAnHoiBenh('Vỏ bệnh án hỏi bệnh', 101, '30'),
  bangKiemCBGiaoTruocPTTT('Bảng kiểm chuẩn bị bàn giao trước PTTT', 105, '61'),
  phieuDanhGiaBenhNhiNhapVien('Phiếu đánh giá bệnh nhi nhập viện', 107, '59'),
  bangKiemCBGiaoSauPTTT('Bảng kiểm chuẩn bị bàn giao sau PTTT', 108, '58'),
  phieuLocMauCapCuu('Phiếu lọc máu cấp cứu', 109, '56'),
  bangKiemTruocMo('Bảng kiểm trước mổ', 111, '54'),
  phieuSoSinh('Phiếu sơ sinh', 112, '52'),
  phieuTDChiSoSinhTon('Phiếu theo dõi chỉ số sinh tồn', 114, '51'),
  phieuKhamGayMeTruocMo('Phiếu khám gây mê trước mổ', 115, '34'),
  soKetBenhAnDuyetMo('Sơ kết bệnh án duyệt mổ', 116, '36'),
  bangKiemAnToanPhauThuat('Bảng kiểm an toàn phẫu thuật', 117, '35'),
  phieuGayMeHoiSuc('Phiếu gây mê hồi sức', 118, '40'),
  phieuDanhGiaDinhDuong('Phiếu đánh giá dinh dưỡng', 119, '38'),
  phieuCBBNBTruocPhauThuat('Phiếu chuẩn bị người bệnh trước phẫu thuật', 120, '37'),
  phieuKiemSoatGacTrongCaMo('Phiếu kiểm soát gạc trong ca mổ', 121, '39'),
  phieuSangLocDanhGiaDD('Phiếu sàng lọc đánh giá dinh dưỡng', 122, '48'),
  giayCamDoanChapNhanPTTT('Giấy cam đoan chấp nhận PTTT', 123, '32'),
  bangKeVTTieuHaoTrongMo('Bảng kê vật tư tiêu hao trong mổ', 140, '64'),
  ketQuaGhiDienTimCC('Kết quả ghi điện tim cấp cứu tại giường', 160, '65'),
  phieuTDVaCSBNICU('Phiếu theo dõi và chăm sóc bệnh nhân ICU', 220, '80'),
  trichBienBanHoiChan('Trích biên bản hội chẩn', 340, '86'),
  phieuTDVaCS('Phiếu theo dõi và chăm sóc', 400, '45'),
  khamSucKhoeTren18('Khám sức khỏe trên 18', 420, 'KST18'),
  khamSucKhoeDuoi18('Khám sức khỏe dưới 18', 421, 'KSD18'),
  khamSucKhoeLaiXe('Khám sức khỏe lái xe', 422, 'LX'),
  phieuKhac('Phiếu khác', 20, 'OT');  // v2.63.0: từ log PLogger EMR_DOCUMENT_TYPE=20 (app Y tế số)

  final String label;
  final int docTypeId;
  final String docTypeCode;
  const EmrDocumentKind(this.label, this.docTypeId, this.docTypeCode);

  static EmrDocumentKind? fromDocTypeId(int id) {
    for (final k in EmrDocumentKind.values) {
      if (k.docTypeId == id) return k;
    }
    return null;
  }

  /// Auto-detect kind từ label phiếu (search keyword trong label)
  /// Trả về kind match đầu tiên, hoặc null nếu không match
  static EmrDocumentKind? fromString(String s) {
    final k = s.toLowerCase().trim();
    if (k.isEmpty) return null;
    // Phiếu khám
    if (k.contains('khám') && k.contains('vào')) return EmrDocumentKind.phieuKhamVaoVien;
    if (k.contains('khám') && (k.contains('gây mê') || k.contains('gây me'))) return EmrDocumentKind.phieuKhamGayMeTruocMo;
    if (k.contains('khám') && k.contains('trên 18')) return EmrDocumentKind.khamSucKhoeTren18;
    if (k.contains('khám') && k.contains('dưới 18')) return EmrDocumentKind.khamSucKhoeDuoi18;
    if (k.contains('khám') && k.contains('lái xe')) return EmrDocumentKind.khamSucKhoeLaiXe;
    if (k.contains('khám')) return EmrDocumentKind.phieuKhamVaoVien;
    // Phiếu theo dõi (4 biến thể)
    if (k.contains('icu')) return EmrDocumentKind.phieuTDVaCSBNICU;
    if (k.contains('sinh tồn') || k.contains('sinh ton')) return EmrDocumentKind.phieuTDChiSoSinhTon;
    if (k.contains('theo dõi và chăm sóc') || k.contains('theo doi va cham soc')) return EmrDocumentKind.phieuTDVaCS;
    if (k.contains('theo dõi') || k.contains('theo doi')) return EmrDocumentKind.phieuTheoDoi;
    // Chăm sóc
    if (k.contains('chăm sóc') || k.contains('cham soc')) return EmrDocumentKind.phieuChamSoc;
    // Truyền dịch
    if (k.contains('truyền dịch') || k.contains('truyen dich')) return EmrDocumentKind.phieuTruyenDich;
    // v3.0.35: Bàn giao bệnh nhân / Bàn giao ca → Phiếu khác (ID 20)
    // Trước đây match nhầm vào bangKiemCBGiaoTruocPTTT (ID 105) - SAI
    // vì HIS Pro không có loại "bàn giao" chung, chỉ có bảng kiểm PTTT
    if (k.contains('bàn giao ca') || k.contains('ban giao ca') ||
        k.contains('bàn giao bệnh nhân') || k.contains('ban giao benh nhan')) {
      return EmrDocumentKind.phieuKhac;
    }
    // Bàn giao (bảng kiểm PTTT - 2 biến thể)
    if (k.contains('bàn giao') && k.contains('trước')) return EmrDocumentKind.bangKiemCBGiaoTruocPTTT;
    if (k.contains('bàn giao') && k.contains('sau')) return EmrDocumentKind.bangKiemCBGiaoSauPTTT;
    if (k.contains('bàn giao') || k.contains('ban giao')) return EmrDocumentKind.phieuKhac; // v3.0.35: fallback "bàn giao" khác → Phiếu khác
    // PTTT
    if (k.contains('chứng nhận pttt') || k.contains('chung nhan pttt')) return EmrDocumentKind.chungNhanPTTT;
    if (k.contains('cam đoan') && k.contains('pttt')) return EmrDocumentKind.giayCamDoanChapNhanPTTT;
    if (k.contains('gây mê hồi sức') || k.contains('gây mê hoi suc')) return EmrDocumentKind.phieuGayMeHoiSuc;
    if (k.contains('gây mê') && k.contains('trước mổ')) return EmrDocumentKind.phieuKhamGayMeTruocMo;
    if (k.contains('gây mê')) return EmrDocumentKind.phieuGayMeHoiSuc;
    if (k.contains('bàn giao trước')) return EmrDocumentKind.bangKiemCBGiaoTruocPTTT;
    if (k.contains('bàn giao sau')) return EmrDocumentKind.bangKiemCBGiaoSauPTTT;
    if (k.contains('chuẩn bị người bệnh') && k.contains('phẫu thuật')) return EmrDocumentKind.phieuCBBNBTruocPhauThuat;
    if (k.contains('bảng kiểm an toàn') && k.contains('phẫu thuật')) return EmrDocumentKind.bangKiemAnToanPhauThuat;
    if (k.contains('bảng kiểm trước mổ') || k.contains('bang kiem truoc mo')) return EmrDocumentKind.bangKiemTruocMo;
    if (k.contains('bệnh nhi')) return EmrDocumentKind.phieuDanhGiaBenhNhiNhapVien;
    if (k.contains('sơ sinh') || k.contains('so sinh')) return EmrDocumentKind.phieuSoSinh;
    if (k.contains('kiểm soát gạc') || k.contains('kiem soat gac')) return EmrDocumentKind.phieuKiemSoatGacTrongCaMo;
    if (k.contains('duyệt mổ') || k.contains('duyet mo')) return EmrDocumentKind.soKetBenhAnDuyetMo;
    if (k.contains('vật tư tiêu hao') || k.contains('vat tu tieu hao')) return EmrDocumentKind.bangKeVTTieuHaoTrongMo;
    // CLS
    if (k.contains('chỉ định') || k.contains('chi dinh')) return EmrDocumentKind.phieuChiDinh;
    if (k.contains('kết quả') || k.contains('ket qua')) return EmrDocumentKind.phieuKetQua;
    // Thuốc
    if (k.contains('phản ứng thuốc') || k.contains('phan ung thuoc')) return EmrDocumentKind.phieuPhanUngThuoc;
    // Vỏ bệnh án
    if (k.contains('vỏ bệnh án') && k.contains('hỏi')) return EmrDocumentKind.voBenhAnHoiBenh;
    if (k.contains('vỏ bệnh án')) return EmrDocumentKind.voBenhAnHanhChinh;
    // Hội chẩn
    if (k.contains('trích biên bản') || k.contains('trich bien ban')) return EmrDocumentKind.trichBienBanHoiChan;
    if (k.contains('hội chẩn') || k.contains('hoi chan')) return EmrDocumentKind.bienBanHoiChan;
    // Điều trị
    if (k.contains('sơ kết') && k.contains('điều trị')) return EmrDocumentKind.soKet15NgayDT;
    if (k.contains('tờ điều trị') || k.contains('to dieu tri')) return EmrDocumentKind.toDieuTri;
    // Lọc máu / ECG / Dinh dưỡng
    if (k.contains('lọc máu') || k.contains('loc mau')) return EmrDocumentKind.phieuLocMauCapCuu;
    if (k.contains('điện tim') || k.contains('dien tim')) return EmrDocumentKind.ketQuaGhiDienTimCC;
    if (k.contains('sàng lọc dinh dưỡng') || k.contains('sang loc dinh duong')) return EmrDocumentKind.phieuSangLocDanhGiaDD;
    if (k.contains('dinh dưỡng') || k.contains('dinh duong')) return EmrDocumentKind.phieuDanhGiaDinhDuong;
    return null;
  }

  /// Default fallback khi không match.
  /// v3.0.35: Đổi từ phieuTDVaCS (ID 400) sang phieuKhac (ID 20) - vì ID 20
  /// là generic nhất, app thật BVBM cũng dùng cho mọi loại phiếu không phân loại được.
  static EmrDocumentKind get defaultKind => EmrDocumentKind.phieuKhac;
}

class EmrPushResult {
  final bool success;
  final String? documentCode;
  final int? documentId;
  final String? fssUrl;
  final String? error;
  final String? errorType;  // 'no_token' | 'network' | 'auth' | 'server' | 'pdf' | 'fss' | 'no_kind'

  EmrPushResult({
    required this.success,
    this.documentCode,
    this.documentId,
    this.fssUrl,
    this.error,
    this.errorType,
  });
}

class EmrPushService {
  static final EmrPushService instance = EmrPushService._();
  EmrPushService._();

  // v2.45.0: Configurable EMR server URL (default BV Ninh Thuan, port 1417)
  String emrBaseUrl = 'http://172.16.9.6:1417';
  // v2.61.0: FSS (File Storage Service) - port 1405
  String fssBaseUrl = 'http://172.16.9.6:1405';
  String _kTokenKey = 'emr_bearer_token';
  String _kEmrBaseUrlKey = 'emr_base_url';
  String _kFssBaseUrlKey = 'fss_base_url';
  String _kDocTypesCacheKey = 'emr_doc_types_cache_v1';

  /// v2.62.0: Cache DocumentTypes (37 loại) - load từ API hoặc dùng default
  List<EmrDocTypeInfo>? _cachedDocTypes;

  /// v2.62.0: Lấy danh sách 37 loại phiếu (ưu tiên cache, fallback về hardcoded 37 enum)
  Future<List<EmrDocTypeInfo>> getDocumentTypes({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedDocTypes != null) return _cachedDocTypes!;
    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final cached = prefs.getString(_kDocTypesCacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final List data = jsonDecode(cached) as List;
          _cachedDocTypes = data.map((e) => EmrDocTypeInfo.fromJson(e as Map<String, dynamic>)).toList();
          return _cachedDocTypes!;
        } catch (_) {}
      }
    }
    // Thử load từ API (EmrDocument/GetView - endpoint trả list types)
    try {
      final api = HisProApiService.instance;
      if (api.isLoggedIn) {
        await api.refreshTokenIfNeeded();
        final url = '${api.getEmrBaseUrlSync()}/api/DocumentType/Get';
        debugPrint('Fetching DocumentTypes từ $url');
        final r = await api.post(url, {'IsActive': 1}, limit: 10);
        if (r.success && r.data is Map) {
          final root = r.data as Map;
          if (root['Success'] == true && root['Data'] is List) {
            final list = (root['Data'] as List)
                .map((e) => EmrDocTypeInfo.fromJson(e as Map<String, dynamic>))
                .toList();
            _cachedDocTypes = list;
            await prefs.setString(_kDocTypesCacheKey,
                jsonEncode(list.map((e) => e.toJson()).toList()));
            return list;
          }
        }
      }
    } catch (e) {
      debugPrint('fetchDocumentTypes error: $e');
    }
    // Fallback: hardcoded 37 enum values
    _cachedDocTypes = EmrDocumentKind.values
        .map((k) => EmrDocTypeInfo(
              id: k.docTypeId,
              code: k.docTypeCode,
              name: k.label,
              numOrder: 0,
            ))
        .toList();
    return _cachedDocTypes!;
  }

  Future<void> setBearerToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token.trim());
  }

  Future<String?> getBearerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  Future<void> setEmrBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmrBaseUrlKey, url.trim());
    emrBaseUrl = url.trim();
  }

  Future<String> getEmrBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    emrBaseUrl = prefs.getString(_kEmrBaseUrlKey) ?? 'http://172.16.9.6:1417';
    return emrBaseUrl;
  }

  Future<void> setFssBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFssBaseUrlKey, url.trim());
    fssBaseUrl = url.trim();
  }

  Future<String> getFssBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    fssBaseUrl = prefs.getString(_kFssBaseUrlKey) ?? 'http://172.16.9.6:1405';
    return fssBaseUrl;
  }

  /// Test connection với token hiện tại
  /// v3.0.42: Dùng TokenCode headers thay vì Authorization: Bearer
  Future<EmrPushResult> testConnection() async {
    try {
      final headers = HisProApiService.instance.getEffectiveAuthHeaders();
      headers['Accept'] = 'application/json';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        headers: headers,
      ));
      final r = await dio.get('$emrBaseUrl/api/EmrDocumentGroup/Get');
      if (r.statusCode == 200) {
        return EmrPushResult(success: true);
      } else if (r.statusCode == 401) {
        return EmrPushResult(success: false, error: 'Token không hợp lệ (401)', errorType: 'auth');
      } else {
        return EmrPushResult(success: false, error: 'Server trả ${r.statusCode}', errorType: 'server');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        return EmrPushResult(success: false, error: 'Không kết nối được EMR server (cần WiFi BV)', errorType: 'network');
      }
      return EmrPushResult(success: false, error: e.message ?? 'Unknown error', errorType: 'network');
    } catch (e) {
      return EmrPushResult(success: false, error: e.toString(), errorType: 'unknown');
    }
  }

  /// v2.45.0: Convert image (jpg/png) to PDF bytes
  Future<Uint8List?> imageToPdfBytes(File imageFile, {String? documentName}) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final image = pw.MemoryImage(imageBytes);
      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (documentName != null) ...[
                  pw.Text(documentName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 12),
                ],
                pw.Image(image, fit: pw.BoxFit.contain, width: 480),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Ngày tạo: ${DateTime.now().toIso8601String().substring(0, 19)}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                ),
              ],
            ),
          );
        },
      ));
      return pdf.save();
    } catch (e) {
      debugPrint('imageToPdfBytes error: $e');
      return null;
    }
  }

  /// v2.61.0: Upload file lên FSS (File Storage Service) trước khi tạo EMR Document
  /// Pattern từ EmrScanApp: POST /api/File/Upload với body {imageFile: <base64>}
  /// → trả về URL của file
  /// v3.0.42: Dùng TokenCode headers thay vì Authorization: Bearer
  Future<String?> uploadFss(Uint8List fileBytes, {
    String? bearerToken,
    String? departmentCode,
  }) async {
    try {
      // v3.0.42: Lấy TokenCode headers
      final headers = HisProApiService.instance.getEffectiveAuthHeaders();
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';

      final url = fssBaseUrl;
      final fileBase64 = base64Encode(fileBytes);
      final body = {'imageFile': fileBase64};
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
      ));
      debugPrint('FSS Upload -> $url/api/File/Upload (${(fileBytes.length / 1024).toStringAsFixed(1)}KB)');
      final r = await dio.post('$url/api/File/Upload', data: body);
      debugPrint('FSS status=${r.statusCode} body=${r.data}');
      if (r.statusCode == 200) {
        final data = r.data;
        if (data is Map) {
          // Có thể trả {Url: "..."} hoặc {FileUrl: "..."} hoặc direct URL string
          if (data['Url'] is String) return data['Url'];
          if (data['FileUrl'] is String) return data['FileUrl'];
          if (data['url'] is String) return data['url'];
          if (data['Data'] is String) return data['Data'];
          // Tìm bất kỳ string nào giống URL
          for (final v in data.values) {
            if (v is String && (v.startsWith('http://') || v.startsWith('https://'))) {
              return v;
            }
          }
        } else if (data is String && data.startsWith('http')) {
          return data;
        }
        debugPrint('FSS response not URL: $data');
      }
      return null;
    } catch (e) {
      debugPrint('FSS upload error: $e');
      return null;
    }
  }

  /// v3.0.35: Helper - check response từ HisProApiService.post() và trả về EmrPushResult fail nếu lỗi
  /// Trước đây, khi server trả `{"Data":null,"Success":false,"Param":null}` với Content-Type: text/plain,
  /// Dio parse thành String, app cũ tưởng là "text OK" thành công → bug nghiêm trọng.
  /// post() giờ đã check Success field; helper này chỉ unwrap message cho đẹp.
  /// v3.0.43: Thêm log chi tiết + status code vào message
  EmrPushResult? _checkPostFailure(Map<String, dynamic> r, {String? fssUrl}) {
    if (r['success'] == true) return null; // OK, caller xử lý tiếp
    final data = r['data'];
    final message = r['message']?.toString() ?? 'Lỗi không xác định';
    final status = r['status'];
    String errorType = 'unknown';
    String detailMsg = message;
    if (data is Map) {
      if (data['Success'] == false) errorType = 'server';
      // Lấy message từ Param nếu có
      final param = data['Param'];
      if (param is Map && param['Messages'] is List && (param['Messages'] as List).isNotEmpty) {
        detailMsg = (param['Messages'] as List).first.toString();
        // v3.0.43: Kèm status code nếu có
        if (status != null) detailMsg = '[$status] $detailMsg';
        return EmrPushResult(
          success: false,
          error: detailMsg,
          errorType: 'server',
          fssUrl: fssUrl,
        );
      }
      // v3.0.43: Nếu không có Messages, log raw data để debug
      debugPrint('EMR push fail - raw response: $data');
    }
    if (status == 401) errorType = 'auth';
    else if (status == 500) errorType = 'server';
    // v3.0.43: Prefix với status code để BS biết
    if (status != null) detailMsg = 'HTTP $status: $message';
    return EmrPushResult(
      success: false,
      error: detailMsg,
      errorType: errorType,
      fssUrl: fssUrl,
    );
  }

  /// v2.62.0: Đẩy phiếu lên EMR thật (pattern copy từ EmrScanApp)
  /// Flow:
  ///   1. Convert image → PDF
  ///   2. Upload PDF to FSS (port 1405) → URL
  ///   3. POST EMR CreateByTdo (port 1417) với URL trong imageFile
  /// [kind] = loại phiếu → tự động map DocumentTypeId
  /// [phieuLabel] = label phiếu (vd "Phiếu khám") để auto-detect kind
  /// [documentTypeId] = override ID cụ thể (vd 400 = "Phiếu theo dõi và chăm sóc")
  /// v3.0.6: Ưu tiên Bearer hardcode từ app Y tế số, fallback AcsToken
  /// v3.0.13: Push image lên EMR thật với 2 mode:
  ///   - useFss=true (mặc định): upload FSS 1405 trước → EMR với URL
  ///   - useFss=false: gửi base64 trực tiếp qua OriginalVersion.Base64Data (work 100%, không cần FSS)
  ///     → FALLBACK khi FSS fail (port 1405 trả 404 từ VPN)
  Future<EmrPushResult> pushImageToEmr({
    required File imageFile,
    required String treatmentCode,
    required String documentName,
    EmrDocumentKind? kind,
    String? phieuLabel,        // để auto-detect kind từ label
    int? documentTypeId,       // v2.62.0: override ID cụ thể
    String? signaturePath,
    String? roomCode,
    String roomTypeCode = 'XL',
    String? workingDeptName,
    String? departmentCode,
    bool useFss = true,         // v3.0.13: false = dùng base64
  }) async {
    final api = HisProApiService.instance;
    final token = api.getEffectiveBearer();
    if (token == null || token.isEmpty) {
      return EmrPushResult(success: false, error: 'Chưa có Bearer token (cần login HIS Pro hoặc có hardcode)', errorType: 'no_token');
    }
    await api.refreshTokenIfNeeded();
    final session = api.session; // có thể null nếu chỉ dùng hardcode Bearer

    // v2.62.0: Resolve DocumentTypeId từ nhiều nguồn
    int? dtId = documentTypeId;
    if (dtId == null && kind != null) {
      dtId = kind.docTypeId;
    }
    if (dtId == null && phieuLabel != null) {
      final detected = EmrDocumentKind.fromString(phieuLabel);
      if (detected != null) dtId = detected.docTypeId;
    }
    dtId ??= EmrDocumentKind.defaultKind.docTypeId;
    debugPrint('EMR push: DocTypeId=$dtId (kind=${kind?.label}, phieuLabel=$phieuLabel, useFss=$useFss)');

    // Step 1: Convert image to PDF
    final pdfBytes = await imageToPdfBytes(imageFile, documentName: documentName);
    if (pdfBytes == null) {
      return EmrPushResult(success: false, error: 'Không convert được ảnh sang PDF', errorType: 'pdf');
    }

    // v3.0.13: Quyết định mode upload
    String? fssUrl;
    String? base64Data;
    if (useFss) {
      // Step 2a: Upload PDF to FSS (port 1405) - mặc định
      fssUrl = await uploadFss(pdfBytes, bearerToken: token);
      if (fssUrl == null || fssUrl.isEmpty) {
        debugPrint('FSS upload failed → fallback dùng base64');
        base64Data = base64Encode(pdfBytes);
        fssUrl = null;
      } else {
        debugPrint('FSS uploaded: $fssUrl');
      }
    } else {
      // Step 2b: Dùng base64 trực tiếp (không qua FSS)
      base64Data = base64Encode(pdfBytes);
    }

    // Step 3: Build SDO với signer info từ session
    final now = DateTime.now();
    final docTime = now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
    final signTime = now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
    final signerId = session?.signerId ?? 0;
    final depCode = departmentCode ?? session?.departmentCode ?? 'HSCC';
    final depName = workingDeptName ?? session?.departmentName ?? 'Khoa Cấp Cứu';
    final rCode = roomCode ?? session?.roomCode ?? 'PKCC';
    final loginName = session?.loginName ?? HisProHardcoded.loginName;
    final userName = session?.userName ?? HisProHardcoded.loginName;

    final sdo = <String, dynamic>{
      'DocumentName': documentName,
      'DocumentTypeId': dtId,           // v2.62.0: ID thật từ HIS Pro
      'DocumentGroupId': null,          // v2.62.0: HIS Pro log trả null
      'DocumentCode': null,
      'DocumentId': null,
      'IsCapture': true,
      'IsFinishSign': signaturePath != null,
      'IsSigning': false,
      'IsSignElectronic': false,
      'IsSignParallel': false,
      'TreatmentCode': treatmentCode,
      'HisCode': null,
      'Description': null,
      'PointSign': 1,
      'WorkingDepartmentName': depName,
      'DepartmentCode': depCode,
      'RoomCode': rCode,
      'RoomTypeCode': roomTypeCode,
      'PaperName': 'A4',
      'RawKind': 9,
      'Width': 827.0,
      'Height': 1169.0,
        'IsOutsideTreatment': false,
        'MediOrgCode': '58001',
      'FileType': 0,
      'BusinessCode': '',
      'DependentCode': null,
      'ParentDependentCode': null,
      'AttachmentCount': null,
      'DocumentTime': docTime,
      'Signs': [
        if (signerId > 0)
          {
            'DocumentCode': null,
            'NumOrder': 1,
            'Loginname': loginName,
            'Username': userName,
            'SignTime': signTime,
            'SignerId': signerId,
            'DepartmentCode': depCode,
            'DepartmentName': depName,
            'Title': 'BS',
            'FirstName': userName,
            'LastName': null,
            'FullName': null,
            'SerialNumber': null,
            'CardCode': null,
            'CmndNumber': null,
            'ServiceCode': null,
            'RelationPeopleName': null,
            'RelationName': null,
            'RelationId': null,
            'FlowId': null,
            'RoomCode': rCode,
            'RoomName': null,
            'RoomTypeCode': roomTypeCode,
            'Version': null,
            'LinkCode': null,
            'IsSigned': signaturePath != null,
            'Description': null,
            'UnSigners': null,
            'SignedImageData': null,
          }
      ],
      // v3.0.13: OriginalVersion có cả Base64Data (work 100%, không cần FSS) và ImageUrl
      'OriginalVersion': {
        'Base64Data': base64Data,     // v3.0.13: gửi base64 trực tiếp (work 100%)
        'UrlXml': null,
        'Base64DataXml': null,
        'UrlJson': null,
        'Base64DataJson': null,
        'Base64Header': '',
        'MergeCode': null,
        'OriginalHigh': null,
        'ImageUrl': fssUrl,           // v2.61.0: FSS URL (null nếu useFss=false)
      },
      'LinkCode': null,
      'UnSigners': null,
      'SignedImageData': null,
      // v3.0.13: imageFile ở root SDO - ưu tiên base64 (work 100%)
      'imageFile': base64Data ?? fssUrl,
    };
    final body = {'ApiData': sdo};

    // Step 4: POST qua HisProApiService (handle base64 wrapper + Bearer + ___ipAddress)
    try {
      await api.refreshTokenIfNeeded();
      final url = '${api.getEmrBaseUrlSync()}/api/EmrDocument/CreateByTdo';
      debugPrint('EMR Create -> $url (DocTypeId=$dtId)');
      final r = await api.post(url, body, limit: 10);
      debugPrint('EMR push response: status=${r.status} body=${r.data}');
      // v3.0.35: post() đã check Success field của server, unwrap fail nếu có
      final fail = _checkPostFailure({
        'success': r.success,
        'status': r.status,
        'data': r.data,
        'message': r.message,
      }, fssUrl: fssUrl);
      if (fail != null) return fail;
      if (r.data is Map) {
        final root = r.data as Map;
        final data = root['Data'];
        if (data is Map && data['DocumentCode'] != null) {
          return EmrPushResult(
            success: true,
            documentCode: data['DocumentCode']?.toString(),
            documentId: data['DocumentId'] is int ? data['DocumentId'] as int : null,
            fssUrl: fssUrl,
          );
        }
        // Trường hợp lạ: success=true nhưng Data không có DocumentCode
        return EmrPushResult(success: true, documentCode: null, fssUrl: fssUrl);
      }
      // Fallback: response lạ (không phải Map, không phải String đã parse)
      return EmrPushResult(success: false, error: 'Response không hợp lệ: ${r.data?.runtimeType}', errorType: 'unknown', fssUrl: fssUrl);
    } catch (e) {
      debugPrint('EMR push error: $e');
      return EmrPushResult(success: false, error: e.toString(), errorType: 'unknown');
    }
  }

  /// v2.99.0: Push PDF lên EMR KHÔNG ký số (BS sẽ vào HIS Pro desktop ký sau)
  /// Phù hợp khi:
  ///   - Chưa có PFX cert
  ///   - Muốn upload nhanh để BS ký trên HIS Pro desktop (workflow cũ)
  ///   - Test kết nối EMR server
  ///
  /// Flow giống pushImageToEmr nhưng:
  ///   - Nhận Uint8List pdfBytes thay vì File image (đỡ mất công convert)
  ///   - IsFinishSign = false, IsSigning = false
  ///   - KHÔNG có Signs array (BS ký sau trên HIS Pro)
  ///   - WorkingDepartmentName mặc định "Khoa Cấp Cứu" nếu không truyền
  /// v3.0.6: Ưu tiên Bearer hardcode từ app Y tế số, fallback AcsToken
  /// v3.0.10: Hỗ trợ 2 mode upload:
  ///   - useFss=true (mặc định): upload FSS 1405 trước → EMR với URL
  ///   - useFss=false: gửi base64 trực tiếp qua OriginalVersion.Base64Data (work 100%, không cần FSS)
  ///     → FALLBACK khi FSS fail (port 1405 trả 404 từ VPN)
  Future<EmrPushResult> pushPdfToEmrUnsigned({
    required Uint8List pdfBytes,
    required String treatmentCode,
    required String documentName,
    EmrDocumentKind? kind,
    String? phieuLabel,
    int? documentTypeId,
    String? roomCode,
    String roomTypeCode = 'XL',
    String? workingDeptName,
    String? departmentCode,
    bool useFss = true,
  }) async {
    if (pdfBytes.isEmpty) {
      return EmrPushResult(success: false, error: 'PDF rỗng', errorType: 'pdf');
    }
    final api = HisProApiService.instance;
    final token = api.getEffectiveBearer();
    if (token == null || token.isEmpty) {
      return EmrPushResult(success: false, error: 'Chưa có Bearer token (cần login HIS Pro hoặc có hardcode)', errorType: 'no_token');
    }
    await api.refreshTokenIfNeeded();
    final session = api.session; // có thể null nếu chỉ dùng hardcode Bearer

    // Resolve DocumentTypeId
    int? dtId = documentTypeId;
    if (dtId == null && kind != null) dtId = kind.docTypeId;
    if (dtId == null && phieuLabel != null) {
      final detected = EmrDocumentKind.fromString(phieuLabel);
      if (detected != null) dtId = detected.docTypeId;
    }
    dtId ??= EmrDocumentKind.defaultKind.docTypeId;
    debugPrint('EMR push (UNSIGNED): DocTypeId=$dtId (kind=${kind?.label}, phieuLabel=$phieuLabel, useFss=$useFss)');

    // v3.0.10: Quyết định mode upload
    String? fssUrl;
    String? base64Data;
    if (useFss) {
      // Mode FSS: upload trước, lấy URL
      fssUrl = await uploadFss(pdfBytes, bearerToken: token);
      if (fssUrl == null || fssUrl.isEmpty) {
        debugPrint('FSS upload failed → fallback dùng base64');
        base64Data = base64Encode(pdfBytes);
        fssUrl = null;
      } else {
        debugPrint('FSS uploaded: $fssUrl');
      }
    } else {
      // Mode Base64: encode thẳng
      base64Data = base64Encode(pdfBytes);
    }

    // Build SDO KHÔNG có Signs, IsFinishSign=false
    final now = DateTime.now();
    final docTime = now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
    final depCode = departmentCode ?? session?.departmentCode ?? 'HSCC';
    final depName = workingDeptName ?? session?.departmentName ?? 'Khoa Cấp Cứu';
    final rCode = roomCode ?? session?.roomCode ?? 'PKCC';

    final sdo = <String, dynamic>{
      'DocumentName': documentName,
      'DocumentTypeId': dtId,
      'DocumentGroupId': null,
      'DocumentCode': null,
      'DocumentId': null,
      'IsCapture': true,
      'IsFinishSign': false,           // v2.99.0: KHÔNG ký trong app
      'IsSigning': false,
      'IsSignElectronic': false,
      'IsSignParallel': false,
      'TreatmentCode': treatmentCode,
      'HisCode': null,
      'Description': null,
      'PointSign': 1,
      'WorkingDepartmentName': depName,
      'DepartmentCode': depCode,
      'RoomCode': rCode,
      'RoomTypeCode': roomTypeCode,
      'PaperName': 'A4',
      'RawKind': 9,
      'Width': 827.0,
      'Height': 1169.0,
        'IsOutsideTreatment': false,
        'MediOrgCode': '58001',
      'FileType': 0,
      'BusinessCode': '',
      'DependentCode': null,
      'ParentDependentCode': null,
      'AttachmentCount': null,
      'DocumentTime': docTime,
      'Signs': <Map<String, dynamic>>[],  // v2.99.0: rỗng, BS ký sau trên HIS Pro
      'OriginalVersion': <String, dynamic>{
        'Base64Data': base64Data,        // v3.0.10: gửi base64 trực tiếp
        'UrlXml': null,
        'Base64DataXml': null,
        'UrlJson': null,
        'Base64DataJson': null,
        'Base64Header': '',
        'MergeCode': null,
        'OriginalHigh': null,
        'ImageUrl': fssUrl,             // null nếu dùng base64
      },
      'LinkCode': null,
      'UnSigners': null,
      'SignedImageData': null,
      // v3.0.10: imageFile cũng chứa base64 (work với EMR 1417)
      'imageFile': base64Data ?? fssUrl,
    };
    final body = {'ApiData': sdo};

    try {
      await api.refreshTokenIfNeeded();
      final url = '${api.getEmrBaseUrlSync()}/api/EmrDocument/CreateByTdo';
      debugPrint('EMR Create (UNSIGNED) -> $url (DocTypeId=$dtId, mode=${fssUrl != null ? "FSS" : "Base64"})');
      // v3.0.43: Ghi log request chi tiết
      await UploadLogService.instance.logRequest(
        endpoint: url,
        method: 'POST',
        treatmentCode: treatmentCode,
        documentTypeId: dtId,
        documentName: documentName,
        fileSize: pdfBytes.length,
      );
      final r = await api.post(url, body, limit: 10);
      debugPrint('EMR push (UNSIGNED) response: status=${r.status} body=${r.data}');
      // v3.0.43: Ghi log response chi tiết
      await UploadLogService.instance.logResponse(
        endpoint: url,
        httpStatus: r.status ?? 0,
        success: r.success,
        message: r.message,
      );
      // v3.0.35: post() đã check Success field của server, unwrap fail nếu có
      final fail = _checkPostFailure({
        'success': r.success,
        'status': r.status,
        'data': r.data,
        'message': r.message,
      }, fssUrl: fssUrl);
      if (fail != null) return fail;
      if (r.data is Map) {
        final root = r.data as Map;
        final data = root['Data'];
        if (data is Map && data['DocumentCode'] != null) {
          return EmrPushResult(
            success: true,
            documentCode: data['DocumentCode']?.toString(),
            documentId: data['DocumentId'] is int ? data['DocumentId'] as int : null,
            fssUrl: fssUrl,
          );
        }
        // Trường hợp lạ: success=true nhưng Data không có DocumentCode
        return EmrPushResult(success: true, documentCode: null, fssUrl: fssUrl);
      }
      return EmrPushResult(success: false, error: 'Response không hợp lệ: ${r.data?.runtimeType}', errorType: 'unknown', fssUrl: fssUrl);
    } catch (e) {
      debugPrint('EMR push (UNSIGNED) error: $e');
      return EmrPushResult(success: false, error: e.toString(), errorType: 'unknown');
    }
  }

  /// v3.0.14: Push PDF đã ký số (signed) lên EMR HIS Pro
  /// Flow:
  ///   1. PDF đã ký bằng SmartCA (hoặc PFX) → Base64
  ///   2. POST EMR CreateByTdo với IsFinishSign=true + SignedImageData
  ///   3. Trả DocumentCode
  ///
  /// Dùng cho nút "Lưu ký" trong các phiếu:
  ///   - Phiếu khám, Phiếu form, Scan phiếu, Y tế số (20 chức năng)
  Future<EmrPushResult> pushSignedPdfToEmr({
    required Uint8List signedPdfBytes,
    required String treatmentCode,
    required String documentName,
    int? documentTypeId,
    EmrDocumentKind? kind,
    String? phieuLabel,
    String? roomCode,
    String roomTypeCode = 'XL',
    String? workingDeptName,
    String? departmentCode,
    String? certSerial,  // SmartCA cert serial
  }) async {
    if (signedPdfBytes.isEmpty) {
      return EmrPushResult(success: false, error: 'PDF đã ký rỗng', errorType: 'pdf');
    }
    final api = HisProApiService.instance;
    final token = api.getEffectiveBearer();
    if (token == null || token.isEmpty) {
      return EmrPushResult(success: false, error: 'Chưa có Bearer token', errorType: 'no_token');
    }
    await api.refreshTokenIfNeeded();
    final session = api.session;

    // Resolve DocumentTypeId
    int? dtId = documentTypeId;
    if (dtId == null && kind != null) dtId = kind.docTypeId;
    if (dtId == null && phieuLabel != null) {
      final detected = EmrDocumentKind.fromString(phieuLabel);
      if (detected != null) dtId = detected.docTypeId;
    }
    dtId ??= EmrDocumentKind.defaultKind.docTypeId;
    debugPrint('EMR push SIGNED: DocTypeId=$dtId, PDF size=${(signedPdfBytes.length / 1024).toStringAsFixed(1)}KB');

    // v3.0.14: PDF đã ký → base64
    final base64Data = base64Encode(signedPdfBytes);
    final depCode = departmentCode ?? session?.departmentCode ?? 'HSCC';
    final depName = workingDeptName ?? session?.departmentName ?? 'Khoa Cấp Cứu';
    final rCode = roomCode ?? session?.roomCode ?? 'PKCC';
    final now = DateTime.now();
    final docTime = now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
    final signTime = now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
    final signerId = session?.signerId ?? 0;
    final loginName = session?.loginName ?? HisProHardcoded.loginName;
    final userName = session?.userName ?? HisProHardcoded.loginName;

    // v3.0.14: Build SDO với IsFinishSign=true + SignedImageData
    final sdo = <String, dynamic>{
      'DocumentName': documentName,
      'DocumentTypeId': dtId,
      'DocumentGroupId': null,
      'DocumentCode': null,
      'DocumentId': null,
      'IsCapture': true,
      'IsFinishSign': true,            // v3.0.14: PDF đã ký rồi
      'IsSigning': false,
      'IsSignElectronic': true,         // v3.0.14: ký điện tử
      'IsSignParallel': false,
      'TreatmentCode': treatmentCode,
      'HisCode': null,
      'Description': null,
      'PointSign': 1,
      'WorkingDepartmentName': depName,
      'DepartmentCode': depCode,
      'RoomCode': rCode,
      'RoomTypeCode': roomTypeCode,
      'PaperName': 'A4',
      'RawKind': 9,
      'Width': 827.0,
      'Height': 1169.0,
      'IsOutsideTreatment': false,
      'MediOrgCode': '58001',
      'FileType': 0,
      'BusinessCode': '',
      'DependentCode': null,
      'ParentDependentCode': null,
      'AttachmentCount': null,
      'DocumentTime': docTime,
      // v3.0.15: BỎ Signs array (server reject EMR002 khi có SignerId)
      // BS sẽ ký trên HIS Pro desktop sau, hoặc workflow này = "đã ký điện tử local"
      'Signs': <Map<String, dynamic>>[],
      'OriginalVersion': <String, dynamic>{
        'Base64Data': base64Data,       // v3.0.14: PDF đã ký (base64)
        'UrlXml': null,
        'Base64DataXml': null,
        'UrlJson': null,
        'Base64DataJson': null,
        'Base64Header': '',
        'MergeCode': null,
        'OriginalHigh': null,
        'ImageUrl': null,                // không dùng FSS
      },
      'LinkCode': null,
      'UnSigners': null,
      'SignedImageData': base64Data,    // v3.0.14: PDF đã ký ở root
      'imageFile': base64Data,          // v3.0.14: PDF đã ký
    };
    final body = {'ApiData': sdo};

    try {
      await api.refreshTokenIfNeeded();
      final url = '${api.getEmrBaseUrlSync()}/api/EmrDocument/CreateByTdo';
      debugPrint('EMR Create (SIGNED) -> $url (DocTypeId=$dtId)');
      final r = await api.post(url, body, limit: 10);
      debugPrint('EMR push SIGNED response: status=${r.status} body=${r.data}');
      // v3.0.35: post() đã check Success field của server, unwrap fail nếu có
      final fail = _checkPostFailure({
        'success': r.success,
        'status': r.status,
        'data': r.data,
        'message': r.message,
      });
      if (fail != null) return fail;
      if (r.data is Map) {
        final root = r.data as Map;
        final data = root['Data'];
        if (data is Map && data['DocumentCode'] != null) {
          return EmrPushResult(
            success: true,
            documentCode: data['DocumentCode']?.toString(),
            documentId: data['DocumentId'] is int ? data['DocumentId'] as int : null,
          );
        }
        return EmrPushResult(success: true, documentCode: null);
      }
      return EmrPushResult(success: false, error: 'Response không hợp lệ: ${r.data?.runtimeType}', errorType: 'unknown');
    } catch (e) {
      debugPrint('EMR push SIGNED error: $e');
      return EmrPushResult(success: false, error: e.toString(), errorType: 'unknown');
    }
  }

  /// v2.76.0: Push PDF lên EMR qua Cục KCB gateway (Bộ Y tế)
  /// Thay thế flow HIS Pro 1417 (thường bị silent-fail do key hết hạn)
  /// Input: PDF bytes + metadata → POST base64 lên Cục KCB → nhận emrDocumentCode
  Future<EmrPushResult> pushPdfToKcb({
    required Uint8List pdfBytes,
    required String treatmentCode,  // MADT
    required String documentName,    // vd "giải thích bệnh.pdf"
    int emrDocumentType = 20,        // 20 = Phiếu khác (Cục KCB)
    String? signatureBase64,
  }) async {
    if (pdfBytes.isEmpty) {
      return EmrPushResult(success: false, error: 'PDF rỗng', errorType: 'pdf');
    }
    final base64Pdf = base64Encode(pdfBytes);
    final result = await KcbEmrPushService.instance.pushFullFlow(
      madt: treatmentCode,
      tenTaiLieu: documentName,
      emrDocumentType: emrDocumentType,
      fileBase64: base64Pdf,
      signatureBase64: signatureBase64,
    );
    if (result.success) {
      return EmrPushResult(
        success: true,
        documentCode: result.emrDocumentCode,
        documentId: result.emrDocumentId,
        fssUrl: result.filePath,
      );
    }
    return EmrPushResult(
      success: false,
      error: 'Cục KCB: ${result.message}',
      errorType: 'kcb',
    );
  }

  /// v2.76.0: Hybrid - thử Cục KCB trước, fallback HIS Pro
  /// Trả về kết quả cuối cùng (ưu tiên KCB)
  Future<EmrPushResult> pushPdfHybrid({
    required Uint8List pdfBytes,
    required String treatmentCode,
    required String documentName,
    int emrDocumentType = 20,
    String? signatureBase64,
  }) async {
    if (HisConfigService.instance.config.useKcbForEmr) {
      debugPrint('🚀 [Hybrid] Thử Cục KCB trước...');
      final kcb = await pushPdfToKcb(
        pdfBytes: pdfBytes,
        treatmentCode: treatmentCode,
        documentName: documentName,
        emrDocumentType: emrDocumentType,
        signatureBase64: signatureBase64,
      );
      if (kcb.success) {
        debugPrint('✅ [Hybrid] Cục KCB thành công');
        return kcb;
      }
      debugPrint('⚠ [Hybrid] Cục KCB fail: ${kcb.error} → fallback HIS Pro');
    } else {
      debugPrint('ℹ [Hybrid] Cục KCB bị tắt → dùng HIS Pro');
    }
    // Fallback: gọi HIS Pro 1417 thông qua pushImageToEmr không có ảnh
    // (cần upload PDF thay vì image - tạm thời chưa hỗ trợ, trả lỗi rõ ràng)
    return EmrPushResult(
      success: false,
      error: 'Cục KCB thất bại và HIS Pro chưa hỗ trợ push PDF (chỉ image). Hãy bật Cục KCB trong Cấu hình.',
      errorType: 'kcb_only',
    );
  }

  // ============================================================
  // v3.0.42: Dispatch theo EmrPushApiSource đã chọn ở HomeScreen
  // - hisPro: HIS Pro 1417 (mặc định, work cho mọi user)
  // - public: HIS Pro 8080 (public fallback)
  // - mockLocal: Mock server local (test offline)
  // - BỎ: bvbm, kcb (không còn dùng)
  // ============================================================

  /// v3.0.42: Lấy EmrPushApiSource hiện tại (default = hisPro nếu chưa load)
  Future<EmrPushApiSource> _getApiSource() async {
    try {
      return await EmrApiSelectorService.instance.getSelected();
    } catch (_) {
      return EmrPushApiSource.hisPro;
    }
  }

  /// v3.0.42: Push image lên EMR HIS Pro 1417 (mặc định) hoặc mock
  Future<EmrPushResult> pushImageToEmrWithApi({
    required File imageFile,
    required String treatmentCode,
    required String documentName,
    EmrDocumentKind? kind,
    String? phieuLabel,
    int? documentTypeId,
    String? signaturePath,
    String? roomCode,
    String roomTypeCode = 'XL',
    String? workingDeptName,
    String? departmentCode,
    bool useFss = true,
  }) async {
    final src = await _getApiSource();
    debugPrint('🚀 [Dispatch] pushImageToEmr via ${src.label}');
    switch (src) {
      case EmrPushApiSource.hisPro:
      case EmrPushApiSource.public:
        return pushImageToEmr(
          imageFile: imageFile,
          treatmentCode: treatmentCode,
          documentName: documentName,
          kind: kind,
          phieuLabel: phieuLabel,
          documentTypeId: documentTypeId,
          signaturePath: signaturePath,
          roomCode: roomCode,
          roomTypeCode: roomTypeCode,
          workingDeptName: workingDeptName,
          departmentCode: departmentCode,
          useFss: useFss,
        );
      case EmrPushApiSource.mockLocal:
        // v3.0.42: Convert image to PDF trước, rồi push mock
        try {
          final pdfBytes = await imageToPdfBytes(imageFile, documentName: documentName);
          if (pdfBytes == null) {
            return EmrPushResult(
              success: false,
              error: 'Mock: không convert được ảnh sang PDF',
              errorType: 'pdf',
            );
          }
          final tempPath = await _saveTempPdf(pdfBytes, documentName);
          return _pushToMock(
            documentName: documentName,
            documentTypeId: documentTypeId ?? 20,
            treatmentCode: treatmentCode,
            filePath: tempPath,
            fileSize: pdfBytes.length,
            isSigned: signaturePath != null,
          );
        } catch (e) {
          return EmrPushResult(
            success: false,
            error: 'Mock: $e',
            errorType: 'unknown',
          );
        }
    }
  }

  /// v3.0.42: Push PDF unsigned lên EMR HIS Pro 1417 (mặc định) hoặc mock
  Future<EmrPushResult> pushPdfToEmrUnsignedWithApi({
    required Uint8List pdfBytes,
    required String treatmentCode,
    required String documentName,
    EmrDocumentKind? kind,
    String? phieuLabel,
    int? documentTypeId,
    String? roomCode,
    String roomTypeCode = 'XL',
    String? workingDeptName,
    String? departmentCode,
    bool useFss = true,
  }) async {
    final src = await _getApiSource();
    debugPrint('🚀 [Dispatch] pushPdfToEmrUnsigned via ${src.label}');
    switch (src) {
      case EmrPushApiSource.hisPro:
      case EmrPushApiSource.public:
        return pushPdfToEmrUnsigned(
          pdfBytes: pdfBytes,
          treatmentCode: treatmentCode,
          documentName: documentName,
          kind: kind,
          phieuLabel: phieuLabel,
          documentTypeId: documentTypeId,
          roomCode: roomCode,
          roomTypeCode: roomTypeCode,
          workingDeptName: workingDeptName,
          departmentCode: departmentCode,
          useFss: useFss,
        );
      case EmrPushApiSource.mockLocal:
        try {
          final tempPath = await _saveTempPdf(pdfBytes, documentName);
          return _pushToMock(
            documentName: documentName,
            documentTypeId: documentTypeId ?? 20,
            treatmentCode: treatmentCode,
            filePath: tempPath,
            fileSize: pdfBytes.length,
            isSigned: false,
          );
        } catch (e) {
          return EmrPushResult(
            success: false,
            error: 'Mock: $e',
            errorType: 'unknown',
          );
        }
    }
  }

  /// v3.0.42: Push PDF signed lên EMR HIS Pro 1417 (mặc định) hoặc mock
  Future<EmrPushResult> pushSignedPdfToEmrWithApi({
    required Uint8List signedPdfBytes,
    required String treatmentCode,
    required String documentName,
    int? documentTypeId,
    EmrDocumentKind? kind,
    String? phieuLabel,
    String? roomCode,
    String roomTypeCode = 'XL',
    String? workingDeptName,
    String? departmentCode,
    String? certSerial,
  }) async {
    final src = await _getApiSource();
    debugPrint('🚀 [Dispatch] pushSignedPdfToEmr via ${src.label}');
    switch (src) {
      case EmrPushApiSource.hisPro:
      case EmrPushApiSource.public:
        return pushSignedPdfToEmr(
          signedPdfBytes: signedPdfBytes,
          treatmentCode: treatmentCode,
          documentName: documentName,
          documentTypeId: documentTypeId,
          kind: kind,
          phieuLabel: phieuLabel,
          roomCode: roomCode,
          roomTypeCode: roomTypeCode,
          workingDeptName: workingDeptName,
          departmentCode: departmentCode,
          certSerial: certSerial,
        );
      case EmrPushApiSource.mockLocal:
        return _pushToMock(
          documentName: documentName,
          documentTypeId: documentTypeId ?? 20,
          treatmentCode: treatmentCode,
          filePath: '',
          fileSize: signedPdfBytes.length,
          isSigned: true,
        );
    }
  }

  // ============================================================
  // v3.0.39: Helper methods cho Mock server
  // ============================================================

  /// Lưu PDF bytes vào file temp trong app docs
  Future<String> _saveTempPdf(Uint8List pdfBytes, String documentName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final tempDir = Directory('${docsDir.path}/temp');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final safeName = documentName.replaceAll(RegExp(r'[^\w\-\.]'), '_');
    final file = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName.pdf');
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// Push to MockEmrServer
  Future<EmrPushResult> _pushToMock({
    required String documentName,
    required int documentTypeId,
    required String treatmentCode,
    required String filePath,
    int? fileSize,
    bool isSigned = false,
  }) async {
    final user = HisProHardcoded.loginName.isNotEmpty
        ? HisProHardcoded.loginName
        : 'mock_user';
    final mockResp = await MockEmrServer.instance.createDocument(
      documentName: documentName,
      documentTypeId: documentTypeId,
      treatmentCode: treatmentCode,
      user: user,
      isSigned: isSigned,
      filePath: filePath,
      fileSize: fileSize,
    );
    if (mockResp.success) {
      return EmrPushResult(
        success: true,
        documentCode: mockResp.documentCode,
        documentId: mockResp.documentId,
        fssUrl: 'mock://${mockResp.documentCode}',
      );
    }
    return EmrPushResult(
      success: false,
      error: mockResp.error ?? 'Mock server: lỗi không xác định',
      errorType: 'server',
    );
  }

  /// v3.0.42: BỎ _pushToBvbm (không còn dùng BVBM Gateway)
  /// Code cũ đã được xóa - app giờ chỉ push qua HIS Pro 1417 + Mock
}