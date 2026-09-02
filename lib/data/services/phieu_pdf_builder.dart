// PDF generator matching HIS Pro EMR style (BVĐK Ninh Thuận)
// Reference: D:\Soft\HISPRO_THAT\Integrate\EMR\temp\DDMMYYYY\*.pdf
// Layout:
//   - Header trái: SỞ Y TẾ TỈNH NINH THUẬN / BỆNH VIỆN ĐA KHOA NINH THUẬN / Khoa X
//   - Tiêu đề giữa: in hoa, bold
//   - Phải: MS, Số vào viện, Mã người bệnh
//   - Bảng thông tin BN 1-9
//   - Body: section I, II, III, IV...
//   - Footer: ký tên BS (2 cột: gửi + nhận / BS điều trị + BS trưởng khoa)
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PhieuPdf {
  final String id;
  final String name;
  final String shortName;
  final IconDataType icon;
  const PhieuPdf({required this.id, required this.name, required this.shortName, required this.icon});
}

class IconDataType {
  final int codePoint;
  const IconDataType(this.codePoint);
}

/// 13 phiếu theo BS (anh Nểm screenshot Y Tế Số reference)
class PhieuCatalog {
  static const List<PhieuPdf> all = [
    PhieuPdf(id: 'benh_an_cap_cuu', name: 'BỆNH ÁN CẤP CỨU', shortName: 'Bệnh án CC', icon: IconDataType(0xe1b7)),
    PhieuPdf(id: 'phieu_kham_vao_vien', name: 'PHIẾU KHÁM VÀO VIỆN', shortName: 'Khám vào viện', icon: IconDataType(0xe558)),
    PhieuPdf(id: 'to_dieu_tri', name: 'TỜ ĐIỀU TRỊ', shortName: 'Tờ ĐT', icon: IconDataType(0xe558)),
    PhieuPdf(id: 'phieu_cham_soc', name: 'PHIẾU CHẸ SÓC', shortName: 'Chăm sóc', icon: IconDataType(0xe138)),
    PhieuPdf(id: 'phieu_theo_doi_sh', name: 'PHIẾU THEO DÕI SH', shortName: 'Theo dõi SH', icon: IconDataType(0xe87d)),
    PhieuPdf(id: 'phieu_ban_giao', name: 'PHIẾU BÀN GIAO', shortName: 'Bàn giao', icon: IconDataType(0xe8d5)),
    PhieuPdf(id: 'bien_ban_hoi_chan', name: 'BIÊN BẢN HỘI CHẨN', shortName: 'Hội chẩn', icon: IconDataType(0xe7ef)),
    PhieuPdf(id: 'phieu_chi_dinh', name: 'PHIẾU CHỈ ĐỊNH', shortName: 'Chỉ định', icon: IconDataType(0xe3ab)),
    PhieuPdf(id: 'phieu_su_dung_thuoc', name: 'PHIẾU SỬ DỤNG THUỐC', shortName: 'SD thuốc', icon: IconDataType(0xe8b0)),
    PhieuPdf(id: 'giay_ra_vien', name: 'GIẤY RA VIỆN', shortName: 'Ra viện', icon: IconDataType(0xe88a)),
    PhieuPdf(id: 'giay_chuyen_vien', name: 'GIẤY CHUYỂN VIỆN', shortName: 'Chuyển viện', icon: IconDataType(0xe8d5)),
    PhieuPdf(id: 'tom_tat_benh_an', name: 'TÓM TẮT BỆNH ÁN', shortName: 'Tóm tắt BA', icon: IconDataType(0xe873)),
    PhieuPdf(id: 'so_ket_15_ngay', name: 'SỔ KẾT 15 NGÀY', shortName: 'Sổ kết 15N', icon: IconDataType(0xe7f4)),
  ];

  static PhieuPdf? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Common patient info (map từ action_sheet patient)
class PatientContext {
  final String name;
  final String? age;
  final String? gender;
  final String? patientCode;
  final String? treatmentCode;
  final String? dob;
  final String? heinCard;
  final String? address;
  final String? phone;
  final String? career;
  final String? ethnic;
  final String? bedName;
  final String? department;
  final String? icdCode;
  final String? icdName;
  final String? diagnosis;
  final DateTime? admissionDate;
  final String? weight;
  final String? pulse;
  final String? temperature;
  final String? bpMax;
  final String? bpMin;
  final String? spo2;
  final String? breathRate;

