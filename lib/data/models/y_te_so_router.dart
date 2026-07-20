// v3.0.9: Router cho 20 chức năng Y tế số
// - Các chức năng đã có screen → route trực tiếp
// - Các chức năng chưa có → tạo form generic (3-4 trường + lưu local)
import 'package:flutter/material.dart';
import 'package:his_mobile/data/models/y_te_so_feature.dart';
import 'package:his_mobile/presentation/screens/phieu_kham_screen.dart';
import 'package:his_mobile/presentation/screens/scan_phieu_screen.dart';
import 'package:his_mobile/presentation/screens/xem_benh_an_screen.dart';
import 'package:his_mobile/presentation/screens/qr_scanner_screen.dart';
import 'package:his_mobile/presentation/screens/y_te_so_form_screen.dart';

class YTeSoRoute {
  final String id;
  final YTeSoFeature feature;
  final Widget Function(BuildContext, Map<String, dynamic> patient, Map<String, dynamic> department) builder;
  final bool requiresTreatment;

  const YTeSoRoute({
    required this.id,
    required this.feature,
    required this.builder,
    this.requiresTreatment = true,
  });
}

class YTeSoRouter {
  /// v3.0.9: Mapping 20 chức năng → màn hình tương ứng
  /// Các chức năng dùng screen có sẵn: canlamsang, scan_tai_lieu, benh_an, qr_code_scanner, ...
  /// Các chức năng chưa có: tạo form generic (YTeSoFormScreen)
  static final Map<String, YTeSoRoute> _routes = {
    // 1. bacsidibuong - Bác sĩ đi buồng (form generic)
    'bacsidibuong': YTeSoRoute(
      id: 'bacsidibuong',
      feature: YTeSoFeatures.byId('bacsidibuong')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'bacsidibuong',
        featureName: 'Bác sĩ đi buồng',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('chan_doan', 'Chẩn đoán', required: true),
          YTeSoField.text('dien_bien', 'Diễn biến', required: true, multiline: true),
          YTeSoField.text('y_lenh_moi', 'Y lệnh mới', multiline: true),
        ],
        emrDocType: 7, // to dieu tri
      ),
    ),

    // 2. bangiaobenhnhan - Bàn giao bệnh nhân (form generic)
    // v3.0.35: Đổi emrDocType từ 8 (phieuChamSoc) sang 20 (phieuKhac) - vì HIS Pro 1417
    // không có loại "Bàn giao bệnh nhân" riêng, app thật BVBM cũng dùng 20 cho mọi loại.
    'bangiaobenhnhan': YTeSoRoute(
      id: 'bangiaobenhnhan',
      feature: YTeSoFeatures.byId('bangiaobenhnhan')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'bangiaobenhnhan',
        featureName: 'Bàn giao bệnh nhân',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('tinh_trang', 'Tình trạng BN', required: true, multiline: true),
          YTeSoField.text('cv_can_lam', 'Công việc cần làm tiếp', multiline: true),
          YTeSoField.text('canh_bao', 'Cảnh báo / Lưu ý', multiline: true),
        ],
        emrDocType: 20, // v3.0.35: Phiếu khác (HIS Pro không có "Bàn giao" riêng)
      ),
    ),

    // 3. bangiaoca - Bàn giao ca (form generic)
    // v3.0.35: Thêm emrDocType: 20 (Phiếu khác) - trước đây thiếu nên dùng defaultKind
    'bangiaoca': YTeSoRoute(
      id: 'bangiaoca',
      feature: YTeSoFeatures.byId('bangiaoca')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'bangiaoca',
        featureName: 'Bàn giao ca',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.select('ca', 'Ca trực', options: ['Sáng', 'Trưa', 'Chiều', 'Đêm'], required: true),
          YTeSoField.text('nguoi_giao', 'Người giao ca', required: true),
          YTeSoField.text('nguoi_nhan', 'Người nhận ca', required: true),
          YTeSoField.text('ghi_chu', 'Ghi chú bàn giao', multiline: true),
        ],
        emrDocType: 20, // v3.0.35: Phiếu khác
      ),
    ),

    // 4. canlamsang - Cận lâm sàng (dùng PhieuKhamScreen đã có)
    'canlamsang': YTeSoRoute(
      id: 'canlamsang',
      feature: YTeSoFeatures.byId('canlamsang')!,
      builder: (ctx, p, d) => PhieuKhamScreen(
        patient: p,
        department: d,
        treatmentId: p['TREATMENT_ID'] is int
            ? p['TREATMENT_ID']
            : int.tryParse(p['TREATMENT_ID']?.toString() ?? p['id']?.toString() ?? ''),
      ),
    ),

    // 5. dieuxe - Điều xe (form generic)
    'dieuxe': YTeSoRoute(
      id: 'dieuxe',
      feature: YTeSoFeatures.byId('dieuxe')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'dieuxe',
        featureName: 'Điều xe',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('bien_so', 'Biển số xe', required: true),
          YTeSoField.text('tai_xe', 'Tài xế', required: true),
          YTeSoField.text('diem_den', 'Điểm đến', required: true),
          YTeSoField.text('ly_do', 'Lý do điều xe', required: true, multiline: true),
          YTeSoField.select('muc_do', 'Mức độ', options: ['Thường', 'Cấp cứu']),
        ],
      ),
    ),

    // 6. ghichisosinhton - Ghi chú sinh tồn (form generic - tracking)
    'ghichisosinhton': YTeSoRoute(
      id: 'ghichisosinhton',
      feature: YTeSoFeatures.byId('ghichisosinhton')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'ghichisosinhton',
        featureName: 'Ghi chú sinh tồn',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.number('mach', 'Mạch (l/p)'),
          YTeSoField.number('huyet_ap_tt', 'HA tâm thu (mmHg)'),
          YTeSoField.number('huyet_ap_td', 'HA tâm trương (mmHg)'),
          YTeSoField.number('nhiet_do', 'Nhiệt độ (°C)'),
          YTeSoField.number('spo2', 'SpO2 (%)'),
          YTeSoField.number('nhip_tho', 'Nhịp thở (l/p)'),
          YTeSoField.select('tri_giac', 'Tri giác', options: ['Tỉnh', 'Lơ mơ', 'Hôn mê']),
          YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
        ],
      ),
    ),

    // 7. hanhchinhdieuxe - Hành chính điều xe (form generic)
    'hanhchinhdieuxe': YTeSoRoute(
      id: 'hanhchinhdieuxe',
      feature: YTeSoFeatures.byId('hanhchinhdieuxe')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'hanhchinhdieuxe',
        featureName: 'Hành chính điều xe',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('so_lenh', 'Số lệnh điều xe', required: true),
          YTeSoField.text('nguoi_ky', 'Người ký duyệt', required: true),
          YTeSoField.text('ly_do', 'Lý do', multiline: true),
        ],
      ),
    ),

    // 8. phieuchamsoc - Phiếu chăm sóc (form generic)
    'phieuchamsoc': YTeSoRoute(
      id: 'phieuchamsoc',
      feature: YTeSoFeatures.byId('phieuchamsoc')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'phieuchamsoc',
        featureName: 'Phiếu chăm sóc',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('nhan_dinh', 'Nhận định', required: true, multiline: true),
          YTeSoField.text('can_thiep', 'Can thiệp điều dưỡng', required: true, multiline: true),
          YTeSoField.text('danh_gia', 'Đánh giá', multiline: true),
          YTeSoField.text('giao_duc_sk', 'Giáo dục sức khỏe', multiline: true),
        ],
        emrDocType: 8, // phieu cham soc
      ),
    ),

    // 9. phieucongkhaithuoc - Phiếu công khai thuốc
    'phieucongkhaithuoc': YTeSoRoute(
      id: 'phieucongkhaithuoc',
      feature: YTeSoFeatures.byId('phieucongkhaithuoc')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'phieucongkhaithuoc',
        featureName: 'Phiếu công khai thuốc',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('danh_sach_thuoc', 'Danh sách thuốc', required: true, multiline: true),
          YTeSoField.text('gia_thuoc', 'Giá thuốc (VNĐ)'),
          YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
        ],
      ),
    ),

    // 10. phieutonghopthuockhongthuchien - Phiếu tổng hợp thuốc không thực hiện
    'phieutonghopthuockhongthuchien': YTeSoRoute(
      id: 'phieutonghopthuockhongthuchien',
      feature: YTeSoFeatures.byId('phieutonghopthuockhongthuchien')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'phieutonghopthuockhongthuchien',
        featureName: 'Phiếu tổng hợp thuốc không thực hiện',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('thuoc_khong_thuc_hien', 'Thuốc không thực hiện', required: true, multiline: true),
          YTeSoField.text('ly_do', 'Lý do không thực hiện', required: true, multiline: true),
        ],
      ),
    ),

    // 11. phieutruyendich - Phiếu truyền dịch (form generic)
    'phieutruyendich': YTeSoRoute(
      id: 'phieutruyendich',
      feature: YTeSoFeatures.byId('phieutruyendich')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'phieutruyendich',
        featureName: 'Phiếu truyền dịch',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('loai_dich', 'Loại dịch truyền', required: true),
          YTeSoField.number('the_tich', 'Thể tích (ml)', required: true),
          YTeSoField.number('toc_do', 'Tốc độ (giọt/phút)', required: true),
          YTeSoField.text('thoi_gian_bat_dau', 'Thời gian bắt đầu'),
          YTeSoField.text('thoi_gian_ket_thuc', 'Thời gian kết thúc'),
          YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
        ],
        emrDocType: 9, // phieu truyen dich
      ),
    ),

    // 12. scan_tai_lieu - Quét tài liệu (dùng ScanPhieuScreen)
    'scan_tai_lieu': YTeSoRoute(
      id: 'scan_tai_lieu',
      feature: YTeSoFeatures.byId('scan_tai_lieu')!,
      builder: (ctx, p, d) => ScanPhieuScreen(
        treatmentCode: p['TDL_TREATMENT_CODE']?.toString() ?? p['treatment_code']?.toString() ?? '',
        patientName: p['TDL_PATIENT_UNSIGNED_NAME']?.toString() ?? '',
        signedBy: 'mobile_user',
      ),
    ),

    // 13. thuchienylenh - Thực hiện y lệnh (form generic)
    'thuchienylenh': YTeSoRoute(
      id: 'thuchienylenh',
      feature: YTeSoFeatures.byId('thuchienylenh')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'thuchienylenh',
        featureName: 'Thực hiện y lệnh',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('y_lenh', 'Y lệnh', required: true, multiline: true),
          YTeSoField.select('trang_thai', 'Trạng thái', options: ['Đang thực hiện', 'Đã hoàn thành', 'Hoãn', 'Hủy'], required: true),
          YTeSoField.text('ghi_chu', 'Ghi chú thực hiện', multiline: true),
        ],
      ),
    ),

    // 14. xemchisosinhton - Xem chỉ số sinh tồn (danh sách)
    'xemchisosinhton': YTeSoRoute(
      id: 'xemchisosinhton',
      feature: YTeSoFeatures.byId('xemchisosinhton')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'xemchisosinhton',
        featureName: 'Xem chỉ số sinh tồn',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('lich_su', 'Lịch sử (sẽ load từ HisTracking)'),
        ],
        readOnly: true,
      ),
    ),

    // 15. xemphieuchamsoc - Xem phiếu chăm sóc
    'xemphieuchamsoc': YTeSoRoute(
      id: 'xemphieuchamsoc',
      feature: YTeSoFeatures.byId('xemphieuchamsoc')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'xemphieuchamsoc',
        featureName: 'Xem phiếu chăm sóc',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('danh_sach', 'Danh sách phiếu (sẽ load từ EMR)'),
        ],
        readOnly: true,
      ),
    ),

    // 16. qr_code_scanner - Quét QR (dùng QrScannerScreen có sẵn)
    'qr_code_scanner': YTeSoRoute(
      id: 'qr_code_scanner',
      feature: YTeSoFeatures.byId('qr_code_scanner')!,
      builder: (ctx, p, d) => const QrScannerScreen(),
      requiresTreatment: false,
    ),

    // 17. benh_an - Bệnh án (dùng XemBenhAnScreen)
    'benh_an': YTeSoRoute(
      id: 'benh_an',
      feature: YTeSoFeatures.byId('benh_an')!,
      builder: (ctx, p, d) => XemBenhAnScreen(patient: p),
    ),

    // 18. cham_soc_suc_khoe - Chăm sóc sức khỏe
    'cham_soc_suc_khoe': YTeSoRoute(
      id: 'cham_soc_suc_khoe',
      feature: YTeSoFeatures.byId('cham_soc_suc_khoe')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'cham_soc_suc_khoe',
        featureName: 'Chăm sóc sức khỏe',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('tu_van', 'Tư vấn', required: true, multiline: true),
          YTeSoField.text('ke_hoach', 'Kế hoạch chăm sóc', multiline: true),
          YTeSoField.text('ghi_chu', 'Ghi chú', multiline: true),
        ],
      ),
    ),

    // 19. danh_sach_tiem_chung - DS tiêm chủng
    'danh_sach_tiem_chung': YTeSoRoute(
      id: 'danh_sach_tiem_chung',
      feature: YTeSoFeatures.byId('danh_sach_tiem_chung')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'danh_sach_tiem_chung',
        featureName: 'Danh sách tiêm chủng',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('ds_cho', 'DS chờ tiêm'),
          YTeSoField.text('ls_tiem', 'Lịch sử tiêm chủng'),
        ],
        readOnly: true,
      ),
    ),

    // 20. danh_sach_y_lenh - DS y lệnh
    'danh_sach_y_lenh': YTeSoRoute(
      id: 'danh_sach_y_lenh',
      feature: YTeSoFeatures.byId('danh_sach_y_lenh')!,
      builder: (ctx, p, d) => YTeSoFormScreen(
        featureId: 'danh_sach_y_lenh',
        featureName: 'Danh sách y lệnh',
        patient: p,
        department: d,
        fields: const [
          YTeSoField.text('ds_cho', 'DS y lệnh chờ thực hiện'),
        ],
        readOnly: true,
      ),
    ),
  };

  /// Lấy route cho 1 feature id
  static YTeSoRoute? forId(String id) => _routes[id];

  /// Lấy tất cả routes
  static List<YTeSoRoute> get all => _routes.values.toList();

  /// Navigate từ feature id
  static Future<T?> navigate<T>(BuildContext context, String id, {
    required Map<String, dynamic> patient,
    required Map<String, dynamic> department,
  }) {
    final route = _routes[id];
    if (route == null) {
      return Future.value(null);
    }
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (ctx) => route.builder(ctx, patient, department),
      ),
    );
  }
}
