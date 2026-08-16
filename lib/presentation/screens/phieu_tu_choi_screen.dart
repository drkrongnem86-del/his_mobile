// PhieuTuChoiScreen v3.0.134 - GIẤY CAM KẾT TỪ CHỐI SỬ DỤNG DỊCH VỤ KHÁM BỆNH, CHỮA BỆNH
// Mẫu MS: 41/BV2 - BỆNH VIỆN ĐA KHOA NINH THUẬN
// v3.0.134: Tương tự Phiếu phẫu thuật - Arial font + date picker + 2 chỗ ký + EMR upload
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as pathJoin;
import 'package:signature/signature.dart';
import 'package:printing/printing.dart';
import 'package:his_mobile/data/api/attach_document_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/local/scanned_forms_service.dart';

/// v3.0.134: Form Giấy cam kết từ chối sử dụng dịch vụ khám bệnh, chữa bệnh
/// Mẫu: MS 41/BV2 - BỆNH VIỆN ĐA KHOA NINH THUẬN

class PhieuTuChoiScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const PhieuTuChoiScreen({
    super.key,
    required this.patient,
    required this.department,
  });

  @override
  State<PhieuTuChoiScreen> createState() => _PhieuTuChoiScreenState();
}

class _PhieuTuChoiScreenState extends State<PhieuTuChoiScreen> {
  // ===== Controllers =====
  final _tenNguoiKyCtrl = TextEditingController();
  final _quanHeCtrl = TextEditingController();
  final _diaChiCtrl = TextEditingController();
  final _soCccdCtrl = TextEditingController();
  final _khoaCtrl = TextEditingController();
  final _phongCtrl = TextEditingController();
  final _giuongCtrl = TextEditingController();
  final _gioCtrl = TextEditingController();
  final _phutCtrl = TextEditingController();
  final _phanMemCtrl = TextEditingController();
  final _nguyCoCtrl = TextEditingController();
  final _tenBacSiCtrl = TextEditingController();

  // ===== Loại người ký =====
  String? _laNguoiBenh; // 'BN' | 'TN'
  String? _gioiTinh; // 'NAM' | 'NU'

  // ===== Date =====
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;

  // ===== Signature =====
  final SignatureController _sigCtrlNB = SignatureController(
    penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );
  final SignatureController _sigCtrlBS = SignatureController(
    penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );

  bool _saving = false;

  String get _signerName {
    final session = HisProApiService.instance.session;
    return session?.userName ?? session?.loginName ?? 'Khoa Cấp Cứu';
  }

  String get _treatmentCode {
    final p = widget.patient;
    return (p['TDL_TREATMENT_CODE'] ?? p['tdl_treatment_code'] ?? '').toString();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = now.day;
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _gioCtrl.text = now.hour.toString().padLeft(2, '0');
    _phutCtrl.text = now.minute.toString().padLeft(2, '0');
    _prefillFromPatient();
  }

