// PhieuKhamScreen.dart v2.55.0





// Workflow phiếu khám HOÀN CHỈNH:





//   1. Sinh hiệu (mạch / nhiệt / HHA / SpO2)





//   2. Chẩn đoán ICD chính





//   3. Chỉ định Cận lâm sàng (CLS)





//   4. Đơn thuốc (liều/cách dùng/số ngày)





//   5. Ghi chú





//   6. Ký số → push EMR





//   7. Auto-create Tracking sau khám





//





// Flow save:





//   1. Validate form





//   2. POST HisServiceReq/Update cho từng CLS





//   3. Nếu có thuốc → POST HisPrescription/Create (TBD v2.55.1)





//   4. POST HisTracking/Update với content sinh hiệu





//   5. Tạo EMR Document PDF → push











import 'dart:convert';





import 'dart:io';





import 'dart:typed_data';





import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';





import 'package:flutter/material.dart';





import 'package:flutter/foundation.dart' show debugPrint;





import 'package:signature/signature.dart';





import 'package:path_provider/path_provider.dart';





import 'package:his_mobile/data/api/his_catalog_service.dart';





import 'package:his_mobile/data/api/his_service_req_service.dart';





import 'package:his_mobile/data/api/his_tracking_service.dart';





import 'package:his_mobile/data/api/thongke_auth_service.dart';





import 'package:his_mobile/data/api/emr_push_service.dart';





import 'package:his_mobile/data/api/his_pro_api_service.dart';





import 'package:his_mobile/data/services/phieu_save_service.dart';





import 'package:his_mobile/data/services/treatment_id_cache.dart';





import 'package:his_mobile/presentation/screens/icd10_webview_screen.dart';





import 'package:his_mobile/presentation/widgets/catalog_picker.dart';





import 'package:his_mobile/presentation/widgets/icd_input_field.dart';





import 'package:his_mobile/presentation/widgets/medicine_selector.dart';











class PhieuKhamScreen extends StatefulWidget {





  final Map<String, dynamic> patient;





  final Map<String, dynamic> department;





  final int? treatmentId;











  const PhieuKhamScreen({





    super.key,





    required this.patient,





    required this.department,





    this.treatmentId,





  });











  @override





  State<PhieuKhamScreen> createState() => _PhieuKhamScreenState();





}











class _PhieuKhamScreenState extends State<PhieuKhamScreen> {





  // v2.55.0: Sinh hiệu





  final _machCtrl = TextEditingController();





  final _nhietCtrl = TextEditingController();





  final _hhaTTCtrl = TextEditingController();





  final _hhaTDCtrl = TextEditingController();





  final _spo2Ctrl = TextEditingController();











  // v2.55.0: Form fields





  final _lyDoCtrl = TextEditingController();





  final _ghiChuCtrl = TextEditingController();











  // v2.98.5: ICD dùng IcdInputField widget (chuẩn hóa với Lập phiếu khác)





  // Không cần controller riêng - IcdInputField tự quản lý





  // Lưu giá trị ICD vào _icdValues để dùng cho save





  final List<IcdValue> _icdValues = [];











  // v2.55.0: Selections





  CatalogItem? _selectedIcd;





  final List<CatalogItem> _selectedServices = [];





  bool _loadingAllCls = false;  // v2.98.7: Loading state cho nút "Chọn tất cả"





  final List<PrescriptionItem> _medicines = [];











  // v2.55.0: Signature





  final SignatureController _sigCtrl = SignatureController(





    penStrokeWidth: 2.5,





    penColor: Colors.black,





    exportBackgroundColor: Colors.white,





  );











  bool _saving = false;





  // PDF font (TNKeyUni - v3.0.143)
  static pw.Font? _pdfFont;
  static pw.Font? _pdfFontBold;

  String? _result;











  @override





  void initState() {





    super.initState();





    // v3.0.32: Đảm bảo catalog đã load - nếu chưa có data thì trigger refresh





    _ensureCatalogLoaded();





  }











  /// v3.0.32: Đảm bảo HisCatalogService đã load xong (tránh case mở màn nhanh khi catalog chưa ready)





  Future<void> _ensureCatalogLoaded() async {





    try {





      // Init (nếu chưa) - sẽ load cache + background refresh





      await HisCatalogService.instance.init();





      // Check nếu cả 3 catalog trống → trigger refresh đồng bộ





      final empty = HisCatalogService.instance.isEmpty();





      if (empty) {





        debugPrint('Catalog empty → force refresh');





        await HisCatalogService.instance.refreshAll();





      }





    } catch (e) {





      debugPrint('Catalog ensure error: $e');





    }





  }











  /// v3.0.1: tìm treatment ID từ nhiều nguồn (fix lỗi "không có TREATMENT_ID")





  int? get _treatmentId {





    // 1. Widget truyền vào





    if (widget.treatmentId != null) return widget.treatmentId;





    // 2. Patient map (HIS Pro uppercase)





    final v1 = widget.patient['TREATMENT_ID'];





    if (v1 is int) return v1;





    if (v1 is String) {





      final i = int.tryParse(v1);





      if (i != null) return i;





    }





    // 3. ID thường





    final v2 = widget.patient['id'];





    if (v2 is int) return v2;





    if (v2 is String) {





      final i = int.tryParse(v2);





      if (i != null) return i;





    }





    // 4. TreatmentCode (string) → fetch từ HIS Pro





    // Nếu không có sẵn, _save() sẽ tự fetch từ treatmentCode





    return null;





  }











