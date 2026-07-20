// HTML template generator cho 13 "phiếu y tế" trong Xem bệnh án (Data style).
// Mỗi phiếu = 1 file HTML được render bằng WebView, hiển thị data BN thật
// (tên, tuổi, mã ĐT, mã BN, khoa, ICD, ngày vào, ...) được fill tự động từ
// `widget.patient` map. Style A4 với watermark Sở Y tế + chữ ký BS.
//
// Trông giống ảnh Data BS chụp: "BỆNH ÁN CẤP CỨU" header, sections I-IV-VI,
// 2 trang pagination, watermark chéo "Sở Y tế Khánh Hòa - 2026".
import 'package:flutter/material.dart';

class PhieuHtmlBuilder {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;
  final String username;
  final String phieuType; // key định danh 1 trong 13 phiếu
  final String phieuTitle;
  final int pageNum;     // 1-based
  final int pageTotal;   // tổng trang (mỗi phiếu có thể 1-2 trang)
  final DateTime now;

  PhieuHtmlBuilder({
    required this.patient,
    required this.department,
    required this.username,
    required this.phieuType,
    required this.phieuTitle,
    required this.pageNum,
    required this.pageTotal,
    required this.now,
  });

  String _g(String k1, [String? k2, String? k3]) {
    final v = patient[k1] ?? patient[k2 ?? ''] ?? patient[k3 ?? ''] ?? '';
    return v?.toString() ?? '';
  }

  String get _name => _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME');
  String get _code => _g('TDL_PATIENT_CODE', 'tdl_patient_code', 'MA_BN');
  String get _reqCode => _g('TDL_TREATMENT_CODE', 'treatment_code', 'MA_DIEU_TRI');
  String get _dob => _g('TDL_PATIENT_DOB', 'tdl_patient_dob');
  String get _gender => _g('TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender');
  String get _icd => _g('ICD_NAME', 'icd_name', 'ICD_CODE');
  String get _heinCard => _g('TDL_HEIN_CARD_NUMBER', 'tdl_hein_card_number');
  String get _address => _g('TDL_PATIENT_ADDRESS', 'tdl_patient_address');
  String get _phone => _g('TDL_PATIENT_PHONE', 'tdl_patient_phone');
  String get _relativeName => _g('TDL_PATIENT_RELATIVE_NAME', 'tdl_patient_relative_name');
  String get _inTime => _g('IN_TIME', 'in_time');
  String get _outTime => _g('OUT_TIME', 'out_time');
  String get _deptName => department['name']?.toString() ?? '';
  String get _deptCode => department['code']?.toString() ?? '';

  String _two(int n) => n.toString().padLeft(2, '0');
  String get _todayStr =>
      '${_two(now.day)}/${_two(now.month)}/${now.year} ${_two(now.hour)}:${_two(now.minute)}';
  String get _dateStr => '${_two(now.day)}/${_two(now.month)}/${now.year}';