  void _prefillFromPatient() {
    final p = widget.patient;
    _tenNguoiKyCtrl.text =
        (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name'] ?? '').toString();
    if (_tenNguoiKyCtrl.text.isEmpty) {
      _tenNguoiKyCtrl.text = (p['VIR_PATIENT_NAME'] ?? '').toString();
    }
    final dob = (p['TDL_PATIENT_DOB'] ?? p['tdl_patient_dob'] ?? '').toString();
    final gender = (p['TDL_PATIENT_GENDER'] ?? p['gender'] ?? '').toString();
    if (gender.toUpperCase().contains('F') || gender == '0' || gender.toLowerCase().contains('nữ')) {
      _gioiTinh = 'NU';
    } else {
      _gioiTinh = 'NAM';
    }
    _khoaCtrl.text = (widget.department['name'] ?? '').toString();
  }

  @override
  void dispose() {
    _tenNguoiKyCtrl.dispose();
    _quanHeCtrl.dispose();
    _diaChiCtrl.dispose();
    _soCccdCtrl.dispose();
    _khoaCtrl.dispose();
    _phongCtrl.dispose();
    _giuongCtrl.dispose();
    _gioCtrl.dispose();
    _phutCtrl.dispose();
    _phanMemCtrl.dispose();
    _nguyCoCtrl.dispose();
    _tenBacSiCtrl.dispose();
    _sigCtrlNB.dispose();
    _sigCtrlBS.dispose();
    super.dispose();
  }

  // ===========================================================================
  // UI BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Giấy từ chối sử dụng dịch vụ'),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 8),
              _buildTitle(),
              const Divider(thickness: 1),
              _buildThongTinCaNhan(),
              const Divider(thickness: 1),
              _buildNoiDung(),
              const Divider(thickness: 1),
              _buildDateTimeSection(),
              const SizedBox(height: 12),
              _buildSignatureSection(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Hủy', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveEmr,
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload, size: 18),
                  label: Text(_saving ? 'Đang lưu...' : 'Lưu',
                      style: const TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB71C1C),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('SỞ Y TẾ TỈNH KHÁNH HÒA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SizedBox(height: 2),
              Text('BỆNH VIỆN ĐA KHOA NINH THUẬN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Text('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              SizedBox(height: 2),
              Text('Độc lập - Tự do - Hạnh phúc',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: Text('MS: 41/BV2',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: const Text(
            'GIẤY CAM KẾT TỪ CHỐI SỬ DỤNG DỊCH VỤ KHÁM BỆNH, CHỮA BỆNH',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFB71C1C)),
          ),
        ),
      ],
    );
  }

  Widget _buildThongTinCaNhan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('I. THÔNG TIN CÁ NHÂN CỦA NGƯỜI KÝ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        // Là người bệnh / thân nhân
        Row(
          children: [
            const Text('Là người bệnh', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            _radio('BN'),
            const SizedBox(width: 16),
            const Text('Là thân nhân', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            _radio('TN'),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Tôi tên là:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_tenNguoiKyCtrl, hint: 'Họ và tên')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Giới tính:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            _radioGT('NAM'),
            const Text('Nam', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 16),
            _radioGT('NU'),
            const Text('Nữ', style: TextStyle(fontSize: 13)),
          ],
        ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Quan hệ:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_quanHeCtrl, hint: 'Bố/Mẹ/Vợ/Chồng...')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Địa chỉ:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_diaChiCtrl, hint: 'Địa chỉ')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Số CCCD/Hộ chiếu:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_soCccdCtrl, hint: 'Số CCCD')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Đang điều trị tại Khoa:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_khoaCtrl, hint: 'Khoa')),
            const SizedBox(width: 8),
            const Text('Phòng:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: _redField(_phongCtrl, hint: 'P')),
            const SizedBox(width: 8),
            const Text('Giường:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: _redField(_giuongCtrl, hint: 'G')),
          ],
        ),
      ],
    );
  }

  Widget _buildNoiDung() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('II. NỘI DUNG',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        const Text('Phương pháp điều trị/chỉ định dự kiến thực hiện:',
            style: TextStyle(fontSize: 13)),
        _redField(_phanMemCtrl, hint: 'Mô tả phương pháp điều trị/chỉ định...', maxLines: 2),
        const SizedBox(height: 6),
        const Text(
          'Tôi đã được giải thích về lợi ích của phương pháp điều trị dự kiến, những nguy cơ, đặc biệt là những rủi ro, biến chứng có thể xảy ra nếu từ chối điều trị hoặc sử dụng dịch vụ khám bệnh, chữa bệnh nêu trên.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 6),
        const Text('Nguy cơ/rủi ro:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        _redField(_nguyCoCtrl, hint: 'Mô tả nguy cơ/rủi ro...', maxLines: 3),
      ],
    );
  }

  Widget _buildDateTimeSection() {
    return Row(
      children: [
        const Text('Thời gian: Giờ:', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        SizedBox(width: 50,
            child: _redField(_gioCtrl, hint: 'HH', keyboardType: TextInputType.number)),
        const Text('Phút:', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        SizedBox(width: 50,
            child: _redField(_phutCtrl, hint: 'mm', keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        const Text('Ngày:', style: TextStyle(fontSize: 13)),
        GestureDetector(
          onTap: _showDatePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.shade700),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Text(
                  '${(_selectedDay ?? 0).toString().padLeft(2, '0')}/'
                  '${(_selectedMonth ?? 0).toString().padLeft(2, '0')}/${_selectedYear ?? ''}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFFB71C1C)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.calendar_today, size: 16, color: Color(0xFFB71C1C)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _showDatePicker,
          icon: const Icon(Icons.edit_calendar, size: 16),
          label: const Text('Đổi'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB71C1C)),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Người bệnh/thân nhân
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Người bệnh/thân nhân:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Signature(controller: _sigCtrlNB, backgroundColor: Colors.white),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _sigCtrlNB.clear()),
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Xóa', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Bác sĩ điều trị
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bác sĩ điều trị:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Tên:', style: TextStyle(fontSize: 12)),
                  Expanded(child: _redField(_tenBacSiCtrl, hint: 'Tên BS')),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Signature(controller: _sigCtrlBS, backgroundColor: Colors.white),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _sigCtrlBS.clear()),
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Xóa', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // REUSABLE WIDGETS
  // ===========================================================================
  Widget _radio(String value) {
    return GestureDetector(
      onTap: () => setState(() => _laNguoiBenh = value),
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFB71C1C), width: 2),
          color: _laNguoiBenh == value ? const Color(0xFFB71C1C) : Colors.white,
        ),
      ),
    );
  }

  Widget _radioGT(String value) {
    return GestureDetector(
      onTap: () => setState(() => _gioiTinh = value),
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFB71C1C), width: 2),
          color: _gioiTinh == value ? const Color(0xFFB71C1C) : Colors.white,
        ),
      ),
    );
  }

  Widget _redField(TextEditingController? c,
      {String? hint, int maxLines = 1, TextInputType? keyboardType,
       Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFB71C1C), fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _showDatePicker() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _selectedYear ?? now.year,
        _selectedMonth ?? now.month,
        _selectedDay ?? now.day,
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDay = picked.day;
        _selectedMonth = picked.month;
        _selectedYear = picked.year;
      });
    }
  }

  // ===========================================================================
  // EMR SAVE
  // ===========================================================================
  Future<void> _saveEmr() async {
    if (_tenNguoiKyCtrl.text.isEmpty) {
      _toast('Vui lòng nhập tên người ký');
      return;
    }

    setState(() => _saving = true);
    try {
      final pdfBytes = await _buildPdf();
      final localPath = await _savePdfLocal(pdfBytes);

      final r = await AttachDocumentService.instance.attachFile(
        treatmentCode: _treatmentCode,
        documentTypeId: 20, // Phiếu khác
        documentName: 'GIẤY TỪ CHỐI SỬ DỤNG DỊCH VỤ',
        filePath: localPath,
        signerName: _signerName,
      );

      if (!mounted) return;
      setState(() => _saving = false);

      if (r.success) {
        _toast('✅ Đã lưu EMR thành công');
        Navigator.of(context).pop(true);
      } else {
        _toast('⚠️ Đã lưu local. EMR lỗi: ${r.error ?? "không rõ"}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Lỗi: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
  }

  // ===========================================================================
  // PDF GENERATION
  // ===========================================================================
  static pw.Font? _pdfFont;
  static pw.Font? _pdfFontBold;

  Future<void> _ensurePdfFonts() async {
    if (_pdfFont != null) return;
    try {
      final fontData = await rootBundle.load('assets/fonts/arial.ttf');
      final boldData = await rootBundle.load('assets/fonts/arialbd.ttf');
      _pdfFont = pw.Font.ttf(fontData.buffer.asByteData()!);
      _pdfFontBold = pw.Font.ttf(boldData.buffer.asByteData()!);
    } catch (e) {
      debugPrint('Failed to load Arial font: $e');
      _pdfFont = pw.Font.helvetica();
      _pdfFontBold = pw.Font.helveticaBold();
    }
  }

  pw.TextStyle _s(double size, {bool bold = false, PdfColor? color, pw.FontStyle style = pw.FontStyle.normal}) {
    return pw.TextStyle(
      font: bold ? (_pdfFontBold ?? _pdfFont) : _pdfFont,
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
      fontStyle: style,
    );
  }

  Future<Uint8List> _buildPdf() async {
    await _ensurePdfFonts();

    final now = DateTime.now();
    final pdfDate = DateTime(
      _selectedYear ?? now.year,
      _selectedMonth ?? now.month,
      _selectedDay ?? now.day,
    );

    final sigNbBytes = _sigCtrlNB.isNotEmpty ? await _sigCtrlNB.toPngBytes() : null;
    final sigBsBytes = _sigCtrlBS.isNotEmpty ? await _sigCtrlBS.toPngBytes() : null;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => [
          _pdfHeader(),
          _pdfTitle(),
          _pdfSection1(),
          _pdfSection2(),
          _pdfSignatureRow(sigNbBytes, sigBsBytes),
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfHeader() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('SỞ Y TẾ TỈNH KHÁNH HÒA', style: _s(11, bold: true)),
              pw.Text('BỆNH VIỆN ĐA KHOA NINH THUẬN', style: _s(11, bold: true)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM', style: _s(11, bold: true)),
              pw.Text('Độc lập - Tự do - Hạnh phúc', style: _s(10, style: pw.FontStyle.italic)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfTitle() {
    return pw.Column(
      children: [
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('MS: 41/BV2', style: _s(10, style: pw.FontStyle.italic)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Center(
            child: pw.Text(
              'GIẤY CAM KẾT TỪ CHỐI SỬ DỤNG DỊCH VỤ\nKHÁM BỆNH, CHỮA BỆNH',
              textAlign: pw.TextAlign.center,
              style: _s(13, bold: true, color: PdfColors.red900),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfSection1() {
    final isBN = _laNguoiBenh == 'BN';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('I. THÔNG TIN CÁ NHÂN CỦA NGƯỜI KÝ', style: _s(11, bold: true)),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text('Là người bệnh: ${isBN ? "☑" : "☐"}    Là thân nhân: ${!isBN ? "☑" : "☐"}', style: _s(11)),
          ],
        ),
        pw.SizedBox(height: 2),
        _pdfKv('Tôi tên là:', _tenNguoiKyCtrl.text),
        pw.Row(children: [
          pw.Text('Giới tính: ', style: _s(11)),
          pw.Text('Nam ${_gioiTinh == 'NAM' ? "☑" : "☐"}    Nữ ${_gioiTinh == 'NU' ? "☑" : "☐"}', style: _s(11)),
        ]),
        _pdfKv('Quan hệ với người bệnh:', _quanHeCtrl.text),
        _pdfKv('Địa chỉ:', _diaChiCtrl.text),
        _pdfKv('Số CCCD/Hộ chiếu:', _soCccdCtrl.text),
        pw.Row(children: [
          pw.Text('Đang điều trị tại Khoa: ', style: _s(11)),
          pw.Expanded(child: pw.Text(_khoaCtrl.text, style: _s(11, bold: true))),
          pw.Text('Phòng: ${_phongCtrl.text}', style: _s(11)),
          pw.Text('  Giường: ${_giuongCtrl.text}', style: _s(11)),
        ]),
      ],
    );
  }

  pw.Widget _pdfSection2() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text('II. NỘI DUNG', style: _s(11, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text('Phương pháp điều trị/chỉ định dự kiến thực hiện:', style: _s(11)),
        pw.Text(_phanMemCtrl.text.isEmpty ? '(...)' : _phanMemCtrl.text,
            style: _s(11, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Tôi đã được giải thích về lợi ích của phương pháp điều trị dự kiến, những nguy cơ, đặc biệt là những rủi ro, biến chứng có thể xảy ra nếu từ chối điều trị hoặc sử dụng dịch vụ khám bệnh, chữa bệnh nêu trên.',
          style: _s(11),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Nguy cơ/rủi ro:', style: _s(11, bold: true)),
        pw.Text(_nguyCoCtrl.text.isEmpty ? '(...)' : _nguyCoCtrl.text, style: _s(11)),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Text('Tôi xác nhận việc từ chối điều trị hoặc sử dụng dịch vụ y tế trên vào ', style: _s(11)),
        ]),
        pw.Row(children: [
          pw.Text('Giờ: ${_gioCtrl.text} : ${_phutCtrl.text}  Ngày: ', style: _s(11)),
          pw.Text(
            '${pdfDate.day.toString().padLeft(2, '0')} tháng ${pdfDate.month.toString().padLeft(2, '0')} năm ${pdfDate.year}',
            style: _s(11, bold: true),
          ),
        ]),
      ],
    );
  }

  pw.Widget _pdfSignatureRow(Uint8List? sigNb, Uint8List? sigBs) {
    pw.Widget _sigBox(String title, String name, Uint8List? bytes) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: _s(10, bold: true)),
              pw.SizedBox(height: 1),
              if (name.isNotEmpty) pw.Text(name, style: _s(9, style: pw.FontStyle.italic)),
              pw.SizedBox(height: 3),
              if (bytes != null)
                pw.Container(
                  height: 70,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(pw.MemoryImage(bytes), height: 70, fit: pw.BoxFit.contain),
                )
              else
                pw.Container(height: 70, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
              pw.SizedBox(height: 2),
              pw.Text('(Ký, ghi rõ họ tên)', style: _s(9, style: pw.FontStyle.italic)),
            ],
          ),
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sigBox('Người bệnh/thân nhân:', _tenNguoiKyCtrl.text, sigNb),
          _sigBox('Bác sĩ điều trị:', _tenBacSiCtrl.text, sigBs),
        ],
      ),
    );
  }

  pw.Widget _pdfKv(String key, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 140, child: pw.Text('$key ', style: _s(11))),
          pw.Expanded(
            child: pw.Text(value.isEmpty ? '(...)' : value,
                style: _s(11, bold: value.isNotEmpty)),
          ),
        ],
      ),
    );
  }

  DateTime get pdfDate {
    final now = DateTime.now();
    return DateTime(
      _selectedYear ?? now.year,
      _selectedMonth ?? now.month,
      _selectedDay ?? now.day,
    );
  }

  Future<String> _savePdfLocal(Uint8List pdfBytes) async {
    final treatmentCode = (widget.patient['TDL_TREATMENT_CODE'] ??
            widget.patient['treatment_code'] ?? 'BN')
        .toString();
    final fileName =
        'PhieuTuChoi_${treatmentCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final dir = await getApplicationDocumentsDirectory();
    final hisDir = Directory(pathJoin.join(dir.path, 'HisMobile'));
    if (!await hisDir.exists()) await hisDir.create(recursive: true);
    final file = File(pathJoin.join(hisDir.path, fileName));
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }
}