  /// v3.0.1: Lấy treatment ID từ HIS Pro qua treatmentCode (nếu chưa có)





  /// v3.0.7: Lấy treatment ID từ HIS Pro qua treatmentCode (nếu chưa có)





  /// PHÁT HIỆN MỚI (2026-07-14 test Python):





  ///   - Filter `TREATMENT_CODE` (string) KHÔNG work trên tất cả endpoint HIS Pro





  ///   - 3/4 endpoint (HisTreatment/Get 1408, HisServiceReq/GetLView, EmrDocument/GetView)





  ///     là DETAIL API, chỉ nhận filter `ID` (int) hoặc `TREATMENT_ID` (int)





  ///   - CHỈ `EmrTreatment/Get 1417` LÀ LIST API - trả 500 records không cần filter





  ///   → Workflow đúng:





  ///     1. Gọi EmrTreatment/Get 1417 với limit=500, KHÔNG filter





  ///     2. Scan list tìm record có TREATMENT_CODE == code





  ///     3. Lấy ID từ record đó





  ///     4. (Optional) Verify qua HisTreatment/Get 1408 với filter ID





  Future<int?> _fetchTreatmentIdFromCode(String treatmentCode) async {





    if (treatmentCode.isEmpty) return null;











    // Strategy 1: Cache





    try {





      await TreatmentIdCache.instance.load();





      final cached = TreatmentIdCache.instance.get(treatmentCode);





      if (cached != null) {





        debugPrint('✅ _fetchTreatmentIdFromCode: cache HIT for $treatmentCode = $cached');





        return cached;





      }





    } catch (e) {





      debugPrint('Cache load error: $e');





    }











    final api = HisProApiService.instance;





    await api.refreshTokenIfNeeded();











    // Strategy 2: EMR /api/EmrTreatment/Get (1417) - LIST API duy nhất





    // Gọi KHÔNG filter (filter TREATMENT_CODE bị server bỏ qua)





    // Scan 500 records tìm record có TREATMENT_CODE = code





    try {





      final r = await api.get('${api.getEmrBaseUrlSync()}/api/EmrTreatment/Get', {





        'LOGIN_NAME': 'nemk',





      }, limit: 500);





      final id = _findTreatmentIdInList(r, treatmentCode);





      if (id != null) {





        debugPrint('✅ _fetchTreatmentIdFromCode: Got ID=$id from EMR EmrTreatment/Get (limit=500)');





        // Verify ID qua HisTreatment/Get 1408 (optional, nếu work thì càng chắc)





        try {





          final verify = await api.get('${api.getMosBaseUrlSync()}/api/HisTreatment/Get', {





            'ID': id,





          }, limit: 10);





          if (verify.success) {





            final d = verify.data is Map ? verify.data as Map : null;





            if (d != null && d['Data'] is List && (d['Data'] as List).isNotEmpty) {





              debugPrint('   ✓ Verified via MOS 1408 HisTreatment/Get');





            }





          }





        } catch (e) {





          debugPrint('   ⚠ Verify qua MOS 1408 fail (không sao): $e');





        }





        await TreatmentIdCache.instance.set(treatmentCode, id);





        return id;





      }





    } catch (e) {





      debugPrint('EmrTreatment/Get (limit=500) error: $e');





    }











    debugPrint('❌ _fetchTreatmentIdFromCode: No strategy worked for $treatmentCode (có thể ca cũ ngoài 500 records)');





    return null;





  }











  /// Tìm treatment ID trong list data (filter theo TREATMENT_CODE)





  int? _findTreatmentIdInList(dynamic r, String treatmentCode) {





    if (r == null || !r.success || r.data is! Map) return null;





    final d = r.data as Map;





    if (d['Success'] != true) return null;





    final data = d['Data'];





    if (data is List) {





      for (final t in data) {





        if (t is Map && t['TREATMENT_CODE'] == treatmentCode) {





          final id = t['ID'] ?? t['id'];





          if (id is int) return id;





          if (id is String) return int.tryParse(id);





        }





      }





    }





    return null;





  }











  /// Parse treatment ID từ response (lấy đầu tiên)





  int? _parseTreatmentId(dynamic r) {





    if (r == null || !r.success || r.data is! Map) return null;





    final d = r.data as Map;





    if (d['Success'] != true) return null;





    final data = d['Data'];





    if (data is List && data.isNotEmpty) {





      final t = data.first;





      if (t is Map) {





        final id = t['ID'] ?? t['id'];





        if (id is int) return id;





        if (id is String) return int.tryParse(id);





      }





    }





    return null;





  }











  int? get _departmentId {





    if (widget.department['deptId'] is int) return widget.department['deptId'];





    if (widget.department['id'] is int) return widget.department['id'];





    return int.tryParse(widget.department['id']?.toString() ?? '');





  }











  String? get _patientName =>





      (widget.patient['TDL_PATIENT_UNSIGNED_NAME'] ?? widget.patient['TDL_PATIENT_NAME'] ?? widget.patient['tdl_patient_name'] ?? '').toString();











  String? get _patientCode =>





      (widget.patient['TDL_PATIENT_CODE'] ??





              widget.patient['tdl_patient_code'] ??





              widget.patient['PATIENT_CODE'] ??





              '')





          .toString();











  String? get _treatmentCode =>





      (widget.patient['TDL_TREATMENT_CODE'] ??





              widget.patient['treatment_code'] ??





              '')





