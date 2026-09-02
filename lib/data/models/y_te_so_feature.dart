// v3.0.9: Model + 15 chức năng Y tế số (copy từ app com.snd.adbc v1.0.44)
// Phân tích từ file Y Tế Số.apk (29.9MB) - extracted 158 icon files
// 15 chức năng chính ở icons/home/:
import 'package:flutter/material.dart';

class YTeSoFeature {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String iconPath; // asset path nếu extract được

  const YTeSoFeature({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    this.iconPath = '',
  });
}

/// v3.0.9: 15 chức năng chính của app Y tế số (Bộ Y tế)
/// Icon từ assets/flutter_assets/assets/icons/home/ic_*.png
class YTeSoFeatures {
  static const List<YTeSoFeature> all = [
    YTeSoFeature(
      id: 'bacsidibuong',
      name: 'Bác sĩ đi buồng',
      description: 'Ghi nhận thăm khám tại giường cho bệnh nhân đang điều trị',
      icon: Icons.medical_services,
      color: Color(0xFF1976D2),
    ),
    YTeSoFeature(
      id: 'bangiaobenhnhan',
      name: 'Bàn giao bệnh nhân',
      description: 'Phiếu bàn giao BN giữa các ca trực / khoa',
      icon: Icons.swap_horiz,
      color: Color(0xFF6A1B9A),
    ),
    YTeSoFeature(
      id: 'bangiaoca',
      name: 'Bàn giao ca',
      description: 'Bàn giao công việc giữa các ca trực (sáng - chiều - đêm)',
      icon: Icons.compare_arrows,
      color: Color(0xFF4527A0),
    ),
    YTeSoFeature(
      id: 'canlamsang',
      name: 'Cận lâm sàng',
      description: 'Chỉ định và theo dõi kết quả CLS (XN, CDHA, thủ thuật)',
      icon: Icons.science,
      color: Color(0xFF00838F),
    ),
    YTeSoFeature(
      id: 'dieuxe',
      name: 'Điều xe',
      description: 'Quản lý điều xe cấp cứu vận chuyển BN',
      icon: Icons.local_shipping,
      color: Color(0xFFEF6C00),
    ),
    YTeSoFeature(
      id: 'ghichisosinhton',
      name: 'Ghi chú sinh tồn',
      description: 'Ghi nhận chỉ số sinh tồn: Mạch, HA, Nhiệt độ, SpO2, nhịp thở',
      icon: Icons.favorite,
      color: Color(0xFFE91E63),
    ),
    YTeSoFeature(
      id: 'hanhchinhdieuxe',
      name: 'Hành chính điều xe',
      description: 'Thủ tục hành chính cho điều xe (lệnh, phê duyệt, log)',
      icon: Icons.assignment,
      color: Color(0xFFE65100),
    ),
    YTeSoFeature(
      id: 'phieuchamsoc',
      name: 'Phiếu chăm sóc',
      description: 'Phiếu chăm sóc điều dưỡng: theo dõi, chăm sóc, giáo dục SK',
      icon: Icons.healing,
      color: Color(0xFFFB8C00),
    ),
    YTeSoFeature(
      id: 'phieucongkhaithuoc',
      name: 'Phiếu công khai thuốc',
      description: 'Phiếu công khai thuốc sử dụng cho BN và người nhà',
      icon: Icons.public,
      color: Color(0xFF0288D1),
    ),
    YTeSoFeature(
      id: 'phieutonghopthuockhongthuchien',
      name: 'Phiếu tổng hợp thuốc không thực hiện',
      description: 'Tổng hợp thuốc kê nhưng không thực hiện + lý do',
      icon: Icons.block,
      color: Color(0xFFD32F2F),
    ),
    YTeSoFeature(
      id: 'phieutruyendich',
      name: 'Phiếu truyền dịch',
      description: 'Phiếu truyền dịch: loại dịch, tốc độ, thời gian, theo dõi',
      icon: Icons.water_drop,
      color: Color(0xFF00ACC1),
    ),
    YTeSoFeature(
      id: 'scan_tai_lieu',
      name: 'Quét tài liệu',
      description: 'Quét (scan) tài liệu giấy → PDF đẩy lên EMR',
      icon: Icons.document_scanner,
      color: Color(0xFF1565C0),
    ),
    YTeSoFeature(
      id: 'thuchienylenh',
      name: 'Thực hiện y lệnh',
      description: 'Thực hiện y lệnh BS: thuốc, CLS, chăm sóc, theo dõi',
      icon: Icons.checklist,
      color: Color(0xFF388E3C),
    ),
    YTeSoFeature(
      id: 'xemchisosinhton',
      name: 'Xem chỉ số sinh tồn',
      description: 'Xem lịch sử chỉ số sinh tồn theo thời gian (biểu đồ)',
      icon: Icons.show_chart,
      color: Color(0xFFAD1457),
    ),
    YTeSoFeature(
      id: 'xemphieuchamsoc',
      name: 'Xem phiếu chăm sóc',
      description: 'Xem các phiếu chăm sóc đã lập của BN',
      icon: Icons.folder_open,
      color: Color(0xFF7B1FA2),
    ),

    // ===== 5 chức năng bổ sung từ folder icons root =====
    YTeSoFeature(
      id: 'qr_code_scanner',
      name: 'Quét QR bệnh nhân',
      description: 'Quét QR BN để tải thông tin nhanh + mở EMR',
      icon: Icons.qr_code_scanner,
      color: Color(0xFF1A237E),
    ),
    // v3.0.93: Bỏ mục 'Bệnh án' (dư - đã có 'Xem bệnh án' ở patient actions sheet)
    YTeSoFeature(
      id: 'cham_soc_suc_khoe',
      name: 'Chăm sóc sức khỏe',
      description: 'Phiếu tư vấn chăm sóc SK cho BN + người nhà',
      icon: Icons.health_and_safety_outlined,
      color: Color(0xFF00695C),
    ),
    YTeSoFeature(
      id: 'danh_sach_tiem_chung',
      name: 'Danh sách tiêm chủng',
      description: 'Danh sách BN chờ tiêm chủng + lịch sử tiêm',
      icon: Icons.vaccines,
      color: Color(0xFFC62828),
    ),
    YTeSoFeature(
      id: 'danh_sach_y_lenh',
      name: 'Danh sách y lệnh',
      description: 'Danh sách y lệnh BS đang chờ thực hiện',
      icon: Icons.assignment_late,
      color: Color(0xFF4527A0),
    ),
  ];

  static YTeSoFeature? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }
}
