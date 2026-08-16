// PhieuPhauThuatScreen v3.0.132 - GIẤY CAM KẾT CHẤP THUẬN PHẪU THUẬT, THỦ THUẬT VÀ GÂY MÊ HỒI SỨC
// Mẫu MS: 01/BV2 - Fix font tiếng Việt (Roboto TTF) + 3 chỗ ký + layout đúng mau.pdf
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as pathJoin;
import 'package:signature/signature.dart';
import 'package:printing/printing.dart';

/// v3.0.132: Form Phiếu phẫu thuật (Giấy cam kết chấp thuận PT/TT/GMHS)
/// Mẫu: MS 01/BV2 - SỞ Y TẾ TỈNH KHÁNH HÒA / BVĐK NINH THUẬN
/// Changes v3.0.132:
/// - Fix font Vietnamese (Roboto TTF from assets)
/// - 3 chỗ ký (NB + Bác sỹ gây mê + Phẫu thuật viên)
/// - Checkbox đồng ý/không đồng ý
/// - Dòng ghi chú tay
/// - Ngày tháng năm
class PhieuPhauThuatScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const PhieuPhauThuatScreen({
    super.key,
    required this.patient,
    required this.department,
  });

  @override
  State<PhieuPhauThuatScreen> createState() => _PhieuPhauThuatScreenState();
}

class _PhieuPhauThuatScreenState extends State<PhieuPhauThuatScreen> {
  // ===== Controllers =====
  final _tenBacSiCtrl = TextEditingController();
  final _chucDanhCtrl = TextEditingController();
  final _khoaCtrl = TextEditingController();
  final _tenBenhNhanCtrl = TextEditingController();
  final _chanDoanCtrl = TextEditingController();
  final _nguyenLyCtrl = TextEditingController();
  final _ketQuaCtrl = TextEditingController();
  final _nguyCoKhacCtrl = TextEditingController();
  final _phuongPhapKhacCtrl = TextEditingController();
  final _gayMeKhacCtrl = TextEditingController();
  final _dieuTriKhacCtrl = TextEditingController();
  final _tenThanNhanCtrl = TextEditingController();
  final _namSinhThanNhanCtrl = TextEditingController();
  final _quanHeThanNhanCtrl = TextEditingController();

  // ===== Mức (Cấp cứu/Bán cấp/Chương trình/Phiên) =====
  String? _muc;

  // ===== Phương pháp phẫu thuật (chọn 1) =====
  String? _phuongPhapPT;

  // ===== Phương pháp gây mê (multi-select) =====
  final Set<String> _gayMe = <String>{};

  // ===== Phương pháp điều trị khác =====
  String? _dieuTriKhac;

  // ===== Nguy cơ tai biến (multi-select) =====
  final Set<String> _nguyCo = <String>{};

  // ===== Đồng ý =====
  bool? _dongY; // null=chưa chọn, true=đồng ý, false=không

  // ===== 3 Signature controllers =====
  final SignatureController _sigCtrlNB = SignatureController(
    penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );
  final SignatureController _sigCtrlGayMe = SignatureController(
    penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );
  final SignatureController _sigCtrlPTTB = SignatureController(
    penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white,
  );