          .toString();











  String _getUsername() =>





      ThongkeAuthService.instance.currentUsername ?? 'mobile_user';











  /// v2.98.7: Chọn tất cả CLS (load từ HisCatalogService)





  /// Lấy tất cả dịch vụ đã cache (Xét nghiệm, CDHA, Thủ thuật) - không qua API





  Future<void> _selectAllCls() async {





    if (_loadingAllCls) return;





    setState(() => _loadingAllCls = true);





    try {





      // Lấy tất cả services (giới hạn 500 để tránh quá tải)





      final all = HisCatalogService.instance.searchServices('', limit: 500);





      setState(() {





        _selectedServices





          ..clear()





          ..addAll(all);





        _loadingAllCls = false;





      });





      if (mounted) {





        ScaffoldMessenger.of(context).showSnackBar(





          SnackBar(





            content: Text('Đã chọn tất cả ${all.length} CLS (Xét nghiệm, CDHA, Thủ thuật)'),





            backgroundColor: Colors.teal.shade700,





            duration: const Duration(seconds: 2),





          ),





        );





      }





    } catch (e) {





      setState(() => _loadingAllCls = false);





      if (mounted) {





        ScaffoldMessenger.of(context).showSnackBar(





          SnackBar(content: Text('Lỗi chọn tất cả CLS: $e')),





        );





      }





    }





  }











  // =================================================================
  // PDF GENERATION v3.0.143 (TNKeyUni font - SCAN PHIEU pattern)
  // =================================================================
  Future<void> _ensurePdfFonts() async {
    if (_pdfFont != null) return;
    try {
      final fd = await rootBundle.load('assets/fonts/times.ttf');
      final bd = await rootBundle.load('assets/fonts/timesbd.ttf');
      _pdfFont = pw.Font.ttf(fd.buffer.asByteData()!);
      _pdfFontBold = pw.Font.ttf(bd.buffer.asByteData()!);
    } catch (e) {
      debugPrint('TNKeyUni font error: $e');
      _pdfFont = pw.Font.helvetica();
      _pdfFontBold = pw.Font.helveticaBold();
    }
  }

  pw.TextStyle _s(double sz, {bool bold = false, PdfColor? color, pw.FontStyle fs = pw.FontStyle.normal}) {
    return pw.TextStyle(
      font: bold ? (_pdfFontBold ?? _pdfFont) : _pdfFont,
      fontSize: sz,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color, fontStyle: fs,
    );
  }

