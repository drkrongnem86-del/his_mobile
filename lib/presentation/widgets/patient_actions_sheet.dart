// PatientActionsSheet v3.0.32 - SIMPLIFIED UI (theo yêu cầu BS 16/07/2026)
// CHỈ GIỮ 2 SECTION:
//   1. Xem bệnh án (PDF thật từ Data/EMR)
//   2. Y tế số (Bộ Y tế) - 15 chức năng copy từ app com.snd.adbc v1.0.44
// BỎ hết: Lập phiếu, Tạo phiếu khám, Phiếu đã lưu, Thao tác nhanh 16 chức năng,
//         Chuyển khoa, Xuất viện, Tiện ích (4 grid)
// Mục đích: 15 chức năng Y tế số đã cover TẤT CẢ nhu cầu tạo phiếu
//
// v3.0.75: Thêm tile "Mở trên EMR web" - VPN detect:
//   - VPN ON  → http://172.16.9.6/emr/treatment-detail?code={code}
//   - VPN OFF → http://thongke.benhvienninhthuan.vn:8080/emr/index/search?treatment_code={code}
// v3.0.78: Thêm tile "Lịch sử điều trị" - mở TreatmentHistoryScreen
//   - Gọi 5 API HIS Pro: HisTreatment/GetLView, HisDepartmentTran/GetView, HisServiceReq/Get,
//     HisSereServ/GetDHisSereServ2, HisServiceReq/GetDynamic
//   - Cần HIS Pro token (Settings → EMR Sync nếu thiếu/hết hạn)
// v3.0.79: Thêm tile "Đính kèm tài liệu" - mở AttachDocumentScreen
//   - Gọi api/EmrDocument/CreateWithFile (port 1417) để upload ảnh/file lên EMR BN
//   - Workflow giống HIS desktop "Chi tiết BA → Đính kèm" (theo note2.docx)
import 'package:flutter/material.dart';
import 'package:his_mobile/data/models/y_te_so_feature.dart';
import 'package:his_mobile/data/models/y_te_so_router.dart';
import 'package:his_mobile/presentation/screens/attach_document_screen.dart';
import 'package:his_mobile/presentation/screens/treatment_history_screen.dart';
// v3.0.90: BỎ import y_te_screen.dart - menu Chức năng Y tế đã xóa
import 'package:his_mobile/presentation/screens/y_te_so_screen.dart';
import 'package:his_mobile/presentation/screens/xem_benh_an_screen.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class PatientActionsSheet extends StatelessWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> department;

  const PatientActionsSheet({
    super.key,
    required this.patient,
    required this.department,
  });

  String _g(String k1, [String? k2, String? k3]) => (patient[k1] ??
          patient[k2 ?? ''] ??
          patient[k3 ?? ''] ??
          '')
      .toString();

  String get _patientCode => _g('TDL_PATIENT_CODE', 'tdl_patient_code', 'PATIENT_CODE');
  String get _patientName => _g('TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME', 'TDL_PATIENT_UNSIGNED_NAME');
  String get _treatmentCode => _g('TDL_TREATMENT_CODE', 'treatment_code');

  void _openXemBenhAn(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => XemBenhAnScreen(patient: patient),
    ));
  }

  /// v3.0.78: Mở màn hình Lịch sử điều trị (3-pane: list lần khám → khoa → DV/thuốc)
  void _openLichSuDieuTri(BuildContext context) {
    if (_patientCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BN chưa có mã (TDL_PATIENT_CODE)')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TreatmentHistoryScreen(patient: patient),
    ));
  }

  /// v3.0.79: Mở màn hình Đính kèm tài liệu (ảnh/file → EMR BN)
  /// Yêu cầu: treatment_code (mã điều trị), HIS Pro token (EMR port 1417)
  void _openDinhKemTaiLieu(BuildContext context) {
    if (_treatmentCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BN chưa có mã điều trị - không thể đính kèm')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AttachDocumentScreen(patient: patient),
    ));
  }

  /// v3.0.75: Mở EMR trên web/browser
  /// - VPN ON  → LAN EMR (172.16.9.6)
  /// v3.0.83: Mở Y Tế Số (Bộ Y tế) - tích hợp native, không cần VPN
  /// API: http://113.163.187.3:3000 (public) - 50+ endpoints đã khám phá
  Future<void> _openYTeSo(BuildContext context) async {
    if (_treatmentCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BN chưa có mã điều trị')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => YTeSoScreen(
        treatmentCode: _treatmentCode,
        patientName: _patientName,
        patientCode: _patientCode,
      ),
    ));
  }

  // v3.0.90: BỎ _openYTe - đã xóa menu "Chức năng Y tế" (theo yêu cầu user)

  @override
  Widget build(BuildContext context) {
    final name = _patientName;
    final nameDisplay = name.isEmpty ? 'BN' : name;
    final code = _patientCode;
    final reqCode = _treatmentCode;
    final icd = _g('ICD_NAME', 'icd_name');
    final deptName = department['name']?.toString() ?? '';
    final deptCode = department['code']?.toString() ?? '';
    final hasServerData = reqCode.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,  // Full-screen ngay (chỉ có 2 section)
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          color: Colors.white,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              UserHeader.fromAuth(department: deptName),

              // === HEADER BN ===
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                        child: const Text('ĐANG THAO TÁC',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${department['icon'] ?? '🏥'}  $deptName',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                            overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 22),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white54, width: 2)),
                        child: Center(child: Text(nameDisplay[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nameDisplay,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.15),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          if (code.isNotEmpty)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                              child: Text('Mã: $code', style: const TextStyle(color: Colors.white, fontSize: 10))),
                          if (reqCode.isNotEmpty)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                              child: Text('ĐT: $reqCode', style: const TextStyle(color: Colors.white, fontSize: 10))),
                          if (deptCode.isNotEmpty)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                              child: Text(deptCode, style: const TextStyle(color: Colors.white, fontSize: 10))),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasServerData ? const Color(0xFF1B5E20) : const Color(0xFFFF8F00),
                              borderRadius: BorderRadius.circular(6)),
                            child: Text(hasServerData ? '☁ Server' : '⚠ Mẫu',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                        ]),
                        if (icd.isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 6),
                            child: Text('ICD: $icd', style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ])),
                    ]),
                  ],
                ),
              ),

              // === TILE 1: XEM BỆNH ÁN (big) ===
              _sectionHeader('XEM BỆNH ÁN', Icons.folder_open, const Color(0xFFAD1457), 'PDF thật'),
              _bigTile(
                context: context,
                title: 'Xem bệnh án',
                subtitle: 'Phiếu đã ký trên Data public / HIS Pro — Zoom, pan, tải xuống, in, chia sẻ',
                icon: Icons.picture_as_pdf,
                color1: const Color(0xFFAD1457), color2: const Color(0xFF6A1B9A),
                onTap: () => _openXemBenhAn(context),
                chips: const ['📄 Đã ký', '🔍 Zoom', '⬇ Tải về', '🖨 In'],
              ),

              // v3.0.83: TILE 1b: Y tế số (Bộ Y tế) - 50+ API native
              // Thay thế "Mở trên EMR web" cũ. Dùng Y Tế Số public API (113.163.187.3:3000)
              _yTeSoTile(context),

              // v3.0.90: BỎ TILE 1b2 "Chức năng Y tế (Bộ Y tế) - menu 6 mục" theo yêu cầu user
              // (sau này tính sau)

              // v3.0.78: TILE 1c: Lịch sử điều trị (HIS Pro, 3-pane)
              _lichSuDieuTriTile(context),

              // v3.0.79: TILE 1d: Đính kèm tài liệu (EMR upload)
              _dinhKemTaiLieuTile(context),

              // === GRID TILE: Y TẾ SỐ (Bộ Y tế) - 15 chức năng ===
              _sectionHeader('Y TẾ SỐ (BỘ Y TẾ)', Icons.health_and_safety, const Color(0xFF00838F), '15 chức năng'),
              _buildYTeSoGrid(context),

              // Footer
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBBDEFB)),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 14, color: Color(0xFF1565C0)),
                    SizedBox(width: 6),
                    Expanded(child: Text(
                      '15 chức năng Y tế số (Bộ Y tế) cover tất cả: tạo phiếu khám, lập phiếu chăm sóc, theo dõi sinh hiệu, bàn giao, hội chẩn, CLS, đơn thuốc... Mỗi chức năng có nút Lưu/Lưu ký/Ký VNPT thống nhất qua PhieuSaveService.',
                      style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.4),
                    )),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color, String badge) {
    return Container(
      color: const Color(0xFFF6F8FB),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(badge, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _bigTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color1,
    required Color color2,
    required VoidCallback onTap,
    required List<String> chips,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color1, width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: color1, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11, height: 1.3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 2, children: [
                for (final c in chips) _miniChip(c, color1),
              ]),
            ])),
            Icon(Icons.chevron_right, color: color1.withOpacity(0.5), size: 22),
          ]),
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }

  /// v3.0.83: Tile Y tế số (Bộ Y tế) - native, thay thế "Mở trên EMR web"
  /// Tích hợp trực tiếp Y Tế Số public API (113.163.187.3:3000)
  /// 50+ endpoints: xem bệnh án, y lệnh, điều dưỡng, phiếu bàn giao, ...
  /// Không cần VPN, không cần HIS Pro token, dùng chung tài khoản thongke
  Widget _yTeSoTile(BuildContext context) {
    final color1 = const Color(0xFF00838F);
    final color2 = const Color(0xFF006064);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: InkWell(
        onTap: () => _openYTeSo(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color1, width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.health_and_safety, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('Y tế số - Xem bệnh án',
                    style: TextStyle(color: color1, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color1.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Bộ Y tế • 50+ API',
                    style: TextStyle(color: Color(0xFF00838F), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 2),
              const Text(
                'List tài liệu theo nhóm, xem PDF/ảnh native, không cần VPN • dùng chung tk thongke',
                style: TextStyle(color: Colors.black54, fontSize: 11, height: 1.3),
              ),
            ])),
            Icon(Icons.chevron_right, color: color1.withOpacity(0.5), size: 20),
          ]),
        ),
      ),
    );
  }

  // v3.0.90: BỎ _yTeTile - "Chức năng Y tế" menu (theo yêu cầu user, sẽ tính sau)

  /// v3.0.78: Tile Lịch sử điều trị — mở TreatmentHistoryScreen
  /// - Lấy tất cả các lần khám + khoa ĐT + dịch vụ/thuốc từ HIS Pro
  /// - Yêu cầu: HIS Pro token còn hạn (Cài đặt → EMR Sync)
  /// - Yêu cầu: VPN BV nội bộ để tới 172.16.9.6:1429
  Widget _lichSuDieuTriTile(BuildContext context) {
    final color1 = const Color(0xFF6A1B9A);
    final color2 = const Color(0xFF4A148C);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: InkWell(
        onTap: () => _openLichSuDieuTri(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color1, width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_edu, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('Lịch sử điều trị',
                    style: TextStyle(color: color1, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color1.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: const Text('HIS Pro', style: TextStyle(color: Color(0xFF6A1B9A), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 2),
              const Text(
                'Tất cả lần khám + khoa ĐT + dịch vụ/thuốc (giống HIS desktop)',
                style: TextStyle(color: Colors.black54, fontSize: 11, height: 1.3),
              ),
            ])),
            const Icon(Icons.chevron_right, color: Color(0xFF6A1B9A), size: 22),
          ]),
        ),
      ),
    );
  }

  /// v3.0.79: Tile Đính kèm tài liệu - mở AttachDocumentScreen
  /// - Upload ảnh/file lên EMR BN (port 1417 EmrDocument/CreateWithFile)
  /// - Workflow giống HIS desktop "Chi tiết BA → Đính kèm" (theo note2.docx)
  /// - Yêu cầu: HIS Pro token + mã điều trị (treatment_code)
  Widget _dinhKemTaiLieuTile(BuildContext context) {
    final hasTreatmentCode = _treatmentCode.isNotEmpty;
    final color1 = hasTreatmentCode ? const Color(0xFF00897B) : const Color(0xFFBDBDBD);
    final color2 = hasTreatmentCode ? const Color(0xFF00695C) : const Color(0xFF9E9E9E);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: InkWell(
        onTap: hasTreatmentCode ? () => _openDinhKemTaiLieu(context) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color1, width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.attach_file, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('Đính kèm tài liệu',
                    style: TextStyle(color: color1, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color1.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text('EMR • 1417', style: TextStyle(color: color1, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                hasTreatmentCode
                    ? 'Chụp ảnh / chọn file → upload EMR BN (giống HIS desktop)'
                    : 'BN chưa có mã điều trị - không thể đính kèm',
                style: const TextStyle(color: Colors.black54, fontSize: 11, height: 1.3),
              ),
            ])),
            Icon(Icons.chevron_right, color: color1.withOpacity(0.5), size: 20),
          ]),
        ),
      ),
    );
  }

  /// GRID: Y tế số - 15 chức năng copy từ app Y tế số (Bộ Y tế)
  /// v3.0.23: BỎ màn giới thiệu YTeSoActionScreen → vào thẳng form/screen tương ứng
  /// Tap vào tile → mở thẳng form qua YTeSoRouter.navigate (1 bước thay vì 2 bước)
  Widget _buildYTeSoGrid(BuildContext context) {
    final tiles = <_GridTile>[];
    for (final f in YTeSoFeatures.all) {
      tiles.add(_GridTile(
        f.name,
        f.icon,
        f.color,
        () {
          if (_treatmentCode.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('BN chưa có mã điều trị - không thể dùng chức năng này')),
            );
            return;
          }
          YTeSoRouter.navigate(
            context,
            f.id,
            patient: patient,
            department: department,
          );
        },
      ));
    }
    return _buildGrid(tiles, crossAxisCount: 4);
  }

  Widget _buildGrid(List<_GridTile> tiles, {int crossAxisCount = 4}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.95,
          mainAxisSpacing: 6, crossAxisSpacing: 6,
        ),
        itemCount: tiles.length,
        itemBuilder: (ctx, i) {
          final t = tiles[i];
          return InkWell(
            onTap: t.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.color.withOpacity(0.3)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
              ),
              padding: const EdgeInsets.all(6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: t.color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(t.icon, color: t.color, size: 18),
                ),
                const SizedBox(height: 4),
                Text(t.label, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.black87, height: 1.15),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _GridTile {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _GridTile(this.label, this.icon, this.color, this.onTap);
}
