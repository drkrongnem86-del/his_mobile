// ProcedureRoomActionsSheet v3.1.00 - THAO TÁC BỆNH NHÂN RIÊNG cho Phòng thử thuật HSCC
// Workflow HIS Desktop (theo note Word của BS):
// 1. Click vào tên BN ở phòng thử thuật
// 2. Hiện bảng thao tác → click "Thực hiện" → mở form
// 3. Form có sẵn (template) → nhập KQ → đính kèm ảnh → chọn thời gian
// 4. Lưu + Ký → đẩy EMR
// 5. Quay lại phòng thử thuật → BN chuyển sang "Đã thực hiện"
//
// v3.1.00: Sheet RIÊNG (không dùng PatientActionsSheet chung) vì:
// - Chỉ có 1 chức năng chính: "Thực hiện ECG"
// - Workflow đặc thù: chỉ cần 1 nút bấm để mở ECG form
// - Không cần 4 mục (Xem BA / Y tế số / Lịch sử / Đính kèm) vì BN này đang trong workflow thủ thuật
// - Auto-load lại danh sách sau khi hoàn thành
import 'package:flutter/material.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/core/utils/patient_name_helper.dart';
import 'package:his_mobile/presentation/screens/ecg_execute_screen.dart';
import 'package:his_mobile/presentation/screens/treatment_history_screen.dart';
import 'package:his_mobile/presentation/screens/xem_benh_an_screen.dart';
import 'package:his_mobile/presentation/widgets/user_header.dart';

class ProcedureRoomActionsSheet extends StatelessWidget {
  final Map<String, dynamic> patient;
  final Map<String, dynamic> serviceReq;
  final VoidCallback? onECGSaved; // callback sau khi lưu ECG thành công

  const ProcedureRoomActionsSheet({
    super.key,
    required this.patient,
    required this.serviceReq,
    this.onECGSaved,
  });

  String _g(String k1, [String? k2, String? k3]) =>
      (patient[k1] ?? patient[k2 ?? ''] ?? patient[k3 ?? ''] ?? serviceReq[k1] ?? serviceReq[k2 ?? ''] ?? serviceReq[k3 ?? ''] ?? '')
          .toString();

  String get _patientName => fixVietnameseMojibake(PatientNameHelper.getName(patient));
  String get _patientCode => _g('TDL_PATIENT_CODE', 'tdl_patient_code');
  String get _treatmentCode => _g('TDL_TREATMENT_CODE', 'treatment_code');
  String get _serviceReqCode => _g('SERVICE_REQ_CODE', 'service_req_code');
  String get _serviceName => _g('SERVICE_NAME', 'service_name');
  String get _icdName => _g('ICD_NAME', 'icd_name');
  String get _icdCode => _g('ICD_CODE', 'icd_code');
  String get _bedName => _g('BED_NAME', 'bed_name');
  String get _sttName => _g('SERVICE_REQ_STT_NAME', 'service_req_stt_name');

  int get _sttId {
    final v = serviceReq['SERVICE_REQ_STT_ID'] ?? serviceReq['service_req_stt_id'] ?? 1;
    return int.tryParse(v.toString()) ?? 1;
  }

  bool get _isChua => _sttId == 1 || _sttId == 2;