  Future<Uint8List> _buildPdf({Uint8List? signatureBytes}) async {
    await _ensurePdfFonts();
    final now = DateTime.now();
    final tCode = _treatmentCode ?? '';
    final pName = _patientName ?? '';
    final user = _getUsername();
    final cls = _selectedServices.take(20).map((s) => '  - ' + (s.code ?? '') + ' - ' + (s.name ?? '')).join('\n');
    final meds = _medicines.take(20).map((m) => '  - ' + (m.medicine.name ?? '') + ' (' + m.amountPerDose.toString() + ' ' + m.route + ') x' + m.timesPerDay.toString() + ' lan').join('\n');
    final icd = _icdValues.isNotEmpty ? _icdValues.first.code + ' - ' + _icdValues.first.name : 'Z00.0 - Kham benh';
    final lyDo = _lyDoCtrl.text.isEmpty ? '(...)' : _lyDoCtrl.text;
    final gc = _ghiChuCtrl.text.isEmpty ? '(...)' : _ghiChuCtrl.text;
    final m = _machCtrl.text.isEmpty ? '(...)' : _machCtrl.text;
    final n = _nhietCtrl.text.isEmpty ? '(...)' : _nhietCtrl.text;
    final ha1 = _hhaTTCtrl.text.isEmpty ? '(...)' : _hhaTTCtrl.text;
    final ha2 = _hhaTDCtrl.text.isEmpty ? '(...)' : _hhaTDCtrl.text;
    final sp = _spo2Ctrl.text.isEmpty ? '(...)' : _spo2Ctrl.text;
    final date = now.day.toString().padLeft(2,'0') + '/' + now.month.toString().padLeft(2,'0') + '/' + now.year.toString();
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: _pdfFont));
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SO Y TE TINH KHANH HOA', style: _s(11, bold: true)),
                pw.Text('BENH VIEN DA KHOA NINH THUAN', style: _s(11, bold: true)),
                pw.SizedBox(height: 4),
                pw.Text('Khoa Cap Cuu', style: _s(10)),
              ],
            )),
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('CONG HOA XA HOI CHU NGHIA VIET NAM', style: _s(10, bold: true)),
                pw.Text('Doc lap - Tu do - Hanh phuc', style: _s(10, fs: pw.FontStyle.italic)),
              ],
            )),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('PHIEU KHAM BENH', style: _s(14, bold: true, color: PdfColors.purple900))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('MS: 01/BV2', style: _s(10, fs: pw.FontStyle.italic))),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all()),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('I. THONG TIN BENH NHAN', style: _s(11, bold: true, color: PdfColors.purple900)),
              pw.SizedBox(height: 4),
              pw.Row(children: [
                pw.Text('So vao vien: ', style: _s(11)),
                pw.Text(tCode.isEmpty ? '(...)' : tCode, style: _s(11, bold: true)),
                pw.SizedBox(width: 20),
                pw.Text('Ho ten: ', style: _s(11)),
                pw.Text(pName.isEmpty ? '(...)' : pName, style: _s(11, bold: true)),
              ]),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all()),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('II. SINH HIEU', style: _s(11, bold: true, color: PdfColors.purple900)),
              pw.SizedBox(height: 4),
              pw.Text('Mach: $m l/p  |  Nhiet: $n C  |  HA: $ha1/$ha2 mmHg  |  SpO2: $sp%', style: _s(10)),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all()),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('III. KHAM BENH', style: _s(11, bold: true, color: PdfColors.purple900)),
              pw.SizedBox(height: 4),
              pw.Text('Ly do: $lyDo', style: _s(11)),
              pw.SizedBox(height: 2),
              pw.Text('Chan doan: $icd', style: _s(11, bold: true)),
              pw.SizedBox(height: 2),
              pw.Text('Ghi chu: $gc', style: _s(11)),
            ],
          ),
        ),
        if (_selectedServices.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('IV. CHI DINH CLS (' + _selectedServices.length.toString() + ' dv)', style: _s(11, bold: true, color: PdfColors.purple900)),
                pw.SizedBox(height: 4),
                pw.Text(cls.isEmpty ? '(...)' : cls, style: _s(9)),
              ],
            ),
          ),
        ],
        if (_medicines.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('V. DON THUOC (' + _medicines.length.toString() + ' thuoc)', style: _s(11, bold: true, color: PdfColors.purple900)),
                pw.SizedBox(height: 4),
                pw.Text(meds.isEmpty ? '(...)' : meds, style: _s(9)),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 20),
        pw.Row(children: [
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Text(date, style: _s(10)),
            pw.SizedBox(height: 4),
            pw.Text('Bac si kham', style: _s(10, fs: pw.FontStyle.italic)),
            pw.SizedBox(height: 30),
            if (signatureBytes != null)
              pw.Container(height: 60, width: 150, child: pw.Image(pw.MemoryImage(signatureBytes), height: 60, fit: pw.BoxFit.contain))
            else
              pw.Container(height: 60, width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
            pw.SizedBox(height: 2),
            pw.Text(user, style: _s(9, bold: true)),
          ]),
        ]),
      ],
    ));
    return pdf.save();
  }

  /// Build content for HIS Tracking (mô tả sinh hiệu)





  String _buildTrackingContent() {





    final parts = <String>[];





    final m = _machCtrl.text.trim();





    final n = _nhietCtrl.text.trim();





    final tt = _hhaTTCtrl.text.trim();





    final td = _hhaTDCtrl.text.trim();





    final s = _spo2Ctrl.text.trim();











    if (m.isNotEmpty) parts.add('Mạch: $m l/p');





    if (n.isNotEmpty) parts.add('Nhiệt: $n°C');





    if (tt.isNotEmpty && td.isNotEmpty) parts.add('HA: $tt/$td mmHg');





    if (s.isNotEmpty) parts.add('SpO₂: $s%');





    if (_lyDoCtrl.text.isNotEmpty) parts.add('Lý do: ${_lyDoCtrl.text}');





    // v2.98.5: Lấy ICD đầu tiên từ _icdValues (IcdInputField)





    if (_icdValues.isNotEmpty) {





      final icd = _icdValues.first;





      parts.add('Chẩn đoán: ${icd.code.isNotEmpty ? icd.code : "?"} - ${icd.name.isNotEmpty ? icd.name : "?"}');





    }





    return parts.join(' • ');





  }











  bool _formValid() {





    // v2.98.7: ICD chính - check từ _icdValues (IcdInputField)





    // KHÔNG bắt buộc CLS - cho phép lưu khi không có cận lâm sàng





    if (_icdValues.isEmpty) return false;





    return true;





  }











  /// v3.0.0: 3 chế độ - Lưu / Lưu chưa ký / Lưu ký





  /// - pushEmr=false: chỉ lưu local





  /// - pushEmr=true, forceSigned=false: lưu + đẩy EMR unsigned





  /// - pushEmr=true, forceSigned=true: lưu + ký + đẩy EMR (auto-sign nếu chưa vẽ)





  /// v3.0.1: Nếu thiếu treatment_id → tự fetch từ treatmentCode qua HIS Pro





  /// v3.0.46: Thêm useVnptSignature=true → ký PKCS#7 qua VNPT SmartCA





  Future<void> _save({bool pushEmr = false, bool forceSigned = false, bool useVnptSignature = false}) async {





    if (_saving) return;





    if (!_formValid()) {





      _snack('Vui lòng chọn ICD chính (CLS không bắt buộc)');





      return;





    }





    int? tid = _treatmentId;





    // v3.0.1: Nếu chưa có tid, fetch từ treatmentCode





    if (tid == null) {





      final tc = _treatmentCode ?? '';





      if (tc.isNotEmpty) {





        _snack('Đang lấy TREATMENT_ID từ HIS Pro...', color: Colors.blue);





        tid = await _fetchTreatmentIdFromCode(tc);





        if (tid != null) {





          setState(() {





            widget.patient['TREATMENT_ID'] = tid;  // cache lại





          });





        }





      }





    }





    if (tid == null) {





      _snack('Không lấy được TREATMENT_ID (chọn lại BN hoặc kiểm tra VPN)');





      return;





    }





    setState(() {





      _saving = true;





      _result = null;





    });





    try {





      final results = <String>[];





      // 1. Save Service Reqs (CLS)





      results.add('Đang tạo ${_selectedServices.length} phiếu CLS...');





      final clsResults = await HisServiceReqService.instance.createKhamPhieu(





        treatmentId: tid,





        requestLoginname: 'nemk',





        requestUsername: _getUsername(),





        primaryIcdCodes: [





          if (_icdValues.isNotEmpty && _icdValues.first.code.isNotEmpty) _icdValues.first.code





          else 'Z00.0'





        ],





        selectedServices: _selectedServices,





        instructionNote: _ghiChuCtrl.text.isNotEmpty ? _ghiChuCtrl.text : _lyDoCtrl.text,





      );





      final successCls = clsResults.where((r) => r.success).toList();





      results.add('CLS: ${successCls.length}/${clsResults.length} OK');





      if (successCls.isNotEmpty) {





        results.add('Mã: ${successCls.take(8).map((r) => r.serviceReqCode).join(", ")}');





      }











      // 2. Tracking (sinh hiệu + ICD + lý do)





      if (_machCtrl.text.isNotEmpty || _nhietCtrl.text.isNotEmpty ||





          _hhaTTCtrl.text.isNotEmpty || _spo2Ctrl.text.isNotEmpty) {





        results.add('Đang lưu sinh hiệu...');





        final tr = await HisTrackingService.instance.createTracking(





          TrackingInput(





            treatmentId: tid,





            departmentId: _departmentId ?? 22,





            roomId: 36,  // PKCC - v3.0.105: ROOM_ID thật = 36 (từ log HIS Pro)





            trackingType: 1, // NHẬP VIỆN/KHÁM





            content: _buildTrackingContent(),





            icdCode: _icdValues.isNotEmpty && _icdValues.first.code.isNotEmpty





                ? _icdValues.first.code





                : 'Z00.0',





            icdName: _icdValues.isNotEmpty && _icdValues.first.name.isNotEmpty





                ? _icdValues.first.name





                : 'Khám bệnh',





            trackingTime: DateTime.now(),





            pulsel: double.tryParse(_machCtrl.text),





            temperature: double.tryParse(_nhietCtrl.text),





            systolic: double.tryParse(_hhaTTCtrl.text),





            diastolic: double.tryParse(_hhaTDCtrl.text),





            spo2: double.tryParse(_spo2Ctrl.text),





          ),





        );





        results.add(tr.success ? 'Theo dõi: OK (ID=${tr.id})' : 'Theo dõi: ${tr.error}');





      }











      // 3. v3.0.22: EMR push theo mode (dùng PhieuSaveService thống nhất)





      if (pushEmr) {





        if (forceSigned) {





          results.add('Đang ký + đẩy EMR...');





        } else {





          results.add('Đang đẩy EMR (chưa ký)...');





        }





        try {





          // v3.0.22: Lấy signature (user vẽ hoặc auto-gen) cho mode signed





          String? signaturePath;  // kept for backward compat (unused when prebuiltPdfBytes used)
          Uint8List? signatureBytes;





          if (forceSigned) {





            final dir = await getTemporaryDirectory();





            final sigFile = File('${dir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');





            final sigBytes = await _sigCtrl.toPngBytes();





            if (sigBytes == null || sigBytes.isEmpty) {





              final autoBytes = await _generateAutoSignatureBytes();





              if (autoBytes == null || autoBytes.isEmpty) {





                throw Exception('Không tạo được chữ ký tự động');





              }





              signatureBytes = autoBytes;





            } else {





              signatureBytes = sigBytes;





            }





            signaturePath = sigFile.path;





          }











          // Build formData cho PDF





          final formData = <String, dynamic>{





            'sinh_hieu': 'Mạch: ${_machCtrl.text}, Nhiệt: ${_nhietCtrl.text}°C, HHA: ${_hhaTTCtrl.text}/${_hhaTDCtrl.text}, SpO2: ${_spo2Ctrl.text}%',





            'icd_chinh': _icdValues.isNotEmpty ? _icdValues.first.name : 'Khám bệnh',





            'icd_code': _icdValues.isNotEmpty ? _icdValues.first.code : 'Z00.0',





            'ly_do': _lyDoCtrl.text,





            'ghi_chu': _ghiChuCtrl.text,





            'cls_count': _selectedServices.length,





            'cls_list': _selectedServices.take(8).map((s) => s.name).join(', '),





            'bs': _getUsername(),





            'ngay_tao': DateTime.now().toString().substring(0, 19),





          };











          // Gọi PhieuSaveService thống nhất





          // v3.0.143: Build PDF with TNKeyUni font
          final pdfBytes = await _buildPdf(signatureBytes: signatureBytes);

          final result = await PhieuSaveService.instance.save(





            mode: forceSigned ? PhieuSaveMode.signed : PhieuSaveMode.unsigned,





            input: PhieuSaveInput(






              patient: widget.patient,





              formName: 'Phiếu khám - ${_patientCode}_${DateTime.now().millisecondsSinceEpoch}',





              formData: const {},
              prebuiltPdfBytes: pdfBytes,










              documentTypeId: 2,










              roomCode: 'PKCC',





              roomTypeCode: 'XL',





              departmentCode: 'HSCC',





              workingDeptName: 'Khoa Cấp Cứu',





            ),





          );











          // Cleanup signature temp





          if (signaturePath != null) {





            final sigFile = File(signaturePath);





            if (await sigFile.exists()) await sigFile.delete();





          }











          if (result.emrPushed) {





            results.add(forceSigned





                ? 'EMR: ✅ push + ký thành công (${result.documentCode})'





                : 'EMR: ✅ push thành công (chưa ký) (${result.documentCode})');





          } else if (result.success) {





            results.add('EMR: ⚠ fail (${result.error}) - PDF giữ tại ${result.tempPdfPath}');





          } else {





            results.add('EMR: ❌ ${result.error}');





          }





        } catch (e) {





          results.add('EMR: lỗi $e');





        }





      }











      if (mounted) {





        setState(() {





          _result = results.join('\n');





        });





        _snack('Phiếu khám: ${successCls.length} CLS OK');





      }





    } catch (e) {





      _snack('Lỗi: $e', color: Colors.red);





      if (mounted) {





        setState(() {





          _result = '❌ Lỗi: $e';





        });





      }





    } finally {





      if (mounted) setState(() => _saving = false);





    }





  }











  /// v3.0.22: _pushSignatureToEmr cũ đã bỏ - giờ dùng PhieuSaveService trực tiếp trong _save()











  /// v2.98.7: Tự tạo signature text-based (PNG) - vẽ text "Đã ký bởi..." lên canvas





  /// Dùng khi user bấm "Ký" mà chưa vẽ signature tay





  Future<Uint8List?> _generateAutoSignatureBytes() async {





    try {





      // vẽ lên Canvas





      final recorder = ui.PictureRecorder();





      final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, 400, 150));





      // Nền trắng





      canvas.drawRect(Rect.fromLTWH(0, 0, 400, 150), Paint()..color = Colors.white);





      // Viền đen





      canvas.drawRect(





        Rect.fromLTWH(0, 0, 400, 150),





        Paint()





          ..color = Colors.black87





          ..style = PaintingStyle.stroke





          ..strokeWidth = 1.5,





      );





      // Text "Đã ký bởi: [username]"





      final username = _getUsername();





      final now = DateTime.now();





      final timeStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '





          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';





      final tp1 = TextPainter(





        text: TextSpan(





          text: 'Đã ký bởi: $username',





          style: const TextStyle(





            color: Colors.black,





            fontSize: 16,





            fontStyle: FontStyle.italic,





            fontWeight: FontWeight.w600,





          ),





        ),





        textDirection: TextDirection.ltr,





      )..layout(maxWidth: 380);





      tp1.paint(canvas, const Offset(10, 30));





      // Text ngày giờ





      final tp2 = TextPainter(





        text: TextSpan(





          text: 'Lúc: $timeStr',





          style: const TextStyle(color: Colors.black54, fontSize: 12),





        ),





        textDirection: TextDirection.ltr,





      )..layout(maxWidth: 380);





      tp2.paint(canvas, const Offset(10, 60));





      // Text "HIS Mobile - v2.98.7"





      final tp3 = TextPainter(





        text: const TextSpan(





          text: 'HIS Mobile - Auto-signed',





          style: TextStyle(color: Colors.indigo, fontSize: 10, fontStyle: FontStyle.italic),





        ),





        textDirection: TextDirection.ltr,





      )..layout(maxWidth: 380);





      tp3.paint(canvas, const Offset(10, 110));











      final image = await recorder.endRecording().toImage(400, 150);





      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);





      return byteData?.buffer.asUint8List();





    } catch (e) {





      debugPrint('Lỗi tạo auto signature: $e');





      return null;





    }





  }











  void _snack(String msg, {Color color = Colors.green}) {





    if (!mounted) return;





    ScaffoldMessenger.of(context).showSnackBar(





      SnackBar(





        content: Text(msg),





        backgroundColor: color,





        behavior: SnackBarBehavior.floating,





        margin: const EdgeInsets.all(8),





        duration: const Duration(seconds: 3),





      ),





    );





  }











  @override





  Widget build(BuildContext context) {





    return Scaffold(





      appBar: AppBar(





        title: const Text('Tạo phiếu khám'),





        elevation: 0,





        backgroundColor: Colors.indigo,





        foregroundColor: Colors.white,





      ),





      body: SafeArea(





        child: Column(





          children: [





            _patientHeader(),





            Expanded(





              child: SingleChildScrollView(





                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),





                child: Column(





                  crossAxisAlignment: CrossAxisAlignment.start,





                  children: [





                    _sectionTitle('🌡️ Sinh hiệu', Icons.favorite),





                    _vitalSigns(),





                    const SizedBox(height: 16),





                    _sectionTitle('📝 Lý do khám', Icons.notes),





                    TextField(





                      controller: _lyDoCtrl,





                      maxLines: 2,





                      decoration: const InputDecoration(





                        hintText: 'Đau ngực, khó thở, ...',





                        border: OutlineInputBorder(),





                        isDense: true,





                      ),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('🔍 Chẩn đoán ICD chính', Icons.assignment),





                    // v2.98.5: Dùng IcdInputField widget dùng chung (chuẩn hóa)





                    IcdInputField(





                      fieldKey: 'CHAN_DOAN_CHINH',





                      label: 'Chẩn đoán ICD',





                      required: true,





                      multiSelect: false,





                      initialValues: const [],





                      onChanged: (values) {





                        setState(() {





                          _icdValues





                            ..clear()





                            ..addAll(values);





                        });





                      },





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('🩺 Chỉ định Cận lâm sàng', Icons.medical_services),





                    // v2.98.7: Nút chọn tất cả CLS + đếm số đã chọn





                    Row(





                      children: [





                        Expanded(





                          child: Text(





                            'Bao gồm: XN máu, X-quang, SA, Điện tim, Nội soi... (${_selectedServices.length} đã chọn)',





                            style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontStyle: FontStyle.italic),





                            maxLines: 2, overflow: TextOverflow.ellipsis,





                          ),





                        ),





                        const SizedBox(width: 4),





                        if (_selectedServices.isEmpty)





                          FilledButton.tonalIcon(





                            onPressed: _loadingAllCls ? null : _selectAllCls,





                            icon: _loadingAllCls





                              ? const SizedBox(





                                  width: 12, height: 12,





                                  child: CircularProgressIndicator(strokeWidth: 1.5),





                                )





                              : const Icon(Icons.select_all, size: 14),





                            label: const Text('Chọn tất cả', style: TextStyle(fontSize: 10)),





                            style: FilledButton.styleFrom(





                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),





                              minimumSize: const Size(0, 28),





                            ),





                          )





                        else





                          TextButton.icon(





                            onPressed: () => setState(() => _selectedServices.clear()),





                            icon: const Icon(Icons.clear, size: 14, color: Colors.red),





                            label: Text('Xoá (${_selectedServices.length})', style: const TextStyle(fontSize: 10, color: Colors.red)),





                            style: TextButton.styleFrom(





                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),





                              minimumSize: const Size(0, 28),





                            ),





                          ),





                      ],





                    ),





                    const SizedBox(height: 4),





                    CatalogPicker(





                      type: CatalogPickerType.service,





                      title: 'CLS (Xét nghiệm, CDHA, Thủ thuật)',





                      hintText: 'Tìm CLS (XN máu, X-quang, SA tim...)',





                      selected: _selectedServices,





                      multiSelect: true,





                      maxSelect: 30,





                      onChanged: (list) => setState(() {





                        _selectedServices.clear();





                        _selectedServices.addAll(list);





                      }),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('💊 Đơn thuốc', Icons.medication),





                    MedicineSelector(





                      items: _medicines,





                      onChanged: (list) => setState(() {





                        _medicines.clear();





                        _medicines.addAll(list);





                      }),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('📋 Ghi chú (tùy chọn)', Icons.edit_note),





                    TextField(





                      controller: _ghiChuCtrl,





                      maxLines: 3,





                      decoration: const InputDecoration(





                        hintText: 'Ghi chú thêm cho phiếu...',





                        border: OutlineInputBorder(),





                        isDense: true,





                      ),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('✍️ Ký số (tùy chọn - cho EMR)', Icons.draw),





                    Container(





                      height: 150,





                      decoration: BoxDecoration(





                        color: Colors.grey.shade50,





                        border: Border.all(color: Colors.grey.shade300),





                        borderRadius: BorderRadius.circular(8),





                      ),





                      child: ClipRRect(





                        borderRadius: BorderRadius.circular(7),





                        child: Signature(





                          controller: _sigCtrl,





                          backgroundColor: Colors.white,





                        ),





                      ),





                    ),





                    Row(





                      children: [





                        TextButton.icon(





                          onPressed: () => _sigCtrl.clear(),





                          icon: const Icon(Icons.clear, size: 16),





                          label: const Text('Xóa chữ ký'),





                        ),





                        const Spacer(),





                        Container(





                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),





                          decoration: BoxDecoration(





                            color: _sigCtrl.isNotEmpty ? Colors.green.shade100 : Colors.grey.shade200,





                            borderRadius: BorderRadius.circular(8),





                          ),





                          child: Text(





                            _sigCtrl.isNotEmpty ? '✅ Đã ký' : 'Chưa ký',





                            style: TextStyle(





                              fontSize: 11,





                              color: _sigCtrl.isNotEmpty ? Colors.green.shade800 : Colors.grey,





                              fontWeight: FontWeight.w500,





                            ),





                          ),





                        ),





                      ],





                    ),





                    if (_result != null) ...[





                      const SizedBox(height: 16),





                      Container(





                        padding: const EdgeInsets.all(12),





                        decoration: BoxDecoration(





                          color: _result!.startsWith('❌')





                              ? Colors.red.shade50





                              : Colors.green.shade50,





                          borderRadius: BorderRadius.circular(8),





                          border: Border.all(





                            color: _result!.startsWith('❌')





                                ? Colors.red.shade300





                                : Colors.green.shade300,





                          ),





                        ),





                        child: Text(





                          _result!,





                          style: TextStyle(





                            color: _result!.startsWith('❌')





                                ? Colors.red.shade900





                                : Colors.green.shade900,





                            fontSize: 13,





                            fontFamily: 'monospace',





                          ),





                        ),





                      ),





                    ],





                  ],





                ),





              ),





            ),





          ],





        ),





      ),





      bottomNavigationBar: SafeArea(





        child: Container(





          color: Colors.white,





          padding: const EdgeInsets.all(12),





          // v3.0.46: 3 nút - [Lưu] [Lưu ký] [Ký VNPT SmartCA] theo mẫu Bàn giao BN





          child: Column(





            mainAxisSize: MainAxisSize.min,





            children: [





              Row(





                children: [





                  Expanded(





                    child: OutlinedButton.icon(





                      onPressed: _saving ? null : () => _save(pushEmr: false),





                      icon: const Icon(Icons.save, size: 16),





                      label: const Text('Lưu', style: TextStyle(fontSize: 12)),





                      style: OutlinedButton.styleFrom(





                        foregroundColor: Colors.indigo,





                        side: const BorderSide(color: Colors.indigo, width: 1.5),





                        padding: const EdgeInsets.symmetric(vertical: 12),





                      ),





                    ),





                  ),





                  const SizedBox(width: 4),





                  Expanded(





                    child: FilledButton.icon(





                      onPressed: _saving ? null : () => _save(pushEmr: true, forceSigned: true),





                      icon: const Icon(Icons.draw, size: 16),





                      label: const Text('Lưu ký', style: TextStyle(fontSize: 12)),





                      style: FilledButton.styleFrom(





                        backgroundColor: Colors.green.shade700,





                        padding: const EdgeInsets.symmetric(vertical: 12),





                      ),





                    ),





                  ),





                ],





              ),





              const SizedBox(height: 6),





              // v3.0.46: Nút Ký VNPT SmartCA - ký PKCS#7 thật qua app VNPT





              SizedBox(





                  width: double.infinity,





                  child: FilledButton.tonalIcon(





                    icon: const Icon(Icons.verified, size: 16),





                    label: const Text('Ký VNPT SmartCA', style: TextStyle(fontSize: 12)),





                    style: FilledButton.styleFrom(





                      backgroundColor: Colors.purple.shade50,





                      foregroundColor: Colors.purple.shade800,





                      padding: const EdgeInsets.symmetric(vertical: 10),





                    ),





                    onPressed: _saving ? null : () => _save(pushEmr: true, forceSigned: true, useVnptSignature: true),





                  ),





                ),





            ],





          ),





        ),





      ),





    );





  }











  /// Build 5 vital signs inputs (mạch/nhiệt/HHA TT-TD/SpO2)





  Widget _vitalSigns() {





    return Container(





      padding: const EdgeInsets.all(12),





      decoration: BoxDecoration(





        color: Colors.red.shade50,





        borderRadius: BorderRadius.circular(8),





        border: Border.all(color: Colors.red.shade100),





      ),





      child: Column(





        children: [





          Row(





            children: [





              Expanded(child: _vitalField(_machCtrl, 'Mạch', 'l/p')),





              const SizedBox(width: 8),





              Expanded(child: _vitalField(_nhietCtrl, 'Nhiệt', '°C')),





              const SizedBox(width: 8),





              Expanded(child: _vitalField(_spo2Ctrl, 'SpO₂', '%')),





            ],





          ),





          const SizedBox(height: 8),





          Row(





            children: [





              Expanded(flex: 2, child: _vitalField(_hhaTTCtrl, 'HA Tâm thu', 'mmHg')),





              const SizedBox(width: 8),





              Expanded(flex: 2, child: _vitalField(_hhaTDCtrl, 'HA Tâm trương', 'mmHg')),





              const Spacer(),





            ],





          ),





        ],





      ),





    );





  }











  Widget _vitalField(TextEditingController ctrl, String label, String unit) {





    return TextField(





      controller: ctrl,





      keyboardType: TextInputType.number,





      textAlign: TextAlign.center,





      decoration: InputDecoration(





        labelText: label,





        hintText: unit,





        border: const OutlineInputBorder(),





        isDense: true,





        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),





        suffixIcon: Padding(





          padding: const EdgeInsets.only(left: 4, right: 4, top: 12),





          child: Text(unit, style: const TextStyle(fontSize: 9, color: Colors.grey)),





        ),





        suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),





      ),





      style: const TextStyle(fontSize: 13),





    );





  }











  Widget _patientHeader() {





    final icd = widget.patient['ICD_NAME'] ?? widget.patient['icd_name'];





    return Container(





      width: double.infinity,





      padding: const EdgeInsets.all(12),





      color: Colors.indigo.shade50,





      child: Column(





        crossAxisAlignment: CrossAxisAlignment.start,





        children: [





          Text(





            _patientName ?? '—',





            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),





          ),





          const SizedBox(height: 4),





          Text(





            'Mã ĐT: ${_treatmentCode ?? '—'} | Mã BN: ${_patientCode ?? '—'}',





            style: const TextStyle(fontSize: 12, color: Colors.grey),





          ),





          if (icd != null && icd.toString().isNotEmpty)





            Padding(





              padding: const EdgeInsets.only(top: 4),





              child: Container(





                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),





                decoration: BoxDecoration(





                  color: Colors.orange.shade100,





                  borderRadius: BorderRadius.circular(4),





                ),





                child: Text(





                  'ICD cũ: ${icd}',





                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.w500),





                ),





              ),





            ),





        ],





      ),





    );





  }











  /// v2.98.5: Widget _buildIcdInputField cũ đã xóa - dùng IcdInputField widget dùng chung











  Widget _sectionTitle(String text, IconData icon) {





    return Padding(





      padding: const EdgeInsets.only(bottom: 8),





      child: Row(





        children: [





          Icon(icon, size: 16, color: Colors.indigo),





          const SizedBox(width: 6),





          Text(





            text,





            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.indigo),





          ),





        ],





      ),





    );





  }











  @override





  void dispose() {





    _machCtrl.dispose();





    _nhietCtrl.dispose();





    _hhaTTCtrl.dispose();





    _hhaTDCtrl.dispose();





    _spo2Ctrl.dispose();





    _lyDoCtrl.dispose();





    _ghiChuCtrl.dispose();





    _sigCtrl.dispose();





    super.dispose();





  }





}





