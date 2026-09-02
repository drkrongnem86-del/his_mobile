/// Catalog các phiếu y tế từ HIS Pro (BVĐK Ninh Thuận)
/// Định nghĩa mapping Mps000xxx → thông tin phiếu + fields + saveType
/// Dựa trên ảnh user gửi + Tmp/Mps folder + LogAction.txt
library;
import 'package:flutter/material.dart';
import 'phieu.dart';

/// Catalog tất cả phiếu có trong HIS Pro
class PhieuCatalog {
  /// === PHIẾU CẤP CỨU / ĐIỀU TRỊ - Quan trọng nhất với HSCC ===

  /// Mps000062 - TỜ ĐIỀU TRỊ (theo dõi hàng ngày: diễn biến, chỉ định, đơn thuốc)
  /// v3.0.61: Thêm 6 fields theo dõi sinh hiệu theo template HIS Pro (file code)
  ///   - MACH, NHIET_DO, HA, NHIP_THO, CAN_NANG (5 sinh hiệu)
  ///   - BENH_KEM_THEO (từ ICD_TEXT_BY_TRACKING)
  /// - Mapping đầy đủ với template: TrackingADOs.PULSE, TEMPERATURE, etc.
  static final phieuToDieuTri = Phieu(
    id: 'Mps000062',
    code: '062',
    name: 'Tờ điều trị',
    description: 'Theo dõi diễn biến bệnh, sinh hiệu, chỉ định CLS, đơn thuốc hàng ngày',
    category: PhieuCategory.dieuTri,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.monitor_heart,
    color: const Color(0xFFD32F2F),
    fields: const [
      // === THỜI GIAN + DIỄN BIẾN ===
      PhieuField(key: 'TRACKING_TIME', label: 'Thời gian theo dõi', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'CONTENT', label: 'Diễn biến bệnh', type: PhieuFieldType.textLong, required: true),
      // === v3.0.61: SINH HIỆU (5 ô theo template) ===
      PhieuField(key: 'PULSE', label: 'Mạch', type: PhieuFieldType.number,
          helpText: 'TrackingADOs.PULSE', unit: 'lần/phút'),
      PhieuField(key: 'TEMPERATURE', label: 'Nhiệt độ', type: PhieuFieldType.number,
          helpText: 'TrackingADOs.TEMPERATURE', unit: '°C'),
      PhieuField(key: 'BLOOD_PRESSURE', label: 'Huyết áp', type: PhieuFieldType.text,
          helpText: 'TrackingADOs.BLOOD_PRESSURE_MAX/MIN (vd: 120/80)', unit: 'mmHg'),
      PhieuField(key: 'BREATH_RATE', label: 'Nhịp thở', type: PhieuFieldType.number,
          helpText: 'TrackingADOs.BREATH_RATE', unit: 'lần/phút'),
      PhieuField(key: 'WEIGHT', label: 'Cân nặng', type: PhieuFieldType.number,
          helpText: 'TrackingADOs.WEIGHT', unit: 'kg'),
      // === Y LỆNH + CHẨN ĐOÁN ===
      PhieuField(key: 'SUBCLINICAL_PROCESSES', label: 'Diễn biến CLS', type: PhieuFieldType.textLong,
          helpText: 'TrackingADOs.SUBCLINICAL_PROCESSES (kết quả CLS mới)'),
      PhieuField(key: 'MEDICAL_INSTRUCTION', label: 'Xử lý / Y lệnh', type: PhieuFieldType.textLong),
      PhieuField(key: 'CARE_INSTRUCTION', label: 'Y lệnh chăm sóc', type: PhieuFieldType.textLong),
      PhieuField(key: 'ICD_NAME', label: 'Chẩn đoán chính', type: PhieuFieldType.icd),
      PhieuField(key: 'ICD_TEXT', label: 'Chẩn đoán phân biệt', type: PhieuFieldType.textLong),
      PhieuField(key: 'BENH_KEM_THEO', label: 'Bệnh kèm theo', type: PhieuFieldType.textLong,
          helpText: 'TrackingADOs.ICD_TEXT_BY_TRACKING (bệnh phụ)'),
      // === ĐƠN THUỐC + CLS ===
      PhieuField(key: 'SERVICES', label: 'Dịch vụ CLS chỉ định', type: PhieuFieldType.service),
      PhieuField(key: 'MEDICINES', label: 'Đơn thuốc', type: PhieuFieldType.medicine),
      PhieuField(key: 'CARE_DETAIL', label: 'Chăm sóc (Dinh dưỡng/Loại CS)', type: PhieuFieldType.textLong),
      // === KÝ ===
      PhieuField(key: 'SIGN', label: 'Ký tên BS', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// Mps000374 - BỆNH ÁN CẤP CỨU (bệnh án đầy đủ cho BN cấp cứu)
  static final phieuBenhAnCapCuu = Phieu(
    id: 'Mps000374',
    code: '374',
    name: 'Bệnh án cấp cứu',
    description: 'Bệnh án đầy đủ cho bệnh nhân cấp cứu (7 mục, 105 hàng, 84 cột)',
    category: PhieuCategory.khamBenh,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.emergency,
    color: const Color(0xFFE53935),
    fields: const [
      PhieuField(key: 'IN_TIME', label: 'Giờ vào viện', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'CHAN_DOAN_VAO_VIEN', label: 'Chẩn đoán vào viện', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'LY_DO_VAO_VIEN', label: 'Lý do vào viện', type: PhieuFieldType.textLong),
      PhieuField(key: 'BENH_SU', label: 'Bệnh sử', type: PhieuFieldType.textLong),
      PhieuField(key: 'KHAM_TOAN_THAN', label: 'Khám toàn thân', type: PhieuFieldType.textLong),
      PhieuField(key: 'KHAM_BO_PHAN', label: 'Khám bộ phận', type: PhieuFieldType.textLong),
      PhieuField(key: 'XET_NHIEM', label: 'Xét nghiệm cận lâm sàng', type: PhieuFieldType.textLong),
      PhieuField(key: 'CHAN_DOAN_SO_BO', label: 'Chẩn đoán sơ bộ', type: PhieuFieldType.icd),
      PhieuField(key: 'HUONG_XU_TRI', label: 'Hướng xử trí ban đầu', type: PhieuFieldType.textLong),
      PhieuField(key: 'NGUOI_KY', label: 'BS khám', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// === PHIẾU HÀNH CHÍNH - Vào viện, ra viện, chuyển viện ===

  /// Mps000007 - PHIẾU YÊU CẦU KHÁM BỆNH VÀO VIỆN (CC = Cấp Cứu)
  /// v3.0.61: Thêm 7 fields sinh hiệu theo template HIS Pro (file code)
  ///   - MACH, NHIET_DO, HA (huyết áp), NHIP_THO, SPO2, CAN_NANG, CHIEU_CAO
  /// - Hiển thị trên EMR là bệnh án cấp cứu với 8 ô sinh hiệu chuẩn
  static final phieuYeuCauKBVV = Phieu(
    id: 'Mps000007',
    code: '007',
    name: 'Phiếu yêu cầu khám bệnh vào viện',
    description: 'Phiếu yêu cầu nhập viện cho bệnh nhân cấp cứu (kèm sinh hiệu)',
    category: PhieuCategory.khamBenh,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.medical_information,
    color: const Color(0xFFE91E63),
    fields: const [
      // === I. HÀNH CHÍNH ===
      PhieuField(key: 'PATIENT_NAME', label: 'Họ tên bệnh nhân', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'GENDER_NAME', label: 'Giới tính', type: PhieuFieldType.select,
          options: ['Nam', 'Nữ'], required: true),
      PhieuField(key: 'VIR_ADDRESS', label: 'Địa chỉ', type: PhieuFieldType.text),
      PhieuField(key: 'INTRUCTION_TIME', label: 'Đến khám lúc', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'TRANSFER_IN_ICD_CODE', label: 'Mã ICD nơi giới thiệu', type: PhieuFieldType.icd),
      PhieuField(key: 'TRANSFER_IN_ICD_NAME', label: 'Tên ICD nơi giới thiệu', type: PhieuFieldType.textLong),
      PhieuField(key: 'LY_DO_VAO_VIEN', label: 'Lý do vào viện', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'CHAN_DOAN_BAN_DAU', label: 'Chẩn đoán ban đầu', type: PhieuFieldType.textLong, required: true),
      // === v3.0.61: SINH HIỆU (8 ô theo template HIS Pro) ===
      PhieuField(key: 'MACH', label: 'Mạch', type: PhieuFieldType.number,
          helpText: 'Số lần đập mỗi phút (60-100 bình thường)', unit: 'lần/phút'),
      PhieuField(key: 'NHIET_DO', label: 'Nhiệt độ', type: PhieuFieldType.number,
          helpText: 'Nhiệt độ cơ thể (36.5-37.5 bình thường)', unit: '°C'),
      PhieuField(key: 'HA', label: 'Huyết áp', type: PhieuFieldType.text,
          helpText: 'Huyết áp tâm thu/tâm trương (vd: 120/80)', unit: 'mmHg'),
      PhieuField(key: 'NHIP_THO', label: 'Nhịp thở', type: PhieuFieldType.number,
          helpText: 'Số lần thở mỗi phút (12-20 bình thường)', unit: 'lần/phút'),
      PhieuField(key: 'SPO2', label: 'SpO2', type: PhieuFieldType.number,
          helpText: 'Độ bão hoà oxy (95-100% bình thường)', unit: '%'),
      PhieuField(key: 'CAN_NANG', label: 'Cân nặng', type: PhieuFieldType.number,
          helpText: 'Cân nặng bệnh nhân', unit: 'kg'),
      PhieuField(key: 'CHIEU_CAO', label: 'Chiều cao', type: PhieuFieldType.number,
          helpText: 'Chiều cao bệnh nhân', unit: 'cm'),
      // === BÁC SĨ + KÝ ===
      PhieuField(key: 'BS_KHAM', label: 'Bác sĩ khám', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// Mps000008 - GIẤY RA VIỆN
  static final phieuRaVien = Phieu(
    id: 'Mps000008',
    code: '008',
    name: 'Giấy ra viện',
    description: 'Xác nhận bệnh nhân đủ điều kiện ra viện',
    category: PhieuCategory.hanhChinh,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.exit_to_app,
    color: const Color(0xFF2E7D32),
    fields: const [
      PhieuField(key: 'NGAY_RA_VIEN', label: 'Ngày ra viện', type: PhieuFieldType.date, required: true),
      PhieuField(key: 'CHAN_DOAN_RA_VIEN', label: 'Chẩn đoán ra viện', type: PhieuFieldType.icdText, required: true),
      PhieuField(key: 'PHUONG_PHAP_DT', label: 'Phương pháp điều trị', type: PhieuFieldType.textLong),
      PhieuField(key: 'HUONG_DAN_DT', label: 'Hướng dẫn điều trị tiếp', type: PhieuFieldType.textLong),
      PhieuField(key: 'HEN_TAI_KHAM', label: 'Hẹn tái khám', type: PhieuFieldType.date),
      PhieuField(key: 'GHI_CHU', label: 'Ghi chú', type: PhieuFieldType.textLong),
      PhieuField(key: 'BS_DIEU_TRI', label: 'BS điều trị', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// Mps000009 - GIẤY CHUYỂN VIỆN
  static final phieuChuyenVien = Phieu(
    id: 'Mps000009',
    code: '009',
    name: 'Giấy chuyển viện',
    description: 'Chuyển bệnh nhân sang cơ sở y tế khác',
    category: PhieuCategory.hanhChinh,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.local_hospital,
    color: const Color(0xFFEF6C00),
    fields: const [
      PhieuField(key: 'BV_CHUYEN_DEN', label: 'BV chuyển đến', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'LY_DO_CHUYEN', label: 'Lý do chuyển viện', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'CHAN_DOAN_TRUOC_CHUYEN', label: 'Chẩn đoán trước chuyển', type: PhieuFieldType.icdText, required: true),
      PhieuField(key: 'HUONG_DIEU_TRI', label: 'Hướng điều trị tiếp', type: PhieuFieldType.textLong),
      PhieuField(key: 'PHUONG_TIEN_VC', label: 'Phương tiện vận chuyển', type: PhieuFieldType.select,
          options: ['Xe cấp cứu', 'Xe ô tô', 'Máy bay', 'Khác']),
      PhieuField(key: 'NGAY_CHUYEN', label: 'Ngày chuyển', type: PhieuFieldType.date, required: true),
      PhieuField(key: 'BS_CHUYEN', label: 'BS chuyển', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// Mps000010 - GIẤY HẸN KHÁM
  static final phieuHenKham = Phieu(
    id: 'Mps000010',
    code: '010',
    name: 'Giấy hẹn khám',
    description: 'Hẹn lịch tái khám cho bệnh nhân',
    category: PhieuCategory.hanhChinh,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.event,
    color: const Color(0xFF1976D2),
    fields: const [
      PhieuField(key: 'NGAY_HEN', label: 'Ngày hẹn', type: PhieuFieldType.date, required: true),
      PhieuField(key: 'GIO_HEN', label: 'Giờ hẹn', type: PhieuFieldType.text),
      PhieuField(key: 'KHOA_HEN', label: 'Khoa hẹn khám', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'LY_DO_HEN', label: 'Lý do tái khám', type: PhieuFieldType.textLong),
      PhieuField(key: 'BS_HEN', label: 'BS hẹn', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// Mps000399 - GIẤY XÁC NHẬN
  static final phieuXacNhan = Phieu(
    id: 'Mps000399',
    code: '399',
    name: 'Giấy xác nhận',
    description: 'Xác nhận điều trị / nghỉ ốm / các giấy tờ hành chính',
    category: PhieuCategory.hanhChinh,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.verified_outlined,
    color: const Color(0xFF455A64),
    fields: const [
      PhieuField(key: 'NOI_DUNG_XAC_NHAN', label: 'Nội dung xác nhận', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'THOI_GIAN', label: 'Thời gian (từ - đến)', type: PhieuFieldType.text),
      PhieuField(key: 'LY_DO', label: 'Lý do', type: PhieuFieldType.textLong),
      PhieuField(key: 'BS_XAC_NHAN', label: 'BS xác nhận', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// === HỘI CHẨN - Mps000019 ===

  /// Mps000019 - TRÍCH BIÊN BẢN HỘI CHẨN (HC)
  static final phieuHoiChan = Phieu(
    id: 'Mps000019',
    code: '019',
    name: 'Trích biên bản hội chẩn',
    description: 'Biên bản hội chẩn đa chuyên khoa cho ca khó',
    category: PhieuCategory.hoiChan,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.groups,
    color: const Color(0xFF8D6E63),
    fields: const [
      PhieuField(key: 'HOI_CHAN_LUC', label: 'Hội chẩn lúc', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'DIA_DIEM', label: 'Địa điểm', type: PhieuFieldType.text, defaultValue: 'Tại khoa Cấp cứu'),
      PhieuField(key: 'CHU_TOA', label: 'Chủ tọa', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'THANH_VIEN', label: 'Thành viên tham gia', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'TOM_TAT_DIEN_BIEN', label: 'Tóm tắt diễn biến bệnh, quá trình điều trị', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'KET_LUAN', label: 'Kết luận (sau khi khám lại và thảo luận)', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'PHUONG_PHAP_DT', label: 'Phương pháp điều trị', type: PhieuFieldType.textLong),
      PhieuField(key: 'HUONG_DT_TIEP', label: 'Hướng điều trị tiếp', type: PhieuFieldType.textLong),
      PhieuField(key: 'BS_CHU_TOA', label: 'BS chủ tọa', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên chủ tọa', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// === BÀN GIAO - HT (Hồi Sức Tích Cực ↔ Cấp Cứu) ===

  /// HT - PHIẾU BÀN GIAO NGƯỜI BỆNH CHUYỂN KHOA
  /// Template: HT_t_mau_phieu_ban_giao_cc.docx (template có sẵn)
  static final phieuBanGiao = Phieu(
    id: 'HT',
    code: 'HT',
    name: 'Phiếu bàn giao NB chuyển khoa',
    description: 'Bàn giao bệnh nhân giữa các khoa (CC ↔ HSTC ↔ chuyên khoa)',
    category: PhieuCategory.banGiao,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.swap_horiz,
    color: const Color(0xFF6A1B9A),
    fields: const [
      PhieuField(key: 'KHOA_BAN_GIAO', label: 'Khoa bàn giao', type: PhieuFieldType.deptSelect,
          defaultValue: 'HSCC - Khoa Cấp Cứu', required: true),
      PhieuField(key: 'KHOA_NHAN', label: 'Khoa nhận', type: PhieuFieldType.deptSelect, required: true),
      PhieuField(key: 'LY_DO_CHUYEN', label: 'Lý do chuyển', type: PhieuFieldType.textLong,
          defaultValue: 'Nhập viện điều trị', required: true),
      PhieuField(key: 'LY_DO_NHAP_VIEN', label: 'Lý do nhập viện', type: PhieuFieldType.textLong),
      PhieuField(key: 'DIEN_BIEN_BENH', label: 'Diễn biến bệnh', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'CHAN_DOAN', label: 'Chẩn đoán', type: PhieuFieldType.icdSuggest, required: true),
      PhieuField(key: 'DA_CAN_THIEP', label: 'Đã can thiệp (thuốc, CLS)', type: PhieuFieldType.textLong),
      PhieuField(key: 'TINH_TRANG_HIEN_TAI', label: 'Tình trạng hiện tại', type: PhieuFieldType.textLong),
      PhieuField(key: 'KE_HOACH_DT_TIEP', label: 'Kế hoạch điều trị tiếp theo', type: PhieuFieldType.textLong),
      PhieuField(key: 'THOI_GIAN_BG', label: 'Thời gian bàn giao', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'BS_BAN_GIAO', label: 'BS bàn giao', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'BS_NHAN', label: 'BS nhận', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên 2 bên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// === CHỈ ĐỊNH CẬN LÂM SÀNG ===

  /// Mps000105 - PHIẾU CHỈ ĐỊNH CLS
  /// Track riêng: theo dõi CLS → có tracking riêng cho phiếu chỉ định
  static final phieuChiDinhCLS = Phieu(
    id: 'Mps000105',
    code: '105',
    name: 'Phiếu chỉ định CLS',
    description: 'Chỉ định xét nghiệm, chẩn đoán hình ảnh, thăm dò chức năng',
    category: PhieuCategory.chanDoan,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.science,
    color: const Color(0xFF00838F),
    fields: const [
      PhieuField(key: 'DICH_VU', label: 'Dịch vụ chỉ định', type: PhieuFieldType.service, required: true),
      PhieuField(key: 'CHAN_DOAN_TRUOC', label: 'Chẩn đoán trước CLS', type: PhieuFieldType.icdText, required: true),
      PhieuField(key: 'MUC_DICH', label: 'Mục đích chỉ định', type: PhieuFieldType.textLong),
      PhieuField(key: 'THOI_GIAN_CHI_DINH', label: 'Thời gian chỉ định', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'BS_CHI_DINH', label: 'BS chỉ định', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// Mps000192 - ĐƠN THUỐC (Bảo hiểm)
  static final phieuDonThuoc = Phieu(
    id: 'Mps000192',
    code: '192',
    name: 'Đơn thuốc BHYT',
    description: 'Đơn thuốc cho bệnh nhân BHYT (theo template chuẩn BYT)',
    category: PhieuCategory.donThuoc,
    saveType: PhieuSaveType.hisAndSignEmr,
    icon: Icons.medication,
    color: const Color(0xFFC62828),
    fields: const [
      PhieuField(key: 'CHAN_DOAN', label: 'Chẩn đoán', type: PhieuFieldType.icd, required: true),
      PhieuField(key: 'DANH_SACH_THUOC', label: 'Danh sách thuốc', type: PhieuFieldType.medicine, required: true),
      PhieuField(key: 'NGAY_TAI_KHAM', label: 'Ngày tái khám', type: PhieuFieldType.date),
      PhieuField(key: 'GHI_CHU', label: 'Ghi chú / Lời dặn', type: PhieuFieldType.textLong),
      PhieuField(key: 'BS_KE_DON', label: 'BS kê đơn', type: PhieuFieldType.text, required: true),
      PhieuField(key: 'SIGN', label: 'Ký tên', type: PhieuFieldType.signature, required: true),
    ],
  );

  /// === CHỈ LƯU HIS (KHÔNG EMR) - Nhập/xuất ===

  /// Mps000037 - PHIẾU THU CÔNG NỢ
  static final phieuThuCongNo = Phieu(
    id: 'Mps000370',
    code: '370',
    name: 'Phiếu thu công nợ',
    description: 'Lưu sổ thu công nợ - chỉ lưu HIS, không EMR',
    category: PhieuCategory.thuPhi,
    saveType: PhieuSaveType.hisOnly,
    icon: Icons.account_balance,
    color: const Color(0xFF558B2F),
    fields: const [
      PhieuField(key: 'SO_TIEN', label: 'Số tiền', type: PhieuFieldType.number, required: true),
      PhieuField(key: 'LY_DO_THU', label: 'Lý do thu', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'NGAY_THU', label: 'Ngày thu', type: PhieuFieldType.date, required: true),
      PhieuField(key: 'NGUOI_NOP', label: 'Người nộp', type: PhieuFieldType.text),
      PhieuField(key: 'BS', label: 'BS xử lý', type: PhieuFieldType.text, required: true),
    ],
  );

  /// Mps000199 - BIÊN BẢN NHẬP
  static final phieuBienBanNhap = Phieu(
    id: 'Mps000199',
    code: '199',
    name: 'Biên bản nhập',
    description: 'Biên bản nhập viện - lưu HIS nội bộ',
    category: PhieuCategory.hanhChinh,
    saveType: PhieuSaveType.hisOnly,
    icon: Icons.fact_check_outlined,
    color: const Color(0xFF607D8B),
    fields: const [
      PhieuField(key: 'THOI_GIAN_NHAP', label: 'Thời gian nhập', type: PhieuFieldType.dateTime, required: true),
      PhieuField(key: 'NOI_NHAP', label: 'Nơi nhập', type: PhieuFieldType.text, defaultValue: 'Khoa Cấp cứu'),
      PhieuField(key: 'LY_DO_NHAP', label: 'Lý do nhập', type: PhieuFieldType.textLong, required: true),
      PhieuField(key: 'CHAN_DOAN', label: 'Chẩn đoán', type: PhieuFieldType.icd),
      PhieuField(key: 'NGUOI_NHAP', label: 'Người nhập', type: PhieuFieldType.text, required: true),
    ],
  );

  /// === DANH SÁCH TẤT CẢ PHIẾU ===

  /// Danh sách theo nhóm (category)
  static final List<Phieu> allPhieu = [
    phieuToDieuTri,           // 062 - Tờ điều trị
    phieuBenhAnCapCuu,        // 374 - Bệnh án cấp cứu
    phieuYeuCauKBVV,          // 007 - Phiếu yêu cầu khám bệnh vào viện
    phieuRaVien,              // 008 - Giấy ra viện
    phieuChuyenVien,          // 009 - Giấy chuyển viện
    phieuHenKham,             // 010 - Giấy hẹn khám
    phieuXacNhan,             // 399 - Giấy xác nhận
    phieuHoiChan,             // 019 - Trích biên bản hội chẩn
    phieuBanGiao,             // HT - Phiếu bàn giao NB chuyển khoa
    phieuChiDinhCLS,          // 105 - Phiếu chỉ định CLS
    phieuDonThuoc,            // 192 - Đơn thuốc BHYT
    phieuThuCongNo,           // 370 - Phiếu thu công nợ
    phieuBienBanNhap,         // 199 - Biên bản nhập
  ];

  /// Lấy phiếu theo ID
  static Phieu? findById(String id) {
    try {
      return allPhieu.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Group phiếu theo category
  static Map<PhieuCategory, List<Phieu>> groupedByCategory() {
    final map = <PhieuCategory, List<Phieu>>{};
    for (final p in allPhieu) {
      map.putIfAbsent(p.category, () => []).add(p);
    }
    return map;
  }
}