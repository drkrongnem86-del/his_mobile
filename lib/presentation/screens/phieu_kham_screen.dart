// PhieuKhamScreen.dart v2.55.0





// Workflow phiáº¿u khÃ¡m HOÃ€N CHá»ˆNH:





//   1. Sinh hiá»‡u (máº¡ch / nhiá»‡t / HHA / SpO2)





//   2. Cháº©n Ä‘oÃ¡n ICD chÃ­nh





//   3. Chá»‰ Ä‘á»‹nh Cáº­n lÃ¢m sÃ ng (CLS)





//   4. ÄÆ¡n thuá»‘c (liá»u/cÃ¡ch dÃ¹ng/sá»‘ ngÃ y)





//   5. Ghi chÃº





//   6. KÃ½ sá»‘ â†’ push EMR





//   7. Auto-create Tracking sau khÃ¡m





//





// Flow save:





//   1. Validate form





//   2. POST HisServiceReq/Update cho tá»«ng CLS





//   3. Náº¿u cÃ³ thuá»‘c â†’ POST HisPrescription/Create (TBD v2.55.1)





//   4. POST HisTracking/Update vá»›i content sinh hiá»‡u





//   5. Táº¡o EMR Document PDF â†’ push











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
import 'package:his_mobile/data/services/pdf_to_image_service.dart';





import 'package:his_mobile/data/services/treatment_id_cache.dart';





import 'package:his_mobile/presentation/screens/icd10_webview_screen.dart';





import 'package:his_mobile/presentation/widgets/catalog_picker.dart';





import 'package:his_mobile/presentation/widgets/icd_input_field.dart';





import 'package:his_mobile/presentation/widgets/medicine_selector.dart';











