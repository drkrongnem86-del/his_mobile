// PhieuPhauThuatScreen v3.0.131 - GIẤY CAM KẾT CHẤP THUẬN PHẪU THUẬT, THỦ THUẬT VÀ GÂY MÊ HỒI SỨC
// Form Word-style (mẫu MS: 01/BV2) với text fields đỏ (editable) và checkboxes ☐/☒
// Sau khi Lưu → tạo PDF (mimetype y Word doc) → lưu local + sync EMR (placeholder)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as pathJoin;
import 'package:signature/signature.dart';
import 'package:printing/printing.dart';

/// v3.0.131: Form Phiếu phẫu thuật (Giấy cam kết chấp thuận PT/TT/GMHS)
/// Mẫu: MS 01/BV2 - SỞ Y TẾ TỈNH KHÁNH HÒA / BVĐK NINH THUẬN
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
  // ===== Controllers cho text fields (chữ tô đỏ trong Word) =====
  final _tenBacSiCtrl = TextEditingController();
  final _chucDanhCtrl = TextEditingController();
  final _khoaCtrl = TextEditingController();
  final _tenBenhNhanCtrl = TextEditingController();
  final _chanDoanCtrl = TextEditingController();
  final _nguyCoKhacCtrl = TextEditingController();
  final _phuongPhapKhacCtrl = TextEditingController();
  final _gayMeKhacCtrl = TextEditingController();
  final _dieuTriKhacCtrl = TextEditingController();
  final _tenThanNhanCtrl = TextEditingController();
  final _namSinhThanNhanCtrl = TextEditingController();
  final _quanHeThanNhanCtrl = TextEditingController();

  // ===== Mức (Cấp cứu/Bán cấp/Chương trình/Phiên) =====
  String? _muc; // 'CAP_CUU' | 'BAN_CAP' | 'CHUONG_TRINH' | 'PHIEN'

  // ===== Phương pháp phẫu thuật (chọn 1) =====
  String? _phuongPhapPT; // 'MO' | 'NOI_SOI' | 'THU_THUAT' | 'KHAC'

  // ===== Phương pháp gây mê (multi-select) =====
  final Set<String> _gayMe = <String>{};

  // ===== Phương pháp điều trị khác =====
  String? _dieuTriKhac; // 'KHONG' | 'CO'

  // ===== Nguy cơ tai biến (multi-select) =====
  final Set<String> _nguyCo = <String>{};

  // ===== Signature =====
  final SignatureController _sigCtrl = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

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
    // Năm sinh
    final dob = (p['TDL_PATIENT_DOB'] ?? p['tdl_patient_dob'] ?? '').toString();
    if (dob.isNotEmpty && dob.length >= 4) {
      _namSinhThanNhanCtrl.text = dob.substring(0, 4);
    }
    // Khoa
    _khoaCtrl.text = (widget.department['name'] ?? '').toString();
  }

  @override
  void dispose() {
    _tenBacSiCtrl.dispose();
    _chucDanhCtrl.dispose();
    _khoaCtrl.dispose();
    _tenBenhNhanCtrl.dispose();
    _chanDoanCtrl.dispose();
    _nguyCoKhacCtrl.dispose();
    _phuongPhapKhacCtrl.dispose();
    _gayMeKhacCtrl.dispose();
    _dieuTriKhacCtrl.dispose();
    _tenThanNhanCtrl.dispose();
    _namSinhThanNhanCtrl.dispose();
    _quanHeThanNhanCtrl.dispose();
    _sigCtrl.dispose();
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
        actions: [
          IconButton(
            tooltip: 'Lưu',
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : () => _save(uploadToEmr: false),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== HEADER (Word style) =====
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

              // ===== CAM KẾT NGƯỜI BỆNH =====
              _buildCamKetNB(),

              const SizedBox(height: 16),
              // ===== KÝ TÊN =====
              _buildSignature(),

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
                  icon: const Icon(Icons.save_outlined, color: Color(0xFFB71C1C)),
                  label: const Text('Lưu (PDF local)',
                      style: TextStyle(color: Color(0xFFB71C1C))),
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
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Lưu + EMR'),
                  onPressed: _saving ? null : () => _save(uploadToEmr: true),
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
        style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFB71C1C)),
      ),
    );
  }

  Widget _buildMuc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _checkBox('Cấp cứu', _muc == 'CAP_CUU',
                (v) => setState(() => _muc = v ? 'CAP_CUU' : null)),
            const SizedBox(width: 12),
            _checkBox('Bán cấp', _muc == 'BAN_CAP',
                (v) => setState(() => _muc = v ? 'BAN_CAP' : null)),
            const SizedBox(width: 12),
            _checkBox('Chương trình', _muc == 'CHUONG_TRINH',
                (v) => setState(() => _muc = v ? 'CHUONG_TRINH' : null)),
            const SizedBox(width: 12),
            _checkBox('Phiên', _muc == 'PHIEN',
                (v) => setState(() => _muc = v ? 'PHIEN' : null)),
          ],
        ),
      ],
    );
  }

  Widget _buildBacSi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Chúng tôi có tên dưới đây cùng làm Bản cam kết như sau:'),
        const SizedBox(height: 8),
        const Text('Tôi tên là:'),
        _redField(_tenBacSiCtrl, hint: 'TÊN BÁC SĨ'),
        const SizedBox(height: 6),
        const Text('Chức danh:'),
        _redField(_chucDanhCtrl, hint: 'Bác sĩ / Bác sĩ chuyên khoa...'),
        const SizedBox(height: 6),
        const Text('Khoa:'),
        _redField(_khoaCtrl, hint: 'Khoa Chấn thương chỉnh hình...'),
        const SizedBox(height: 6),
        const Text(
            'Được phân công thực hiện phẫu thuật/thủ thuật/gây mê cho người bệnh:'),
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
          spacing: 8,
          runSpacing: 4,
          children: options.map((o) {
            final k = o[0];
            final label = o[1];
            return SizedBox(
              width: (MediaQuery.of(context).size.width / 2) - 24,
              child: _checkBox(
                label,
                _gayMe.contains(k),
                (v) => setState(() {
                  if (v) {
                    _gayMe.add(k);
                  } else {
                    _gayMe.remove(k);
                  }
                }),
              ),
            );
          }).toList(),
        ),
        Row(
          children: [
            _checkBox('Khác (ghi rõ nếu có):', _gayMe.contains('KHAC'),
                (v) => setState(() {
                      if (v) {
                        _gayMe.add('KHAC');
                      } else {
                        _gayMe.remove('KHAC');
                      }
                    })),
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
        const Text(
            'Các phương pháp điều trị khác ngoài phẫu thuật/thủ thuật:',
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
        const Text(
            'Nguy cơ, tai biến trong và sau phẫu thuật/thủ thuật có thể xảy ra:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: options.map((o) {
            final k = o[0];
            final label = o[1];
            return SizedBox(
              width: (MediaQuery.of(context).size.width / 2) - 24,
              child: _checkBox(label, _nguyCo.contains(k), (v) {
                setState(() {
                  if (v) {
                    _nguyCo.add(k);
                  } else {
                    _nguyCo.remove(k);
                  }
                });
              }),
            );
          }).toList(),
        ),
        Row(
          children: [
            _checkBox('Nguy cơ/rủi ro khác:', _nguyCo.contains('KHAC'),
                (v) => setState(() {
                      if (v) {
                        _nguyCo.add('KHAC');
                      } else {
                        _nguyCo.remove('KHAC');
                      }
                    })),
            const SizedBox(width: 8),
            Expanded(child: _redField(_nguyCoKhacCtrl, hint: 'Nguy cơ khác...')),
          ],
        ),
      ],
    );
  }

  Widget _buildCamKetBS() {
    return const Text(
      'Chúng tôi đã dành đủ thời gian để người bệnh/thân nhân đặt các câu hỏi liên quan đến phẫu thuật/thủ thuật/gây mê sẽ được thực hiện hoặc các mối quan tâm khác và chúng tôi đã trả lời tất cả các câu hỏi đó.\n\nChúng tôi cam kết phục vụ người bệnh bằng lương tâm và trách nhiệm của người thầy thuốc cùng với tất cả kiến thức, sự hiểu biết về chuyên môn và phương tiện hiện có của BỆNH VIỆN ĐA KHOA NINH THUẬN để nỗ lực đem lại kết quả tốt nhất cho người bệnh.',
      style: TextStyle(fontSize: 12, height: 1.4),
    );
  }

  Widget _buildNguoiBenh() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Họ và tên người bệnh:'),
        _redField(_tenBenhNhanCtrl, hint: 'TÊN BỆNH NHÂN'),
        const SizedBox(height: 6),
        const Text('Họ và tên thân nhân:'),
        _redField(_tenThanNhanCtrl, hint: 'TÊN THÂN NHÂN'),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Năm sinh: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            SizedBox(
                width: 80,
                child: _redField(_namSinhThanNhanCtrl,
                    hint: 'YYYY', keyboardType: TextInputType.number)),
            const SizedBox(width: 16),
            const Text('Quan hệ với NB: ', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Expanded(child: _redField(_quanHeThanNhanCtrl, hint: 'Bố/Mẹ/Vợ/Chồng/Con...')),
          ],
        ),
      ],
    );
  }

  Widget _buildCamKetNB() {
    return const Text(
      'Tôi đã được nghe các Bác sỹ giải thích và đã trao đổi với các Bác sỹ về tất cả các thông tin của cuộc phẫu thuật/thủ thuật/gây mê, những nguy cơ thường gặp có thể xảy ra trong phẫu thuật/thủ thuật/gây mê như: ... và mức độ thành công. Tôi đã hiểu lý do phải thực hiện phẫu thuật/thủ thuật/gây mê và đồng ý để Bác sỹ phẫu thuật/thủ thuật/gây mê cho tôi/thân nhân của tôi.\n\n'
      'Tôi đã được tư vấn những thông tin về chi phí phẫu thuật/thủ thuật/gây mê, vật tư y tế tiêu hao dự kiến sử dụng trong cuộc phẫu thuật/thủ thuật/gây mê, tôi cam kết chi trả chi phí khám bệnh, chữa bệnh ngoài phạm vi được hưởng và mức hưởng theo quy định của pháp luật về bảo hiểm y tế và các quy định khác.\n\n'
      'Tôi đồng ý để các Bác sỹ thực hiện các phẫu thuật/thủ thuật/gây mê/kiểm tra/điều trị nếu việc đó là cần thiết để cứu tính mạng hoặc ngăn ngừa tác hại nghiêm trọng cho sức khỏe của tôi/thân nhân của tôi.\n\n'
      'Tôi hiểu rằng các Bác sỹ của BỆNH VIỆN ĐA KHOA NINH THUẬN sẽ làm hết lương tâm, trách nhiệm cùng với tất cả kiến thức, sự hiểu biết và phương tiện hiện có để nỗ lực đem lại kết quả tốt nhất cho tôi/thân nhân.',
      style: TextStyle(fontSize: 12, height: 1.4),
    );
  }

  Widget _buildSignature() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Chữ ký người bệnh/thân nhân:',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black54),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Signature(
            controller: _sigCtrl,
            backgroundColor: Colors.white,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _sigCtrl.clear()),
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Xóa chữ ký'),
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
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          Text(label, style: const TextStyle(fontSize: 13)),
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
  Future<void> _save({required bool uploadToEmr}) async {
    if (_tenBacSiCtrl.text.isEmpty) {
      _toast('Vui lòng nhập tên Bác sĩ');
      return;
    }
    if (_tenBenhNhanCtrl.text.isEmpty) {
      _toast('Vui lòng nhập tên Bệnh nhân');
      return;
    }
    setState(() => _saving = true);
    try {
      // 1. Render PDF
      final pdfBytes = await _buildPdf();
      // 2. Save local
      final path = await _savePdfLocal(pdfBytes);
      // 3. (Optional) Sync EMR
      String? emrResult;
      if (uploadToEmr) {
        emrResult = await _syncEmr(pdfBytes);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              uploadToEmr
                  ? (emrResult == null
                      ? '✅ Đã lưu PDF + upload EMR\n$path'
                      : '✅ Đã lưu PDF\n⚠️ EMR: $emrResult\n$path')
                  : '✅ Đã lưu PDF local\n$path'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'MỞ',
            onPressed: () => _openPdf(path),
          ),
        ),
      );
      if (uploadToEmr && emrResult == null) {
        // optional: pop after success
      }
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

  /// Render PDF giống Word doc (mẫu MS: 01/BV2)
  Future<Uint8List> _buildPdf() async {
    final hasSig = _sigCtrl.isNotEmpty;
    final sigBytes = hasSig ? await _sigCtrl.toPngBytes() : null;
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
          _pdfCamKet(),
          _pdfNguoiBenh(),
          _pdfCamKetNB(),
          if (hasSig && sigBytes != null) _pdfSignature(sigBytes),
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
              pw.Text('SỞ Y TẾ TỈNH KHÁNH HÒA',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('BỆNH VIỆN ĐA KHOA NINH THUẬN',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('Độc lập - Tự do - Hạnh phúc',
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10)),
              pw.Text('─────────────────', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfFormNumber() => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('MS: 01/BV2',
            style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10)),
      );

  pw.Widget _pdfTitle() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        child: pw.Center(
          child: pw.Text(
            'GIẤY CAM KẾT CHẤP THUẬN PHẪU THUẬT, THỦ THUẬT VÀ GÂY MÊ HỒI SỨC',
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red900),
          ),
        ),
      );

  pw.Widget _pdfMuc() {
    String label;
    if (_muc == 'CAP_CUU') {
      label = '☒ Cấp cứu    ☐ Bán cấp    ☐ Chương trình    ☐ Phiên';
    } else if (_muc == 'BAN_CAP') {
      label = '☐ Cấp cứu    ☒ Bán cấp    ☐ Chương trình    ☐ Phiên';
    } else if (_muc == 'CHUONG_TRINH') {
      label = '☐ Cấp cứu    ☐ Bán cấp    ☒ Chương trình    ☐ Phiên';
    } else if (_muc == 'PHIEN') {
      label = '☐ Cấp cứu    ☐ Bán cấp    ☐ Chương trình    ☒ Phiên';
    } else {
      label = '☐ Cấp cứu    ☐ Bán cấp    ☐ Chương trình    ☐ Phiên';
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
    );
  }

  pw.Widget _pdfBacSi() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('I. BÁC SỸ PHẪU THUẬT/THỦ THUẬT/GÂY MÊ HỒI SỨC:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),
          pw.Text('Chúng tôi có tên dưới đây cùng làm Bản cam kết như sau:',
              style: const pw.TextStyle(fontSize: 11)),
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
                style: const pw.TextStyle(fontSize: 11)),
            pw.Bullet(text: 'Chẩn đoán'),
            pw.Bullet(text: 'Lý do phẫu thuật/thủ thuật'),
            pw.Bullet(text: 'Rủi ro, nguy cơ nếu không thực hiện phẫu thuật/thủ thuật'),
            pw.Bullet(text: 'Kết quả sau phẫu thuật/thủ thuật (dự kiến)'),
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
          pw.Text('Phương pháp phẫu thuật/thủ thuật dự kiến:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 2),
          pw.Text(
              '${m == 'MO' ? '☒' : '☐'} Phẫu thuật mở    ${m == 'NOI_SOI' ? '☒' : '☐'} Phẫu thuật nội soi    ${m == 'THU_THUAT' ? '☒' : '☐'} Thủ thuật',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
              '${m == 'KHAC' ? '☒' : '☐'} Khác (ghi rõ nếu có): ${_phuongPhapKhacCtrl.text}',
              style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _pdfPhuongPhapGayMe() {
    String row(int i) {
      const labels = [
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
      String pair(List<String> o) => '${_gayMe.contains(o[0]) ? '☒' : '☐'} ${o[1]}';
      return b == null ? pair(a) : '${pair(a)}    ${pair(b)}';
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Phương pháp gây mê hồi sức dự kiến:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 2),
          pw.Text(row(0), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(row(1), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(row(2), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(row(3), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
              '${_gayMe.contains('KHAC') ? '☒' : '☐'} Khác (ghi rõ nếu có): ${_gayMeKhacCtrl.text}',
              style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _pdfDieuTriKhac() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Các phương pháp điều trị khác ngoài phẫu thuật/thủ thuật:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.SizedBox(height: 2),
            pw.Text(
                '${_dieuTriKhac == 'KHONG' ? '☒' : '☐'} Không    ${_dieuTriKhac == 'CO' ? '☒' : '☐'} Có, cụ thể: ${_dieuTriKhacCtrl.text}',
                style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      );

  pw.Widget _pdfNguyCo() {
    const labels = [
      ['PHAN_UNG_THUOC', 'Phản ứng thuốc'],
      ['NHIEM_TRUNG', 'Nhiễm trùng'],
      ['SUY_HO_HAP_TUAN_HOAN', 'Suy hô hấp - tuần hoàn'],
      ['TU_VONG', 'Tử vong'],
      ['CHAY_MAU', 'Chảy máu'],
    ];
    String row(int i) {
      final a = labels[i * 2];
      final b = (i * 2 + 1 < labels.length) ? labels[i * 2 + 1] : null;
      String pair(List<String> o) => '${_nguyCo.contains(o[0]) ? '☒' : '☐'} ${o[1]}';
      return b == null ? pair(a) : '${pair(a)}    ${pair(b)}';
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
              'Nguy cơ, tai biến trong và sau phẫu thuật/thủ thuật có thể xảy ra:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 2),
          pw.Text(row(0), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(row(1), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(row(2), style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
              '${_nguyCo.contains('KHAC') ? '☒' : '☐'} Nguy cơ/rủi ro khác: ${_nguyCoKhacCtrl.text}',
              style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _pdfCamKet() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(
          'Chúng tôi đã dành đủ thời gian để người bệnh/thân nhân đặt các câu hỏi liên quan đến phẫu thuật/thủ thuật/gây mê sẽ được thực hiện hoặc các mối quan tâm khác và chúng tôi đã trả lời tất cả các câu hỏi đó.\n\nChúng tôi cam kết phục vụ người bệnh bằng lương tâm và trách nhiệm của người thầy thuốc cùng với tất cả kiến thức, sự hiểu biết về chuyên môn và phương tiện hiện có của BỆNH VIỆN ĐA KHOA NINH THUẬN để nỗ lực đem lại kết quả tốt nhất cho người bệnh.',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.3),
        ),
      );

  pw.Widget _pdfNguoiBenh() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 6),
          pw.Text('II. NGƯỜI BỆNH/THÂN NHÂN:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),
          _pdfKv('Họ và tên người bệnh:', _tenBenhNhanCtrl.text),
          _pdfKv('Họ và tên thân nhân:', _tenThanNhanCtrl.text),
          _pdfKv('Năm sinh:', _namSinhThanNhanCtrl.text),
          _pdfKv('Quan hệ với người bệnh:', _quanHeThanNhanCtrl.text),
        ],
      );

  pw.Widget _pdfCamKetNB() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(
          'Tôi đã được nghe các Bác sỹ giải thích và đã trao đổi với các Bác sỹ về tất cả các thông tin của cuộc phẫu thuật/thủ thuật/gây mê, những nguy cơ thường gặp có thể xảy ra trong phẫu thuật/thủ thuật/gây mê và mức độ thành công. Tôi đã hiểu lý do phải thực hiện phẫu thuật/thủ thuật/gây mê và đồng ý để Bác sỹ phẫu thuật/thủ thuật/gây mê cho tôi/thân nhân của tôi.\n\n'
          'Tôi đã được tư vấn những thông tin về chi phí phẫu thuật/thủ thuật/gây mê, vật tư y tế tiêu hao dự kiến sử dụng trong cuộc phẫu thuật/thủ thuật/gây mê, tôi cam kết chi trả chi phí khám bệnh, chữa bệnh ngoài phạm vi được hưởng và mức hưởng theo quy định của pháp luật về bảo hiểm y tế và các quy định khác.\n\n'
          'Tôi đồng ý để các Bác sỹ thực hiện các phẫu thuật/thủ thuật/gây mê/kiểm tra/điều trị nếu việc đó là cần thiết để cứu tính mạng hoặc ngăn ngừa tác hại nghiêm trọng cho sức khỏe của tôi/thân nhân của tôi.\n\n'
          'Tôi hiểu rằng các Bác sỹ của BỆNH VIỆN ĐA KHOA NINH THUẬN sẽ làm hết lương tâm, trách nhiệm cùng với tất cả kiến thức, sự hiểu biết và phương tiện hiện có để nỗ lực đem lại kết quả tốt nhất cho tôi/thân nhân.',
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.3),
        ),
      );

  pw.Widget _pdfSignature(Uint8List sigBytes) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Chữ ký người bệnh/thân nhân:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 120,
            alignment: pw.Alignment.centerLeft,
            child: pw.Image(pw.MemoryImage(sigBytes), height: 120, fit: pw.BoxFit.contain),
          ),
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
          pw.SizedBox(
            width: 150,
            child: pw.Text('$key ', style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Expanded(
            child: pw.Text(value.isEmpty ? '(...)' : value,
                style: pw.TextStyle(
                    fontSize: 11,
                    color: value.isEmpty ? PdfColors.grey : PdfColors.red900,
                    fontWeight: value.isEmpty ? pw.FontWeight.normal : pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Save PDF to local file. Return path.
  /// - Tries to save into Download/HisMobile/ (scoped MediaStore via MainActivity if SDK>=29)
  /// - Falls back to app docs dir
  Future<String> _savePdfLocal(Uint8List pdfBytes) async {
    final treatmentCode = (widget.patient['TDL_TREATMENT_CODE'] ??
            widget.patient['treatment_code'] ??
            'BN')
        .toString();
    final fileName =
        'PhieuPhauThuat_${treatmentCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    // Save to app docs dir (always works)
    final dir = await getApplicationDocumentsDirectory();
    final hisDir = Directory(pathJoin.join(dir.path, 'HisMobile'));
    if (!await hisDir.exists()) {
      await hisDir.create(recursive: true);
    }
    final file = File(pathJoin.join(hisDir.path, fileName));
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// v3.0.131: Sync EMR với placeholder endpoint.
  /// TODO: Khi có endpoint EMR, paste URL + auth vào đây.
  /// Hiện tại chỉ return null (success - không làm gì).
  Future<String?> _syncEmr(Uint8List pdfBytes) async {
    const String emrEndpoint = ''; // TODO: paste EMR endpoint URL
    if (emrEndpoint.isEmpty) {
      // Placeholder mode - chỉ log, không thật sự upload
      debugPrint('EMR sync placeholder: ${pdfBytes.length} bytes (no endpoint configured)');
      return null;
    }
    try {
      // TODO: Implement thật khi có endpoint
      // final req = http.MultipartRequest('POST', Uri.parse(emrEndpoint));
      // req.files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: 'phieu_phau_thuat.pdf'));
      // final resp = await req.send().timeout(Duration(seconds: 30));
      // if (resp.statusCode != 200) return 'HTTP ${resp.statusCode}';
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _openPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    await Printing.sharePdf(bytes: bytes, filename: path.split(Platform.pathSeparator).last);
  }
}
