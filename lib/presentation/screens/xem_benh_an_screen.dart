// XemBenhAnScreen v2.37.0

// Layout:

//   - Split view: list phiếu (trái 36%) + PDF viewer (phải 64%)

//   - Swipe LEFT trên PDF → fullscreen

//   - Swipe RIGHT trên PDF → mở drawer menu

//   - Gom phiếu cùng loại vào section (group by document_type)

//   - Chọn phiếu trong list → xem PDF

//   - Download về folder Download của Android

//   - Ô ghi chú nhỏ cho mỗi phiếu

import 'dart:io';

import 'dart:math';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:path_provider/path_provider.dart';

import 'package:printing/printing.dart';

import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../core/utils/mojibake_fixer.dart';

import '../../data/api/his_pro_api_service.dart';

import '../../data/services/data_service.dart';

import '../../data/local/scanned_forms_service.dart';

import '../../presentation/widgets/thong_tin_benh_nhan.dart';

import '../navigation/safe_navigator.dart';



class XemBenhAnScreen extends StatefulWidget {

  /// Hỗ trợ 2 dạng: DataPatient (Y Tế Số mới) hoặc Map (legacy)

  final dynamic patient;

  final DataDepartment? department;

  final DataRoom? room;

  final String? doctorName;

  final String? hospitalCode;



  const XemBenhAnScreen({

    super.key,

    required this.patient,

    this.department,

    this.room,

    this.doctorName,

    this.hospitalCode,

  });



  @override

  State<XemBenhAnScreen> createState() => _XemBenhAnScreenState();

}



class _XemBenhAnScreenState extends State<XemBenhAnScreen> {

  final _ytso = DataService.instance;

  final PdfViewerController _pdfController = PdfViewerController();



  bool _loading = true;

  String? _error;

  List<DataDocument> _docs = [];

  List<ScannedForm> _scannedForms = [];  // v2.41.0: local scanned forms

  DataDocument? _selected;

  Map<int, Uint8List> _docBytes = {};

  bool _fullscreen = false;

  bool _savingPdf = false;

  final Map<int, TextEditingController> _noteCtrls = {};



  // v2.37.0: Gom phiếu theo loại

  Map<String, List<DataDocument>> get _groupedDocs {

    final map = <String, List<DataDocument>>{};

    for (final d in _docs) {

      final key = (d.documentTypeName ?? 'Khác').toString().trim();

      if (key.isEmpty) {

        map.putIfAbsent('Khác', () => []).add(d);

      } else {

        map.putIfAbsent(key, () => []).add(d);

      }

    }

    return map;

  }



  // Helpers - support both DataPatient and Map

  String? _pTreatmentCode() {

    final p = widget.patient;

    if (p is DataPatient) return p.treatmentCode;

    if (p is Map) {

      return (p['MADT'] ?? p['TREATMENT_CODE'] ?? p['treatment_code'] ?? p['TDL_TREATMENT_CODE'])?.toString();

    }

    return null;

  }



  String _patientName() {

    final p = widget.patient;

    String raw = 'Bệnh nhân';

    if (p is DataPatient) raw = p.patientName ?? 'Bệnh nhân';

    if (p is Map) {

      raw = (p['HOTENBN'] ?? p['VIR_PATIENT_NAME'] ?? p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['TEN_BENH_NHAN'] ?? 'Bệnh nhân').toString();

    }

    return _capitalizeName(raw);

  }



  /// Chuẩn hóa tên BN: "nguyễn văn a" → "Nguyễn Văn A"

  String _capitalizeName(String raw) {

    return capitalizeVietnameseName(raw);

  }



  /// Tính tuổi chính xác (năm/tháng/ngày nếu < 6 tuổi)

  String _patientAgeText() {

    final p = widget.patient;

    int? year, month, day;

    if (p is DataPatient) {

      year = p.yearOfBirth;

    } else if (p is Map) {

      final dob = p['NGAYSINH'] ?? p['DOB'] ?? p['TDL_PATIENT_DOB'];

      if (dob is num) {

        // Format yyyymmdd hoặc yyyy

        final d = dob.toInt();

        if (d > 10000000) {

          year = d ~/ 10000;

          month = (d ~/ 100) % 100;

          day = d % 100;

        } else {

          year = d;

        }

      } else if (dob is String && dob.length >= 4) {

        year = int.tryParse(dob.substring(0, 4));

        if (dob.length >= 7) month = int.tryParse(dob.substring(5, 7));

        if (dob.length >= 10) day = int.tryParse(dob.substring(8, 10));

      }

    }

    if (year == null) return '';

    final now = DateTime.now();

    int ageY = now.year - year;

    int ageM = 0;

    if (month != null) {

      ageM = now.month - month;

      if (now.day < (day ?? 1)) ageM -= 1;

      if (ageM < 0) {

        ageY -= 1;

        ageM += 12;

      }

    }

    if (ageY == 0 && ageM > 0) return '$ageM tháng';

    if (ageY == 0) return '<1 tuổi';

    return '$ageY tuổi';

  }



