// PhieuBanGiaoScreen v3.0.135 - PHIẾU BÀN GIAO NGƯỜI BỆNH CHUYỂN KHOA
// Mẫu MS: 43/BV2 - BỆNH VIỆN ĐA KHOA NINH THUẬN
// v3.0.135: Tương tự các PHIẾU khác - Arial font + editable date/time + 2 chữ ký BS + EMR upload
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
import 'package:his_mobile/data/services/phieu_save_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/local/scanned_forms_service.dart';
import 'package:his_mobile/data/services/pdf_to_image_service.dart';

/// v3.0.135: Form Phiếu bàn giao người bệnh chuyển khoa
/// Mẫu: MS 43/BV2 - BỆNH VIỆN ĐA KHOA NINH THUẬN

class PhieuBanGiaoScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const PhieuBanGiaoScreen({
    super.key,
    required this.patient,
    required this.department,
  });

  @override
  State<PhieuBanGiaoScreen> createState() => _PhieuBanGiaoScreenState();
}

class _PhieuBanGiaoScreenState extends State<PhieuBanGiaoScreen> {
  // ===== Controllers =====
  final _lyDoChuyenCtrl = TextEditingController();
  final _lyDoNhapVienCtrl = TextEditingController();
  final _dienBienCtrl = TextEditingController();
  final _chanDoanCtrl = TextEditingController();
  final _daCanThiepCtrl = TextEditingController();
  final _tinhTrangCtrl = TextEditingController();
  final _keHoachCtrl = TextEditingController();
  final _khoaNhanCtrl = TextEditingController();
  final _bsGiaoCtrl = TextEditingController();
  final _bsNhanCtrl = TextEditingController();
  final _phongCtrl = TextEditingController();
  final _giuongCtrl = TextEditingController();
  final _gioCtrl = TextEditingController();
  final _phutCtrl = TextEditingController();
  final _ngayCtrl = TextEditingController();
  final _thangCtrl = TextEditingController();
  final _namCtrl = TextEditingController();

  // ===== Signature =====
  final SignatureController _sigCtrlGiao = SignatureController(
    penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );
  final SignatureController _sigCtrlNhan = SignatureController(
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
    _ngayCtrl.text = now.day.toString().padLeft(2, '0');
    _thangCtrl.text = now.month.toString().padLeft(2, '0');
    _namCtrl.text = now.year.toString();
    _gioCtrl.text = now.hour.toString().padLeft(2, '0');
    _phutCtrl.text = now.minute.toString().padLeft(2, '0');
    _prefillFromPatient();
  }

  void _prefillFromPatient() {
    final p = widget.patient;
    // Name
    final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name'] ?? '').toString();
    if (name.isNotEmpty) {
      _bsGiaoCtrl.text = name;
    }
    // Department
    _khoaNhanCtrl.text = (widget.department['name'] ?? '').toString();
    // Room/bed
    final bed = (p['BED_CODE'] ?? p['bed_code'] ?? '').toString();
    if (bed.contains('-')) {
      final parts = bed.split('-');
      if (parts.length >= 2) {
        _phongCtrl.text = parts[0];
        _giuongCtrl.text = parts.sublist(1).join('-');
      } else {
        _giuongCtrl.text = bed;
      }
    } else {
      _giuongCtrl.text = bed;
    }
    // Diagnosis
    _chanDoanCtrl.text =
        (p['ICD_NAME'] ?? p['icd_name'] ?? p['ICD_END_MAIN_TEXT'] ?? '').toString();
    // Hospitalization reason
    _lyDoNhapVienCtrl.text =
        (p['HOSPITALIZATION_REASON'] ?? p['TREATMENT_INSTRUCTION'] ?? '').toString();
  }

