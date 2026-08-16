// PhieuRaVienScreen v3.0.134 - GIẤY CAM KẾT RA VIỆN KHÔNG THEO CHỈ ĐỊNH CỦA BÁC SỸ
// Mẫu MS: 46/BV2 - BỆNH VIỆN ĐA KHOA NINH THUẬN
// v3.0.134: Arial font + date picker + 2 chỗ ký + EMR upload
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

/// v3.0.134: Form Giấy cam kết ra viện không theo chỉ định của bác sĩ
/// Mẫu: MS 46/BV2 - BỆNH VIỆN ĐA KHOA NINH THUẬN

class PhieuRaVienScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const PhieuRaVienScreen({
    super.key,
    required this.patient,
    required this.department,
  });

  @override
  State<PhieuRaVienScreen> createState() => _PhieuRaVienScreenState();
}

class _PhieuRaVienScreenState extends State<PhieuRaVienScreen> {
  // ===== Controllers =====
  final _tenNguoiKyCtrl = TextEditingController();
  final _ngaySinhCtrl = TextEditingController();
  final _tuoiCtrl = TextEditingController();
  final _soCccdCtrl = TextEditingController();
  final _diaChiCtrl = TextEditingController();
  final _quanHeCtrl = TextEditingController();
  final _khoaCtrl = TextEditingController();
  final _phongCtrl = TextEditingController();

  final _loiIchCtrl = TextEditingController();
  final _nguyCoKhamCtrl = TextEditingController();
  final _nguyCoDieuTriCtrl = TextEditingController();
  final _nguyCoRaVienCtrl = TextEditingController();
  final _nguyenLyChuyenVienCtrl = TextEditingController();
  final _nguyCoChuyenVienCtrl = TextEditingController();
  final _tenBacSiCtrl = TextEditingController();

  // ===== Radio selections =====
  String? _laNguoiBenh; // 'BN' | 'TN'
  String? _lyDo; // 'KHAM' | 'DIEUTRI' | 'NAMVIEN' | 'CHUYENVIEN'
  String? _khongLamXn; // 'CO' | null

  // ===== Date =====
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;