  String _patientGender() {

    final p = widget.patient;

    int? g;

    String? nameForInference;

    if (p is DataPatient) {

      g = p.gender;

      nameForInference = p.patientName;

    }

    if (p is Map) {

      // Thử tất cả các key có thể

      final v = p['GIOITINH'] ?? p['GENDER_NAME'] ?? p['TDL_PATIENT_GENDER_NAME']

          ?? p['tdl_patient_gender_name'] ?? p['gender_name'] ?? p['gender'];

      if (v is num) {

        g = v.toInt();

      } else if (v is String && v.isNotEmpty) {

        final vl = v.toLowerCase().trim();

        if (vl == '1' || vl == '01') g = 1;

        else if (vl == '2' || vl == '02') g = 2;

        else if (vl == 'nam' || vl == 'male' || vl == 'm') g = 1;

        else if (vl == 'nữ' || vl == 'nu' || vl == 'female' || vl == 'f') g = 2;

        else if (vl.contains('nam')) g = 1;

        else if (vl.contains('nữ') || vl.contains('nu')) g = 2;

      }

      // Lấy tên để infer nếu gender không có

      nameForInference = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['TDL_PATIENT_NAME'] ?? p['tdl_patient_name'] ?? p['TEN_BENH_NHAN'] ?? '').toString();

    }

    // v2.42.0: Infer từ tên Việt nếu gender data không có

    if (g == null && nameForInference != null && nameForInference.isNotEmpty) {

      g = _inferGenderFromVietnameseName(nameForInference);

    }

    if (g == 1) return 'Nam';

    if (g == 2) return 'Nữ';