  @override
  void dispose() {
    _lyDoChuyenCtrl.dispose();
    _lyDoNhapVienCtrl.dispose();
    _dienBienCtrl.dispose();
    _chanDoanCtrl.dispose();
    _daCanThiepCtrl.dispose();
    _tinhTrangCtrl.dispose();
    _keHoachCtrl.dispose();
    _khoaNhanCtrl.dispose();
    _bsGiaoCtrl.dispose();
    _bsNhanCtrl.dispose();
    _phongCtrl.dispose();
    _giuongCtrl.dispose();
    _gioCtrl.dispose();
    _phutCtrl.dispose();
    _ngayCtrl.dispose();
    _thangCtrl.dispose();
    _namCtrl.dispose();
    _sigCtrlGiao.dispose();
    _sigCtrlNhan.dispose();
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
        title: const Text('Phiếu bàn giao chuyển khoa'),
        backgroundColor: const Color(0xFF6A1B9A),
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
              _buildThongTinBenhNhan(),
              const Divider(thickness: 1),
              _buildNoiDungBanGiao(),
              const Divider(thickness: 1),
              _buildKhoaVaThoiGian(),
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
                    backgroundColor: const Color(0xFF6A1B9A),
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              SizedBox(height: 2),
              Text('Độc lập - Tự do - Hạnh phúc',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11)),
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
          child: Text('MS: 43/BV2',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: const Text(
            'PHIẾU BÀN GIAO NGƯỜI BỆNH CHUYỂN KHOA',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF6A1B9A)),
          ),
        ),
        const Text(
          '(Dành cho Bác sĩ)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildThongTinBenhNhan() {
    final p = widget.patient;
    final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name'] ?? '').toString()
        .isNotEmpty
        ? (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name']).toString()
        : (p['VIR_PATIENT_NAME'] ?? '').toString();
    final dob = (p['TDL_PATIENT_DOB'] ?? p['tdl_patient_dob'] ?? '').toString();
    final gender = (p['TDL_PATIENT_GENDER'] ?? p['gender'] ?? '').toString();
    String genderLabel = gender;
    if (gender.toUpperCase().contains('F') || gender == '0' || gender.toLowerCase().contains('nữ')) {
      genderLabel = 'Nữ';
    } else {
      genderLabel = 'Nam';
    }

    String ageLabel = '';
    if (dob.isNotEmpty) {
      try {
        final birthDate = DateTime.parse(dob.substring(0, 10));
        final age = DateTime.now().difference(birthDate).inDays ~/ 365;
        if (age > 0) {
          ageLabel = '$age tuổi';
        } else {
          final months = DateTime.now().difference(birthDate).inDays ~/ 30;
          ageLabel = '$months tháng';
        }
      } catch (_) {
        ageLabel = dob;
      }
    }

    final treatmentCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('I. THÔNG TIN NGƯỜI BỆNH',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6A1B9A))),
        const SizedBox(height: 8),
        // Số vào viện + Mã NB
        if (treatmentCode.isNotEmpty)
          Row(
            children: [
              const Text('Số vào viện:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF6A1B9A)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(treatmentCode,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6A1B9A))),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        // Họ tên + tuổi + giới
        Row(
          children: [
            const Text('Họ và tên:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.red.shade700)),
                ),
                child: Text(name.isEmpty ? '...' : name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Tuổi:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.red.shade700)),
              ),
              child: Text(ageLabel.isEmpty ? '...' : ageLabel,
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            const Text('Giới:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.red.shade700)),
              ),
              child: Text(genderLabel, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Khoa + Phòng + Giường
        Row(
          children: [
            const Text('Khoa:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.red.shade700)),
                ),
                child: const Text('Cấp cứu',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Phòng:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(
              width: 50,
              child: _redField(_phongCtrl, hint: 'P'),
            ),
            const SizedBox(width: 8),
            const Text('Giường:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(
              width: 60,
              child: _redField(_giuongCtrl, hint: 'G'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoiDungBanGiao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('II. THÔNG TIN BÀN GIAO',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6A1B9A))),
        const SizedBox(height: 8),
        // Lý do chuyển
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Lý do chuyển:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_lyDoChuyenCtrl, hint: 'Lý do chuyển khoa...', maxLines: 2),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Lý do nhập viện
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Lý do nhập viện:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_lyDoNhapVienCtrl, hint: 'Lý do nhập viện...', maxLines: 2),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Diễn biến bệnh
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Diễn biến bệnh:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_dienBienCtrl, hint: 'Diễn biến lâm sàng...', maxLines: 3),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Chẩn đoán
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Chẩn đoán:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_chanDoanCtrl, hint: 'ICD chẩn đoán...', maxLines: 2),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Đã can thiệp
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Đã can thiệp:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_daCanThiepCtrl, hint: 'Các can thiệp đã thực hiện...', maxLines: 2),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Tình trạng hiện tại
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Tình trạng hiện tại:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_tinhTrangCtrl, hint: 'Tình trạng người bệnh hiện tại...', maxLines: 3),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Kế hoạch điều trị tiếp theo
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 120,
              child: Text('Kế hoạch điều trị tiếp theo:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: _redField(_keHoachCtrl, hint: 'Kế hoạch điều trị...', maxLines: 2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKhoaVaThoiGian() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('III. KHOA VÀ THỜI GIAN BÀN GIAO',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6A1B9A))),
        const SizedBox(height: 8),
        // 3 cột: Khoa bàn giao | Khoa nhận | Thời gian
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Khoa bàn giao
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Khoa bàn giao:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF6A1B9A)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Khoa Cấp cứu',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6A1B9A))),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Khoa nhận
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Khoa nhận:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  _redField(_khoaNhanCtrl, hint: 'Tên khoa nhận'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Thời gian
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Thời gian bàn giao:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: _redField(_gioCtrl, hint: 'HH', keyboardType: TextInputType.number),
                      ),
                      const Text(' : ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(
                        width: 36,
                        child: _redField(_phutCtrl, hint: 'mm', keyboardType: TextInputType.number),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: _redField(_ngayCtrl, hint: 'DD', keyboardType: TextInputType.number),
                      ),
                      const Text(' / ', style: TextStyle(fontSize: 12)),
                      SizedBox(
                        width: 32,
                        child: _redField(_thangCtrl, hint: 'MM', keyboardType: TextInputType.number),
                      ),
                      const Text(' / ', style: TextStyle(fontSize: 12)),
                      SizedBox(
                        width: 52,
                        child: _redField(_namCtrl, hint: 'YYYY', keyboardType: TextInputType.number),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BS giao
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bác sỹ bàn giao (ký, ghi rõ họ tên):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              _redField(_bsGiaoCtrl, hint: 'Tên bác sỹ giao'),
              const SizedBox(height: 4),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Signature(controller: _sigCtrlGiao, backgroundColor: Colors.white),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _sigCtrlGiao.clear()),
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Xóa', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // BS nhận
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bác sỹ nhận (ký, ghi rõ họ tên):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              _redField(_bsNhanCtrl, hint: 'Tên bác sỹ nhận'),
              const SizedBox(height: 4),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Signature(controller: _sigCtrlNhan, backgroundColor: Colors.white),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _sigCtrlNhan.clear()),
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
  Widget _redField(TextEditingController? c,
      {String? hint, int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFF6A1B9A), fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6A1B9A), fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  // ===========================================================================
  // EMR SAVE
  // ===========================================================================
  /// v3.0.141: Lưu PDF (TNKeyUni font) + push EMR theo PhieuSaveService (SCAN PHIẾU pattern)
  Future<void> _saveEmr() async {
    setState(() => _saving = true);
    try {
      final pdfBytes = await _buildPdf();
      // v3.0.145: Render PDF → PNG → EMR (font trên server không garble nữa)
      final pngBytes = await PdfToImageService.pdfToPngPdf(pdfBytes);

      // v3.0.141: Dùng PhieuSaveService với prebuiltPdfBytes - font TNKeyUni đúng cho EMR
      final result = await PhieuSaveService.instance.save(
        mode: PhieuSaveMode.unsigned,
        input: PhieuSaveInput(
          patient: widget.patient,
          formName: 'PHIẾU BÀN GIAO CHUYỂN KHOA',
          formData: const {},
          documentTypeId: 20,
          prebuiltPdfBytes: pngBytes ?? pdfBytes,
          workingDeptName: 'Khoa Cấp Cứu',
          departmentCode: 'HSCC',
          roomCode: 'PKCC',
          roomTypeCode: 'XL',
        ),
      );

      if (!mounted) return;
      setState(() => _saving = false);

      if (result.emrPushed) {
        _toast('✅ Đã lưu EMR thành công');
        Navigator.of(context).pop(true);
      } else if (result.success) {
        _toast('⚠️ Đã lưu local. EMR: ${result.error}');
      } else {
        _toast('❌ Lỗi: ${result.error}');
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
      // v3.0.140: TNKeyUni Times New Roman - font chuẩn HIS Pro (full Vietnamese glyphs)
      final fontData = await rootBundle.load('assets/fonts/times.ttf');
      final boldData = await rootBundle.load('assets/fonts/timesbd.ttf');
      _pdfFont = pw.Font.ttf(fontData.buffer.asByteData()!);
      _pdfFontBold = pw.Font.ttf(boldData.buffer.asByteData()!);
    } catch (e) {
      debugPrint('Failed to load TNKeyUni font: $e');
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

    final sigGiaoBytes = _sigCtrlGiao.isNotEmpty ? await _sigCtrlGiao.toPngBytes() : null;
    final sigNhanBytes = _sigCtrlNhan.isNotEmpty ? await _sigCtrlNhan.toPngBytes() : null;

    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: _pdfFont));
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => [
          _pdfHeader(),
          _pdfTitle(),
          _pdfSection1(),
          pw.SizedBox(height: 8),
          _pdfSection2(),
          pw.SizedBox(height: 8),
          _pdfSection3(),
          pw.SizedBox(height: 12),
          _pdfSignatureRow(sigGiaoBytes, sigNhanBytes),
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
              pw.Text('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM', style: _s(10, bold: true)),
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
          child: pw.Text('MS: 43/BV2', style: _s(10, style: pw.FontStyle.italic)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Center(
            child: pw.Text(
              'PHIẾU BÀN GIAO NGƯỜI BỆNH CHUYỂN KHOA\n(Dành cho Bác sĩ)',
              textAlign: pw.TextAlign.center,
              style: _s(13, bold: true, color: PdfColors.purple900),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfSection1() {
    final p = widget.patient;
    final name = (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name'] ?? '').toString()
        .isNotEmpty
        ? (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name']).toString()
        : (p['VIR_PATIENT_NAME'] ?? '').toString();
    final treatmentCode = (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? '').toString();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('I. THÔNG TIN NGƯỜI BỆNH', style: _s(11, bold: true, color: PdfColors.purple900)),
        pw.SizedBox(height: 4),
        if (treatmentCode.isNotEmpty)
          pw.Row(children: [
            pw.Text('Số vào viện: ', style: _s(11)),
            pw.Expanded(child: pw.Text(treatmentCode, style: _s(11, bold: true))),
          ]),
        pw.Row(children: [
          pw.Text('Họ và tên: ', style: _s(11)),
          pw.Expanded(child: pw.Text(name.isEmpty ? '(...)' : name, style: _s(11, bold: true))),
          pw.Text('Khoa: ', style: _s(11)),
          pw.Text('Cấp cứu', style: _s(11, bold: true)),
          pw.Text('  Phòng: ${_phongCtrl.text}', style: _s(11)),
          pw.Text('  Giường: ${_giuongCtrl.text}', style: _s(11)),
        ]),
      ],
    );
  }

  pw.Widget _pdfSection2() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('II. THÔNG TIN BÀN GIAO', style: _s(11, bold: true, color: PdfColors.purple900)),
        pw.SizedBox(height: 4),
        _pdfKv('Lý do chuyển:', _lyDoChuyenCtrl.text),
        _pdfKv('Lý do nhập viện:', _lyDoNhapVienCtrl.text),
        _pdfKv('Diễn biến bệnh:', _dienBienCtrl.text),
        _pdfKv('Chẩn đoán:', _chanDoanCtrl.text),
        _pdfKv('Đã can thiệp:', _daCanThiepCtrl.text),
        _pdfKv('Tình trạng hiện tại:', _tinhTrangCtrl.text),
        _pdfKv('Kế hoạch điều trị tiếp theo:', _keHoachCtrl.text),
      ],
    );
  }

  pw.Widget _pdfSection3() {
    final ngay = _ngayCtrl.text.padLeft(2, '0');
    final thang = _thangCtrl.text.padLeft(2, '0');
    final nam = _namCtrl.text;
    final gio = _gioCtrl.text.padLeft(2, '0');
    final phut = _phutCtrl.text.padLeft(2, '0');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('III. KHOA VÀ THỜI GIAN BÀN GIAO', style: _s(11, bold: true, color: PdfColors.purple900)),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Khoa bàn giao:', style: _s(10)),
                pw.Text('Khoa Cấp cứu', style: _s(11, bold: true)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Khoa nhận:', style: _s(10)),
                pw.Text(_khoaNhanCtrl.text.isEmpty ? '(...)' : _khoaNhanCtrl.text,
                    style: _s(11, bold: true)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Thời gian bàn giao:', style: _s(10)),
                pw.Text('$gio:$phut  $ngay/$thang/$nam', style: _s(11, bold: true)),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  pw.Widget _pdfSignatureRow(Uint8List? sigGiao, Uint8List? sigNhan) {
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
          _sigBox('Bác sỹ bàn giao:', _bsGiaoCtrl.text, sigGiao),
          _sigBox('Bác sỹ nhận:', _bsNhanCtrl.text, sigNhan),
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

  Future<String> _savePdfLocal(Uint8List pdfBytes) async {
    final treatmentCode = (widget.patient['TDL_TREATMENT_CODE'] ??
            widget.patient['treatment_code'] ?? 'BN')
        .toString();
    final fileName =
        'PhieuBanGiao_${treatmentCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final dir = await getApplicationDocumentsDirectory();
    final hisDir = Directory(pathJoin.join(dir.path, 'HisMobile'));
    if (!await hisDir.exists()) await hisDir.create(recursive: true);
    final file = File(pathJoin.join(hisDir.path, fileName));
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }
}