import 'package:his_mobile/core/security/credentials.dart';
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





  // v2.55.0: Sinh hiá»‡u





  final _machCtrl = TextEditingController();





  final _nhietCtrl = TextEditingController();





  final _hhaTTCtrl = TextEditingController();





  final _hhaTDCtrl = TextEditingController();





  final _spo2Ctrl = TextEditingController();











  // v2.55.0: Form fields





  final _lyDoCtrl = TextEditingController();





  final _ghiChuCtrl = TextEditingController();











  // v2.98.5: ICD dÃ¹ng IcdInputField widget (chuáº©n hÃ³a vá»›i Láº­p phiáº¿u khÃ¡c)





  // KhÃ´ng cáº§n controller riÃªng - IcdInputField tá»± quáº£n lÃ½





  // LÆ°u giÃ¡ trá»‹ ICD vÃ o _icdValues Ä‘á»ƒ dÃ¹ng cho save





  final List<IcdValue> _icdValues = [];











  // v2.55.0: Selections





  CatalogItem? _selectedIcd;





  final List<CatalogItem> _selectedServices = [];





  bool _loadingAllCls = false;  // v2.98.7: Loading state cho nÃºt "Chá»n táº¥t cáº£"





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





    // v3.0.32: Äáº£m báº£o catalog Ä‘Ã£ load - náº¿u chÆ°a cÃ³ data thÃ¬ trigger refresh





    _ensureCatalogLoaded();





  }











  /// v3.0.32: Äáº£m báº£o HisCatalogService Ä‘Ã£ load xong (trÃ¡nh case má»Ÿ mÃ n nhanh khi catalog chÆ°a ready)





  Future<void> _ensureCatalogLoaded() async {





    try {





      // Init (náº¿u chÆ°a) - sáº½ load cache + background refresh





      await HisCatalogService.instance.init();





      // Check náº¿u cáº£ 3 catalog trá»‘ng â†’ trigger refresh Ä‘á»“ng bá»™





      final empty = HisCatalogService.instance.isEmpty();





      if (empty) {





        debugPrint('Catalog empty â†’ force refresh');





        await HisCatalogService.instance.refreshAll();





      }





    } catch (e) {





      debugPrint('Catalog ensure error: $e');





    }





  }











  /// v3.0.1: tÃ¬m treatment ID tá»« nhiá»u nguá»“n (fix lá»—i "khÃ´ng cÃ³ TREATMENT_ID")





  int? get _treatmentId {





    // 1. Widget truyá»n vÃ o





    if (widget.treatmentId != null) return widget.treatmentId;





    // 2. Patient map (HIS Pro uppercase)





    final v1 = widget.patient['TREATMENT_ID'];





    if (v1 is int) return v1;





    if (v1 is String) {





      final i = int.tryParse(v1);





      if (i != null) return i;





    }





    // 3. ID thÆ°á»ng





    final v2 = widget.patient['id'];





    if (v2 is int) return v2;





    if (v2 is String) {





      final i = int.tryParse(v2);





      if (i != null) return i;





    }





    // 4. TreatmentCode (string) â†’ fetch tá»« HIS Pro





    // Náº¿u khÃ´ng cÃ³ sáºµn, _save() sáº½ tá»± fetch tá»« treatmentCode





    return null;





  }











  /// v3.0.1: Láº¥y treatment ID tá»« HIS Pro qua treatmentCode (náº¿u chÆ°a cÃ³)





  /// v3.0.7: Láº¥y treatment ID tá»« HIS Pro qua treatmentCode (náº¿u chÆ°a cÃ³)





  /// PHÃT HIá»†N Má»šI (2026-07-14 test Python):





  ///   - Filter `TREATMENT_CODE` (string) KHÃ”NG work trÃªn táº¥t cáº£ endpoint HIS Pro





  ///   - 3/4 endpoint (HisTreatment/Get 1408, HisServiceReq/GetLView, EmrDocument/GetView)





  ///     lÃ  DETAIL API, chá»‰ nháº­n filter `ID` (int) hoáº·c `TREATMENT_ID` (int)





  ///   - CHá»ˆ `EmrTreatment/Get 1417` LÃ€ LIST API - tráº£ 500 records khÃ´ng cáº§n filter





  ///   â†’ Workflow Ä‘Ãºng:





  ///     1. Gá»i EmrTreatment/Get 1417 vá»›i limit=500, KHÃ”NG filter





  ///     2. Scan list tÃ¬m record cÃ³ TREATMENT_CODE == code





  ///     3. Láº¥y ID tá»« record Ä‘Ã³





  ///     4. (Optional) Verify qua HisTreatment/Get 1408 vá»›i filter ID





  Future<int?> _fetchTreatmentIdFromCode(String treatmentCode) async {





    if (treatmentCode.isEmpty) return null;











    // Strategy 1: Cache





    try {





      await TreatmentIdCache.instance.load();





      final cached = TreatmentIdCache.instance.get(treatmentCode);





      if (cached != null) {





        debugPrint('âœ… _fetchTreatmentIdFromCode: cache HIT for $treatmentCode = $cached');





        return cached;





      }





    } catch (e) {





      debugPrint('Cache load error: $e');





    }











    final api = HisProApiService.instance;





    await api.refreshTokenIfNeeded();











    // Strategy 2: EMR /api/EmrTreatment/Get (1417) - LIST API duy nháº¥t





    // Gá»i KHÃ”NG filter (filter TREATMENT_CODE bá»‹ server bá» qua)





    // Scan 500 records tÃ¬m record cÃ³ TREATMENT_CODE = code





    try {





      final r = await api.get('${api.getEmrBaseUrlSync()}/api/EmrTreatment/Get', {





        'LOGIN_NAME': Credentials.defaultNemkLogin,





      }, limit: 500);





      final id = _findTreatmentIdInList(r, treatmentCode);





      if (id != null) {





        debugPrint('âœ… _fetchTreatmentIdFromCode: Got ID=$id from EMR EmrTreatment/Get (limit=500)');





        // Verify ID qua HisTreatment/Get 1408 (optional, náº¿u work thÃ¬ cÃ ng cháº¯c)





        try {





          final verify = await api.get('${api.getMosBaseUrlSync()}/api/HisTreatment/Get', {





            'ID': id,





          }, limit: 10);





          if (verify.success) {





            final d = verify.data is Map ? verify.data as Map : null;





            if (d != null && d['Data'] is List && (d['Data'] as List).isNotEmpty) {





              debugPrint('   âœ“ Verified via MOS 1408 HisTreatment/Get');





            }





          }





        } catch (e) {





          debugPrint('   âš  Verify qua MOS 1408 fail (khÃ´ng sao): $e');





        }





        await TreatmentIdCache.instance.set(treatmentCode, id);





        return id;





      }





    } catch (e) {





      debugPrint('EmrTreatment/Get (limit=500) error: $e');





    }











    debugPrint('âŒ _fetchTreatmentIdFromCode: No strategy worked for $treatmentCode (cÃ³ thá»ƒ ca cÅ© ngoÃ i 500 records)');





    return null;





  }











  /// TÃ¬m treatment ID trong list data (filter theo TREATMENT_CODE)





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











  /// Parse treatment ID tá»« response (láº¥y Ä‘áº§u tiÃªn)





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











  /// v2.98.7: Chá»n táº¥t cáº£ CLS (load tá»« HisCatalogService)





  /// Láº¥y táº¥t cáº£ dá»‹ch vá»¥ Ä‘Ã£ cache (XÃ©t nghiá»‡m, CDHA, Thá»§ thuáº­t) - khÃ´ng qua API





  Future<void> _selectAllCls() async {





    if (_loadingAllCls) return;





    setState(() => _loadingAllCls = true);





    try {





      // Láº¥y táº¥t cáº£ services (giá»›i háº¡n 500 Ä‘á»ƒ trÃ¡nh quÃ¡ táº£i)





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





            content: Text('ÄÃ£ chá»n táº¥t cáº£ ${all.length} CLS (XÃ©t nghiá»‡m, CDHA, Thá»§ thuáº­t)'),





            backgroundColor: Colors.teal.shade700,





            duration: const Duration(seconds: 2),





          ),





        );





      }





    } catch (e) {





      setState(() => _loadingAllCls = false);





      if (mounted) {





        ScaffoldMessenger.of(context).showSnackBar(





          SnackBar(content: Text('Lá»—i chá»n táº¥t cáº£ CLS: $e')),





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

  /// Build content for HIS Tracking (mÃ´ táº£ sinh hiá»‡u)





  String _buildTrackingContent() {





    final parts = <String>[];





    final m = _machCtrl.text.trim();





    final n = _nhietCtrl.text.trim();





    final tt = _hhaTTCtrl.text.trim();





    final td = _hhaTDCtrl.text.trim();





    final s = _spo2Ctrl.text.trim();











    if (m.isNotEmpty) parts.add('Máº¡ch: $m l/p');





    if (n.isNotEmpty) parts.add('Nhiá»‡t: $nÂ°C');





    if (tt.isNotEmpty && td.isNotEmpty) parts.add('HA: $tt/$td mmHg');





    if (s.isNotEmpty) parts.add('SpOâ‚‚: $s%');





    if (_lyDoCtrl.text.isNotEmpty) parts.add('LÃ½ do: ${_lyDoCtrl.text}');





    // v2.98.5: Láº¥y ICD Ä‘áº§u tiÃªn tá»« _icdValues (IcdInputField)





    if (_icdValues.isNotEmpty) {





      final icd = _icdValues.first;





      parts.add('Cháº©n Ä‘oÃ¡n: ${icd.code.isNotEmpty ? icd.code : "?"} - ${icd.name.isNotEmpty ? icd.name : "?"}');





    }





    return parts.join(' â€¢ ');





  }











  bool _formValid() {





    // v2.98.7: ICD chÃ­nh - check tá»« _icdValues (IcdInputField)





    // KHÃ”NG báº¯t buá»™c CLS - cho phÃ©p lÆ°u khi khÃ´ng cÃ³ cáº­n lÃ¢m sÃ ng





    if (_icdValues.isEmpty) return false;





    return true;





  }











  /// v3.0.0: 3 cháº¿ Ä‘á»™ - LÆ°u / LÆ°u chÆ°a kÃ½ / LÆ°u kÃ½





  /// - pushEmr=false: chá»‰ lÆ°u local





  /// - pushEmr=true, forceSigned=false: lÆ°u + Ä‘áº©y EMR unsigned





  /// - pushEmr=true, forceSigned=true: lÆ°u + kÃ½ + Ä‘áº©y EMR (auto-sign náº¿u chÆ°a váº½)





  /// v3.0.1: Náº¿u thiáº¿u treatment_id â†’ tá»± fetch tá»« treatmentCode qua HIS Pro





  /// v3.0.46: ThÃªm useVnptSignature=true â†’ kÃ½ PKCS#7 qua VNPT SmartCA





  Future<void> _save({bool pushEmr = false, bool forceSigned = false, bool useVnptSignature = false}) async {





    if (_saving) return;





    if (!_formValid()) {





      _snack('Vui lÃ²ng chá»n ICD chÃ­nh (CLS khÃ´ng báº¯t buá»™c)');





      return;





    }





    int? tid = _treatmentId;





    // v3.0.1: Náº¿u chÆ°a cÃ³ tid, fetch tá»« treatmentCode





    if (tid == null) {





      final tc = _treatmentCode ?? '';





      if (tc.isNotEmpty) {





        _snack('Äang láº¥y TREATMENT_ID tá»« HIS Pro...', color: Colors.blue);





        tid = await _fetchTreatmentIdFromCode(tc);





        if (tid != null) {





          setState(() {





            widget.patient['TREATMENT_ID'] = tid;  // cache láº¡i





          });





        }





      }





    }





    if (tid == null) {





      _snack('KhÃ´ng láº¥y Ä‘Æ°á»£c TREATMENT_ID (chá»n láº¡i BN hoáº·c kiá»ƒm tra VPN)');





      return;





    }





    setState(() {





      _saving = true;





      _result = null;





    });





    try {





      final results = <String>[];





      // 1. Save Service Reqs (CLS)





      results.add('Äang táº¡o ${_selectedServices.length} phiáº¿u CLS...');





      final clsResults = await HisServiceReqService.instance.createKhamPhieu(





        treatmentId: tid,





        requestLoginname: Credentials.defaultNemkLogin,





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





        results.add('MÃ£: ${successCls.take(8).map((r) => r.serviceReqCode).join(", ")}');





      }











      // 2. Tracking (sinh hiá»‡u + ICD + lÃ½ do)





      if (_machCtrl.text.isNotEmpty || _nhietCtrl.text.isNotEmpty ||





          _hhaTTCtrl.text.isNotEmpty || _spo2Ctrl.text.isNotEmpty) {





        results.add('Äang lÆ°u sinh hiá»‡u...');





        final tr = await HisTrackingService.instance.createTracking(





          TrackingInput(





            treatmentId: tid,





            departmentId: _departmentId ?? 22,





            roomId: 36,  // PKCC - v3.0.105: ROOM_ID tháº­t = 36 (tá»« log HIS Pro)





            trackingType: 1, // NHáº¬P VIá»†N/KHÃM





            content: _buildTrackingContent(),





            icdCode: _icdValues.isNotEmpty && _icdValues.first.code.isNotEmpty





                ? _icdValues.first.code





                : 'Z00.0',





            icdName: _icdValues.isNotEmpty && _icdValues.first.name.isNotEmpty





                ? _icdValues.first.name





                : 'KhÃ¡m bá»‡nh',





            trackingTime: DateTime.now(),





            pulsel: double.tryParse(_machCtrl.text),





            temperature: double.tryParse(_nhietCtrl.text),





            systolic: double.tryParse(_hhaTTCtrl.text),





            diastolic: double.tryParse(_hhaTDCtrl.text),





            spo2: double.tryParse(_spo2Ctrl.text),





          ),





        );





        results.add(tr.success ? 'Theo dÃµi: OK (ID=${tr.id})' : 'Theo dÃµi: ${tr.error}');





      }











      // 3. v3.0.22: EMR push theo mode (dÃ¹ng PhieuSaveService thá»‘ng nháº¥t)





      if (pushEmr) {





        if (forceSigned) {





          results.add('Äang kÃ½ + Ä‘áº©y EMR...');





        } else {





          results.add('Äang Ä‘áº©y EMR (chÆ°a kÃ½)...');





        }





        try {





          // v3.0.22: Láº¥y signature (user váº½ hoáº·c auto-gen) cho mode signed





          String? signaturePath;  // kept for backward compat (unused when prebuiltPdfBytes used)
          Uint8List? signatureBytes;





          if (forceSigned) {





            final dir = await getTemporaryDirectory();





            final sigFile = File('${dir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');





            final sigBytes = await _sigCtrl.toPngBytes();





            if (sigBytes == null || sigBytes.isEmpty) {





              final autoBytes = await _generateAutoSignatureBytes();





              if (autoBytes == null || autoBytes.isEmpty) {





                throw Exception('KhÃ´ng táº¡o Ä‘Æ°á»£c chá»¯ kÃ½ tá»± Ä‘á»™ng');





              }





              signatureBytes = autoBytes;





            } else {





              signatureBytes = sigBytes;





            }





            signaturePath = sigFile.path;





          }











          // Build formData cho PDF





          final formData = <String, dynamic>{





            'sinh_hieu': 'Máº¡ch: ${_machCtrl.text}, Nhiá»‡t: ${_nhietCtrl.text}Â°C, HHA: ${_hhaTTCtrl.text}/${_hhaTDCtrl.text}, SpO2: ${_spo2Ctrl.text}%',





            'icd_chinh': _icdValues.isNotEmpty ? _icdValues.first.name : 'KhÃ¡m bá»‡nh',





            'icd_code': _icdValues.isNotEmpty ? _icdValues.first.code : 'Z00.0',





            'ly_do': _lyDoCtrl.text,





            'ghi_chu': _ghiChuCtrl.text,





            'cls_count': _selectedServices.length,





            'cls_list': _selectedServices.take(8).map((s) => s.name).join(', '),





            'bs': _getUsername(),





            'ngay_tao': DateTime.now().toString().substring(0, 19),





          };











          // Gá»i PhieuSaveService thá»‘ng nháº¥t





          // v3.0.143: Build PDF with TNKeyUni font
          // v3.0.145: Render PDF -> PNG -> EMR (font trÃªn server khong garble)
          final pdfBytes = await _buildPdf(signatureBytes: signatureBytes);
          final pngBytes = await PdfToImageService.pdfToPngPdf(pdfBytes);

          final result = await PhieuSaveService.instance.save(





            mode: forceSigned ? PhieuSaveMode.signed : PhieuSaveMode.unsigned,





            input: PhieuSaveInput(






              patient: widget.patient,





              formName: 'Phiáº¿u khÃ¡m - ${_patientCode}_${DateTime.now().millisecondsSinceEpoch}',





              formData: const {},
              prebuiltPdfBytes: pngBytes ?? pdfBytes,










              documentTypeId: 2,










              roomCode: 'PKCC',





              roomTypeCode: 'XL',





              departmentCode: 'HSCC',





              workingDeptName: 'Khoa Cáº¥p Cá»©u',





            ),





          );











          // Cleanup signature temp





          if (signaturePath != null) {





            final sigFile = File(signaturePath);





            if (await sigFile.exists()) await sigFile.delete();





          }











          if (result.emrPushed) {





            results.add(forceSigned





                ? 'EMR: âœ… push + kÃ½ thÃ nh cÃ´ng (${result.documentCode})'





                : 'EMR: âœ… push thÃ nh cÃ´ng (chÆ°a kÃ½) (${result.documentCode})');





          } else if (result.success) {





            results.add('EMR: âš  fail (${result.error}) - PDF giá»¯ táº¡i ${result.tempPdfPath}');





          } else {





            results.add('EMR: âŒ ${result.error}');





          }





        } catch (e) {





          results.add('EMR: lá»—i $e');





        }





      }











      if (mounted) {





        setState(() {





          _result = results.join('\n');





        });





        _snack('Phiáº¿u khÃ¡m: ${successCls.length} CLS OK');





      }





    } catch (e) {





      _snack('Lá»—i: $e', color: Colors.red);





      if (mounted) {





        setState(() {





          _result = 'âŒ Lá»—i: $e';





        });





      }





    } finally {





      if (mounted) setState(() => _saving = false);





    }





  }











  /// v3.0.22: _pushSignatureToEmr cÅ© Ä‘Ã£ bá» - giá» dÃ¹ng PhieuSaveService trá»±c tiáº¿p trong _save()











  /// v2.98.7: Tá»± táº¡o signature text-based (PNG) - váº½ text "ÄÃ£ kÃ½ bá»Ÿi..." lÃªn canvas





  /// DÃ¹ng khi user báº¥m "KÃ½" mÃ  chÆ°a váº½ signature tay





  Future<Uint8List?> _generateAutoSignatureBytes() async {





    try {





      // váº½ lÃªn Canvas





      final recorder = ui.PictureRecorder();





      final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, 400, 150));





      // Ná»n tráº¯ng





      canvas.drawRect(Rect.fromLTWH(0, 0, 400, 150), Paint()..color = Colors.white);





      // Viá»n Ä‘en





      canvas.drawRect(





        Rect.fromLTWH(0, 0, 400, 150),





        Paint()





          ..color = Colors.black87





          ..style = PaintingStyle.stroke





          ..strokeWidth = 1.5,





      );





      // Text "ÄÃ£ kÃ½ bá»Ÿi: [username]"





      final username = _getUsername();





      final now = DateTime.now();





      final timeStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '





          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';





      final tp1 = TextPainter(





        text: TextSpan(





          text: 'ÄÃ£ kÃ½ bá»Ÿi: $username',





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





      // Text ngÃ y giá»





      final tp2 = TextPainter(





        text: TextSpan(





          text: 'LÃºc: $timeStr',





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





      debugPrint('Lá»—i táº¡o auto signature: $e');





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





        title: const Text('Táº¡o phiáº¿u khÃ¡m'),





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





                    _sectionTitle('ðŸŒ¡ï¸ Sinh hiá»‡u', Icons.favorite),





                    _vitalSigns(),





                    const SizedBox(height: 16),





                    _sectionTitle('ðŸ“ LÃ½ do khÃ¡m', Icons.notes),





                    TextField(





                      controller: _lyDoCtrl,





                      maxLines: 2,





                      decoration: const InputDecoration(





                        hintText: 'Äau ngá»±c, khÃ³ thá»Ÿ, ...',





                        border: OutlineInputBorder(),





                        isDense: true,





                      ),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('ðŸ” Cháº©n Ä‘oÃ¡n ICD chÃ­nh', Icons.assignment),





                    // v2.98.5: DÃ¹ng IcdInputField widget dÃ¹ng chung (chuáº©n hÃ³a)





                    IcdInputField(





                      fieldKey: 'CHAN_DOAN_CHINH',





                      label: 'Cháº©n Ä‘oÃ¡n ICD',





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





                    _sectionTitle('ðŸ©º Chá»‰ Ä‘á»‹nh Cáº­n lÃ¢m sÃ ng', Icons.medical_services),





                    // v2.98.7: NÃºt chá»n táº¥t cáº£ CLS + Ä‘áº¿m sá»‘ Ä‘Ã£ chá»n





                    Row(





                      children: [





                        Expanded(





                          child: Text(





                            'Bao gá»“m: XN mÃ¡u, X-quang, SA, Äiá»‡n tim, Ná»™i soi... (${_selectedServices.length} Ä‘Ã£ chá»n)',





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





                            label: const Text('Chá»n táº¥t cáº£', style: TextStyle(fontSize: 10)),





                            style: FilledButton.styleFrom(





                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),





                              minimumSize: const Size(0, 28),





                            ),





                          )





                        else





                          TextButton.icon(





                            onPressed: () => setState(() => _selectedServices.clear()),





                            icon: const Icon(Icons.clear, size: 14, color: Colors.red),





                            label: Text('XoÃ¡ (${_selectedServices.length})', style: const TextStyle(fontSize: 10, color: Colors.red)),





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





                      title: 'CLS (XÃ©t nghiá»‡m, CDHA, Thá»§ thuáº­t)',





                      hintText: 'TÃ¬m CLS (XN mÃ¡u, X-quang, SA tim...)',





                      selected: _selectedServices,





                      multiSelect: true,





                      maxSelect: 30,





                      onChanged: (list) => setState(() {





                        _selectedServices.clear();





                        _selectedServices.addAll(list);





                      }),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('ðŸ’Š ÄÆ¡n thuá»‘c', Icons.medication),





                    MedicineSelector(





                      items: _medicines,





                      onChanged: (list) => setState(() {





                        _medicines.clear();





                        _medicines.addAll(list);





                      }),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('ðŸ“‹ Ghi chÃº (tÃ¹y chá»n)', Icons.edit_note),





                    TextField(





                      controller: _ghiChuCtrl,





                      maxLines: 3,





                      decoration: const InputDecoration(





                        hintText: 'Ghi chÃº thÃªm cho phiáº¿u...',





                        border: OutlineInputBorder(),





                        isDense: true,





                      ),





                    ),





                    const SizedBox(height: 16),





                    _sectionTitle('âœï¸ KÃ½ sá»‘ (tÃ¹y chá»n - cho EMR)', Icons.draw),





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





                          label: const Text('XÃ³a chá»¯ kÃ½'),





                        ),





                        const Spacer(),





                        Container(





                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),





                          decoration: BoxDecoration(





                            color: _sigCtrl.isNotEmpty ? Colors.green.shade100 : Colors.grey.shade200,





                            borderRadius: BorderRadius.circular(8),





                          ),





                          child: Text(





                            _sigCtrl.isNotEmpty ? 'âœ… ÄÃ£ kÃ½' : 'ChÆ°a kÃ½',





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





                          color: _result!.startsWith('âŒ')





                              ? Colors.red.shade50





                              : Colors.green.shade50,





                          borderRadius: BorderRadius.circular(8),





                          border: Border.all(





                            color: _result!.startsWith('âŒ')





                                ? Colors.red.shade300





                                : Colors.green.shade300,





                          ),





                        ),





                        child: Text(





                          _result!,





                          style: TextStyle(





                            color: _result!.startsWith('âŒ')





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





          // v3.0.46: 3 nÃºt - [LÆ°u] [LÆ°u kÃ½] [KÃ½ VNPT SmartCA] theo máº«u BÃ n giao BN





          child: Column(





            mainAxisSize: MainAxisSize.min,





            children: [





              Row(





                children: [





                  Expanded(





                    child: OutlinedButton.icon(





                      onPressed: _saving ? null : () => _save(pushEmr: false),





                      icon: const Icon(Icons.save, size: 16),





                      label: const Text('LÆ°u', style: TextStyle(fontSize: 12)),





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





                      label: const Text('LÆ°u kÃ½', style: TextStyle(fontSize: 12)),





                      style: FilledButton.styleFrom(





                        backgroundColor: Colors.green.shade700,





                        padding: const EdgeInsets.symmetric(vertical: 12),





                      ),





                    ),





                  ),





                ],





              ),





              const SizedBox(height: 6),





              // v3.0.46: NÃºt KÃ½ VNPT SmartCA - kÃ½ PKCS#7 tháº­t qua app VNPT





              SizedBox(





                  width: double.infinity,





                  child: FilledButton.tonalIcon(





                    icon: const Icon(Icons.verified, size: 16),





                    label: const Text('KÃ½ VNPT SmartCA', style: TextStyle(fontSize: 12)),





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











  /// Build 5 vital signs inputs (máº¡ch/nhiá»‡t/HHA TT-TD/SpO2)





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





              Expanded(child: _vitalField(_machCtrl, 'Máº¡ch', 'l/p')),





              const SizedBox(width: 8),





              Expanded(child: _vitalField(_nhietCtrl, 'Nhiá»‡t', 'Â°C')),





              const SizedBox(width: 8),





              Expanded(child: _vitalField(_spo2Ctrl, 'SpOâ‚‚', '%')),





            ],





          ),





          const SizedBox(height: 8),





          Row(





            children: [





              Expanded(flex: 2, child: _vitalField(_hhaTTCtrl, 'HA TÃ¢m thu', 'mmHg')),





              const SizedBox(width: 8),





              Expanded(flex: 2, child: _vitalField(_hhaTDCtrl, 'HA TÃ¢m trÆ°Æ¡ng', 'mmHg')),





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





            _patientName ?? 'â€”',





            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),





          ),





          const SizedBox(height: 4),





          Text(





            'MÃ£ ÄT: ${_treatmentCode ?? 'â€”'} | MÃ£ BN: ${_patientCode ?? 'â€”'}',





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





                  'ICD cÅ©: ${icd}',





                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.w500),





                ),





              ),





            ),





        ],





      ),





    );





  }











  /// v2.98.5: Widget _buildIcdInputField cÅ© Ä‘Ã£ xÃ³a - dÃ¹ng IcdInputField widget dÃ¹ng chung











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