    return '';

  }



  /// v2.42.0: Infer giới tính từ tên Việt dựa trên tên đệm

  /// Nam: VẺ, HỮU, ĐỨC, MINH, QUANG, ĐẺG, CÔNG, ĐÌNH, QUỐC, NGỌC, ĐÔNG, etc.

  /// Nữ: THỊ, THU, NGỌC, HỒNG, LAN, MAI, KIM, HOÀI, DIỆU, THẢO, etc.

  int? _inferGenderFromVietnameseName(String name) {

    final parts = name.trim().split(RegExp(r'\\s+'));

    if (parts.length < 2) return null;

    // Bỏ qua họ (part đầu), lấy tên đệm + tên

    final middleAndGiven = parts.sublist(1).join(' ').toUpperCase();

    // Check các markers Nữ trước (vì THỊ rất phổ biến và unambiguous)

    const femaleMarkers = ['THỊ ', 'THI ', 'THU ', 'THUẦN', 'NGỌC', 'NGOC ', 'HỒNG', 'HONG', 'LAN ', 'MAI ', 'KIM ', 'HOÀI', 'DIỆU', 'DIEU', 'THẢO', 'THAO', 'HƯƠNG', 'HUONG', 'LINH', 'TRANG', 'PHƯỢNG', 'PHUONG', 'UYÊN', 'UYEN', 'MY ', 'TIÊN', 'TIEN', 'TRINH', 'HÀ', 'HA ', 'HIỀN', 'HIEN', 'LIÊN', 'LIEN', 'NGA ', 'ANH ', r'ANH$'];

    for (final marker in femaleMarkers) {

      if (middleAndGiven.contains(marker)) return 2;

    }

    // Check các markers Nam

    const maleMarkers = ['VẺ', 'VAN ', 'HỮU', 'HUU ', 'ĐỨC', 'DUC ', 'MINH', 'QUANG', 'ĐẺG', 'DANG', 'CÔNG', 'CONG', 'ĐÌNH', 'DINH', 'QUỐC', 'QUOC', 'NGỌC ', 'ĐÔNG', 'DONG', 'THANH', 'VIỆT', 'VIET', 'HOÀNG', 'HOANG', 'TRUNG', 'TUẤN', 'TUAN', 'NAM ', 'ANH', 'HIẾU', 'HIEU', 'BẢO', 'BAO', 'PHÚC', 'PHUC', 'TÙNG', 'TUNG', 'SƠN', 'SON '];

    for (final marker in maleMarkers) {

      if (middleAndGiven.contains(marker)) return 1;

    }

    return null;

  }



  String? _patientIcdCode() {

    final p = widget.patient;

    if (p is DataPatient) return p.icdCode;

    if (p is Map) return (p['ICD_CODE'] ?? p['icd_code'])?.toString();

    return null;

  }



  String? _patientIcdName() {

    final p = widget.patient;

    if (p is DataPatient) return p.icdName;

    if (p is Map) return (p['ICD_NAME'] ?? p['ICD_TEXT'] ?? p['icd_name'])?.toString();

    return null;

  }



  @override

  void initState() {

    super.initState();

    _load();

  }



  Future<void> _load() async {

    final tcode = _pTreatmentCode();

    if (tcode == null || tcode.isEmpty) {

      setState(() {

        _loading = false;

        _error = 'Bệnh nhân chưa có mã điều trị';

      });

      return;

    }

    // v3.0.46: Ưu tiên HIS Pro EMR 1417 TRƯỚC (khớp 'Bệnh án điện tử' / 'Chi tiết bệnh án' HIS Pro desktop)

    // Fallback: THONGKE/BVBM (nếu HIS Pro fail)

    await _ytso.loadSession();

    List<DataDocument>? docs;

    String? fetchError;

    String? emrError;

    // v3.0.46: Ưu tiên HIS Pro EMR 1417 - đây là 'Bệnh án điện tử' thật mà app push lên

    try {

      docs = await _fetchFromHisProEmr(tcode);

      if (docs == null || docs.isEmpty) {

        debugPrint('HIS Pro EMR trả rỗng → fallback THONGKE');

      }

    } catch (e) {

      emrError = e.toString();

      debugPrint('HIS Pro EMR error: $e');

    }

    // Fallback: THONGKE/BVBM (nếu HIS Pro fail hoặc rỗng)

    if (docs == null || docs.isEmpty) {

      if (_ytso.isAuthenticated) {

        try {

          docs = await _ytso.getDocuments(tcode);

        } catch (e) {

          fetchError = e.toString();

          debugPrint('THONGKE getDocuments error: $e');

        }

      }

    }

    if (!mounted) return;

    // v2.41.0: Also load scanned forms from local storage

    final scanned = await ScannedFormsService.instance.getForPatient(tcode);

    if (!mounted) return;

    // Append scanned forms as DataDocument-like items (use negative id to distinguish)

    final combined = <DataDocument>[

      ...?docs,

      ...scanned.map((s) => DataDocument(

            id: -1 * (int.tryParse(s.id.length > 9 ? s.id.substring(0, 9) : s.id) ?? 0),

            documentCode: s.id,

            name: s.formName + (s.signaturePath != null ? ' (ký)' : ''),

            documentTypeName: 'Phiếu scan từ điện thoại',

            treatmentCode: s.treatmentCode,

            requestUsername: s.signedBy,

            isSigned: s.signaturePath != null,

            documentDate: s.createdAt.toIso8601String().substring(0, 10),

            // Stash image path in lastVersionUrl for _loadDocBytes to pick up

            lastVersionUrl: s.imagePath,

          )),

    ];

    setState(() {

      _loading = false;

      _docs = combined;

      _scannedForms = scanned;  // keep raw for viewer

      if (_docs.isEmpty) {

        // v3.0.46: Thông báo rõ ràng - HIS Pro thật (Bệnh án điện tử HIS Pro desktop) đang fail

        if (emrError != null) {

          _error = '⚠️ Không tải được danh sách phiếu từ HIS Pro EMR 1417:\n\n'

              '$emrError\n\n'

              '✅ Hãy kiểm tra:\n'

              '• VPN BV đã bật chưa\n'

              '• Token HIS Pro còn hạn không (xem Settings)\n'

              '• HIS Pro server 172.16.9.6:1417 có hoạt động không\n\n'

              '💡 Có thể xem phiếu LOCAL (đã lưu trên app) trong "Quét tài liệu".';

        } else if (!_ytso.isAuthenticated) {

          _error = 'Bệnh nhân chưa có phiếu nào trên HIS Pro EMR.\n\n'

              'Nếu ca đã cũ, có thể HIS Pro chưa sync.\n'

              'Nếu muốn xem qua THONGKE/BVBM, bật trong Settings.';

        } else if (fetchError != null) {

          _error = 'Lỗi tải danh sách phiếu: $fetchError\n\n'

              'Bấm thử "Bệnh án" (icon ở thanh dưới) để dùng view trực tiếp của HIS Pro.';

        } else {

          _error = 'Bệnh nhân chưa có phiếu nào trên HIS Pro EMR.\n\n'

              'Đợi vài giây rồi kéo xuống để reload.';

        }

      } else {

        _error = null;

        // Auto-select first signed document

        final first = _docs.firstWhere(

          (d) => d.isSigned,

          orElse: () => _docs.first,

        );

        _selectDoc(first);

      }

    });

  }



  /// v3.0.30: Lấy danh sách phiếu từ HIS Pro EMR 1417 (đúng server mà app push lên)

  /// CHỈ WORK nếu user có bearer có READ permission (hardcode chỉ có WRITE)

  Future<List<DataDocument>?> _fetchFromHisProEmr(String tcode) async {

    try {

      final hisProDocs = await HisProApiService.instance.getPatientDocumentsFromEmr(tcode);

      if (hisProDocs.isEmpty) return null;

      // Map HIS Pro response → DataDocument

      return hisProDocs.map((m) {

        T g<T>(String k1, [String? k2, String? k3]) {

          for (final k in [k1, k2, k3].whereType<String>()) {

            if (m.containsKey(k) && m[k] != null) return m[k] as T;

          }

          return null as T;

        }

        final id = (g<num>('ID') ?? 0).toInt();

        final docCode = (g<String>('DOCUMENT_CODE', 'DocumentCode') ?? '').toString();

        final name = (g<String>('DOCUMENT_NAME', 'DocumentName') ?? 'Phiếu').toString();

        final typeName = g<String>('DOCUMENT_TYPE_NAME', 'DocumentTypeName')?.toString();

        final signers = g<String>('SIGNERS', 'Signers')?.toString() ?? '';

        final isSigned = signers.isNotEmpty;

        // Parse document time (yyyymmddHHMMSS hoặc yyyymmdd)

        String? docDate;

        final ts = g<num>('DOCUMENT_TIME', 'DocumentTime');

        if (ts != null) {

          final s = ts.toString();

          if (s.length >= 8) {

            docDate = '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';

          }

        }

        return DataDocument(

          id: id,

          documentCode: docCode,

          name: name,

          documentTypeName: typeName,

          treatmentCode: (g<String>('TREATMENT_CODE', 'TreatmentCode') ?? tcode).toString(),

          treatmentId: g<String>('TREATMENT_ID', 'TreatmentId')?.toString(),

          requestUsername: g<String>('REQUEST_USERNAME', 'RequestUsername')?.toString(),

          lastVersionUrl: g<String>('LAST_VERSION_URL', 'LastVersionUrl')?.toString(),

          isSigned: isSigned,

          departmentCode: g<String>('DEPARTMENT_CODE', 'DepartmentCode')?.toString(),

          patientCode: g<String>('PATIENT_CODE', 'PatientCode')?.toString(),

          patientName: g<String>('VIR_PATIENT_NAME', 'VirPatientName')?.toString(),

          documentDate: docDate,

        );

      }).toList();

    } catch (e) {

      debugPrint('_fetchFromHisProEmr error: $e');

      return null;

    }

  }



  void _selectDoc(DataDocument d) {

    setState(() {

      _selected = d;

      _fullscreen = false;

    });

    _loadDocBytes(d);

  }



  Future<void> _loadDocBytes(DataDocument d) async {

    if (_docBytes.containsKey(d.id)) return;

    // v2.41.0: If lastVersionUrl is local file path (scanned form), read it directly

    final path = d.lastVersionUrl;

    if (path != null && !path.startsWith('http')) {

      try {

        final f = File(path);

        if (await f.exists()) {

          final bytes = await f.readAsBytes();

          if (!mounted) return;

          if (bytes != null) {

            setState(() => _docBytes[d.id] = bytes);

          }

          return;

        }

      } catch (_) {}

    }

    // v3.0.31: Ưu tiên THONGKE (workflow chính) - dùng id

    // Fallback: HIS Pro EMR 1417 với DocumentCode (nếu có bearer có READ)

    Uint8List? bytes;

    if (d.id > 0) {

      // THONGKE dùng id (số nguyên)

      final raw = await _ytso.downloadDocument(d.id);

      if (raw != null && raw.isNotEmpty) {

        bytes = Uint8List.fromList(raw);

      }

    }

    if (bytes == null && d.documentCode.isNotEmpty) {

      bytes = await HisProApiService.instance.downloadEmrDocumentAsPdf(d.documentCode);

    }

    if (!mounted) return;

    if (bytes != null) {

      setState(() => _docBytes[d.id] = bytes!);

    }

  }



  /// v2.42.0: Confirm xóa scanned form (chi cho local scan, id am)

  Future<void> _confirmDeleteScanned(DataDocument d) async {
    // v3.0.58: Phân quyền - chỉ user upload mới được xóa
    // TODO: cần thêm field uploadedBy vào DataDocument để check (chưa có sẵn)
    // Tạm thời: chỉ xóa được phiếu local (id < 0) - chỉ phiếu do user này tạo mới có id < 0
    // (HIS Pro EMR phiếu id > 0 thì không xóa được - đã ở trên server)


    HapticFeedback.mediumImpact();

    final confirm = await showDialog<bool>(

      context: context,

      builder: (ctx) => AlertDialog(

        title: const Row(

          children: [

            Icon(Icons.delete_forever, color: Colors.red),

            SizedBox(width: 8),

            Text('Xóa phiếu scan?'),

          ],

        ),

        content: Text(

          'Phiếu "${d.name}" sẽ bị xóa khỏi app.\n\n'

          'Hành động này không thể hoàn tác.',

          style: const TextStyle(fontSize: 13),

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('Hủy'),

          ),

          FilledButton(

            style: FilledButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Xóa'),

          ),

        ],

      ),

    );

    if (confirm == true) {

      await _deleteScannedForm(d);

    }

  }



  Future<void> _deleteScannedForm(DataDocument d) async {

    try {

      // Find the original ScannedForm by id (we used -1 * parseInt of first 9 chars)

      final all = await ScannedFormsService.instance.getAll();

      // Match by id (could be negative)

      final toDelete = all.where((f) {

        // Reconstruct negative id from s.id

        final idNum = int.tryParse(f.id.length > 9 ? f.id.substring(0, 9) : f.id) ?? 0;

        return -1 * idNum == d.id;

      }).toList();

      if (toDelete.isEmpty) {

        _showSnack('Không tìm thấy phiếu để xóa', isError: true);

        return;

      }

      await ScannedFormsService.instance.delete(toDelete.first.id);

      HapticFeedback.mediumImpact();

      if (!mounted) return;

      _showSnack('Đã xóa phiếu "${toDelete.first.formName}"');

      // Reload list

      await _load();

    } catch (e) {

      _showSnack('Lỗi xóa: $e', isError: true);

    }

  }



  /// Tải về folder Download của Android (/storage/emulated/0/Download)

  Future<void> _downloadPdf(DataDocument d) async {

    if (_savingPdf) return;

    setState(() => _savingPdf = true);

    try {

      Uint8List? bytes = _docBytes[d.id];

      if (bytes == null) {

        // v3.0.30: Ưu tiên HIS Pro EMR 1417

        if (d.documentCode.isNotEmpty) {

          bytes = await HisProApiService.instance.downloadEmrDocumentAsPdf(d.documentCode);

        }

        if (bytes == null) {

          final raw = await _ytso.downloadDocument(d.id);

          if (raw != null) bytes = Uint8List.fromList(raw);

        }

      }

      if (bytes == null) {

        _showSnack('Không tải được PDF', isError: true);

        return;

      }

      // v2.37.0: Lưu vào folder Download của Android

      final filename = _safeFilename(d);

      Directory? targetDir;

      String? savedPath;

      try {

        // /storage/emulated/0/Download - chuẩn Android

        targetDir = Directory('/storage/emulated/0/Download');

        if (!await targetDir.exists()) {

          targetDir = await getExternalStorageDirectory();

        }

      } catch (_) {

        targetDir = null;

      }

      targetDir ??= await getApplicationDocumentsDirectory();

      final file = File('${targetDir.path}/$filename');

      await file.writeAsBytes(bytes);

      savedPath = file.path;

      _showSnack('Đã lưu: $savedPath', isError: false);

    } catch (e) {

      _showSnack('Lỗi lưu: $e', isError: true);

    } finally {

      if (mounted) setState(() => _savingPdf = false);

    }

  }



  /// Tên file an toàn (không có ký tự đặc biệt)

  String _safeFilename(DataDocument d) {

    final raw = (d.documentCode.isNotEmpty ? d.documentCode : '${d.id}').toString();

    final cleaned = raw.replaceAll(RegExp(r'[^\w\-\.]'), '_');

    final tcode = _pTreatmentCode() ?? 'unk';

    return 'BA_${tcode}_$cleaned.pdf';

  }



  Future<void> _printPdf(DataDocument d) async {

    final bytes = _docBytes[d.id];

    if (bytes == null) {

      _showSnack('Chưa tải xong PDF', isError: true);

      return;

    }

    try {

      await Printing.layoutPdf(onLayout: (_) async => bytes);

    } catch (e) {

      _showSnack('Lỗi in: $e', isError: true);

    }

  }



  Future<void> _sharePdf(DataDocument d) async {

    if (_savingPdf) return;

    setState(() => _savingPdf = true);

    try {

      Uint8List? bytes = _docBytes[d.id];

      if (bytes == null) {

        // v3.0.30: Ưu tiên HIS Pro EMR 1417

        if (d.documentCode.isNotEmpty) {

          bytes = await HisProApiService.instance.downloadEmrDocumentAsPdf(d.documentCode);

        }

        if (bytes == null) {

          final raw = await _ytso.downloadDocument(d.id);

          if (raw != null) bytes = Uint8List.fromList(raw);

        }

      }

      if (bytes == null) {

        _showSnack('Không tải được PDF', isError: true);

        return;

      }

      final filename = _safeFilename(d);

      try {

        await Printing.sharePdf(bytes: bytes, filename: filename);

      } catch (_) {

        _showSnack('Đã lưu, dùng file manager để chia sẻ');

      }

    } catch (e) {

      _showSnack('Lỗi chia sẻ: $e', isError: true);

    } finally {

      if (mounted) setState(() => _savingPdf = false);

    }

  }



  void _showSnack(String msg, {bool isError = false}) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(

      content: Text(msg),

      backgroundColor: isError ? Colors.red : Colors.green,

    ));

  }



  void _toggleFullscreen() {

    setState(() => _fullscreen = !_fullscreen);

    SystemChrome.setEnabledSystemUIMode(

      _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,

    );

  }



  @override

  Widget build(BuildContext context) {

    if (_loading) {

      return Scaffold(

        appBar: AppBar(title: const Text('Xem bệnh án'), backgroundColor: const Color(0xFF1565C0)),

        body: const Center(child: CircularProgressIndicator()),

      );

    }

    if (_error != null && _docs.isEmpty) {

      return Scaffold(

        appBar: AppBar(title: const Text('Xem bệnh án'), backgroundColor: const Color(0xFF1565C0)),

        body: Padding(

          padding: const EdgeInsets.all(20),

          child: Center(

            child: Column(

              mainAxisSize: MainAxisSize.min,

              children: [

                const Icon(Icons.info_outline, size: 48, color: Colors.grey),

                const SizedBox(height: 12),

                Text(_error!, textAlign: TextAlign.center),

                const SizedBox(height: 12),

                ElevatedButton(

                  onPressed: () {

                    setState(() {

                      _loading = true;

                      _error = null;

                    });

                    _load();

                  },

                  child: const Text('Thử lại'),

                ),

              ],

            ),

          ),

        ),

      );

    }

    return _fullscreen ? _buildFullscreen() : _buildSplitView();

  }



  // ===== Split View (List + PDF) =====

  Widget _buildSplitView() {

    return Scaffold(

      backgroundColor: const Color(0xFFF5F5F5),

      appBar: AppBar(

        backgroundColor: const Color(0xFF1565C0),

        foregroundColor: Colors.white,

        // v2.38.0: Nút back góc trái, nút 3 gạch góc phải (thay drawer)

        leading: IconButton(

          icon: const Icon(Icons.arrow_back),

          tooltip: 'Quay lại',

          onPressed: () => Navigator.of(context).pop(),

        ),

        title: const Text('Xem bệnh án', style: TextStyle(fontSize: 16)),

        actions: [

          IconButton(

            icon: const Icon(Icons.refresh),

            tooltip: 'Tải lại',

            onPressed: () {

              setState(() {

                _loading = true;

                _error = null;

                _docs = [];

                _docBytes = {};

                _noteCtrls.clear();

              });

              _load();

            },

          ),

          // Nút 3 gạch menu (thay drawer)

          PopupMenuButton<String>(

            tooltip: 'Menu',

            icon: const Icon(Icons.more_vert),

            color: Colors.white,

            onSelected: (v) {

              switch (v) {

                case 'list':

                  setState(() => _fullscreen = false);

                  break;

                case 'fullscreen':

                  setState(() => _fullscreen = true);

                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

                  break;

                case 'download':

                  if (_selected != null) _downloadPdf(_selected!);

                  break;

                case 'print':

                  if (_selected != null) _printPdf(_selected!);

                  break;

                case 'share':

                  if (_selected != null) _sharePdf(_selected!);

                  break;

                case 'close':

                  Navigator.of(context).pop();

                  break;

              }

            },

            itemBuilder: (_) => [

              const PopupMenuItem(value: 'list', child: Row(children: [Icon(Icons.list_alt, size: 18), SizedBox(width: 8), Text('Danh sách phiếu')])),

              const PopupMenuItem(value: 'fullscreen', child: Row(children: [Icon(Icons.fullscreen, size: 18), SizedBox(width: 8), Text('Xem toàn bộ')])),

              const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download, size: 18), SizedBox(width: 8), Text('Tải phiếu đang chọn')])),

              const PopupMenuItem(value: 'print', child: Row(children: [Icon(Icons.print, size: 18), SizedBox(width: 8), Text('In phiếu')])),

              const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, size: 18), SizedBox(width: 8), Text('Chia sẻ')])),

              const PopupMenuDivider(),

              const PopupMenuItem(value: 'close', child: Row(children: [Icon(Icons.exit_to_app, size: 18), SizedBox(width: 8), Text('Đóng')])),

            ],

          ),

        ],

      ),

      body: Row(

        children: [

          // Left: list phiếu gom theo loại (1/3 màn hình)

          SizedBox(

            width: MediaQuery.of(context).size.width * 0.40,

            child: _buildLeftList(),

          ),

          // Divider

          Container(width: 1, color: Colors.grey.shade300),

          // Right: PDF viewer (2/3) - swipe LEFT → fullscreen, swipe RIGHT → menu

          Expanded(

            child: GestureDetector(

              onHorizontalDragEnd: (details) {

                final v = details.primaryVelocity ?? 0;

                if (v < -300) {

                  // Swipe LEFT → fullscreen

                  setState(() => _fullscreen = true);

                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

                }

                // Swipe RIGHT → bỏ (đã có nút 3 gạch)

              },

              child: _buildRightPdf(),

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildDrawer() {

    return Drawer(

      child: SafeArea(

        child: Column(

          children: [

            Container(

              padding: const EdgeInsets.all(16),

              color: const Color(0xFF1565C0),

              width: double.infinity,

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(_patientName(),

                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),

                  const SizedBox(height: 4),

                  Text(

                    [

                      if (_patientAgeText().isNotEmpty) _patientAgeText(),

                      if (_patientGender().isNotEmpty) _patientGender(),

                      if (_pTreatmentCode()?.isNotEmpty ?? false) 'Mã ĐT: ${_pTreatmentCode()}',

                    ].join(' - '),

                    style: const TextStyle(color: Colors.white70, fontSize: 11),

                  ),

                ],

              ),

            ),

            ListTile(

              leading: const Icon(Icons.list_alt),

              title: const Text('Danh sách phiếu'),

              onTap: () {

                context.safePop();

                setState(() => _fullscreen = false);

              },

            ),

            ListTile(

              leading: const Icon(Icons.fullscreen),

              title: const Text('Xem toàn bộ'),

              subtitle: const Text('Vuốt trái trên PDF'),

              onTap: () {

                context.safePop();

                setState(() => _fullscreen = true);

                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

              },

            ),

            ListTile(

              leading: const Icon(Icons.download),

              title: const Text('Tải phiếu đang chọn'),

              onTap: () {

                context.safePop();

                if (_selected != null) _downloadPdf(_selected!);

              },

            ),

            ListTile(

              leading: const Icon(Icons.print),

              title: const Text('In phiếu đang chọn'),

              onTap: () {

                context.safePop();

                if (_selected != null) _printPdf(_selected!);

              },

            ),

            const Divider(),

            ListTile(

              leading: const Icon(Icons.close),

              title: const Text('Đóng menu'),

              onTap: () => Navigator.pop(context),

            ),

          ],

        ),

      ),

    );

  }



  Widget _buildLeftList() {

    final ageGender = [

      if (_patientAgeText().isNotEmpty) _patientAgeText(),

      if (_patientGender().isNotEmpty) _patientGender(),

    ].join(' - ');

    return Container(

      color: Colors.white,

      child: Column(

        children: [

          // Patient info card

          Container(

            width: double.infinity,

            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),

            decoration: const BoxDecoration(

              color: Color(0xFF1565C0),

            ),

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  _patientName(),

                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                ),

                const SizedBox(height: 2),

                Text(

                  ageGender,

                  style: const TextStyle(color: Colors.white70, fontSize: 11),

                ),

                const SizedBox(height: 2),

                if (widget.department != null)

                  Text(

                    widget.department!.name,

                    style: const TextStyle(color: Colors.white, fontSize: 11),

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                  ),

              ],

            ),

          ),

          if ((_patientIcdCode() ?? '').isNotEmpty)

            Container(

              width: double.infinity,

              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

              decoration: BoxDecoration(

                color: const Color(0xFFFFF3E0),

                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),

              ),

              child: Row(

                children: [

                  const Icon(Icons.medical_services, color: Color(0xFFE65100), size: 12),

                  const SizedBox(width: 4),

                  Expanded(

                    child: Text(

                      '${_patientIcdCode()} ${_patientIcdName() ?? ""}',

                      style: const TextStyle(fontSize: 11, color: Color(0xFFE65100)),

                      maxLines: 2,

                      overflow: TextOverflow.ellipsis,

                    ),

                  ),

                ],

              ),

            ),

          // Header

          Container(

            width: double.infinity,

            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),

            decoration: BoxDecoration(

              color: Colors.grey.shade100,

              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),

            ),

            child: Row(

              children: [

                const Icon(Icons.folder_open, size: 14, color: Colors.indigo),

                const SizedBox(width: 4),

                Text('Phiếu (${_docs.length})',

                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),

                const Spacer(),

                const Text('← vuốt', style: TextStyle(fontSize: 9, color: Colors.black45)),

              ],

            ),

          ),

          // v2.37.0: List phiếu gom theo loại

          Expanded(

            child: _buildGroupedList(),

          ),

          // v2.37.0: Ô ghi chú nhỏ cho phiếu đang chọn

          if (_selected != null) _buildNoteField(_selected!),

        ],

      ),

    );

  }



  /// Gom phiếu theo document_type_name → section với header

  Widget _buildGroupedList() {

    final grouped = _groupedDocs;

    if (grouped.isEmpty) {

      return const Center(

        child: Padding(

          padding: EdgeInsets.all(20),

          child: Text('Không có phiếu', style: TextStyle(color: Colors.grey)),

        ),

      );

    }

    return ListView(

      padding: EdgeInsets.zero,

      children: [

        for (final entry in grouped.entries) ...[

          // Section header

          Container(

            width: double.infinity,

            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

            color: Colors.indigo.shade50,

            child: Row(

              children: [

                const Icon(Icons.folder, size: 12, color: Colors.indigo),

                const SizedBox(width: 4),

                Expanded(

                  child: Text(

                    entry.key,

                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                  ),

                ),

                Container(

                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),

                  decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(8)),

                  child: Text('${entry.value.length}',

                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),

                ),

              ],

            ),

          ),

          // Items

          for (final doc in entry.value) _buildDocTile(doc),

        ],

        const SizedBox(height: 20),

      ],

    );

  }



  Widget _buildDocTile(DataDocument d) {

    final isSelected = _selected?.id == d.id;

    // v2.42.0: Check if local scanned (id am)

    final isLocal = d.id < 0;

    return InkWell(

      onTap: () => _selectDoc(d),

      onLongPress: () {

        // v2.42.0: Long-press -> neu la scanned form -> hoi xoa

        if (isLocal) {

          _confirmDeleteScanned(d);

        }

      },

      child: Container(

        decoration: BoxDecoration(

          color: isSelected ? Colors.amber.shade100 : Colors.white,

          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),

        ),

        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),

        child: Row(

          children: [

            Icon(

              d.isSigned ? Icons.check_circle : Icons.description_outlined,

              size: 16,

              color: d.isSigned ? Colors.green : Colors.indigo,

            ),

            const SizedBox(width: 8),

            Expanded(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(

                    d.name,

                    style: TextStyle(

                      fontSize: 11,

                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,

                      color: Colors.black87,

                    ),

                    maxLines: 2,

                    overflow: TextOverflow.ellipsis,

                  ),

                  if (d.documentCode.isNotEmpty)

                    Text(d.documentCode,

                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),

                        maxLines: 1, overflow: TextOverflow.ellipsis),

                ],

              ),

            ),

            if (_docBytes.containsKey(d.id))

              const Icon(Icons.image, size: 12, color: Colors.green)

            else

              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),

            // v2.42.0: Delete button for local scanned forms

            if (isLocal)

              IconButton(

                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),

                tooltip: 'Xóa phiếu scan',

                padding: EdgeInsets.zero,

                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),

                onPressed: () => _confirmDeleteScanned(d),

              ),

          ],

        ),

      ),

    );

  }



  /// v2.37.0: Ô ghi chú nhỏ cho phiếu

  Widget _buildNoteField(DataDocument d) {

    final ctrl = _noteCtrls.putIfAbsent(d.id, () => TextEditingController());

    return Container(

      decoration: BoxDecoration(

        color: Colors.amber.shade50,

        border: Border(top: BorderSide(color: Colors.grey.shade300)),

      ),

      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),

      child: Row(

        children: [

          const Icon(Icons.edit_note, size: 14, color: Colors.amber),

          const SizedBox(width: 4),

          Expanded(

            child: TextField(

              controller: ctrl,

              maxLines: 1,

              style: const TextStyle(fontSize: 11),

              decoration: const InputDecoration(

                isDense: true,

                hintText: 'Ghi chú nhanh cho phiếu này...',

                hintStyle: TextStyle(fontSize: 11, color: Colors.black38),

                border: InputBorder.none,

                contentPadding: EdgeInsets.symmetric(vertical: 4),

              ),

            ),

          ),

          IconButton(

            icon: const Icon(Icons.save_outlined, size: 14),

            padding: EdgeInsets.zero,

            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),

            onPressed: () {

              _showSnack('Đã lưu ghi chú (chưa sync)');

            },

          ),

        ],

      ),

    );

  }



  Widget _buildRightPdf() {

    if (_selected == null) {

      return Container(

        color: Colors.grey.shade100,

        alignment: Alignment.center,

        child: const Column(

          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            Icon(Icons.description_outlined, size: 64, color: Colors.black26),

            SizedBox(height: 12),

            Text('Chọn phiếu bên trái', style: TextStyle(color: Colors.black45)),

            SizedBox(height: 6),

            Text('Vuốt trái → toàn bộ\nVuốt phải → menu', textAlign: TextAlign.center, style: TextStyle(color: Colors.black38, fontSize: 10)),

          ],

        ),

      );

    }

    final bytes = _docBytes[_selected!.id];

    if (bytes == null) {

      return Container(

        color: Colors.grey.shade100,

        alignment: Alignment.center,

        child: const CircularProgressIndicator(),

      );

    }

    return Stack(

      children: [

        // v2.41.0: Check if local image (scanned) vs PDF

        Builder(builder: (ctx) {

          final isImage = _selected?.documentTypeName?.contains('scan') ?? false;

          if (isImage) {

            return InteractiveViewer(

              minScale: 0.5,

              maxScale: 4.0,

              child: Center(

                child: Image.memory(bytes, fit: BoxFit.contain),

              ),

            );

          }

          return SfPdfViewer.memory(bytes, controller: _pdfController);

        }),

        Positioned(

          right: 8, bottom: 8,

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              _circleBtn(Icons.fullscreen, () => _toggleFullscreen()),

              const SizedBox(height: 6),

              _circleBtn(Icons.download, _savingPdf ? null : () => _downloadPdf(_selected!), loading: _savingPdf),

              const SizedBox(height: 6),

              _circleBtn(Icons.print, () => _printPdf(_selected!)),

              const SizedBox(height: 6),

              _circleBtn(Icons.share, () => _sharePdf(_selected!)),

            ],

          ),

        ),

      ],

    );

  }



  Widget _circleBtn(IconData icon, VoidCallback? onTap, {bool loading = false}) {

    return Material(

      color: Colors.white,

      shape: const CircleBorder(),

      elevation: 2,

      child: InkWell(

        customBorder: const CircleBorder(),

        onTap: onTap,

        child: SizedBox(

          width: 36, height: 36,

          child: loading

              ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))

              : Icon(icon, size: 18, color: Colors.indigo),

        ),

      ),

    );

  }



  // ===== Fullscreen PDF View =====

  Widget _buildFullscreen() {

    final bytes = _selected == null ? null : _docBytes[_selected!.id];

    return Scaffold(

      backgroundColor: Colors.black,

      body: Stack(

        children: [

          if (_selected != null && bytes != null)

            // v2.41.0: Image vs PDF viewer

            Builder(builder: (_) {

              final isImage = _selected?.documentTypeName?.contains('scan') ?? false;

              if (isImage) {

                return InteractiveViewer(

                  minScale: 0.5,

                  maxScale: 4.0,

                  child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),

                );

              }

              return SfPdfViewer.memory(bytes, controller: _pdfController);

            })

          else

            const Center(child: CircularProgressIndicator()),

          // Top bar

          Positioned(

            top: 0, left: 0, right: 0,

            child: SafeArea(

              child: Container(

                color: Colors.black.withOpacity(0.6),

                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),

                child: Row(

                  children: [

                    IconButton(

                      icon: const Icon(Icons.arrow_back, color: Colors.white),

                      onPressed: _toggleFullscreen,

                    ),

                    Expanded(

                      child: Text(

                        _selected?.name ?? '',

                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),

                        maxLines: 1, overflow: TextOverflow.ellipsis,

                      ),

                    ),

                    IconButton(

                      icon: const Icon(Icons.download, color: Colors.white),

                      onPressed: _savingPdf ? null : () => _selected != null ? _downloadPdf(_selected!) : null,

                    ),

                  ],

                ),

              ),

            ),

          ),

        ],

      ),

    );

  }

}