  const PatientContext({
    required this.name,
    this.age,
    this.gender,
    this.patientCode,
    this.treatmentCode,
    this.dob,
    this.heinCard,
    this.address,
    this.phone,
    this.career,
    this.ethnic,
    this.bedName,
    this.department,
    this.icdCode,
    this.icdName,
    this.diagnosis,
    this.admissionDate,
    this.weight,
    this.pulse,
    this.temperature,
    this.bpMax,
    this.bpMin,
    this.spo2,
    this.breathRate,
  });

  factory PatientContext.fromMap(Map<String, dynamic> m, {Map<String, dynamic>? department}) {
    String g(String k1, [String? k2, String? k3]) => (m[k1] ?? m[k2 ?? ''] ?? m[k3 ?? ''] ?? '').toString();
    return PatientContext(
      name: g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME', 'tdl_patient_name'),
      age: g('AGE', 'TUOI', 'tdl_patient_age'),
      gender: g('TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender_name', 'GENDER_NAME'),
      patientCode: g('TDL_PATIENT_CODE', 'tdl_patient_code'),
      treatmentCode: g('TDL_TREATMENT_CODE', 'treatment_code'),
      dob: g('DOB', 'tdl_patient_dob', 'NGAYSINH'),
      heinCard: g('TDL_HEIN_CARD_NUMBER', 'tdl_hein_card_number'),
      address: g('VIR_ADDRESS', 'vir_address'),
      phone: g('PHONE', 'phone'),
      career: g('CAREER_NAME', 'PATIENT_CAREER_NAME', 'career_name'),
      ethnic: g('ETHNIC_NAME', 'ethnic_name'),
      bedName: g('BED_NAME', 'bed_name'),
      department: department?['name']?.toString() ?? g('DEPARTMENT_NAME'),
      icdCode: g('ICD_CODE', 'icd_code'),
      icdName: g('ICD_NAME', 'icd_name'),
      diagnosis: g('ICD_TEXT', 'icd_text'),
      admissionDate: DateTime.tryParse(g('IN_TIME', 'in_time')),
      weight: g('WEIGHT'),
      pulse: g('PULSE'),
      temperature: g('TEMPERATURE'),
      bpMax: g('BLOOD_PRESSURE_MAX'),
      bpMin: g('BLOOD_PRESSURE_MIN'),
      spo2: g('SPO2'),
      breathRate: g('BREATH_RATE'),
    );
  }
}

/// PDF builder for HIS Pro EMR style
class HisProPdfBuilder {
  static const _soyte = 'SỞ Y TẾ TỈNH NINH THUẬN';
  static const _benhvien = 'BỆNH VIỆN ĐA KHOA NINH THUẬN';
  static const _khoa = 'Khoa Hồi Sức Cấp Cứu';
  static const _ms = 'MS: 43/BV2';

  static pw.Document _baseDoc(PhieuPdf phieu, PatientContext p, {pw.Widget? extra}) {
    return pw.Document(
      title: phieu.name,
      author: _benhvien,
      creator: 'HIS Pro Mobile v2.30',
      pageMode: PdfPageMode.none,
      theme: pw.ThemeData.withFont(),
    );
  }

