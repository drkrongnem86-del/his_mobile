// Màn hình XEM BỆNH ÁN - tabbed view cho 1 BN:
// - Hồ sơ: thông tin hành chính + ICD chính từ Thongke
// - Sinh hiệu: tất cả vital signs đã ghi (biểu đồ text + table)
// - Tờ điều trị: tất cả treatment_sheet
// - Cận lâm sàng: tất cả paraclinical
// - Bàn giao: tất cả handoff
// - Phiếu chăm sóc: tất cả care_sheet
// - Phiếu truyền dịch: tất cả infusion
// - Chẩn đoán ICD: tổng hợp ICD codes từ tất cả phiếu
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:his_mobile/data/local/clinical_notes_service.dart';
import 'package:his_mobile/data/local/icd10_library.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/presentation/widgets/patient_header.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class ViewMedicalRecordScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;
  final String username;

  const ViewMedicalRecordScreen({
    super.key,
    required this.patient,
    required this.department,
    required this.username,
  });

  @override
  State<ViewMedicalRecordScreen> createState() => _ViewMedicalRecordScreenState();
}

class _ViewMedicalRecordScreenState extends State<ViewMedicalRecordScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _notes = ClinicalNotesService.instance;
  String? _patientCode;
  List<ClinicalNote> _allNotes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 8, vsync: this);
    _patientCode = _getPatientCode();
    _load();
  }

  String _getPatientCode() {
    final p = widget.patient;
    return (p['TDL_TREATMENT_CODE'] ?? p['treatment_code'] ?? p['TDL_PATIENT_CODE'] ?? p['tdl_patient_code'] ?? '').toString();
  }

  String _g(String k1, [String? k2, String? k3]) =>
      (widget.patient[k1] ?? widget.patient[k2 ?? ''] ?? widget.patient[k3 ?? ''] ?? '').toString();

  Future<void> _load() async {
    final list = await _notes.getNotesForPatient(widget.username, _patientCode ?? '');
    if (mounted) setState(() {
      _allNotes = list;
      _loading = false;
    });
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  /// Render 1 note (nhỏ gọn)
  Widget _noteCard(ClinicalNote n) {
    final accent = Color(n.type.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                child: Text(n.type.icon, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(n.type.label,
                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              Text(_formatTime(n.createdAt), style: const TextStyle(color: Colors.black54, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 6),
          ...n.data.entries.where((e) => e.value.toString().isNotEmpty).map((e) {
            final v = e.value;
            if (v is List && v.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text('${_humanKey(e.key)}:',
                        style: const TextStyle(color: Colors.black54, fontSize: 11)),
                  ),
                  Expanded(
                    child: v is List
                        ? Wrap(
                            spacing: 4, runSpacing: 2,
                            children: v.map<Widget>((item) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(3)),
                              child: Text(item.toString(), style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                            )).toList(),
                          )
                        : Text(v.toString(), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            );
          }),
          if (n.note.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
              child: Row(
                children: [
                  const Icon(Icons.sticky_note_2, size: 11, color: Colors.amber),
                  const SizedBox(width: 4),
                  Expanded(child: Text(n.note, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Chuyển key data sang label tiếng Việt
  String _humanKey(String key) {
    const map = {
      'mach': 'Mạch', 'huyetap_tamthu': 'HA tâm thu', 'huyetap_tamtruong': 'HA tâm trương',
      'nhietdo': 'Nhiệt độ', 'spo2': 'SpO2', 'nhiptho': 'Nhịp thở',
      'glucose': 'Đường huyết', 'mucdodau': 'VAS', 'glassgow': 'GCS',
      'ghichusinhieu': 'Ghi chú', 'thoigian': 'Thời điểm',
      'tenthuoc': 'Tên thuốc', 'soluong': 'Số lượng', 'donvi': 'Đơn vị',
      'lieu': 'Liều', 'duongdung': 'Đường dùng', 'cachdung': 'Cách dùng',
      'songay': 'Số ngày', 'ghichuthuoc': 'Ghi chú thuốc', 'tuvanthuoc': 'Tư vấn',
      'tomtat': 'Tóm tắt', 'chandoan': 'Chẩn đoán', 'huongdieutri': 'Hướng điều trị',
      'loai': 'Loại', 'icd': 'ICD', 'ngay': 'Ngày', 'dienbien': 'Diễn biến',
      'huongdtmoi': 'Hướng mới', 'chiso': 'Chỉ số', 'ketqua': 'Kết quả',
      'tomtattiep': 'Tóm tắt', 'huongtuvan': 'Hướng dẫn',
      'loaixn': 'Loại XN', 'chiso_can': 'Chỉ số cần', 'lydo_xn': 'Lý do XN',
      'mauchandoan': 'Mã ICD', 'vitri': 'Vị trí', 'loaikq': 'Loại kết quả',
      'ketqua_cls': 'Kết quả CLS', 'ketluan': 'Kết luận', 'loaipt': 'Phân loại',
      'tenpt': 'Tên PT/TT', 'ghichupreop': 'Trước mổ',
      'vesinh': 'Vệ sinh', 'an': 'ẻ', 'tiuthai': 'Tiểu tiện', 'tu_the': 'Tư thế',
      'chong_loet': 'Chống loét', 'ghichucs': 'Ghi chú CS',
      'hinhthuc': 'Hình thức ăn', 'chedo': 'Chế độ', 'calorie': 'Calorie',
      'protein': 'Protein', 'ghichudd': 'Ghi chú DD',
      'catruoc': 'Ca trước', 'casau': 'Ca sau', 'tinhtrang': 'Tình trạng',
      'vieccantheodoi': 'Việc cần theo dõi', 'canhbao': 'Cảnh báo',
      'chandoanht': 'Chẩn đoán chính', 'loaibg': 'Loại BG', 'nguoinhan': 'Người nhận',
      'tomtat_benh': 'Tóm tắt bệnh', 'dien_bien': 'Diễn biến', 'huongtiep': 'Hướng tiếp',
      'thuoc_dang_sd': 'Thuốc đang SD',
      'lydokham': 'Lý do khám', 'tiensu': 'Tiền sử', 'kham': 'Khám',
      'chandoanso': 'Chẩn đoán sơ bộ', 'loaihc': 'Loại HC',
      'thanhphan': 'Thành phần', 'ykien': 'Ý kiến',
      'loaidich': 'Loại dịch', 'thetich': 'Thể tích', 'tocdo': 'Tốc độ',
      'thoigianbatdau': 'Bắt đầu', 'ghichutruyen': 'Ghi chú truyền',
      'tenvt': 'Tên VT', 'lydo_vt': 'Lý do VT',
      'lieu_don': 'Liều mỗi lần', 'thoigian_dung': 'Thời gian dùng', 'ketqua_dung': 'Kết quả',
      'nguoi_thuchien': 'Người thực hiện', 'ghichu_mar': 'Ghi chú',
      'loai_barcode': 'Loại barcode', 'ma_barcode': 'Mã', 'ket_qua': 'Kết quả',
      'nguoi_quet': 'Người quét', 'ghichu_quet': 'Ghi chú quét',
      'thoigian_dibuong': 'Thời điểm', 'tri_giac': 'Tri giác',
      'tinh_trang': 'Tình trạng', 'kham_xet': 'Khám phát hiện',
      'y_lenh_moi': 'Y lệnh mới', 'ket_luan': 'Kết luận',
      'kiemtra_bn': 'BN kiểm tra', 'van_de': 'Vấn đề', 'xuly': 'Xử lý',
      'dd_phutrach': 'ĐD phụ trách',
      'ma_pt': 'Mã PT', 'loai_pt': 'Loại PT', 'ngay_pt': 'Ngày PT',
      'gay_me': 'Gây mê', 'sinh_hieu_15p': 'SH 15p', 'sinh_hieu_1h': 'SH 1h',
      'sinh_hieu_2h': 'SH 2h', 'sinh_hieu_6h': 'SH 6h', 'dan_luu': 'Dẫn lưu',
      'bien_chung': 'Biến chứng', 'ghi_chu_pt': 'Ghi chú',
      'cong_cu': 'Công cụ', 'can_nang': 'Cân nặng', 'chieu_cao': 'Chiều cao',
      'bmi': 'BMI', 'sut_can': 'Sụt cân', 'an_kem_2t': 'ẻ kém 2t',
      'benh_nang': 'Bệnh nặng', 'ket_qua_sdd': 'Kết quả SDD',
      'albumin': 'Albumin', 'prealbumin': 'Prealbumin', 'lympho': 'Lympho',
      'hemoglobin': 'Hb', 'transferrin': 'Transferrin', 'nuoc_tieu': 'Nitơ Ure 24h',
      'danh_gia': 'Đánh giá', 'kehoach_dd': 'Kế hoạch DD',
      'tong_calo_tuan': 'Calo/tuần', 'tong_protein_tuan': 'Protein/tuần', 'danh_gia_tuan': 'Đánh giá tuần',
      'loai_di_ung': 'Loại dị ứng', 'ten_chat': 'Tên chất', 'phan_ung': 'Phản ứng',
      'muc_do': 'Mức độ', 'ngay_phat_hien': 'Ngày phát hiện',
      'nguon_thong_tin': 'Nguồn', 'ghichu_di_ung': 'Ghi chú',
      'so_ylenh': 'Số y lệnh', 'loai_ylenh': 'Loại y lệnh',
      'noidung_ylenh': 'Nội dung y lệnh', 'ketqua_thuchien': 'Kết quả thực hiện',
      'ghichu_thuchien': 'Ghi chú thực hiện',
    };
    return map[key] ?? key;
  }

  Widget _emptyTab(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.black26),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('Hãy ghi phiếu mới ở menu thao tác BN',
              style: TextStyle(color: Colors.black45, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _listTab(ClinicalNoteType type, IconData icon, Color color, String emptyMsg) {
    final notes = _allNotes.where((n) => n.type == type).toList();
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (notes.isEmpty) {
      return _emptyTab(emptyMsg);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
        itemCount: notes.length,
        itemBuilder: (_, i) => _noteCard(notes[i]),
      ),
    );
  }

  /// Tab hồ sơ: thông tin hành chính + ICD chính từ Thongke + ICD tổng hợp từ notes
  Widget _tabHoSo() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = widget.patient;
    final icdChinh = _g('ICD_CODE', 'icd_code', 'ICD_NAME');
    final icdName = _g('ICD_NAME', 'icd_name');
    final benhChinh = _g('TDL_HEIN_CARD_NUMBER'); // not real - check
    final icdFromNotes = <String, int>{};
    for (final n in _allNotes) {
      for (final v in n.data.values) {
        if (v is String && RegExp(r'^[A-Z]\d{2}(\.\d{1,2})?$').hasMatch(v.trim())) {
          final code = v.trim();
          icdFromNotes[code] = (icdFromNotes[code] ?? 0) + 1;
        }
      }
    }
    final icdSorted = icdFromNotes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thông tin hành chính
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, color: Colors.indigo.shade700, size: 18),
                    const SizedBox(width: 6),
                    const Text('HỒ SƠ HÀNH CHÍNH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.indigo)),
                  ],
                ),
                const Divider(height: 12),
                _infoRow('Họ tên:', _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_NAME')),
                _infoRow('Mã BN:', _g('TDL_PATIENT_CODE', 'tdl_patient_code')),
                _infoRow('Mã ĐT:', _g('TDL_TREATMENT_CODE', 'treatment_code')),
                _infoRow('Ngày sinh:', _g('TDL_PATIENT_DOB', 'tdl_patient_dob')),
                _infoRow('Giới tính:', _g('TDL_PATIENT_GENDER_NAME', 'tdl_patient_gender')),
                _infoRow('SĐT:', _g('TDL_PATIENT_PHONE', 'tdl_patient_phone')),
                _infoRow('SĐT người nhà:', _g('TDL_PATIENT_RELATIVE_MOBILE', 'tdl_patient_relative_mobile')),
                _infoRow('BHYT:', _g('TDL_HEIN_CARD_NUMBER', 'tdl_hein_card_number')),
                _infoRow('Địa chỉ:', _g('TDL_PATIENT_ADDRESS', 'tdl_patient_address')),
                _infoRow('Khoa đang điều trị:', _g('DEPARTMENT_NAME', 'department_name')),
                _infoRow('Loại ĐT:', _g('PATIENT_TYPE_NAME', 'patient_type_name')),
                _infoRow('Hình thức ĐT:', _g('TREATMENT_TYPE_NAME', 'treatment_type_name')),
                _infoRow('Ngày vào viện:', _g('IN_TIME', 'in_time')),
                _infoRow('Ngày ra viện:', _g('OUT_TIME', 'out_time')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ICD chính từ Thongke
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.healing, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 6),
                    const Text('CHẨN ĐOÁN ICD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.red)),
                  ],
                ),
                const Divider(height: 12),
                if (icdChinh.isNotEmpty || icdName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 80, child: Text('ICD chính:', style: TextStyle(color: Colors.black54, fontSize: 12))),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (icdChinh.isNotEmpty)
                                  Text(icdChinh, style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
                                if (icdName.isNotEmpty)
                                  Text(icdName, style: const TextStyle(color: Colors.black87, fontSize: 12, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (icdSorted.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 4),
                    child: Text('📊 ICD đã ghi trong các phiếu:', style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold)),
                  ),
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: icdSorted.map((e) {
                      final entry = Icd10Library.common.firstWhere(
                          (c) => c.code == e.key,
                          orElse: () => Icd10Entry(e.key, 'Không rõ'));
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(entry.code, style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Text('×${e.value}', style: const TextStyle(fontSize: 9, color: Colors.red)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (icdChinh.isEmpty && icdName.isEmpty && icdSorted.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    child: const Text('Chưa có ICD. Hãy nhập Mã ICD ở phiếu khám / tờ điều trị.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tổng số phiếu đã ghi
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.assignment_turned_in, color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 6),
                    const Text('THỐNG KÊ PHIẾU ĐÃ GHI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.green)),
                  ],
                ),
                const Divider(height: 12),
                for (final type in ClinicalNoteType.values)
                  () {
                    final cnt = _allNotes.where((n) => n.type == type).length;
                    if (cnt == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          Text(type.icon, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(type.label, style: const TextStyle(color: Colors.black87, fontSize: 12))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: Color(type.colorValue), borderRadius: BorderRadius.circular(8)),
                            child: Text('$cnt', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  }(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(color: value.isEmpty ? Colors.black26 : Colors.black, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vitalSignsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final notes = _allNotes.where((n) => n.type == ClinicalNoteType.vitalSigns).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (notes.isEmpty) {
      return _emptyTab('Chưa ghi sinh hiệu nào');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: notes.length + 1,
      itemBuilder: (ctx, i) {
        if (i == notes.length) return const SizedBox(height: 16);
        final n = notes[i];
        final d = n.data;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(4)),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  Text(_formatTime(n.createdAt), style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(n.createdBy, style: const TextStyle(color: Colors.indigo, fontSize: 10)),
                ],
              ),
              const Divider(height: 8),
              Wrap(
                spacing: 8, runSpacing: 6,
                children: [
                  _vitalChip('🩸 Mạch', d['mach']?.toString() ?? '—', 'lần/ph'),
                  _vitalChip('💉 HA', '${d['huyetap_tamthu']?.toString() ?? '—'}/${d['huyetap_tamtruong']?.toString() ?? '—'}', 'mmHg'),
                  _vitalChip('🌡 NĐ', d['nhietdo']?.toString() ?? '—', '°C'),
                  _vitalChip('💨 SpO2', d['spo2']?.toString() ?? '—', '%'),
                  _vitalChip('🫁 NT', d['nhiptho']?.toString() ?? '—', 'lần/ph'),
                  if (d['glucose']?.toString().isNotEmpty == true) _vitalChip('🩸 Glucose', d['glucose'].toString(), 'mg/dL'),
                  if (d['mucdodau']?.toString().isNotEmpty == true) _vitalChip('😣 VAS', d['mucdodau'].toString(), '/10'),
                  if (d['glassgow']?.toString().isNotEmpty == true) _vitalChip('🧠 GCS', d['glassgow'].toString(), '/15'),
                ],
              ),
              if (d['ghichusinhieu']?.toString().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('📝 ${d['ghichusinhieu']}', style: const TextStyle(color: Colors.black54, fontSize: 11, fontStyle: FontStyle.italic)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _vitalChip(String name, String value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$name ', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFFE53935), fontWeight: FontWeight.bold)),
          Text(' $unit', style: const TextStyle(fontSize: 9, color: Colors.black45)),
        ],
      ),
    );
  }

  Widget _icdTab() {
    final allCodes = <String>{};
    for (final n in _allNotes) {
      for (final v in n.data.values) {
        final s = v.toString().trim();
        if (RegExp(r'^[A-Z]\d{2}(\.\d{1,2})?$').hasMatch(s)) {
          allCodes.add(s);
        }
      }
    }
    final codesFromMain = _g('ICD_CODE', 'icd_code').trim();
    if (RegExp(r'^[A-Z]\d{2}(\.\d{1,2})?$').hasMatch(codesFromMain)) {
      allCodes.add(codesFromMain);
    }
    if (allCodes.isEmpty) {
      return _emptyTab('Chưa có ICD code nào. Hãy thêm Mã ICD khi ghi tờ điều trị / phiếu khám.');
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: allCodes.map((code) {
        final entry = Icd10Library.common.firstWhere((c) => c.code == code,
            orElse: () => Icd10Entry(code, 'Không có trong danh mục'));
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: Text(entry.code, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.nameVi, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(entry.category, style: const TextStyle(color: Colors.black54, fontSize: 11)),
                    if (entry.nameEn != null)
                      Text(entry.nameEn!, style: const TextStyle(color: Colors.black45, fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.content_copy, size: 16, color: Colors.indigo),
                tooltip: 'Copy',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã copy ${entry.code}')));
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Xem bệnh án', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Làm mới'),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Hồ sơ'),
            Tab(text: 'Sinh hiệu'),
            Tab(text: 'Tờ ĐT'),
            Tab(text: 'CLS'),
            Tab(text: 'Bàn giao'),
            Tab(text: 'CS'),
            Tab(text: 'Dịch truyền'),
            Tab(text: 'ICD'),
          ],
        ),
      ),
      body: Column(
        children: [
          // User đăng nhập - tên cố định trên nền
          UserHeader.fromAuth(department: widget.department['name']?.toString()),
          PatientHeader(patient: widget.patient, department: widget.department, accent: const Color(0xFF1565C0)),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _tabHoSo(),
                _vitalSignsTab(),
                _listTab(ClinicalNoteType.treatmentSheet, Icons.note_add, Colors.blue, 'Chưa có tờ điều trị nào'),
                _listTab(ClinicalNoteType.paraclinical, Icons.science, Colors.purple, 'Chưa có phiếu CLS nào'),
                _listTab(ClinicalNoteType.handoff, Icons.swap_horiz, Colors.indigo, 'Chưa có phiếu bàn giao nào'),
                _listTab(ClinicalNoteType.careSheet, Icons.health_and_safety, Colors.pink, 'Chưa có phiếu chăm sóc nào'),
                _listTab(ClinicalNoteType.infusion, Icons.water_drop, Colors.lightBlue, 'Chưa có phiếu truyền dịch nào'),
                _icdTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