  Future<void> _openECGExecute(BuildContext context) async {
    Navigator.pop(context); // đóng sheet
    await Future.delayed(const Duration(milliseconds: 200));
    if (!context.mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ECGExecuteScreen(
          patient: patient,
          serviceReq: serviceReq,
        ),
      ),
    );
    if (result == true && onECGSaved != null) {
      onECGSaved!();
    }
  }

  void _openXemBenhAn(BuildContext context) {
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => XemBenhAnScreen(patient: patient),
      ));
    });
  }

  void _openLichSuDieuTri(BuildContext context) {
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => TreatmentHistoryScreen(patient: patient),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // User header
              UserHeader.fromAuth(department: 'Phòng thử thuật HSCC'),

              // Header BN
              _buildHeader(context),

              // Section: Thao tác chính
              _sectionHeader('THAO TÁC CHÍNH', Icons.flash_on, const Color(0xFFD32F2F), 'Phòng thử thuật'),

              // Big tile: Thực hiện ECG (nếu chưa)
              if (_isChua)
                _bigTile(
                  context: context,
                  title: 'Thực hiện ECG',
                  subtitle: 'Mở form nhập kết quả điện tim - lưu xong tự kết thúc',
                  icon: Icons.flash_on,
                  color1: const Color(0xFFD32F2F),
                  color2: const Color(0xFFB71C1C),
                  onTap: () => _openECGExecute(context),
                  chips: const ['📋 Kết quả', '📷 Ảnh', '⏱ Thời gian', '✅ Auto-finish'],
                )
              else
                _bigTile(
                  context: context,
                  title: 'Đã thực hiện xong',
                  subtitle: 'Yêu cầu đã hoàn thành - xem chi tiết hoặc cập nhật',
                  icon: Icons.check_circle,
                  color1: const Color(0xFF388E3C),
                  color2: const Color(0xFF1B5E20),
                  onTap: () => _openECGExecute(context),
                  chips: const ['📋 Xem KQ', '🔄 Cập nhật'],
                ),

              const SizedBox(height: 8),

              // Section: Tham khảo nhanh
              _sectionHeader('THAM KHẢO NHANH', Icons.info_outline, const Color(0xFF616161), 'Tùy chọn'),

              // Small tile: Xem bệnh án
              _smallTile(
                context: context,
                title: 'Xem bệnh án',
                subtitle: 'PDF đã ký từ Data public / HIS Pro',
                icon: Icons.picture_as_pdf,
                color: const Color(0xFFAD1457),
                onTap: () => _openXemBenhAn(context),
              ),
              // Small tile: Lịch sử điều trị
              _smallTile(
                context: context,
                title: 'Lịch sử điều trị',
                subtitle: 'Tất cả lần khám + khoa + dịch vụ/thuốc (HIS Pro)',
                icon: Icons.history_edu,
                color: const Color(0xFF6A1B9A),
                onTap: () => _openLichSuDieuTri(context),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF6A1B9A), Color(0xFF4A148C)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
              child: const Text('PHÒNG THỬ THUẬT HSCC',
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 22),
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white54, width: 2)),
              child: Center(
                child: Text(
                  _patientName.isNotEmpty ? _patientName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _patientName,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.1),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 2, children: [
                    if (_patientCode.isNotEmpty)
                      _badge('Mã: $_patientCode'),
                    if (_treatmentCode.isNotEmpty)
                      _badge('ĐT: $_treatmentCode'),
                    if (_bedName.isNotEmpty)
                      _badge('🛏 $_bedName', color: const Color(0xFFFFEB3B), textColor: Colors.black87),
                    if (_serviceReqCode.isNotEmpty)
                      _badge('YC: $_serviceReqCode'),
                  ]),
                ],
              ),
            ),
          ]),
          if (_icdName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  _icdCode.isNotEmpty ? '$_icdCode - $_icdName' : _icdName,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          if (_serviceName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.flash_on, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _serviceName,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_sttName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _isChua ? const Color(0xFFFFCDD2) : const Color(0xFFC8E6C9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _sttName,
                      style: TextStyle(
                        color: _isChua ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _badge(String text, {Color color = Colors.white24, Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color, String badge) {
    return Container(
      color: const Color(0xFFF6F8FB),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
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
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color1, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11, height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 2, children: [
                    for (final c in chips) _miniChip(c, color1),
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color1.withValues(alpha: 0.5), size: 24),
          ]),
        ),
      ),
    );
  }

  Widget _smallTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, color.withValues(alpha: 0.7)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 10, height: 1.3),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}
