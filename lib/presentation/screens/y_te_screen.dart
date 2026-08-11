// v3.0.89: YTeScreen - 6 chức năng Y tế số (theo yêu cầu user)
//
//   1. Thực hiện y lệnh (Y lệnh CLS - API: y-lenh-can-lam-sang)
//   2. Phiếu thực hiện thuốc (form - chưa có public API)
//   3. Phiếu chăm sóc (API: danh-sach-dieu-duong - DS điều dưỡng)
//   4. Bảng kê tổng hợp (form - chưa có public API)
//   5. Kê đơn dược (form - chưa có public API)
//   6. Kê đơn tủ trực (form - chưa có public API)
//
// 2 mục đầu dùng public API thật, 4 mục sau dùng YTeSoFormScreen (form local +
// đẩy EMR unsigned - workflow như app cũ).

import 'package:flutter/material.dart';
import 'package:his_mobile/data/api/y_te_so_service.dart';
import 'package:his_mobile/data/api/y_te_so_extended_service.dart';
import 'package:his_mobile/presentation/screens/y_te_so_list_screen.dart';
import 'package:his_mobile/presentation/screens/y_te_so_form_screen.dart';

class YTeScreen extends StatefulWidget {
  final String treatmentCode;
  final int? treatmentId;
  final String? patientName;
  final String? patientCode;
  final Map<String, dynamic>? patientData;
  final Map<String, dynamic>? departmentData;

  const YTeScreen({
    super.key,
    required this.treatmentCode,
    this.treatmentId,
    this.patientName,
    this.patientCode,
    this.patientData,
    this.departmentData,
  });

  @override
  State<YTeScreen> createState() => _YTeScreenState();
}

class _YTeScreenState extends State<YTeScreen> {
  final _yTeService = YTeSoService.instance;
  final _ext = YTeSoExtendedService.instance;

  @override
  void initState() {
    super.initState();
    if (!_yTeService.isLoggedIn) {
      _yTeService.login();
    }
  }

  String get _tc => widget.treatmentCode;
  int get _tid => widget.treatmentId ?? 0;