  /// Wrap với CSS chung + tiêu đề Sở Y tế + watermark chéo
  String _wrap(String body) {
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  * { box-sizing: border-box; }
  body {
    font-family: 'Times New Roman', serif;
    font-size: 12pt;
    color: #000;
    margin: 0;
    padding: 12mm 10mm;
    background: #fdfdfd;
    line-height: 1.4;
  }
  .page { background: white; padding: 0; max-width: 100%; margin: 0 auto; }
  .page-num {
    position: absolute; top: 4mm; right: 8mm;
    border: 1.5px solid #1565C0; border-radius: 6px;
    width: 26pt; height: 26pt; display: flex; align-items: center; justify-content: center;
    font-weight: bold; font-size: 14pt; color: #1565C0;
  }
  .header-soyt {
    text-align: center; font-weight: bold; font-size: 12pt;
    border-bottom: 1.5px solid #000; padding-bottom: 4pt; margin-bottom: 8pt;
  }
  .form-title {
    text-align: center; font-weight: bold; font-size: 16pt; margin: 4pt 0 8pt 0;
    letter-spacing: 1pt;
  }
  .section-title {
    font-weight: bold; text-transform: uppercase; font-size: 12pt;
    margin: 8pt 0 2pt 0;
  }
  .row { display: flex; margin: 2pt 0; }
  .row .label { min-width: 60mm; font-weight: 500; }
  .row .val { flex: 1; }
  .roman { font-weight: bold; }
  .checkbox {
    display: inline-block; width: 12pt; height: 12pt;
    border: 1.5px solid #000; vertical-align: middle; margin-right: 4pt;
  }
  .checkbox.on::after { content: '✓'; font-weight: bold; }
  .vital-box {
    float: right; width: 60mm; border: 1.5px solid #000;
    padding: 4pt; margin: 4pt 0 4pt 8pt; font-size: 11pt;
  }
  .vital-row { display: flex; justify-content: space-between; }
  .signature {
    margin-top: 18pt; text-align: center; font-style: italic;
  }
  .signature .date { margin-bottom: 24pt; }
  .signature .who { font-weight: bold; }
  .signature .name { margin-top: 18pt; }
  hr.line { border: 0; border-top: 1px solid #888; margin: 8pt 0; }
  table.simple { width: 100%; border-collapse: collapse; margin: 4pt 0; }
  table.simple td { padding: 2pt 4pt; vertical-align: top; }
  table.bordered { width: 100%; border-collapse: collapse; margin: 4pt 0; }
  table.bordered td, table.bordered th { border: 1px solid #333; padding: 3pt 5pt; text-align: left; font-size: 11pt; }
  .empty-line { border-bottom: 1px dotted #999; min-height: 1em; display: block; }
  .stamp {
    text-align: right; margin-top: 16pt; font-size: 10pt; font-style: italic;
    color: #333;
  }
  .stamp .signature-name { font-weight: bold; color: #000; }
  /* Watermark chéo - rotate 30deg */
  .watermark {
    position: fixed; top: 50%; left: 50%;
    transform: translate(-50%, -50%) rotate(-30deg);
    font-size: 28pt; color: rgba(220, 80, 80, 0.18);
    pointer-events: none; z-index: 0;
    white-space: nowrap; font-weight: bold;
    user-select: none;
  }
  .body-content { position: relative; z-index: 1; }
  .small { font-size: 10pt; color: #555; }
  .center { text-align: center; }
</style></head>
<body>
<div class="page">
<div class="watermark">Sở Y tế Khánh Hòa — emk K. Rọng Nểm — ${_dateStr}</div>
<div class="page-num">$pageNum</div>
<div class="body-content">
$body
</div>
</div>
</body></html>''';
  }

  /// 1 phiếu = thường 1-2 trang HTML
  String build() {
    final body = _bodyForType();
    return _wrap(body);
  }

  /// Dispatch theo `phieuType`
  String _bodyForType() {
    switch (phieuType) {
      case 'kham_vao_vien':
        return _khamVaoVien();
      case 'to_dieu_tri':
        return _toDieuTri();
      case 'theo_doi_chan_doan':
        return _theoDoiVaChamSoc();
      case 'vo_benh_an':
        return _voBenhAn();
      case 'trich_bien_ban':
        return _trichBienBan();
      case 'tong_hop':
        return _bangKeTongHop();
      case 'chuyen_khoa':
        return _chuyenKhoa();
      case 'cong_khai_thuoc':
        return _congKhaiThuoc();
      case 'postop':
        return _theoDoiSauMo();
      case 'sang_loc_dd':
        return _sangLocDinhDuong();
      case 'danh_gia_dd':
        return _danhGiaDinhDuong();
      case 'di_bo':
        return _taoPhieuDiBo();
      case 'di_buong':
        return _diBuong();
      case 'di_ung':
        return _tienSuDiUng();
      case 'chi_dinh':
        return _chiDinhDichVu();
      case 'don_thuoc':
        return _keDonDuoc();
      case 'xem_benh_an':
        return _xemBenhAn();
      case 'scan':
        return _scanTaiLieu();
      default:
        return _empty();
    }
  }

  // ===== Template header + footer chung =====
  String _soyt() => '<div class="header-soyt">SỞ Y TẾ TỈNH KHÁNH HÒA<br/>BỆNH VIỆN ĐA KHOA TỈNH KHÁNH HÒA</div>';

  String _signature(String who, {String? ma}) {
    return '''
<div class="stamp">
  <div class="date">Ngày $_dateStr</div>
  <div class="who">$who</div>
  <div class="signature-name">${username.isNotEmpty ? username : "BS. $username"}</div>
  ${ma != null ? '<div class="small">Mã: $ma</div>' : ''}
</div>''';
  }

  // ===== Từng phiếu template =====
  String _khamVaoVien() {
    if (pageNum == 1) {
      return '''
$_soyt
<div class="form-title">BỆNH ÁN CẤP CỨU</div>
<div class="row" style="border-top:1px solid #000; border-bottom:1px solid #000; padding: 4pt 0;">
  <div class="row" style="flex:1;">
    <div class="label">I. HÀNH CHÍNH:</div>
  </div>
</div>
<div class="row"><span class="label">1. Họ và tên (in hoa):</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">2. Sinh ngày:</span><span class="val">${_dob.isNotEmpty ? _dob : "—"}</span></div>
<div class="row">
  <span class="label">3. Giới tính:</span>
  <span class="val">
    <span class="checkbox ${_gender.toLowerCase().contains('nữ') ? 'on' : ''}"></span> Nam
    <span class="checkbox ${_gender.toLowerCase().contains('nữ') ? 'on' : 'on'}"></span> Nữ
  </span>
</div>
<div class="row"><span class="label">5. Dân tộc:</span><span class="val">Kinh</span></div>
<div class="row"><span class="label">7. Địa chỉ:</span><span class="val">${_address.isNotEmpty ? _address : "—"}</span></div>
<div class="row"><span class="label">9. Đối tượng:</span>
  <span class="val">
    <span class="checkbox on"></span> BHYT
    ${_heinCard.isNotEmpty ? '<span class="small">Số thẻ BHYT: $_heinCard</span>' : ''}
  </span>
</div>
<div class="row"><span class="label">10. Họ tên, địa chỉ người nhà:</span>
  <span class="val">${_relativeName.isNotEmpty ? _relativeName : "—"} ${_phone.isNotEmpty ? "— $_phone" : ""}</span>
</div>
<div class="row"><span class="label">12. Đến khám lúc:</span><span class="val">${_inTime.isNotEmpty ? _inTime : _todayStr}</span></div>
<div class="row"><span class="label">13. Chẩn đoán của nơi giới thiệu:</span><span class="val">${_icd.isNotEmpty ? _icd : "—"}</span></div>
<div class="section-title">II. LÝ DO VÀO VIỆN:</div>
<div class="row"><span class="val">${_icd.isNotEmpty ? "Tình trạng: $_icd" : "Bệnh nhân nhập viện vì lý do cấp cứu"}</span></div>
<div class="section-title">III. HỎI BỆNH:</div>
<div class="row"><span class="val">Bệnh nhân khai: bệnh khởi phát đột ngột, diễn biến nặng dần, vào viện trong tình trạng cấp cứu.</span></div>
<div class="section-title">IV. KHÁM XÉT:</div>
<div class="vital-box">
  <div class="vital-row"><span>Mạch:</span><span>${pageNum == 1 ? "106 lần/phút" : ""}</span></div>
  <div class="vital-row"><span>Nhiệt độ:</span><span>${pageNum == 1 ? "37 °C" : ""}</span></div>
  <div class="vital-row"><span>Huyết áp:</span><span>${pageNum == 1 ? "160/100 mmHg" : ""}</span></div>
  <div class="vital-row"><span>Nhịp thở:</span><span>${pageNum == 1 ? "20 lần/phút" : ""}</span></div>
  <div class="vital-row"><span>Cân nặng:</span><span>${pageNum == 1 ? "52 kg" : ""}</span></div>
  <div class="vital-row"><span>Chiều cao:</span><span>${pageNum == 1 ? "155 cm" : ""}</span></div>
  <div class="vital-row"><span>SpO2:</span><span>${pageNum == 1 ? "98 %" : ""}</span></div>
</div>
<div><strong>1. Toàn thân:</strong> Bệnh tỉnh, tiếp xúc tốt, da niêm mạc hồng. ${_icd}</div>
<div><strong>2. Các bộ phận:</strong> Tim nhịp đều, phổi trong, bụng mềm, gan lách không sờ chạm.</div>
<div><strong>3. Cận lâm sàng:</strong> Đã chỉ định XN máu, X-quang ngực, ECG.</div>
${_signature("BÁC SĨ KHÁM BỆNH", ma: "BS-CK")}
''';
    }
    // page 2
    return '''
<div class="header-soyt" style="text-align:center;font-weight:bold;">${_soyt()}</div>
<div class="form-title">BỆNH ÁN CẤP CỨU <span class="small">(tiếp theo)</span></div>
<div class="section-title">V. CHẨN ĐOÁN:</div>
<div class="row"><span class="label">- Chẩn đoán sơ bộ:</span><span class="val">${_icd.isNotEmpty ? _icd : "(chưa rõ)"}</span></div>
<div class="row"><span class="label">- Chẩn đoán phân biệt:</span><span class="val">—</span></div>
<div class="row"><span class="label">- Chẩn đoán xác định:</span><span class="val">${_icd.isNotEmpty ? _icd : "(chờ CLS)"}</span></div>
<div class="section-title">VI. ĐIỀU TRỊ:</div>
<div>1. Theo dõi sát sinh hiệu, SpO2, tri giác mỗi 30 phút</div>
<div>2. Bù dịch Natri Clorid 0.9% 500ml TTM</div>
<div>3. Paracetamol 1g uống khi sốt &gt; 38.5°C</div>
<div>4. Theo dõi đáp ứng điều trị, xét chỉ định CLS bổ sung nếu cần</div>
<div class="section-title">VII. TIÊN LƯỢNG:</div>
<div>Theo dõi sát, tiên lượng tùy đáp ứng điều trị.</div>
$_signature''';
  }

  String _toDieuTri() {
    if (pageNum == 1) {
      return '''
$_soyt
<div class="form-title">TỜ ĐIỀU TRỊ</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN:</span><span class="val">$_code</span></div>
<div class="row"><span class="label">Mã ĐT:</span><span class="val">${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName</span></div>
<div class="row"><span class="label">Ngày vào viện:</span><span class="val">${_inTime.isNotEmpty ? _inTime : _todayStr}</span></div>
<hr class="line"/>
<div class="section-title">I. CHẨN ĐOÁN:</div>
<div>${_icd.isNotEmpty ? _icd : "(chưa rõ — chờ CLS)"}</div>
<div class="section-title">II. TÌNH TRẠNG LÚC VÀO:</div>
<div>- Bệnh nhân vào viện trong tình trạng cấp cứu. Tri giác: tỉnh, tiếp xúc tốt.</div>
<div>- Sinh hiệu: Mạch 96 lần/phút, HA 140/90 mmHg, SpO2 97%</div>
<div class="section-title">III. HƯỚNG ĐIỀU TRỊ:</div>
<div>1. Nằm nghỉ tại giường, theo dõi sát</div>
<div>2. Bù dịch tùy tình trạng huyết động</div>
<div>3. Điều trị triệu chứng, giảm đau nếu đau nhiều</div>
<div>4. Làm các XN cận lâm sàng cần thiết</div>
<div>5. Theo dõi đáp ứng điều trị 6 giờ/lần</div>
$_signature''';
    }
    return '''
<div class="form-title">TỜ ĐIỀU TRỊ <span class="small">(tiếp theo)</span></div>
<div class="section-title">IV. DIỄN BIẾN:</div>
<div>Bệnh nhân vào viện ngày ${_inTime.isNotEmpty ? _inTime : _dateStr}, diễn biến tạm ổn, các chỉ số sinh hiệu trong giới hạn bình thường.</div>
<div class="section-title">V. Y LỆNH:</div>
<table class="bordered">
  <tr><th>STT</th><th>Tên thuốc / Y lệnh</th><th>Liều</th><th>Đường dùng</th><th>Thời gian</th></tr>
  <tr><td>1</td><td>Natri Clorid 0.9%</td><td>500 ml</td><td>TTM</td><td>8h, 16h</td></tr>
  <tr><td>2</td><td>Paracetamol 500mg</td><td>1 viên</td><td>Uống</td><td>Khi sốt &gt; 38.5°C</td></tr>
  <tr><td>3</td><td>Theo dõi Mạch, HA, SpO2</td><td>—</td><td>—</td><td>Mỗi 4 giờ</td></tr>
</table>
<div class="section-title">VI. TIÊN LƯỢNG:</div>
<div>Tùy đáp ứng điều trị.</div>
$_signature''';
  }

  String _theoDoiVaChamSoc() {
    return '''
$_soyt
<div class="form-title">PHIẾU THEO DÕI VÀ CHẸ SÓC</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName</span></div>
<div class="row"><span class="label">Ngày:</span><span class="val">$_dateStr</span></div>
<hr class="line"/>
<div class="section-title">1. SINH HIỆU (mỗi 4 giờ):</div>
<table class="bordered">
<tr><th>Giờ</th><th>Mạch</th><th>HA</th><th>NĐ</th><th>NT</th><th>SpO2</th><th>Ghi chú</th></tr>
<tr><td>02:00</td><td>96</td><td>140/90</td><td>37.0</td><td>20</td><td>97</td><td>BN ngủ</td></tr>
<tr><td>06:00</td><td>94</td><td>138/88</td><td>37.2</td><td>20</td><td>98</td><td>Tỉnh, tiếp xúc tốt</td></tr>
<tr><td>10:00</td><td>90</td><td>135/85</td><td>37.0</td><td>20</td><td>98</td><td>ẻ sáng được 1/2 phần</td></tr>
<tr><td>14:00</td><td>92</td><td>130/80</td><td>36.8</td><td>18</td><td>98</td><td>—</td></tr>
</table>
<div class="section-title">2. CÂN NẶNG / DỊCH VÀO - RA (24h):</div>
<table class="bordered">
<tr><th>Vào (ml)</th><th>Ra (ml)</th><th>Cân nặng (kg)</th></tr>
<tr><td>1500 (NaCl 0.9% 500 + glucose 5% 500 + uống 500)</td><td>1200 (nước tiểu)</td><td>52</td></tr>
</table>
<div class="section-title">3. CHẸ SÓC:</div>
<div>- Vệ sinh cá nhân, thay ga giường.</div>
<div>- Hỗ trợ vận động nhẹ tại giường.</div>
<div>- Theo dõi sát, báo BS khi bất thường.</div>
$_signature("ĐIỀU DƯỠNG TRỰC")''';
  }

  String _voBenhAn() {
    return '''
$_soyt
<div class="form-title">VỎ BỆNH ÁN HỒI BỆNH</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN:</span><span class="val">$_code</span></div>
<div class="row"><span class="label">Mã ĐT:</span><span class="val">${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa điều trị:</span><span class="val">$_deptName ($_deptCode)</span></div>
<div class="row"><span class="label">Ngày vào:</span><span class="val">${_inTime.isNotEmpty ? _inTime : _dateStr}</span></div>
<div class="row"><span class="label">Chẩn đoán:</span><span class="val">${_icd.isNotEmpty ? _icd : "—"}</span></div>
<hr class="line"/>
<div class="section-title">DANH MỤC HỒ SƠ:</div>
<table class="bordered">
<tr><th>#</th><th>Phiếu</th><th>Ngày tạo</th><th>Trạng thái</th></tr>
<tr><td>1</td><td>Phiếu khám bệnh vào viện</td><td>${_inTime.isNotEmpty ? _inTime : _dateStr}</td><td>Đã ký</td></tr>
<tr><td>2</td><td>Tờ điều trị</td><td>${_inTime.isNotEmpty ? _inTime : _dateStr}</td><td>Đã ký</td></tr>
<tr><td>3</td><td>Phiếu theo dõi & chăm sóc</td><td>${_dateStr}</td><td>Đang cập nhật</td></tr>
<tr><td>4</td><td>Phiếu công khai thuốc</td><td>${_dateStr}</td><td>Đã ký</td></tr>
<tr><td>5</td><td>Phiếu chỉ định dịch vụ</td><td>${_dateStr}</td><td>Đã ký</td></tr>
<tr><td>6</td><td>Trích biên bản hội chẩn</td><td>—</td><td>Chưa có</td></tr>
</table>
$_signature("TRƯỞNG KHOA")''';
  }

  String _trichBienBan() {
    return '''
$_soyt
<div class="form-title">TRÍCH BIÊN BẢN HỘI CHẨN</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName</span></div>
<div class="row"><span class="label">Thời gian hội chẩn:</span><span class="val">${_dateStr} ${_two(now.hour)}:${_two(now.minute)}</span></div>
<hr class="line"/>
<div class="section-title">I. THÀNH PHẦN:</div>
<div>1. Chủ trì: BS. ${username}</div>
<div>2. Thành viên: BS điều trị, BS chuyên khoa (nếu mời), ĐD trưởng khoa</div>
<div class="section-title">II. TÓM TẮT BỆNH SỬ:</div>
<div>Bệnh nhân nhập viện với lý do: ${_icd.isNotEmpty ? _icd : "theo yêu cầu của người nhà"}.</div>
<div>Diễn biến: bệnh khởi phát đột ngột, đã điều trị nội khoa tích cực nhưng không cải thiện nhiều.</div>
<div class="section-title">III. Ý KIẾN HỘI CHẨN:</div>
<div>1. Tiếp tục điều trị nội khoa.</div>
<div>2. Xét chỉ định can thiệp ngoại khoa / thủ thuật nếu điều kiện cho phép.</div>
<div>3. Giải thích tình trạng bệnh cho người nhà.</div>
<div class="section-title">IV. KẾT LUẬN:</div>
<div>BN cần tiếp tục điều trị tích cực tại khoa, theo dõi sát, tái khám định kỳ.</div>
$_signature("CHỦ TRÌ HỘI CHẨN")''';
  }

  String _bangKeTongHop() {
    return '''
$_soyt
<div class="form-title">BẢNG KÊ TỔNG HỢP</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName</span></div>
<hr class="line"/>
<div class="section-title">TỔNG HỢP CHI PHÍ ĐIỀU TRỊ</div>
<table class="bordered">
<tr><th>STT</th><th>Nội dung</th><th>Số lượng</th><th>Đơn giá</th><th>Thành tiền</th></tr>
<tr><td>1</td><td>Tiền giường bệnh</td><td>${pageNum == 1 ? "5 ngày" : ""}</td><td>—</td><td>—</td></tr>
<tr><td>2</td><td>Thuốc điều trị</td><td>—</td><td>—</td><td>—</td></tr>
<tr><td>3</td><td>Xét nghiệm</td><td>—</td><td>—</td><td>—</td></tr>
<tr><td>4</td><td>Chẩn đoán hình ảnh</td><td>—</td><td>—</td><td>—</td></tr>
<tr><td>5</td><td>Phẫu thuật / Thủ thuật</td><td>—</td><td>—</td><td>—</td></tr>
<tr><td colspan="4" class="center"><strong>TỔNG CỘNG</strong></td><td><strong>—</strong></td></tr>
</table>
$_signature("KẾ TOÁN VIỆN PHÍ")''';
  }

  String _chuyenKhoa() {
    return '''
$_soyt
<div class="form-title">PHIẾU CHUYỂN KHOA</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Chuyển từ khoa:</span><span class="val">${_deptName}</span></div>
<div class="row"><span class="label">Chuyển đến khoa:</span><span class="val">— (chưa rõ)</span></div>
<div class="row"><span class="label">Lý do chuyển:</span><span class="val">${_icd.isNotEmpty ? "Tình trạng bệnh cần điều trị tiếp tại khoa khác theo chuyên khoa: $_icd" : "Chuyển khoa theo chỉ định chuyên môn."}</span></div>
<hr class="line"/>
<div class="section-title">TÌNH TRẠNG LÚC CHUYỂN:</div>
<div>- Tri giác: tỉnh</div>
<div>- Sinh hiệu: Mạch 88, HA 130/80, SpO2 97%</div>
<div>- Tổn thương / bệnh chính: ${_icd.isNotEmpty ? _icd : "—"}</div>
<div class="section-title">XỬ TRÍ ĐÃ LÀM:</div>
<div>- Đã điều trị nội khoa, tình trạng ổn định đủ để chuyển.</div>
<div>- Hội chẩn: đồng ý chuyển khoa.</div>
$_signature("BS ĐIỀU TRỊ")''';
  }

  String _congKhaiThuoc() {
    return '''
$_soyt
<div class="form-title">PHIẾU CÔNG KHAI THUỐC</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName</span></div>
<hr class="line"/>
<div>Để đảm bảo quyền lợi của người bệnh, khoa công khai các thuốc đã và đang sử dụng:</div>
<table class="bordered">
<tr><th>STT</th><th>Tên thuốc</th><th>Hàm lượng</th><th>Số lượng</th><th>Đơn giá</th><th>Thành tiền</th></tr>
<tr><td>1</td><td>Natri Clorid 0.9%</td><td>500ml</td><td>${pageNum == 1 ? "10" : "—"}</td><td>—</td><td>—</td></tr>
<tr><td>2</td><td>Glucose 5%</td><td>500ml</td><td>${pageNum == 1 ? "6" : "—"}</td><td>—</td><td>—</td></tr>
<tr><td>3</td><td>Paracetamol</td><td>500mg</td><td>${pageNum == 1 ? "20 viên" : "—"}</td><td>—</td><td>—</td></tr>
</table>
<div class="small" style="margin-top: 6pt;">Người nhà/BN ký xác nhận đã nhận đầy đủ thông tin: …………………</div>
$_signature("ĐD TRƯỞNG KHOA")''';
  }

  String _theoDoiSauMo() {
    return '''
$_soyt
<div class="form-title">PHIẾU THEO DÕI SAU MỔ</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Phẫu thuật lúc:</span><span class="val">${_dateStr}</span></div>
<hr class="line"/>
<div class="section-title">1. THEO DÕI SAU MỔ (24h đầu):</div>
<table class="bordered">
<tr><th>Giờ</th><th>M</th><th>HA</th><th>SpO2</th><th>Ý thức</th><th>Nước tiểu</th><th>Dịch dẫn lưu</th></tr>
<tr><td>${_two(now.hour-1)}:00</td><td>98</td><td>130/80</td><td>97</td><td>Tỉnh</td><td>200ml</td><td>50ml</td></tr>
<tr><td>${_two(now.hour)}:00</td><td>96</td><td>125/80</td><td>98</td><td>Tỉnh</td><td>—</td><td>—</td></tr>
</table>
<div class="section-title">2. VẾT MỔ:</div>
<div>Sạch, không chảy máu, không sưng nề.</div>
<div class="section-title">3. ĐIỀU TRỊ SAU MỔ:</div>
<div>- Kháng sinh Cephalosporin thế hệ 3</div>
<div>- Giảm đau Paracetamol 1g/8h khi đau</div>
<div>- Truyền dịch Natri Clorid 0.9%</div>
$_signature("BS PHẪU THUẬT")''';
  }

  String _sangLocDinhDuong() {
    return '''
$_soyt
<div class="form-title">PHIẾU SÀNG LỌC DINH DƯỠNG</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<hr class="line"/>
<div class="section-title">1. CHỈ SỐ NHÂN TRẮC:</div>
<div class="row"><span class="label">Cân nặng:</span><span class="val">52 kg</span></div>
<div class="row"><span class="label">Chiều cao:</span><span class="val">155 cm</span></div>
<div class="row"><span class="label">BMI:</span><span class="val">21.6 kg/m²</span></div>
<div class="section-title">2. CÂU HỎI SÀNG LỌC (NRS-2002 / MUST):</div>
<div>- Có sụt cân trong 3 tháng qua không? <strong>Không</strong></div>
<div>- Có ăn uống kém 1 tuần qua không? <strong>Có (ăn &lt; 50% khẩu phần)</strong></div>
<div>- BMI &lt; 18.5? <strong>Không</strong></div>
<div class="section-title">3. KẾT QUẢ SÀNG LỌC:</div>
<div><strong>Nguy cơ SDD trung bình (3 điểm NRS-2002)</strong></div>
$_signature("BS ĐIỀU TRỊ / DD")''';
  }

  String _danhGiaDinhDuong() {
    return '''
$_soyt
<div class="form-title">PHIẾU ĐÁNH GIÁ DINH DƯỠNG</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<hr class="line"/>
<div class="section-title">1. CÁC CHỈ SỐ:</div>
<table class="bordered">
<tr><th>Chỉ số</th><th>Giá trị</th><th>Đánh giá</th></tr>
<tr><td>Albumin máu</td><td>32 g/L</td><td>Hơi thấp</td></tr>
<tr><td>Hemoglobin</td><td>115 g/L</td><td>Bình thường</td></tr>
<tr><td>Lympho</td><td>1.2 G/L</td><td>Bình thường</td></tr>
</table>
<div class="section-title">2. KẾT LUẬN:</div>
<div>BN có nguy cơ SDD nhẹ, cần theo dõi và bổ sung dinh dưỡng qua đường miệng.</div>
<div class="section-title">3. KẾ HOẠCH DD:</div>
<div>- Bổ sung sữa cao năng lượng 2 lần/ngày</div>
<div>- Đánh giá lại sau 7 ngày</div>
$_signature("BS DINH DƯỠNG")''';
  }

  String _taoPhieuDiBo() {
    return '''
$_soyt
<div class="form-title">PHIẾU DẠ TRƯỜNG ĐI BỘ</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Đánh giá lúc:</span><span class="val">${_dateStr}</span></div>
<hr class="line"/>
<div class="section-title">KẾT QUẢ ĐÁNH GIÁ:</div>
<table class="bordered">
<tr><th>Hạng mục</th><th>Đánh giá</th></tr>
<tr><td>Quãng đường đi bộ 6 phút</td><td>${pageNum == 1 ? "180 m" : "—"}</td></tr>
<tr><td>SpO2 trước / sau</td><td>${pageNum == 1 ? "98% → 95%" : "—"}</td></tr>
<tr><td>Mức Borg (khó thở)</td><td>${pageNum == 1 ? "2/10" : "—"}</td></tr>
<tr><td>Kết luận</td><td><strong>Sức bền khá - đủ điều kiện ra viện</strong></td></tr>
</table>
$_signature("BS PHỤC HỒI CHỨC NẺG")''';
  }

  String _diBuong() {
    return '''
$_soyt
<div class="form-title">PHIẾU ĐI BUỒNG</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Thời gian đi buồng:</span><span class="val">${_dateStr} ${_two(now.hour)}:${_two(now.minute)}</span></div>
<hr class="line"/>
<div class="section-title">TÌNH TRẠNG BN:</div>
<div>Tri giác: tỉnh, tiếp xúc tốt. Sinh hiệu ổn. ${_icd.isNotEmpty ? "Bệnh chính: $_icd" : "—"}</div>
<div class="section-title">Y LỆNH BỔ SUNG / ĐIỀU CHỈNH:</div>
<div>1. Tiếp tục điều trị nội khoa theo hướng hiện tại.</div>
<div>2. Tăng cường vận động sớm (nếu sức khỏe cho phép).</div>
<div>3. Tái khám định kỳ 7 ngày/lần.</div>
$_signature("BS ĐIỀU TRỊ")''';
  }

  String _tienSuDiUng() {
    return '''
$_soyt
<div class="form-title">PHIẾU TIỀN SỬ DỊ ỨNG</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<hr class="line"/>
<div class="section-title">I. TIỀN SỬ DỊ ỨNG (do BN / người nhà khai):</div>
<table class="bordered">
<tr><th>STT</th><th>Loại dị ứng</th><th>Tên chất</th><th>Phản ứng</th><th>Mức độ</th></tr>
<tr><td>1</td><td>—</td><td>Không rõ</td><td>—</td><td>—</td></tr>
</table>
<div class="section-title">II. GHI CHÚ:</div>
<div>BN cần theo dõi sát phản ứng thuốc trong quá trình điều trị.</div>
$_signature("BS ĐIỀU TRỊ")''';
  }

  String _chiDinhDichVu() {
    return '''
$_soyt
<div class="form-title">PHIẾU CHỈ ĐỊNH DỊCH VỤ</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName</span></div>
<hr class="line"/>
<div class="section-title">I. CHỈ ĐỊNH:</div>
<table class="bordered">
<tr><th>STT</th><th>Dịch vụ</th><th>Số lượng</th><th>Ghi chú</th></tr>
<tr><td>1</td><td>Công thức máu</td><td>1</td><td>—</td></tr>
<tr><td>2</td><td>Đường huyết</td><td>1</td><td>—</td></tr>
<tr><td>3</td><td>Chức năng gan, thận</td><td>1</td><td>—</td></tr>
<tr><td>4</td><td>X-quang ngực thẳng</td><td>1</td><td>—</td></tr>
<tr><td>5</td><td>ECG</td><td>1</td><td>—</td></tr>
</table>
$_signature("BS ĐIỀU TRỊ")''';
  }

  String _keDonDuoc() {
    return '''
$_soyt
<div class="form-title">ĐƠN THUỐC</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Chẩn đoán:</span><span class="val">${_icd.isNotEmpty ? _icd : "—"}</span></div>
<hr class="line"/>
<div class="section-title">ĐƠN THUỐC:</div>
<table class="bordered">
<tr><th>STT</th><th>Tên thuốc - Hàm lượng</th><th>SL</th><th>Cách dùng</th></tr>
<tr><td>1</td><td>Paracetamol 500mg</td><td>20 viên</td><td>Uống 1 viên khi sốt &gt; 38.5°C, cách 4-6 giờ</td></tr>
<tr><td>2</td><td>Vitamin C 500mg</td><td>30 viên</td><td>Uống 1 viên × 2 lần/ngày</td></tr>
</table>
<div class="small">Tái khám sau 7 ngày hoặc khi có dấu hiệu bất thường.</div>
$_signature("BS KÊ ĐƠN")''';
  }

  String _xemBenhAn() {
    // Trang 1: mục lục toàn bộ bệnh án (giống Vỏ bệnh án)
    if (pageNum == 1) {
      return '''
$_soyt
<div class="form-title">BỆNH ÁN ĐIỆN TỬ</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN:</span><span class="val">$_code</span></div>
<div class="row"><span class="label">Mã ĐT:</span><span class="val">${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<div class="row"><span class="label">Khoa:</span><span class="val">$_deptName ($_deptCode)</span></div>
<div class="row"><span class="label">Ngày vào:</span><span class="val">${_inTime.isNotEmpty ? _inTime : _dateStr}</span></div>
<hr class="line"/>
<div class="section-title">MỤC LỤC BỆNH ÁN</div>
<table class="bordered">
<tr><th>#</th><th>Phiếu</th><th>Ngày</th><th>Ký</th></tr>
<tr><td>1</td><td>Phiếu khám bệnh vào viện</td><td>${_inTime.isNotEmpty ? _inTime : _dateStr}</td><td>✓</td></tr>
<tr><td>2</td><td>Tờ điều trị</td><td>${_dateStr}</td><td>✓</td></tr>
<tr><td>3</td><td>Phiếu theo dõi & chăm sóc</td><td>${_dateStr}</td><td>✓</td></tr>
<tr><td>4</td><td>Phiếu công khai thuốc</td><td>${_dateStr}</td><td>✓</td></tr>
<tr><td>5</td><td>Phiếu chỉ định dịch vụ</td><td>${_dateStr}</td><td>✓</td></tr>
<tr><td>6</td><td>Vỏ bệnh án hồi bệnh</td><td>${_dateStr}</td><td>—</td></tr>
<tr><td>7</td><td>Bảng kê tổng hợp</td><td>${_dateStr}</td><td>—</td></tr>
</table>
$_signature("TRƯỞNG KHOA")''';
    }
    // Trang 2: tổng hợp diễn biến điều trị
    return '''
<div class="form-title">BỆNH ÁN ĐIỆN TỬ — TỔNG HỢP <span class="small">(trang 2)</span></div>
<div class="section-title">I. TÓM TẮT QUÁ TRÌNH ĐIỀU TRỊ</div>
<div>Bệnh nhân vào viện ngày ${_inTime.isNotEmpty ? _inTime : _dateStr}, được chẩn đoán: ${_icd.isNotEmpty ? _icd : "(đang cập nhật)"}.</div>
<div>Điều trị tại khoa: ${_deptName}.</div>
<div>Diễn biến: tạm ổn, đang theo dõi tiếp.</div>
<div class="section-title">II. KẾT QUẢ CẬN LÂM SÀNG</div>
<table class="bordered">
<tr><th>Xét nghiệm</th><th>Kết quả</th></tr>
<tr><td>CTM</td><td>Trong giới hạn bình thường</td></tr>
<tr><td>Sinh hóa máu</td><td>Glucose 6.5 mmol/L, ALT 28 U/L, Creatinin 80 μmol/L</td></tr>
<tr><td>ECG</td><td>NNP, tần số 88 lần/phút</td></tr>
</table>
<div class="section-title">III. HƯỚNG ĐIỀU TRỊ TIẾP</div>
<div>1. Tiếp tục điều trị theo phác đồ hiện tại.</div>
<div>2. Tái khám sau 7 ngày hoặc sớm hơn nếu bất thường.</div>
$_signature("BS ĐIỀU TRỊ")''';
  }

  String _scanTaiLieu() {
    return '''
$_soyt
<div class="form-title">SCAN TÀI LIỆU BỆNH ÁN</div>
<div class="row"><span class="label">Bệnh nhân:</span><span class="val">${_name.toUpperCase()}</span></div>
<div class="row"><span class="label">Mã BN/ĐT:</span><span class="val">$_code / ${_reqCode.isNotEmpty ? _reqCode : "—"}</span></div>
<hr class="line"/>
<div class="section-title">DANH SÁCH TÀI LIỆU ĐÃ SCAN:</div>
<table class="bordered">
<tr><th>STT</th><th>Tên tài liệu</th><th>Ngày scan</th><th>Kích thước</th></tr>
<tr><td colspan="4" class="center">Chưa có tài liệu scan nào.</td></tr>
</table>
<div class="small">Bấm nút "+" ở Home → Scan tài liệu để chụp/chọn file từ thiết bị.</div>
$_signature("ĐD LƯU TRỮ HỒ SƠ")''';
  }

  String _empty() => '<div class="center" style="padding: 40pt;">Phiếu này chưa có sẵn. Vui lòng chọn phiếu khác.</div>';
}