  // ===== Signatures =====
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
    if (dob.isNotEmpty && dob.length >= 10) {
      _ngaySinhCtrl.text = dob;
    }
    _khoaCtrl.text = (widget.department['name'] ?? '').toString();
  }

  @override
  void dispose() {
    _tenNguoiKyCtrl.dispose();
    _ngaySinhCtrl.dispose();
    _tuoiCtrl.dispose();
    _soCccdCtrl.dispose();
    _diaChiCtrl.dispose();
    _quanHeCtrl.dispose();
    _khoaCtrl.dispose();
    _phongCtrl.dispose();
    _loiIchCtrl.dispose();
    _nguyCoKhamCtrl.dispose();
    _nguyCoDieuTriCtrl.dispose();
    _nguyCoRaVienCtrl.dispose();
    _nguyenLyChuyenVienCtrl.dispose();
    _nguyCoChuyenVienCtrl.dispose();
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
        title: const Text('Giấy ra viện không theo chỉ định BS'),
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
              const SizedBox(height: 6),
              _buildTitle(),
              const Divider(thickness: 1),
              _buildThongTinBN(),
              const Divider(thickness: 1),
              _buildXacNhan(),
              const Divider(thickness: 1),
              _buildNguyCo(),
              const Divider(thickness: 1),
              _buildXacNhanNguoiBenh(),
              const SizedBox(height: 12),
              _buildDateSection(),
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
          child: Text('MS: 46/BV2',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: const Text(
            'GIẤY CAM KẾT RA VIỆN KHÔNG THEO CHỈ ĐỊNH CỦA BÁC SỸ\n(Khi chưa kết thúc việc chữa bệnh)',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFB71C1C)),
          ),
        ),
      ],
    );
  }

  Widget _buildThongTinBN() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            const Text('Ngày sinh:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(width: 100, child: _redField(_ngaySinhCtrl, hint: 'dd/MM/yyyy')),
            const SizedBox(width: 12),
            const Text('Tuổi:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: _redField(_tuoiCtrl, hint: '...', keyboardType: TextInputType.number)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Họ tên:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_tenNguoiKyCtrl, hint: 'Họ và tên')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Số CCCD:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_soCccdCtrl, hint: 'Số CCCD/Hộ chiếu')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Địa chỉ:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_diaChiCtrl, hint: 'Địa chỉ')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Quan hệ:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(width: 100, child: _redField(_quanHeCtrl, hint: 'Cha/Mẹ/Vợ...')),
            const SizedBox(width: 12),
            const Text('Khoa:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_khoaCtrl, hint: 'Khoa')),
            const SizedBox(width: 8),
            const Text('P:', style: TextStyle(fontSize: 13)),
            SizedBox(width: 50, child: _redField(_phongCtrl, hint: 'P')),
          ],
        ),
      ],
    );
  }

  Widget _buildXacNhan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('XÁC NHẬN CỦA NGƯỜI BỆNH/THÂN NHÂN',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB71C1C))),
        const SizedBox(height: 8),
        const Text(
          'Tôi xác nhận rằng tôi đã giải thích cho người bệnh/thân nhân về các nguy cơ và lợi ích của việc điều trị (hoặc chuyển viện, xuất viện sớm) được đề xuất như mô tả dưới đây.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text('Từ chối chấp thuận:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _checkBox('Khám bệnh/Điều trị/Nằm viện', _lyDo == 'KHAM',
            (v) => setState(() => _lyDo = v ? 'KHAM' : null)),
        const SizedBox(height: 4),
        _checkBox('Chuyển viện đến cơ sở y tế khác', _lyDo == 'CHUYENVIEN',
            (v) => setState(() => _lyDo = v ? 'CHUYENVIEN' : null)),
        const SizedBox(height: 6),
        _checkBox('Không đồng ý làm xét nghiệm nồng độ cồn và ma túy', _khongLamXn == 'CO',
            (v) => setState(() => _khongLamXn = v ? 'CO' : null)),
        const SizedBox(height: 8),
        const Text('Lý do/lợi ích của việc khám bệnh/điều trị/nằm viện được đề xuất:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        _redField(_loiIchCtrl, hint: 'Mô tả...', maxLines: 3),
        const SizedBox(height: 6),
        if (_lyDo == 'CHUYENVIEN') ...[
          const Text('Lý do chuyển viện được đề xuất:', style: TextStyle(fontSize: 13)),
          _redField(_nguyenLyChuyenVienCtrl, hint: 'Lý do...', maxLines: 2),
        ],
      ],
    );
  }

  Widget _buildNguyCo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Các nguy cơ:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        if (_lyDo == 'KHAM' || _lyDo == 'DIEUTRI' || _lyDo == 'NAMVIEN') ...[
          const Text('Các nguy cơ của việc từ chối khám bệnh/điều trị/nằm viện:',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          _redField(_nguyCoKhamCtrl, hint: 'Nguy cơ khi từ chối...', maxLines: 2),
        ],
        if (_lyDo == 'CHUYENVIEN') ...[
          const Text('Các nguy cơ của việc từ chối chuyển viện:',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          _redField(_nguyCoChuyenVienCtrl, hint: 'Nguy cơ khi từ chối chuyển viện...', maxLines: 2),
        ],
        const SizedBox(height: 6),
        const Text('Các nguy cơ về sức khỏe do xuất viện sớm:',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
        _redField(_nguyCoRaVienCtrl, hint: 'Nguy cơ xuất viện sớm...', maxLines: 2),
      ],
    );
  }

  Widget _buildXacNhanNguoiBenh() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('XÁC NHẬN CỦA NGƯỜI BỆNH/THÂN NHÂN',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB71C1C))),
        const SizedBox(height: 6),
        const Text(
          'Bằng việc ký vào mẫu đơn này, tôi xác nhận quyết định của tôi về việc không làm theo chỉ định, lời khuyên của bác sỹ và xác nhận rằng tôi nhận thức về các rủi ro đối với tôi/thân nhân của tôi do không làm theo chỉ định, lời khuyên của bác sỹ.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Xác nhận của Bác sĩ:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_tenBacSiCtrl, hint: 'Tên bác sĩ')),
          ],
        ),
      ],
    );
  }

  Widget _buildDateSection() {
    return Row(
      children: [
        const Text('Ngày ký:', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
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
                  '${(_selectedDay ?? 0).toString().padLeft(2, '0')} tháng ${(_selectedMonth ?? 0).toString().padLeft(2, '0')} năm ${_selectedYear ?? ''}',
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bác sĩ điều trị:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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

  Widget _checkBox(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value ? '☑' : '☐',
              style: const TextStyle(fontSize: 16, color: Color(0xFFB71C1C))),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _redField(TextEditingController? c,
      {String? hint, int maxLines = 1, TextInputType? keyboardType}) {
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
    final initialDate = DateTime(
      _selectedYear ?? now.year,
      _selectedMonth ?? now.month,
      _selectedDay ?? now.day,
    );
    // Capture mounted state BEFORE await
    final isMounted = mounted;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null && isMounted) {
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
        documentTypeId: 20,
        documentName: 'GIẤY RA VIỆN KHÔNG THEO CHỈ ĐỊNH BÁC SỸ',
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
      final fontData = await rootBundle.load('assets/fonts/times.ttf');
      final boldData = await rootBundle.load('assets/fonts/timesbd.ttf');
      _pdfFont = pw.Font.ttf(fontData.buffer.asByteData()!);
      _pdfFontBold = pw.Font.ttf(boldData.buffer.asByteData()!);
    } catch (e) {
      debugPrint('Failed to load Times New Roman font: $e');
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
          _pdfThongTinBN(),
          _pdfXacNhan(),
          _pdfNguyCo(),
          _pdfXacNhanNB(),
          _pdfDateRow(pdfDate),
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
          child: pw.Text('MS: 46/BV2', style: _s(10, style: pw.FontStyle.italic)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Center(
            child: pw.Text(
              'GIẤY CAM KẾT RA VIỆN\nKHÔNG THEO CHỈ ĐỊNH CỦA BÁC SỸ\n(Khi chưa kết thúc việc chữa bệnh)',
              textAlign: pw.TextAlign.center,
              style: _s(13, bold: true, color: PdfColors.red900),
            ),
          ),
        ),
        pw.Text('Kính gửi: BỆNH VIỆN ĐA KHOA NINH THUẬN', style: _s(11)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Qua đơn này tôi cam kết không để cơ sở khám bệnh, chữa bệnh và các nhân viên y tế có liên quan đã điều trị/tư vấn cho tôi/thân nhân của tôi phải chịu trách nhiệm vì đã không điều trị hoặc chuyển viện hoặc xuất viện như đã nêu trên.',
          style: _s(10, style: pw.FontStyle.italic),
        ),
      ],
    );
  }

  pw.Widget _pdfThongTinBN() {
    final isBN = _laNguoiBenh == 'BN';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Text('Là người bệnh: ${isBN ? "☑" : "☐"}    ', style: _s(11)),
          pw.Text('Là thân nhân: ${!isBN ? "☑" : "☐"}', style: _s(11)),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          pw.Text('Ngày sinh: ${_ngaySinhCtrl.text}    ', style: _s(11)),
          pw.Text('Tuổi: ${_tuoiCtrl.text}', style: _s(11)),
        ]),
        _pdfKv('Họ tên người bệnh:', _tenNguoiKyCtrl.text),
        _pdfKv('Số CCCD/Hộ chiếu:', _soCccdCtrl.text),
        _pdfKv('Địa chỉ:', _diaChiCtrl.text),
        pw.Row(children: [
          pw.Text('Quan hệ: ${_quanHeCtrl.text}    ', style: _s(11)),
          pw.Text('Khoa: ${_khoaCtrl.text}    Phòng: ${_phongCtrl.text}', style: _s(11)),
        ]),
      ],
    );
  }

  pw.Widget _pdfXacNhan() {
    final lyDoMap = {
      'KHAM': 'Khám bệnh/Điều trị/Nằm viện',
      'CHUYENVIEN': 'Chuyển viện đến cơ sở y tế khác',
    };
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text('XÁC NHẬN CỦA NGƯỜI BỆNH/THÂN NHÂN', style: _s(11, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Tôi xác nhận rằng tôi đã giải thích cho người bệnh/thân nhân về các nguy cơ và lợi ích của việc điều trị (hoặc chuyển viện, xuất viện sớm) được đề xuất như mô tả dưới đây.',
          style: _s(10),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Từ chối chấp thuận:', style: _s(11, bold: true)),
        for (final e in lyDoMap.entries)
          pw.Text('${_lyDo == e.key ? "☑" : "☐"} ${e.value}', style: _s(10)),
        pw.Text('${_khongLamXn == 'CO' ? "☑" : "☐"} Không đồng ý làm xét nghiệm nồng độ cồn và ma túy', style: _s(10)),
        pw.SizedBox(height: 4),
        pw.Text('Lý do/lợi ích của việc khám bệnh/điều trị/nằm viện được đề xuất:', style: _s(10, bold: true)),
        pw.Text(_loiIchCtrl.text.isEmpty ? '(...)' : _loiIchCtrl.text, style: _s(10)),
        if (_lyDo == 'CHUYENVIEN') ...[
          pw.SizedBox(height: 4),
          pw.Text('Lý do chuyển viện được đề xuất:', style: _s(10, bold: true)),
          pw.Text(_nguyenLyChuyenVienCtrl.text.isEmpty ? '(...)' : _nguyenLyChuyenVienCtrl.text, style: _s(10)),
        ],
      ],
    );
  }

  pw.Widget _pdfNguyCo() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text('Các nguy cơ:', style: _s(11, bold: true)),
        if (_lyDo == 'CHUYENVIEN') ...[
          pw.Text('Các nguy cơ của việc từ chối chấp thuận chuyển viện:', style: _s(10, style: pw.FontStyle.italic)),
          pw.Text(_nguyCoChuyenVienCtrl.text.isEmpty ? '(...)' : _nguyCoChuyenVienCtrl.text, style: _s(10)),
        ] else ...[
          pw.Text('Các nguy cơ của việc từ chối khám bệnh/điều trị/nằm viện:', style: _s(10, style: pw.FontStyle.italic)),
          pw.Text(_nguyCoKhamCtrl.text.isEmpty ? '(...)' : _nguyCoKhamCtrl.text, style: _s(10)),
        ],
        pw.SizedBox(height: 4),
        pw.Text('Các nguy cơ về sức khỏe do xuất viện sớm:', style: _s(10, style: pw.FontStyle.italic)),
        pw.Text(_nguyCoRaVienCtrl.text.isEmpty ? '(...)' : _nguyCoRaVienCtrl.text, style: _s(10)),
      ],
    );
  }

  pw.Widget _pdfXacNhanNB() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text('XÁC NHẬN CỦA NGƯỜI BỆNH/THÂN NHÂN', style: _s(11, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Bằng việc ký vào mẫu đơn này, tôi xác nhận quyết định của tôi về việc không làm theo chỉ định, lời khuyên của bác sỹ và xác nhận rằng tôi nhận thức về các rủi ro đối với tôi/thân nhân của tôi do không làm theo chỉ định, lời khuyên của bác sỹ.',
          style: _s(10),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Xác nhận của Bác sĩ: ${_tenBacSiCtrl.text}', style: _s(10, bold: true)),
      ],
    );
  }

  pw.Widget _pdfDateRow(DateTime d) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            'Ngày ${d.day.toString().padLeft(2, '0')} tháng ${d.month.toString().padLeft(2, '0')} năm ${d.year}',
            style: _s(11, bold: true),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSignatureRow(Uint8List? sigNb, Uint8List? sigBs) {
    pw.Widget _sigBox(String title, Uint8List? bytes) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: _s(10, bold: true)),
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
              pw.Text('(Ký & ghi rõ họ tên)', style: _s(9, style: pw.FontStyle.italic)),
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
          _sigBox('Người bệnh/thân nhân:', sigNb),
          _sigBox('Bác sĩ điều trị:', sigBs),
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
          pw.SizedBox(width: 130, child: pw.Text('$key ', style: _s(11))),
          pw.Expanded(
            child: pw.Text(value.isEmpty ? '(...)' : value,
                style: _s(11, bold: value.isNotEmpty)),
          ),
        ],
      ),
    );
  }

  Future<String> _savePdfLocal(Uint8List pdfBytes) async {
    final treatmentCode = (widget.patient['TDL_TREATMENT_CODE'] ??
            widget.patient['treatment_code'] ?? 'BN')
        .toString();
    final fileName =
        'PhieuRaVien_${treatmentCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final dir = await getApplicationDocumentsDirectory();
    final hisDir = Directory(pathJoin.join(dir.path, 'HisMobile'));
    if (!await hisDir.exists()) await hisDir.create(recursive: true);
    final file = File(pathJoin.join(hisDir.path, fileName));
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }
}