  // ===== Tên bác sĩ gây mê & phẫu thuật viên =====
  final _tenBacSiGayMeCtrl = TextEditingController();
  final _tenPhauThuatVienCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefillFromPatient();
  }

  void _prefillFromPatient() {
    final p = widget.patient;
    _tenBenhNhanCtrl.text =
        (p['TDL_PATIENT_UNSIGNED_NAME'] ?? p['tdl_patient_unsigned_name'] ?? '')
            .toString();
    if (_tenBenhNhanCtrl.text.isEmpty) {
      _tenBenhNhanCtrl.text = (p['VIR_PATIENT_NAME'] ?? '').toString();
    }
    final dob = (p['TDL_PATIENT_DOB'] ?? p['tdl_patient_dob'] ?? '').toString();
    if (dob.isNotEmpty && dob.length >= 4) {
      _namSinhThanNhanCtrl.text = dob.substring(0, 4);
    }
    _khoaCtrl.text = (widget.department['name'] ?? '').toString();
  }

  @override
  void dispose() {
    _tenBacSiCtrl.dispose();
    _chucDanhCtrl.dispose();
    _khoaCtrl.dispose();
    _tenBenhNhanCtrl.dispose();
    _chanDoanCtrl.dispose();
    _nguyenLyCtrl.dispose();
    _ketQuaCtrl.dispose();
    _nguyCoKhacCtrl.dispose();
    _phuongPhapKhacCtrl.dispose();
    _gayMeKhacCtrl.dispose();
    _dieuTriKhacCtrl.dispose();
    _tenThanNhanCtrl.dispose();
    _namSinhThanNhanCtrl.dispose();
    _quanHeThanNhanCtrl.dispose();
    _tenBacSiGayMeCtrl.dispose();
    _tenPhauThuatVienCtrl.dispose();
    _sigCtrlNB.dispose();
    _sigCtrlGayMe.dispose();
    _sigCtrlPTTB.dispose();
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
        title: const Text('Phiếu phẫu thuật (Cam kết chấp thuận)'),
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
              // ===== HEADER =====
              _buildHeader(),
              const SizedBox(height: 8),
              _buildFormNumber(),
              const SizedBox(height: 16),
              _buildTitle(),
              const SizedBox(height: 16),

              // ===== MỨC =====
              _buildMuc(),
              const Divider(thickness: 1),

              // ===== I. BÁC SỸ =====
              _buildSectionHeader('I. BÁC SỸ PHẪU THUẬT/THỦ THUẬT/GÂY MÊ HỒI SỨC:'),
              _buildBacSi(),
              const Divider(thickness: 1),

              // ===== TƯ VẤN =====
              _buildTuVan(),
              const Divider(thickness: 1),

              // ===== PHƯƠNG PHÁP PT =====
              _buildPhuongPhapPT(),
              const Divider(thickness: 1),

              // ===== PHƯƠNG PHÁP GÂY MÊ =====
              _buildPhuongPhapGayMe(),
              const Divider(thickness: 1),

              // ===== PHƯƠNG PHÁP ĐIỀU TRỊ KHÁC =====
              _buildDieuTriKhac(),
              const Divider(thickness: 1),

              // ===== NGUY CƠ TAI BIẾN =====
              _buildNguyCo(),

              const Divider(thickness: 1),

              // ===== CAM KẾT BS =====
              _buildCamKetBS(),
              const Divider(thickness: 1),

              // ===== II. NGƯỜI BỆNH/THÂN NHÂN =====
              _buildSectionHeader('II. NGƯỜI BỆNH/THÂN NHÂN:'),
              _buildNguoiBenh(),
              const Divider(thickness: 1),

              // ===== CAM KẾT NB + ĐỒNG Ý =====
              _buildCamKetNB(),

              const SizedBox(height: 16),

              // ===== 3 CHỮ KÝ =====
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
                  icon: const Icon(Icons.close, color: Color(0xFFB71C1C)),
                  label: const Text('Hủy', style: TextStyle(color: Color(0xFFB71C1C))),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined, color: Color(0xFFB71C1C)),
                  label: const Text('Lưu', style: TextStyle(color: Color(0xFFB71C1C))),
                  onPressed: _saving ? null : () => _save(uploadToEmr: false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB71C1C),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.edit_document),
                  label: const Text('Lưu+Ký'),
                  onPressed: _saving ? null : () => _save(uploadToEmr: false, requireSignatures: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION WIDGETS
  // ===========================================================================
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              SizedBox(height: 2),
              Text('Độc lập - Tự do - Hạnh phúc',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
              SizedBox(height: 2),
              Text('─────────────────',
                  style: TextStyle(fontSize: 10, color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormNumber() {
    return const Align(
      alignment: Alignment.centerRight,
      child: Text('MS: 01/BV2',
          style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
    );
  }

  Widget _buildTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: const Text(
        'GIẤY CAM KẾT CHẤP THUẬN PHẪU THUẬT, THỦ THUẬT VÀ GÂY MÊ HỒI SỨC',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFB71C1C)),
      ),
    );
  }

  Widget _buildMuc() {
    return Row(
      children: [
        _checkBox('Cấp cứu', _muc == 'CAP_CUU',
            (v) => setState(() => _muc = v ? 'CAP_CUU' : null)),
        const SizedBox(width: 12),
        _checkBox('Bán cấp', _muc == 'BAN_CAP',
            (v) => setState(() => _muc = v ? 'BAN_CAP' : null)),
        const SizedBox(width: 12),
        _checkBox('Chương trình/Phiên', _muc == 'CHUONG_TRINH',
            (v) => setState(() => _muc = v ? 'CHUONG_TRINH' : null)),
      ],
    );
  }

  Widget _buildBacSi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Chúng tôi có tên dưới đây cùng làm Bản cam kết như sau:'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Tôi tên là: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_tenBacSiCtrl, hint: 'BSCKII Ngư Châu Phương')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Chức danh: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_chucDanhCtrl, hint: 'Bác sĩ / Bác sĩ chuyên khoa...')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Khoa: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_khoaCtrl, hint: 'Khoa...')),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Được phân công thực hiện phẫu thuật/thủ thuật/gây mê cho người bệnh:'),
        _redField(_tenBenhNhanCtrl, hint: 'TÊN BỆNH NHÂN'),
        const SizedBox(height: 6),
        const Text('Chẩn đoán:'),
        _redField(_chanDoanCtrl, hint: 'Chẩn đoán bệnh', maxLines: 2),
      ],
    );
  }

  Widget _buildTuVan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
            'Chúng tôi đã tư vấn, giải thích đầy đủ, rõ ràng những thông tin liên quan đến cuộc phẫu thuật/thủ thuật/gây mê hồi sức cho người bệnh/thân nhân người bệnh về các vấn đề sau:'),
        const SizedBox(height: 6),
        _bulletText('Chẩn đoán'),
        _bulletText('Lý do phẫu thuật/thủ thuật'),
        _bulletText('Rủi ro, nguy cơ nếu không thực hiện phẫu thuật/thủ thuật'),
        _bulletText('Kết quả sau phẫu thuật/thủ thuật (dự kiến)'),
        _bulletText('Phương pháp phẫu thuật/thủ thuật dự kiến'),
      ],
    );
  }

  Widget _buildPhuongPhapPT() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Phương pháp phẫu thuật/thủ thuật dự kiến:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: [
            _checkBox('Phẫu thuật mở', _phuongPhapPT == 'MO',
                (v) => setState(() => _phuongPhapPT = v ? 'MO' : null)),
            const SizedBox(width: 12),
            _checkBox('Phẫu thuật nội soi', _phuongPhapPT == 'NOI_SOI',
                (v) => setState(() => _phuongPhapPT = v ? 'NOI_SOI' : null)),
            const SizedBox(width: 12),
            _checkBox('Thủ thuật', _phuongPhapPT == 'THU_THUAT',
                (v) => setState(() => _phuongPhapPT = v ? 'THU_THUAT' : null)),
          ],
        ),
        Row(
          children: [
            _checkBox('Khác (ghi rõ nếu có):', _phuongPhapPT == 'KHAC',
                (v) => setState(() => _phuongPhapPT = v ? 'KHAC' : null)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_phuongPhapKhacCtrl, hint: 'Phương pháp khác...')),
          ],
        ),
      ],
    );
  }

  Widget _buildPhuongPhapGayMe() {
    final options = const [
      ['ME_NOI_KHI_QUAN', 'Mê nội khí quản'],
      ['TE_TUY_SONG', 'Tê tủy sống'],
      ['TIEN_ME_TE_TAI_CHO', 'Tiền mê + Tê tại chỗ'],
      ['ME_MASK_THANH_QUAN', 'Mê mask thanh quản'],
      ['TE_NGOAI_MANG_CUNG', 'Tê ngoài màng cứng'],
      ['ME_TINH_MACH', 'Mê tĩnh mạch'],
      ['TE_DAM_ROI_THANH_KINH', 'Tê đám rối thần kinh'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Phương pháp gây mê hồi sức dự kiến:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8, runSpacing: 4,
          children: options.map((o) {
            final k = o[0];
            final label = o[1];
            return SizedBox(
              width: (MediaQuery.of(context).size.width / 2) - 24,
              child: _checkBox(label, _gayMe.contains(k), (v) {
                setState(() {
                  if (v) { _gayMe.add(k); } else { _gayMe.remove(k); }
                });
              }),
            );
          }).toList(),
        ),
        Row(
          children: [
            _checkBox('Khác (ghi rõ nếu có):', _gayMe.contains('KHAC'), (v) {
              setState(() {
                if (v) { _gayMe.add('KHAC'); } else { _gayMe.remove('KHAC'); }
              });
            }),
            const SizedBox(width: 8),
            Expanded(child: _redField(_gayMeKhacCtrl, hint: 'Phương pháp GM khác...')),
          ],
        ),
      ],
    );
  }

  Widget _buildDieuTriKhac() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Các phương pháp điều trị khác ngoài phẫu thuật/thủ thuật:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: [
            _checkBox('Không', _dieuTriKhac == 'KHONG',
                (v) => setState(() => _dieuTriKhac = v ? 'KHONG' : null)),
            const SizedBox(width: 12),
            _checkBox('Có, cụ thể:', _dieuTriKhac == 'CO',
                (v) => setState(() => _dieuTriKhac = v ? 'CO' : null)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_dieuTriKhacCtrl, hint: 'Phương pháp điều trị khác...')),
          ],
        ),
      ],
    );
  }

  Widget _buildNguyCo() {
    final options = const [
      ['PHAN_UNG_THUOC', 'Phản ứng thuốc'],
      ['NHIEM_TRUNG', 'Nhiễm trùng'],
      ['SUY_HO_HAP_TUAN_HOAN', 'Suy hô hấp - tuần hoàn'],
      ['TU_VONG', 'Tử vong'],
      ['CHAY_MAU', 'Chảy máu'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nguy cơ, tai biến trong và sau phẫu thuật/thủ thuật có thể xảy ra:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8, runSpacing: 4,
          children: options.map((o) {
            final k = o[0];
            final label = o[1];
            return SizedBox(
              width: (MediaQuery.of(context).size.width / 2) - 24,
              child: _checkBox(label, _nguyCo.contains(k), (v) {
                setState(() {
                  if (v) { _nguyCo.add(k); } else { _nguyCo.remove(k); }
                });
              }),
            );
          }).toList(),
        ),
        Row(
          children: [
            _checkBox('Nguy cơ/rủi ro khác:', _nguyCo.contains('KHAC'), (v) {
              setState(() {
                if (v) { _nguyCo.add('KHAC'); } else { _nguyCo.remove('KHAC'); }
              });
            }),
            const SizedBox(width: 8),
            Expanded(child: _redField(_nguyCoKhacCtrl, hint: 'Nguy cơ khác...')),
          ],
        ),
      ],
    );
  }

  Widget _buildCamKetBS() {
    return const Text(
      'Chúng tôi đã dành đủ thời gian để người bệnh/thân nhân đặt các câu hỏi liên quan đến phẫu thuật/thủ thuật/gây mê sẽ được thực hiện hoặc các mối quan tâm khác và chúng tôi đã trả lời tất cả các câu hỏi đó.\n\n'
      'Chúng tôi cam kết phục vụ người bệnh bằng lương tâm và trách nhiệm của người thầy thuốc cùng với tất cả kiến thức, sự hiểu biết về chuyên môn và phương tiện hiện có của BỆNH VIỆN ĐA KHOA NINH THUẬN để nỗ lực đem lại kết quả tốt nhất cho người bệnh.',
      style: TextStyle(fontSize: 12, height: 1.4),
    );
  }

  Widget _buildNguoiBenh() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Họ và tên người bệnh:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_tenBenhNhanCtrl, hint: 'TÊN BỆNH NHÂN')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Họ và tên thân nhân:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: _redField(_tenThanNhanCtrl, hint: 'TÊN THÂN NHÂN')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Năm sinh:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(width: 80, child: _redField(_namSinhThanNhanCtrl, hint: 'YYYY', keyboardType: TextInputType.number)),
            const SizedBox(width: 16),
            const Text('Quan hệ:', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_quanHeThanNhanCtrl, hint: 'Bố/Mẹ/Vợ/Chồng...')),
          ],
        ),
      ],
    );
  }

  Widget _buildCamKetNB() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sau khi nghe các Bác sỹ cho biết tình trạng bệnh của tôi/thân nhân của tôi, những nguy hiểm của bệnh nếu không thực hiện phẫu thuật/thủ thuật/gây mê hồi sức và những rủi ro có thể xảy ra do bệnh tật, do khi tiến hành phẫu thuật/thủ thuật/gây mê hồi sức; tôi tự nguyện viết giấy cam đoan này:',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 8),
        // 2 lựa chọn đồng ý / không đồng ý
        Row(
          children: [
            _checkBox(
              '1. Đồng ý xin phẫu thuật, thủ thuật, gây mê hồi sức và để giấy này làm bằng chứng.',
              _dongY == true,
              (v) => setState(() => _dongY = v ? true : null),
            ),
          ],
        ),
        Row(
          children: [
            _checkBox(
              '2. Không đồng ý xin phẫu thuật, thủ thuật, gây mê hồi sức và để giấy này làm bằng chứng.',
              _dongY == false,
              (v) => setState(() => _dongY = v ? false : null),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tôi đã đọc bản cam kết với tinh thần hoàn toàn minh mẫn và hiểu biết. Tôi đã hiểu các vấn đề mà Bác sỹ đã giải thích về tiến trình phẫu thuật/thủ thuật/gây mê cho tôi/thân nhân của tôi. Tôi xin hoàn toàn chịu trách nhiệm với quyết định đồng ý cho Bác sỹ phẫu thuật/thủ thuật cho tôi/thân nhân của tôi.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('NGƯỜI BỆNH/THÂN NHÂN:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          height: 160,
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
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Xóa'),
          ),
        ),

        const SizedBox(height: 12),
        const Text('BÁC SỸ GÂY MÊ:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('Tên: ', style: TextStyle(fontSize: 13)),
            Expanded(child: _redField(_tenBacSiGayMeCtrl, hint: 'Tên Bác sĩ gây mê')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black54),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Signature(controller: _sigCtrlGayMe, backgroundColor: Colors.white),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _sigCtrlGayMe.clear()),
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Xóa'),
          ),
        ),

        const SizedBox(height: 12),
        const Text('PHẪU THUẬT VIÊN/BÁC SỸ THỰC HIỆN THỦ THUẬT:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('Tên: ', style: TextStyle(fontSize: 13)),
            Expanded(child: _redField(_tenPhauThuatVienCtrl, hint: 'Tên Phẫu thuật viên')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black54),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Signature(controller: _sigCtrlPTTB, backgroundColor: Colors.white),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _sigCtrlPTTB.clear()),
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Xóa'),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // REUSABLE WIDGETS
  // ===========================================================================
  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _redField(TextEditingController c,
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

  Widget _checkBox(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value ? '☒' : '☐',
              style: const TextStyle(fontSize: 16, color: Color(0xFFB71C1C))),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _bulletText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ===========================================================================
  // SAVE / PDF / EMR
  // ===========================================================================
  Future<void> _save({required bool uploadToEmr, bool requireSignatures = false}) async {
    if (_tenBacSiCtrl.text.isEmpty) { _toast('Vui lòng nhập tên Bác sĩ'); return; }
    if (_tenBenhNhanCtrl.text.isEmpty) { _toast('Vui lòng nhập tên Bệnh nhân'); return; }
    if (requireSignatures && !_sigCtrlNB.isNotEmpty) {
      _toast('Vui lòng ký tên người bệnh/thân nhân');
      return;
    }

    setState(() => _saving = true);
    try {
      final pdfBytes = await _buildPdf();
      final path = await _savePdfLocal(pdfBytes);
      String? emrResult;
      if (uploadToEmr) {
        emrResult = await _syncEmr(pdfBytes);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Đã lưu PDF${requireSignatures ? ' + chữ ký' : ''}\n$path'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'MỞ', onPressed: () => _openPdf(path)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Lỗi lưu: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ===========================================================================
  // PDF GENERATION
  // ===========================================================================
  /// Font tiếng Việt - load từ assets
  static pw.Font? _pdfFont;
  static pw.Font? _pdfFontBold;

  Future<void> _ensurePdfFonts() async {
    if (_pdfFont != null) return;
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      _pdfFont = pw.Font.ttf(fontData.buffer.asByteData()!);
      _pdfFontBold = pw.Font.ttf(boldData.buffer.asByteData()!);
    } catch (e) {
      debugPrint('Failed to load Roboto font, using fallback: $e');
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

  /// Render PDF đúng mẫu MS: 01/BV2 với font Roboto + 3 chỗ ký
  Future<Uint8List> _buildPdf() async {
    await _ensurePdfFonts();

    final now = DateTime.now();
    final hasSigNB = _sigCtrlNB.isNotEmpty;
    final hasSigGM = _sigCtrlGayMe.isNotEmpty;
    final hasSigPTTB = _sigCtrlPTTB.isNotEmpty;

    final sigNbBytes = hasSigNB ? await _sigCtrlNB.toPngBytes() : null;
    final sigGmBytes = hasSigGM ? await _sigCtrlGayMe.toPngBytes() : null;
    final sigPttbBytes = hasSigPTTB ? await _sigCtrlPTTB.toPngBytes() : null;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => [
          _pdfHeader(),
          _pdfFormNumber(),
          _pdfTitle(),
          _pdfMuc(),
          _pdfBacSi(),
          _pdfTuVan(),
          _pdfPhuongPhapPT(),
          _pdfPhuongPhapGayMe(),
          _pdfDieuTriKhac(),
          _pdfNguyCo(),
          _pdfCamKetBS(),
          _pdfNguoiBenh(),
          _pdfCamKetNB(),
          // Dòng ghi chú
          _pdfNoteLine(),
          // 3 chữ ký
          _pdfSignatureNB(sigNbBytes),
          _pdfSignatureGayMe(sigGmBytes),
          _pdfSignaturePTTB(sigPttbBytes),
          // Ngày tháng năm
          _pdfDateFooter(now),
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
              pw.Text('─────────────────', style: _s(9)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfFormNumber() => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('MS: 01/BV2', style: _s(10, style: pw.FontStyle.italic)),
      );

  pw.Widget _pdfTitle() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        child: pw.Center(
          child: pw.Text(
            'GIẤY CAM KẾT CHẤP THUẬN\nPHẪU THUẬT, THỦ THUẬT VÀ GÂY MÊ HỒI SỨC',
            textAlign: pw.TextAlign.center,
            style: _s(13, bold: true, color: PdfColors.red900),
          ),
        ),
      );

  pw.Widget _pdfMuc() {
    String label;
    if (_muc == 'CAP_CUU') {
      label = '☑ Cấp cứu    ☐ Bán cấp    ☐ Chương trình/Phiên';
    } else if (_muc == 'BAN_CAP') {
      label = '☐ Cấp cứu    ☑ Bán cấp    ☐ Chương trình/Phiên';
    } else {
      label = '☐ Cấp cứu    ☐ Bán cấp    ☑ Chương trình/Phiên';
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(label, style: _s(11)),
    );
  }

  pw.Widget _pdfBacSi() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('I. BÁC SỸ PHẪU THUẬT/THỦ THUẬT/GÂY MÊ HỒI SỨC:', style: _s(12, bold: true)),
          pw.SizedBox(height: 4),
          pw.Text('Chúng tôi có tên dưới đây cùng làm Bản cam kết như sau:', style: _s(11)),
          pw.SizedBox(height: 4),
          _pdfKv('Tôi tên là:', _tenBacSiCtrl.text),
          _pdfKv('Chức danh:', _chucDanhCtrl.text),
          _pdfKv('Khoa:', _khoaCtrl.text),
          _pdfKv('Được phân công thực hiện cho người bệnh:', _tenBenhNhanCtrl.text),
          _pdfKv('Chẩn đoán:', _chanDoanCtrl.text),
        ],
      );

  pw.Widget _pdfTuVan() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
                'Chúng tôi đã tư vấn, giải thích đầy đủ, rõ ràng những thông tin liên quan đến cuộc phẫu thuật/thủ thuật/gây mê hồi sức cho người bệnh/thân nhân người bệnh về các vấn đề sau:',
                style: _s(11)),
            pw.SizedBox(height: 4),
            pw.Bullet(text: 'Chẩn đoán', style: _s(11)),
            pw.Bullet(text: 'Lý do phẫu thuật/thủ thuật', style: _s(11)),
            pw.Bullet(text: 'Rủi ro, nguy cơ nếu không thực hiện phẫu thuật/thủ thuật', style: _s(11)),
            pw.Bullet(text: 'Kết quả sau phẫu thuật/thủ thuật (dự kiến)', style: _s(11)),
            pw.Bullet(text: 'Phương pháp phẫu thuật/thủ thuật dự kiến', style: _s(11)),
          ],
        ),
      );

  pw.Widget _pdfPhuongPhapPT() {
    final m = _phuongPhapPT;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Phương pháp phẫu thuật/thủ thuật dự kiến:', style: _s(11, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text(
              '${m == 'MO' ? '☑' : '☐'} Phẫu thuật mở    ${m == 'NOI_SOI' ? '☑' : '☐'} Phẫu thuật nội soi    ${m == 'THU_THUAT' ? '☑' : '☐'} Thủ thuật',
              style: _s(11)),
          pw.Text('${m == 'KHAC' ? '☑' : '☐'} Khác (ghi rõ nếu có): ${_phuongPhapKhacCtrl.text}', style: _s(11)),
        ],
      ),
    );
  }

  pw.Widget _pdfPhuongPhapGayMe() {
    String row(int i) {
      final labels = [
        ['ME_NOI_KHI_QUAN', 'Mê nội khí quản'],
        ['TE_TUY_SONG', 'Tê tủy sống'],
        ['TIEN_ME_TE_TAI_CHO', 'Tiền mê + Tê tại chỗ'],
        ['ME_MASK_THANH_QUAN', 'Mê mask thanh quản'],
        ['TE_NGOAI_MANG_CUNG', 'Tê ngoài màng cứng'],
        ['ME_TINH_MACH', 'Mê tĩnh mạch'],
        ['TE_DAM_ROI_THANH_KINH', 'Tê đám rối thần kinh'],
      ];
      final a = labels[i * 2];
      final b = (i * 2 + 1 < labels.length) ? labels[i * 2 + 1] : null;
      String pair(List<String> o) => '${_gayMe.contains(o[0]) ? '☑' : '☐'} ${o[1]}';
      return b == null ? pair(a) : '${pair(a)}    ${pair(b)}';
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Phương pháp gây mê hồi sức dự kiến:', style: _s(11, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text(row(0), style: _s(11)),
          pw.Text(row(1), style: _s(11)),
          pw.Text(row(2), style: _s(11)),
          pw.Text(row(3), style: _s(11)),
          pw.Text('${_gayMe.contains('KHAC') ? '☑' : '☐'} Khác (ghi rõ nếu có): ${_gayMeKhacCtrl.text}', style: _s(11)),
        ],
      ),
    );
  }

  pw.Widget _pdfDieuTriKhac() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Các phương pháp điều trị khác ngoài phẫu thuật/thủ thuật:', style: _s(11, bold: true)),
            pw.SizedBox(height: 2),
            pw.Text('${_dieuTriKhac == 'KHONG' ? '☑' : '☐'} Không    ${_dieuTriKhac == 'CO' ? '☑' : '☐'} Có, cụ thể: ${_dieuTriKhacCtrl.text}', style: _s(11)),
          ],
        ),
      );

  pw.Widget _pdfNguyCo() {
    String row(int i) {
      final labels = [
        ['PHAN_UNG_THUOC', 'Phản ứng thuốc'],
        ['NHIEM_TRUNG', 'Nhiễm trùng'],
        ['SUY_HO_HAP_TUAN_HOAN', 'Suy hô hấp - tuần hoàn'],
        ['TU_VONG', 'Tử vong'],
        ['CHAY_MAU', 'Chảy máu'],
      ];
      final a = labels[i * 2];
      final b = (i * 2 + 1 < labels.length) ? labels[i * 2 + 1] : null;
      String pair(List<String> o) => '${_nguyCo.contains(o[0]) ? '☑' : '☐'} ${o[1]}';
      return b == null ? pair(a) : '${pair(a)}    ${pair(b)}';
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Nguy cơ, tai biến trong và sau phẫu thuật/thủ thuật có thể xảy ra:', style: _s(11, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text(row(0), style: _s(11)),
          pw.Text(row(1), style: _s(11)),
          pw.Text(row(2), style: _s(11)),
          pw.Text('${_nguyCo.contains('KHAC') ? '☑' : '☐'} Nguy cơ/rủi ro khác: ${_nguyCoKhacCtrl.text}', style: _s(11)),
        ],
      ),
    );
  }

  pw.Widget _pdfCamKetBS() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(
          'Chúng tôi đã dành đủ thời gian để người bệnh/thân nhân đặt các câu hỏi liên quan đến phẫu thuật/thủ thuật/gây mê sẽ được thực hiện hoặc các mối quan tâm khác và chúng tôi đã trả lời tất cả các câu hỏi đó.\n\n'
          'Chúng tôi cam kết phục vụ người bệnh bằng lương tâm và trách nhiệm của người thầy thuốc cùng với tất cả kiến thức, sự hiểu biết về chuyên môn và phương tiện hiện có của BỆNH VIỆN ĐA KHOA NINH THUẬN để nỗ lực đem lại kết quả tốt nhất cho người bệnh.',
          style: _s(11),
        ),
      );

  pw.Widget _pdfNguoiBenh() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 6),
          pw.Text('II. NGƯỜI BỆNH/THÂN NHÂN:', style: _s(12, bold: true)),
          pw.SizedBox(height: 4),
          _pdfKv('Họ và tên người bệnh:', _tenBenhNhanCtrl.text),
          _pdfKv('Họ và tên thân nhân:', _tenThanNhanCtrl.text),
          pw.Row(
            children: [
              pw.SizedBox(
                width: 100,
                child: pw.Text('Năm sinh:', style: _s(11)),
              ),
              pw.Text(_namSinhThanNhanCtrl.text, style: _s(11, bold: true)),
            ],
          ),
          _pdfKv('Quan hệ với người bệnh:', _quanHeThanNhanCtrl.text),
        ],
      );

  pw.Widget _pdfCamKetNB() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Sau khi nghe các Bác sỹ cho biết tình trạng bệnh của tôi/thân nhân của tôi, những nguy hiểm của bệnh nếu không thực hiện phẫu thuật/thủ thuật/gây mê hồi sức và những rủi ro có thể xảy ra do bệnh tật, do khi tiến hành phẫu thuật/thủ thuật/gây mê hồi sức; tôi tự nguyện viết giấy cam đoan này:',
              style: _s(11),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '${_dongY == true ? '☑' : '☐'} 1. Đồng ý xin phẫu thuật, thủ thuật, gây mê hồi sức và để giấy này làm bằng chứng.',
              style: _s(11),
            ),
            pw.Text(
              '${_dongY == false ? '☑' : '☐'} 2. Không đồng ý xin phẫu thuật, thủ thuật, gây mê hồi sức và để giấy này làm bằng chứng.',
              style: _s(11),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Tôi đã đọc bản cam kết với tinh thần hoàn toàn minh mẫn và hiểu biết. Tôi đã hiểu các vấn đề mà Bác sỹ đã giải thích về tiến trình phẫu thuật/thủ thuật/gây mê cho tôi/thân nhân của tôi. Tôi xin hoàn toàn chịu trách nhiệm với quyết định đồng ý cho Bác sỹ phẫu thuật/thủ thuật cho tôi/thân nhân của tôi.',
              style: _s(11),
            ),
          ],
        ),
      );

  /// Dòng ghi chú tay
  pw.Widget _pdfNoteLine() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Text(
          '..............................................................................................................................................................................',
          style: _s(11),
        ),
      );

  /// Chữ ký người bệnh/thân nhân
  pw.Widget _pdfSignatureNB(Uint8List? bytes) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NGƯỜI BỆNH/THÂN NHÂN:', style: _s(11, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text('(Ký, ghi rõ họ tên)', style: _s(10, style: pw.FontStyle.italic)),
          pw.SizedBox(height: 4),
          if (bytes != null)
            pw.Container(
              height: 80,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(pw.MemoryImage(bytes), height: 80, fit: pw.BoxFit.contain),
            )
          else
            pw.Container(height: 80, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
          pw.SizedBox(height: 2),
          pw.Text('(Họ và tên)', style: _s(10)),
        ],
      ),
    );
  }

  /// Chữ ký bác sỹ gây mê
  pw.Widget _pdfSignatureGayMe(Uint8List? bytes) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('BÁC SỸ GÂY MÊ:', style: _s(11, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text('(Ký, ghi rõ họ tên) ${_tenBacSiGayMeCtrl.text.isNotEmpty ? _tenBacSiGayMeCtrl.text : ""}', style: _s(10, style: pw.FontStyle.italic)),
          pw.SizedBox(height: 4),
          if (bytes != null)
            pw.Container(
              height: 80,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(pw.MemoryImage(bytes), height: 80, fit: pw.BoxFit.contain),
            )
          else
            pw.Container(height: 80, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
          pw.SizedBox(height: 2),
          pw.Text('(Họ và tên)', style: _s(10)),
        ],
      ),
    );
  }

  /// Chữ ký phẫu thuật viên
  pw.Widget _pdfSignaturePTTB(Uint8List? bytes) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PHẪU THUẬT VIÊN/BÁC SỸ THỰC HIỆN THỦ THUẬT:', style: _s(11, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text('(Ký, ghi rõ họ tên) ${_tenPhauThuatVienCtrl.text.isNotEmpty ? _tenPhauThuatVienCtrl.text : ""}', style: _s(10, style: pw.FontStyle.italic)),
          pw.SizedBox(height: 4),
          if (bytes != null)
            pw.Container(
              height: 80,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(pw.MemoryImage(bytes), height: 80, fit: pw.BoxFit.contain),
            )
          else
            pw.Container(height: 80, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
          pw.SizedBox(height: 2),
          pw.Text('(Họ và tên)', style: _s(10)),
        ],
      ),
    );
  }

  /// Dòng ngày tháng năm
  pw.Widget _pdfDateFooter(DateTime now) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('Ngày  ${now.day.toString().padLeft(2, '0')}  tháng  ${now.month.toString().padLeft(2, '0')}  năm  ${now.year}', style: _s(11)),
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
          pw.SizedBox(width: 160, child: pw.Text('$key ', style: _s(11))),
          pw.Expanded(
            child: pw.Text(value.isEmpty ? '(...)' : value,
                style: _s(11,
                    bold: value.isNotEmpty,
                    color: value.isEmpty ? PdfColors.grey : PdfColors.black)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FILE / EMR
  // ===========================================================================
  Future<String> _savePdfLocal(Uint8List pdfBytes) async {
    final treatmentCode = (widget.patient['TDL_TREATMENT_CODE'] ??
            widget.patient['treatment_code'] ?? 'BN')
        .toString();
    final fileName =
        'PhieuPhauThuat_${treatmentCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final dir = await getApplicationDocumentsDirectory();
    final hisDir = Directory(pathJoin.join(dir.path, 'HisMobile'));
    if (!await hisDir.exists()) await hisDir.create(recursive: true);
    final file = File(pathJoin.join(hisDir.path, fileName));
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  Future<String?> _syncEmr(Uint8List pdfBytes) async {
    const String emrEndpoint = '';
    if (emrEndpoint.isEmpty) {
      debugPrint('EMR sync placeholder: ${pdfBytes.length} bytes');
      return null;
    }
    try {
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _openPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    await Printing.sharePdf(
        bytes: bytes, filename: path.split(Platform.pathSeparator).last);
  }
}