  /// v3.0.87: Helper - format "yyyyMMdd000000" cho NGAYYLENH
  String _todayYmd() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}000000';
  }

  Map<String, dynamic> get _patientMap => widget.patientData ??
      {
        'treatmentCode': _tc,
        'treatmentId': _tid,
        'patientName': widget.patientName ?? '',
        'patientCode': widget.patientCode ?? '',
      };

  Map<String, dynamic> get _deptMap =>
      widget.departmentData ?? {'name': 'HSTC', 'code': 'HSTC'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chức năng Y tế số',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.patientName != null
                  ? '${widget.patientName ?? ""} • $_tc'
                  : _tc,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildBanner(),
          const SizedBox(height: 8),
          _buildMenu(),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00838F), Color(0xFF00ACC1)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.health_and_safety, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Y Tế Số (Bộ y tế)',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  widget.patientName != null
                      ? '${widget.patientName} • $_tc'
                      : 'BN $_tc',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_yTeService.accessToken != null)
            const Icon(Icons.check_circle, color: Colors.white70, size: 20),
        ],
      ),
    );
  }

  /// v3.0.89: 6 mục theo yêu cầu user
  Widget _buildMenu() {
    final items = <_MenuItem>[
      _MenuItem(
        icon: Icons.assignment_turned_in,
        color: const Color(0xFF2E7D32),
        label: 'Thực hiện y lệnh',
        description: 'Danh sách y lệnh CLS theo STT',
        onTap: _openYlenhList,
      ),
      _MenuItem(
        icon: Icons.medication,
        color: const Color(0xFF6A1B9A),
        label: 'Phiếu thực hiện thuốc',
        description: 'Phiếu thực hiện thuốc cho BN',
        onTap: _openPhieuThuoc,
      ),
      _MenuItem(
        icon: Icons.healing,
        color: const Color(0xFFAD1457),
        label: 'Phiếu chăm sóc',
        description: 'Phiếu chăm sóc điều dưỡng',
        onTap: _openDieuDuong,
      ),
      _MenuItem(
        icon: Icons.receipt_long,
        color: const Color(0xFFEF6C00),
        label: 'Bảng kê tổng hợp',
        description: 'Bảng kê tổng hợp viện phí',
        onTap: _openBangKe,
      ),
      _MenuItem(
        icon: Icons.medication_liquid,
        color: const Color(0xFFC62828),
        label: 'Kê đơn dược',
        description: 'Kê đơn thuốc cho BN',
        onTap: _openKeDonDuoc,
      ),
      _MenuItem(
        icon: Icons.local_pharmacy,
        color: const Color(0xFF00838F),
        label: 'Kê đơn tủ trực',
        description: 'Kê đơn tủ trực khoa',
        onTap: _openKeDonTuTruc,
      ),
    ];

    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i == 0)
            _sectionHeader(
                'Y lệnh & Điều trị', Icons.assignment, const Color(0xFF2E7D32)),
          if (i == 2)
            _sectionHeader('Chăm sóc điều dưỡng', Icons.healing,
                const Color(0xFFAD1457)),
          if (i == 3)
            _sectionHeader(
                'Hành chính - Báo cáo', Icons.description, const Color(0xFF455A64)),
          if (i == 4)
            _sectionHeader('Dược', Icons.medication_liquid, const Color(0xFFC62828)),
          _MenuTile(item: items[i]),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(color: color.withValues(alpha: 0.3), height: 1)),
        ],
      ),
    );
  }

  // ============ Mở các screen (6 mục) ============

  void _openYlenhList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoListScreen(
          title: 'Y lệnh cận lâm sàng',
          description: 'STT 1-3 cho điều trị $_tc',
          icon: Icons.assignment_turned_in,
          color: const Color(0xFF2E7D32),
          fetchData: () async {
            final all = <dynamic>[];
            for (int stt = 1; stt <= 3; stt++) {
              final r = await _ext.yLenhCanLamSang(
                  treatmentId: _tid, sttId: stt, treatmentCode: _tc);
              if (r.success && r.data is List) {
                all.addAll(r.data as List);
              }
            }
            return YTeSoApiResult(success: true, data: all);
          },
          extractRecords: (r) => r.data is List ? r.data as List : [],
          recordTitle: (rec) => (rec['SERVICE_REQ_CODE'] ?? '').toString(),
          recordSubtitle: (rec) {
            final code = (rec['SERVICE_REQ_CODE'] ?? '').toString();
            final name = (rec['SERVICE_REQ_TYPE_NAME'] ??
                    rec['SERVICE_REQ_TYPE_ID'] ??
                    '')
                .toString();
            return '$code • $name';
          },
          recordFields: (rec) => [
            YTeSoListField('STT',
                (_) => rec['SERVICE_REQ_STT_ID']?.toString() ?? ''),
            YTeSoListField('Loại y lệnh',
                (_) => (rec['SERVICE_REQ_TYPE_NAME'] ?? '').toString()),
            YTeSoListField('Phòng chỉ định',
                (_) => (rec['REQUEST_ROOM_NAME'] ?? rec['REQUEST_ROOM_ID'] ?? '').toString()),
            YTeSoListField('Bác sĩ',
                (_) => (rec['REQUEST_USERNAME'] ?? '').toString()),
            YTeSoListField('Thời gian',
                (_) => (rec['CREATE_TIME']?.toString() ?? '').substring(0, 14)),
            YTeSoListField('Ghi chú',
                (_) => (rec['NOTE'] ?? '').toString()),
          ],
        ),
      ),
    );
  }

  void _openDieuDuong() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoListScreen(
          title: 'Danh sách điều dưỡng (Khoa HSTC)',
          description: 'Phân công điều dưỡng - Điều trị $_tc',
          icon: Icons.healing,
          color: const Color(0xFFAD1457),
          fetchData: () => _ext.danhSachDieuDuong(
            reportTypeCode: 'TKB20100',
            reportTemplateCode: 'TKB2010008',
            idDieuTri: _tid.toString(),
            ngayYlenh: _todayYmd(),
            departmentId: '29',
            departmentCode: 'HSTC',
            departmentName: 'HSTC',
            bedRoomCode: 'H033',
            bedRoomName: 'H033',
          ),
          extractRecords: (r) {
            if (r.data is List) return r.data as List;
            if (r.data is Map && r.data['data'] is List) {
              return r.data['data'] as List;
            }
            return [];
          },
          recordTitle: (rec) =>
              (rec['userName'] ?? rec['loginName'] ?? 'Điều dưỡng').toString(),
          recordSubtitle: (rec) => (rec['departmentName'] ?? '').toString(),
          recordFields: (rec) {
            final fields = <YTeSoListField>[];
            rec.forEach((k, v) {
              if (v != null &&
                  v.toString().isNotEmpty &&
                  v.toString() != 'null' &&
                  !k.toString().startsWith('_')) {
                fields.add(YTeSoListField(k.toString(), (_) => v.toString()));
              }
            });
            return fields.take(8).toList();
          },
        ),
      ),
    );
  }

  // ============ 4 mục dùng form (chưa có public API) ============

  void _openPhieuThuoc() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoFormScreen(
          featureId: 'phieu-thuc-hien-thuoc',
          featureName: 'Phiếu thực hiện thuốc',
          patient: _patientMap,
          department: _deptMap,
          fields: const [
            YTeSoField.text('ten_thuoc', 'Tên thuốc', required: true),
            YTeSoField.text('lieu_dung', 'Liều dùng', required: true),
            YTeSoField.text('so_luong', 'Số lượng'),
            YTeSoField.text('duong_dung', 'Đường dùng'),
            YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
          ],
        ),
      ),
    );
  }

  void _openBangKe() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoFormScreen(
          featureId: 'bang-ke-tong-hop',
          featureName: 'Bảng kê tổng hợp',
          patient: _patientMap,
          department: _deptMap,
          fields: const [
            YTeSoField.text('tu_ngay', 'Từ ngày', required: true),
            YTeSoField.text('den_ngay', 'Đến ngày', required: true),
            YTeSoField.select('loai_vien_phi', 'Loại viện phí',
                options: ['BHYT', 'Viện phí', 'Dịch vụ', 'Khác']),
            YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
          ],
        ),
      ),
    );
  }

  void _openKeDonDuoc() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoFormScreen(
          featureId: 'ke-don-duoc',
          featureName: 'Kê đơn dược',
          patient: _patientMap,
          department: _deptMap,
          fields: const [
            YTeSoField.text('chan_doan', 'Chẩn đoán', required: true),
            YTeSoField.text('ten_thuoc', 'Tên thuốc', required: true),
            YTeSoField.text('lieu_dung', 'Liều dùng', required: true),
            YTeSoField.text('so_luong', 'Số lượng'),
            YTeSoField.text('cach_dung', 'Cách dùng'),
            YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
          ],
        ),
      ),
    );
  }

  void _openKeDonTuTruc() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => YTeSoFormScreen(
          featureId: 'ke-don-tu-truc',
          featureName: 'Kê đơn tủ trực',
          patient: _patientMap,
          department: _deptMap,
          fields: const [
            YTeSoField.text('ten_thuoc', 'Tên thuốc', required: true),
            YTeSoField.text('lieu_dung', 'Liều dùng', required: true),
            YTeSoField.text('so_luong', 'Số lượng'),
            YTeSoField.text('cach_dung', 'Cách dùng'),
            YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final VoidCallback onTap;
  _MenuItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.onTap,
  });
}

class _MenuTile extends StatelessWidget {
  final _MenuItem item;
  const _MenuTile({required this.item});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(item.description,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