  /// Header chung: Sở Y tế + Tiêu đề + MS
  static pw.Widget _buildHeader(PhieuPdf phieu, PatientContext p) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: 3-line header
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_soyte, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(_benhvien, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Khoa: ${p.department ?? _khoa}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        // Center: Title
        pw.Expanded(
          flex: 3,
          child: pw.Center(
            child: pw.Text(
              phieu.name,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
        // Right: MS, Số vào viện, Mã BN
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_ms, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text('Số vào viện: ${p.treatmentCode ?? ""}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Mã người bệnh: ${p.patientCode ?? ""}', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  /// Bảng thông tin BN 1-9 (HIS Pro style)
  static pw.Widget _buildPatientInfo(PatientContext p) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('I. THÔNG TIN NGƯỜI BỆNH:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('1. Họ và tên: ${p.name.isEmpty ? "............................" : p.name}', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('2. Tuổi: ${p.age ?? ""}    3. Nam/Nữ: ${p.gender ?? "........"}    4. Mã số: ${p.patientCode ?? ""}', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('5. Địa chỉ: ${p.address ?? ""}', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('6. Nghề nghiệp: ${p.career ?? ""}    7. Dân tộc: ${p.ethnic ?? "Kinh"}    8. BHYT: ${p.heinCard ?? ""}', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('9. Giường: ${p.bedName ?? ""}    Khoa: ${p.department ?? ""}', style: _body),
        ],
      ),
    );
  }

  static final _body = pw.TextStyle(fontSize: 10);
  static final _bodyBold = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  static final _section = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);

  /// Footer với 2 chữ ký
  static pw.Widget _buildSignatureFooter({String leftLabel = 'Bác sỹ điều trị', String rightLabel = 'Bác sỹ trưởng khoa'}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(leftLabel, style: _bodyBold),
                pw.Text('(Ký, ghi rõ họ tên)', style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 40),
                pw.Container(width: 1, height: 1),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(rightLabel, style: _bodyBold),
                pw.Text('(Ký, ghi rõ họ tên)', style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 40),
                pw.Container(width: 1, height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ========== 1. BỆNH ÁN CẤP CỨU ==========
  static Future<Uint8List> buildBenhAnCapCuu(PatientContext p) async {
    final doc = _baseDoc(PhieuCatalog.byId('benh_an_cap_cuu')!, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(PhieuCatalog.byId('benh_an_cap_cuu')!, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. CHẨN ĐOÁN:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('- Chẩn đoán sơ bộ: ${p.icdName ?? ".........................................."}', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('- Mã ICD-10: ${p.icdCode ?? ""}', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('- Chẩn đoán phân biệt: ................................................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('III. HỎI BỆNH:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Lý do vào viện: ..........................................................................................................................................', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('Quá trình bệnh lý: ............................................................................................................', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('Tiền sử bệnh: ......................................................................................................................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('IV. KHÁM XÉT:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Toàn thân:', style: _bodyBold),
          pw.SizedBox(height: 2),
          pw.Text('- Tỉnh táo, tiếp xúc tốt. Da niêm mạc hồng.', style: _body),
          pw.Text('- Mạch: ${p.pulse ?? "...."} lần/ph    Nhiệt độ: ${p.temperature ?? "...."} °C', style: _body),
          pw.Text('- HA: ${p.bpMax ?? "..."}/${p.bpMin ?? "..."} mmHg    SpO2: ${p.spo2 ?? "..."}%    Nhịp thở: ${p.breathRate ?? "..."}/ph', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('Bộ phận: Khám theo hệ cơ quan, ghi nhận bất thường (nếu có).', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('V. CẬN LÂM SÀNG:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('- CTM, sinh hóa máu, nước tiểu', style: _body),
          pw.Text('- ECG, X-quang ngực (nếu có chỉ định)', style: _body),
          pw.Text('- Siêu âm, CT scanner (nếu cần)', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('VI. ĐIỀU TRỊ:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('- Oxy (nếu SpO2 < 94%): 2-4 lít/ph qua mask hoặc nasal cannula', style: _body),
          pw.Text('- Truyền dịch: NaCl 0.9% hoặc Ringer Lactate theo chỉ định', style: _body),
          pw.Text('- Thuốc điều trị triệu chứng và đặc hiệu (ghi cụ thể)', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('VII. TIÊN LƯỢNG:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Theo dõi sát diễn biến, đánh giá lại sau 30 phút - 1 giờ.', style: _body),
          _buildSignatureFooter(),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 2. PHIẾU KHÁM VÀO VIỆN ==========
  static Future<Uint8List> buildPhieuKhamVaoVien(PatientContext p) async {
    final phieu = PhieuCatalog.byId('phieu_kham_vao_vien')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. LÝ DO VÀO VIỆN:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('......................................................................................................................................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('III. HỎI BỆNH:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Quá trình bệnh lý: ........................................................................................', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('Tiền sử bản thân: ...........................................................................................', style: _body),
          pw.SizedBox(height: 2),
          pw.Text('Tiền sử gia đình: ...........................................................................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('IV. KHÁM BỆNH:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('1. Toàn thân:', style: _bodyBold),
          pw.Text('- Tỉnh, tiếp xúc tốt/xấu. Thể trạng trung bình/gầy/béo.', style: _body),
          pw.Text('- Da niêm mạc: hồng/xanh tái/vàng. Phù: không.', style: _body),
          pw.Text('- Tuyến giáp: không to. Hạch ngoại biên: không sờ thấy.', style: _body),
          pw.Text('- Mạch: ${p.pulse ?? "...."} lần/ph    Nhiệt: ${p.temperature ?? "...."} °C', style: _body),
          pw.Text('- HA: ${p.bpMax ?? "..."}/${p.bpMin ?? "..."} mmHg    Cân nặng: ${p.weight ?? "...."} kg', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('2. Các cơ quan:', style: _bodyBold),
          for (final organ in [
            'Tuần hoàn: Nhịp đều, T1 T2 rõ, không có tiếng thổi bệnh lý.',
            'Hô hấp: Lồng ngực cân đối, gõ trong, rì rào phế nang đều 2 bên.',
            'Tiêu hóa: Bụng mềm, gan lách không sờ thấy, không có điểm đau khu trú.',
            'Thận - tiết niệu: Chạm thận - điểm niệu quản (-), bụng không.',
            'Thần kinh: Glasgow 15 điểm, không có dấu thần kinh khu trú.',
            'Cơ - xương - khớp: Không có biến dạng, vận động bình thường.',
            'Tai - mũi - họng: Tai hai bên không chảy mủ. Mũi thông. Họng không đỏ.',
            'Răng - hàm - mặt: Răng có sâu? Hàm cân đối.',
            'Mắt: Hai mắt nhìn rõ, đồng tử đều 2 bên, phản xạ ánh sáng (+).',
          ]) ...[
            pw.SizedBox(height: 2),
            pw.Text('- $organ', style: _body),
          ],
          pw.SizedBox(height: 8),
          pw.Text('V. CẬN LÂM SÀNG:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Đề nghị: CTM, sinh hóa máu (đường, ure, creatinin, AST, ALT), nước tiểu, ECG, X-quang ngực.', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('VI. CHẨN ĐOÁN:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('- Sơ bộ: ${p.icdName ?? "............................................"}', style: _body),
          pw.Text('- Mã ICD-10: ${p.icdCode ?? ""}', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('VII. HƯỚNG ĐIỀU TRỊ:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('- Nhập viện điều trị nội trú', style: _body),
          pw.Text('- Theo dõi sinh hiệu mỗi 4-6 giờ', style: _body),
          pw.Text('- Truyền dịch, thuốc điều trị triệu chứng và đặc hiệu', style: _body),
          _buildSignatureFooter(),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 3. TỜ ĐIỀU TRỊ ==========
  static Future<Uint8List> buildToDieuTri(PatientContext p) async {
    final phieu = PhieuCatalog.byId('to_dieu_tri')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('Ngày điều trị: ..../..../.......', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('Chẩn đoán: ${p.icdName ?? ""} (${p.icdCode ?? ""})', style: _bodyBold),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
            headers: ['Giờ', 'Mạch', 'HA', 'Nhiệt', 'SpO2', 'NT', 'Diễn biến', 'Y lệnh'],
            data: List.generate(6, (i) => [
              '0${i+2}:00',
              '', '', '', '', '',
              '',
              '',
            ]),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Y lệnh điều trị:', style: _bodyBold),
          pw.SizedBox(height: 4),
          for (final yl in [
            '- Nằm đầu cao 30°, theo dõi mạch, HA, SpO2 liên tục',
            '- Oxy 2-4 l/ph qua nasal cannula (nếu SpO2 < 94%)',
            '- Truyền dịch: NaCl 0.9% 500ml/8h',
            '- Kháng sinh (nếu có nhiễm trùng)',
            '- Giảm đau, hạ sốt (nếu cần)',
          ]) ...[
            pw.Text(yl, style: _body),
            pw.SizedBox(height: 2),
          ],
          _buildSignatureFooter(leftLabel: 'Bác sỹ điều trị', rightLabel: 'Trưởng tua trực'),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 4. PHIẾU CHẸ SÓC ==========
  static Future<Uint8List> buildPhieuChamSoc(PatientContext p) async {
    final phieu = PhieuCatalog.byId('phieu_cham_soc')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. THEO DÕI CHẸ SÓC:', style: _section),
          pw.SizedBox(height: 4),
          for (final ca in ['Ca 1 (Sáng 6h-14h)', 'Ca 2 (Chiều 14h-22h)', 'Ca 3 (Đêm 22h-6h)']) ...[
            pw.Text(ca, style: _bodyBold),
            pw.SizedBox(height: 2),
            pw.Text('- Tình trạng người bệnh: ...........................................', style: _body),
            pw.Text('- Các can thiệp điều dưỡng: ...................................', style: _body),
            pw.Text('- Diễn biến trong ca: ...........................................', style: _body),
            pw.SizedBox(height: 6),
          ],
          _buildSignatureFooter(leftLabel: 'Điều dưỡng trực', rightLabel: 'Điều dưỡng trưởng'),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 5. PHIẾU THEO DÕI SH ==========
  static Future<Uint8List> buildPhieuTheoDoiSH(PatientContext p) async {
    final phieu = PhieuCatalog.byId('phieu_theo_doi_sh')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. BẢNG THEO DÕI SINH HIỆU:', style: _section),
          pw.SizedBox(height: 4),
          pw.Table.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
            headers: const ['Giờ', 'Mạch', 'HA max', 'HA min', 'Nhiệt', 'SpO2', 'NT', 'Tri giác', 'Ghi chú'],
            data: List.generate(12, (i) => [
              '${(i*2).toString().padLeft(2, '0')}:00',
              '', '', '', '', '', '', '', '',
            ]),
          ),
          _buildSignatureFooter(leftLabel: 'Điều dưỡng theo dõi', rightLabel: 'Bác sỹ điều trị'),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 6. PHIẾU BÀN GIAO ==========
  static Future<Uint8List> buildPhieuBanGiao(PatientContext p) async {
    final phieu = PhieuCatalog.byId('phieu_ban_giao')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. THÔNG TIN BÀN GIAO:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Khoa bàn giao: ${p.department ?? ""}', style: _body),
          pw.Text('Khoa nhận: .................................', style: _body),
          pw.Text('Lý do chuyển: .................................', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('Tình trạng hiện tại: bệnh tỉnh, sinh hiệu ổn', style: _body),
          pw.Text('Diễn biến bệnh: .................................', style: _body),
          pw.Text('Đã can thiệp: .................................', style: _body),
          pw.Text('Kế hoạch điều trị tiếp theo: .................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('Thời gian bàn giao: .... giờ .... ngày ..../..../.......', style: _body),
          _buildSignatureFooter(leftLabel: 'Bác sỹ giao ca', rightLabel: 'Bác sỹ nhận ca'),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 7. BIÊN BẢN HỘI CHẨN ==========
  static Future<Uint8List> buildBienBanHoiChan(PatientContext p) async {
    final phieu = PhieuCatalog.byId('bien_ban_hoi_chan')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. THÀNH PHẦN HỘI CHẨN:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Chủ tọa: .................................', style: _body),
          pw.Text('Thư ký: .................................', style: _body),
          pw.Text('Thành viên: .................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('III. THỜI GIAN - ĐỊA ĐIỂM:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Bắt đầu: .... giờ .... ngày ..../..../.......', style: _body),
          pw.Text('Kết thúc: .... giờ .... ngày ..../..../.......', style: _body),
          pw.Text('Địa điểm: Phòng hội chẩn khoa HSCC', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('IV. TÌNH TRẠNG NGƯỜI BỆNH:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('Chẩn đoán: ${p.icdName ?? ""} (${p.icdCode ?? ""})', style: _body),
          pw.Text('Tiền sử: ........................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('V. KẾT LUẬN HỘI CHẨN:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('................................................................................................................................', style: _body),
          pw.SizedBox(height: 4),
          pw.Text('................................................................................................................................', style: _body),
          pw.SizedBox(height: 8),
          pw.Text('VI. HƯỚNG XỬ TRÍ TIẾP THEO:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text('................................................................................................................................', style: _body),
          _buildSignatureFooter(leftLabel: 'Chủ tọa hội chẩn', rightLabel: 'Thư ký'),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 8. PHIẾU CHỈ ĐỊNH ==========
  static Future<Uint8List> buildPhieuChiDinh(PatientContext p, {String? serviceName, String? serviceCode, String? indication, String? priority}) async {
    final phieu = PhieuCatalog.byId('phieu_chi_dinh')!;
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text('II. CHỈ ĐỊNH CẬN LÂM SÀNG:', style: _section),
          pw.SizedBox(height: 4),
          pw.Table.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
            headers: const ['STT', 'Mã dịch vụ', 'Tên dịch vụ', 'Số lượng', 'Đơn giá', 'Thành tiền'],
            data: [
              ['1', serviceCode ?? '..........', serviceName ?? '..........................', '1', '..........', '..........'],
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text('III. CHỈ ĐỊNH LÂM SÀNG:', style: _section),
          pw.SizedBox(height: 4),
          pw.Text(indication ?? '........................................................................................', style: _body),
          pw.SizedBox(height: 4),
          if (priority != null) pw.Text('Mức độ ưu tiên: $priority', style: _bodyBold),
          pw.SizedBox(height: 8),
          pw.Text('IV. CHẨN ĐOÁN LIÊN QUAN: ${p.icdName ?? ""} (${p.icdCode ?? ""})', style: _body),
          _buildSignatureFooter(),
        ],
      ),
    );
    return doc.save();
  }

  /// ========== 9-13: Generic ==========
  static Future<Uint8List> _buildGeneric(PhieuPdf phieu, PatientContext p, String subtitle, List<MapEntry<String, String>> rows) async {
    final doc = _baseDoc(phieu, p);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 32, marginBottom: 32),
        build: (ctx) => [
          _buildHeader(phieu, p),
          _buildPatientInfo(p),
          pw.SizedBox(height: 8),
          pw.Text(subtitle, style: _section),
          pw.SizedBox(height: 4),
          for (final r in rows) ...[
            pw.Text('${r.key}:', style: _bodyBold),
            pw.SizedBox(height: 2),
            pw.Text(r.value, style: _body),
            pw.SizedBox(height: 6),
          ],
          _buildSignatureFooter(),
        ],
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> buildPhieuSuDungThuoc(PatientContext p) async {
    return _buildGeneric(PhieuCatalog.byId('phieu_su_dung_thuoc')!, p, 'II. THUỐC SỬ DỤNG:', [
      MapEntry('1. Tên thuốc', '................................................................'),
      MapEntry('2. Hàm lượng', '................................................................'),
      MapEntry('3. Liều dùng', '................................................................'),
      MapEntry('4. Đường dùng', '................................................................'),
      MapEntry('5. Thời gian', '................................................................'),
    ]);
  }

  static Future<Uint8List> buildGiayRaVien(PatientContext p) async {
    return _buildGeneric(PhieuCatalog.byId('giay_ra_vien')!, p, 'II. THÔNG TIN RA VIỆN:', [
      MapEntry('1. Ngày vào viện', '................................................................'),
      MapEntry('2. Ngày ra viện', '................................................................'),
      MapEntry('3. Tổng số ngày điều trị', '................................................................'),
      MapEntry('4. Chẩn đoán ra viện', p.icdName ?? '................................................................'),
      MapEntry('5. Tình trạng ra viện', '................................................................'),
      MapEntry('6. Hướng điều trị tiếp', '................................................................'),
      MapEntry('7. Hẹn tái khám', '................................................................'),
    ]);
  }

  static Future<Uint8List> buildGiayChuyenVien(PatientContext p) async {
    return _buildGeneric(PhieuCatalog.byId('giay_chuyen_vien')!, p, 'II. THÔNG TIN CHUYỂN VIỆN:', [
      MapEntry('1. Bệnh viện chuyển đến', 'BVĐK Ninh Thuận'),
      MapEntry('2. Bệnh viện nhận', '................................................................'),
      MapEntry('3. Lý do chuyển viện', '................................................................'),
      MapEntry('4. Chẩn đoán', p.icdName ?? '................................................................'),
      MapEntry('5. Tình trạng lúc chuyển', '................................................................'),
      MapEntry('6. Hướng điều trị đã làm', '................................................................'),
    ]);
  }

  static Future<Uint8List> buildTomTatBenhAn(PatientContext p) async {
    return _buildGeneric(PhieuCatalog.byId('tom_tat_benh_an')!, p, 'II. TÓM TẮT BỆNH ÁN:', [
      MapEntry('1. Lý do nhập viện', '................................................................'),
      MapEntry('2. Quá trình bệnh lý', '................................................................'),
      MapEntry('3. Tiền sử', '................................................................'),
      MapEntry('4. Khám xét', 'Mạch ${p.pulse ?? "..."}, HA ${p.bpMax ?? "..."}/${p.bpMin ?? "..."}, Nhiệt ${p.temperature ?? "..."}°C, SpO2 ${p.spo2 ?? "..."}%'),
      MapEntry('5. Cận lâm sàng', '................................................................'),
      MapEntry('6. Chẩn đoán', p.icdName ?? '................................................................'),
      MapEntry('7. Điều trị', '................................................................'),
      MapEntry('8. Tình trạng ra viện', '................................................................'),
    ]);
  }

  static Future<Uint8List> buildSoKet15Ngay(PatientContext p) async {
    return _buildGeneric(PhieuCatalog.byId('so_ket_15_ngay')!, p, 'II. SỔ KẾT 15 NGÀY ĐIỀU TRỊ:', [
      MapEntry('1. Quá trình bệnh lý & diễn biến', '................................................................'),
      MapEntry('2. Kết quả xét nghiệm / CLS', '................................................................'),
      MapEntry('3. Chẩn đoán', p.icdName ?? '................................................................'),
      MapEntry('4. Hướng điều trị tiếp theo', '................................................................'),
      MapEntry('5. Tiên lượng', '................................................................'),
    ]);
  }

  /// Master switch: build any phiếu by ID
  static Future<Uint8List> buildById(String id, PatientContext p, {Map<String, dynamic>? extras}) async {
    switch (id) {
      case 'benh_an_cap_cuu':
        return buildBenhAnCapCuu(p);
      case 'phieu_kham_vao_vien':
        return buildPhieuKhamVaoVien(p);
      case 'to_dieu_tri':
        return buildToDieuTri(p);
      case 'phieu_cham_soc':
        return buildPhieuChamSoc(p);
      case 'phieu_theo_doi_sh':
        return buildPhieuTheoDoiSH(p);
      case 'phieu_ban_giao':
        return buildPhieuBanGiao(p);
      case 'bien_ban_hoi_chan':
        return buildBienBanHoiChan(p);
      case 'phieu_chi_dinh':
        return buildPhieuChiDinh(
          p,
          serviceName: extras?['service_name']?.toString(),
          serviceCode: extras?['service_code']?.toString(),
          indication: extras?['indication']?.toString(),
          priority: extras?['priority']?.toString(),
        );
      case 'phieu_su_dung_thuoc':
        return buildPhieuSuDungThuoc(p);
      case 'giay_ra_vien':
        return buildGiayRaVien(p);
      case 'giay_chuyen_vien':
        return buildGiayChuyenVien(p);
      case 'tom_tat_benh_an':
        return buildTomTatBenhAn(p);
      case 'so_ket_15_ngay':
        return buildSoKet15Ngay(p);
      default:
        return buildBenhAnCapCuu(p);
    }
  }
}
