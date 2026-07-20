/// HIS Pro Mobile - Application Constants
/// Cấu hình kết nối HIS Pro Backend
///
/// Server VPN: 117.2.25.67 (từ ConfigSystem-vpn.xml)
/// Khi kết nối VPN BV, traffic sẽ route đến server này
/// v3.0.62: Server này cung cấp ACS (1401), MCH (1425 - v3.0.62 đổi từ 1429), MOS (1429 - v3.0.62 đổi từ 1408), SDA (1410)...
/// NẾU port sai, dùng restore_v361.bat để quay lại v3.0.61

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'HIS MOBILE';
  static const String appVersion = '3.0.63';
  static const String hospitalFullName = 'Bệnh Viện Đa khoa Ninh Thuận';

  // v2.75.0: 2 chế độ kết nối
  // 1. Hiện tại (LAN nội bộ BV qua WiFi/VPN) - 172.16.9.6
  // 2. Qua VPN (External qua internet) - 117.2.25.67
  static const String lanAcsUrl = 'http://172.16.9.6:1401/';
  static const String lanEmrUrl = 'http://172.16.9.6:1417/';
  static const String lanSdaUrl = 'http://172.16.9.6:1410/';
  // v3.0.62: Đổi port MOS 1408 → 1429 (theo HIS_ICU v2.35.13)
  static const String lanMosUrl = 'http://172.16.9.6:1429/';
  static const String lanFssUrl = 'http://172.16.9.6:1405/';
  static const String lanLisUrl = 'http://172.16.9.6:1419/';

  // v2.75.0: Connection mode
  static const String connectionModeLan = 'lan';
  static const String connectionModeVpn = 'vpn';
  static const String defaultConnectionMode = connectionModeLan;

  // VPN Gateway
  static const String vpnHost = '113.176.81.193';
  static const int vpnPort = 8443;

  // HIS Pro Backend URLs
  // Server chính: 172.16.9.6 (IP nội bộ bệnh viện - qua VPN)
  // v3.0.62: MCH/OCR đổi 1429 → 1425, MOS đổi 1408 → 1429

  static const List<String> acsBaseUrlCandidates = [
    'http://172.16.9.6:1401/',    // ✅ IP nội bộ (chính)
  ];

  static const List<String> mchBaseUrlCandidates = [
    'http://172.16.9.6:1425/',    // v3.0.62: 1429 → 1425
  ];

  // Default - đã đúng
  static const String acsBaseUrl = 'http://172.16.9.6:1401/';
  // v3.0.62: MCH/OCR đổi 1429 → 1425
  static const String mchBaseUrl = 'http://172.16.9.6:1425/';
  // Legacy: thongkeBaseUrl giờ trỏ về HIS Pro VPN (acquire được qua OpenVPN BV)
  static const String thongkeBaseUrl = 'http://172.16.9.6:1401';
  static const String dashboardBaseUrl = 'http://172.16.212.213:5173/api';

  // MOS - Medical Office System
  // v3.0.62: Đổi 1408 → 1429 (theo HIS_ICU v2.35.13)
  static const String mosBaseUrl = 'http://172.16.9.6:1429/';
  
  // SDA - System Data Admin
  static const String sdaBaseUrl = 'http://172.16.9.6:1410/';
  
  // SAR - Statistical Analysis Report
  static const String sarBaseUrl = 'http://172.16.9.6:1409/';
  
  // MRS - Medical Record Summary
  static const String mrsBaseUrl = 'http://117.2.25.67:1413/';
  
  // v3.0.42: Update URL cho chuẩn (LAN BV 172.16.9.6 thay vì VPN 117.2.25.67)
  // LIS - Laboratory Information System
  static const String lisBaseUrl = 'http://172.16.9.6:1419/';

  // FSS - Financial System
  static const String fssBaseUrl = 'http://172.16.9.6:1405/';

  // EMR - Electronic Medical Record (HIS Pro 1417 - qua LAN BV hoặc VPN)
  static const String emrBaseUrl = 'http://172.16.9.6:1417/';
  
  // PACS - Picture Archiving (cần VPN nội bộ)
  static const String pacsBaseUrl = 'http://192.168.1.200:5000/';

  // Department IDs từ HIS Pro thực tế
  static const int DEPARTMENT_ID_CAP_CUU = 22;  // HSCC
  static const int DEPARTMENT_ID_HS_TICH_CUC = 24;  // Hồi sức tích cực chống độc
  static const int DEPARTMENT_ID_GAY_ME = 25;  // Gây mê hồi sức
  static const int ROOM_ID_KHAM_CAP_CUU = 39;  // PKCC
  static const String DEPARTMENT_CODE_CAP_CUU = 'HSCC';

  /// Danh sách các khoa trong BV - Mapping từ Y Tế Số mobile (log 2026-07-06)
  /// 29 khoa HIS + một số khoa CS2/bổ sung
  /// Theo `parse_log10.py` - data thật từ app Y Tế Số BS đang dùng
  static const List<Map<String, dynamic>> departments = [
    // === 29 khoa HIS chính (id 22-71) ===
    {'id': 22, 'code': 'HSCC', 'name': 'Khoa Cấp Cứu', 'icon': '🚨'},
    // v2.45.0: id=23 (CCS - Cấp Cứu Sản) returns 0 BN. Real "Khoa Phụ sản" = id=38 (KPS)
    {'id': 38, 'code': 'KPS', 'name': 'Khoa Phụ sản', 'icon': '🤰'},
    {'id': 23, 'code': 'CCS', 'name': 'Khoa Phụ sản_CCS (Cấp Cứu Sản)', 'icon': '🤰'},
    {'id': 24, 'code': 'DTYC', 'name': 'Khoa Khám bệnh, chữa bệnh theo yêu cầu', 'icon': '🩺'},
    {'id': 26, 'code': 'DVNTK', 'name': 'Khoa Ngoại thần kinh', 'icon': '🧠'},
    {'id': 27, 'code': 'DVTMCT', 'name': 'Khoa Tim Mạch Can Thiệp', 'icon': '❤️'},
    {'id': 29, 'code': 'HSTC', 'name': 'Hồi Sức Tích Cực Chống Độc', 'icon': '⚡'},
    {'id': 30, 'code': 'NTK', 'name': 'Khoa Thần kinh', 'icon': '🧠'},
    {'id': 31, 'code': 'NTTN', 'name': 'Khoa Nội thận - tiết niệu', 'icon': '🫘'},
    {'id': 32, 'code': 'KM', 'name': 'Khoa Mắt', 'icon': '👁️'},
    {'id': 33, 'code': 'NGCT', 'name': 'Khoa Chấn thương chỉnh hình', 'icon': '🦴'},
    {'id': 34, 'code': 'NGTH', 'name': 'Khoa Ngoại tổng hợp', 'icon': '🩻'},
    {'id': 35, 'code': 'KN', 'name': 'Khoa Nhi', 'icon': '👶'},
    {'id': 36, 'code': 'NTM', 'name': 'Khoa Nội tim mạch', 'icon': '❤️'},
    {'id': 37, 'code': 'KNTH', 'name': 'Khoa Nội tổng hợp', 'icon': '🫀'},
    {'id': 38, 'code': 'KPS', 'name': 'Khoa Phụ sản', 'icon': '🤰'},
    {'id': 39, 'code': 'KTNT', 'name': 'Khoa Thận Nhân Tạo', 'icon': '🫘'},
    {'id': 40, 'code': 'PTGMHS', 'name': 'Khoa Gây mê hồi sức', 'icon': '💉'},
    {'id': 41, 'code': 'KRHM', 'name': 'Khoa Răng - Hàm - Mặt', 'icon': '🦷'},
    {'id': 42, 'code': 'KTMH', 'name': 'Khoa Tai - Mũi - Họng', 'icon': '👂'},
    {'id': 43, 'code': 'KTN', 'name': 'Khoa Truyền Nhiễm', 'icon': '🦠'},
    {'id': 44, 'code': 'KYHCT', 'name': 'Khoa Y dược cổ truyền - Phục hồi chức năng', 'icon': '🌿'},
    {'id': 45, 'code': 'KKB', 'name': 'Khoa Khám bệnh', 'icon': '🩺'},
    {'id': 46, 'code': 'KUB', 'name': 'Khoa Ung bướu (điều trị tia xạ)', 'icon': '🎗️'},
    {'id': 53, 'code': 'KSNK', 'name': 'Khoa Kiểm Soát Nhiễm Khuẩn', 'icon': '🦠'},
    {'id': 65, 'code': 'PTP', 'name': 'Phòng Thu Phí', 'icon': '💰'},
    // v2.79.0: HSCCL/CCSVL alias trỏ về NTHCL (đã có BN mẫu)
    {'id': 68, 'code': 'HSCCL', 'name': 'Khoa Nội Tổng Hợp (Mới)', 'icon': '🫀'},
    {'id': 69, 'code': 'CCSVL', 'name': 'Khoa Nội Tổng Hợp (Mới) CS', 'icon': '🫀'},
    {'id': 70, 'code': 'KDTTHVN', 'name': 'Khoa Điều Trị Tổng Hợp Văn Lâm', 'icon': '🏥'},
    {'id': 71, 'code': 'DTCCLuu', 'name': 'Cấp Cứu Lưu', 'icon': '🚨'},
    // === Khoa bổ sung (id 102+) ===
    {'id': 102, 'code': 'DVNTTN', 'name': 'Khoa Ngoại thận - tiết niệu', 'icon': '🩻'},
    {'id': 122, 'code': 'GTVT', 'name': 'Khu Giao Thông Vận Tải', 'icon': '🚗'},
    {'id': 123, 'code': 'NTHCL', 'name': 'Khu Nội Tổng Hợp (Mới)', 'icon': '🫀'},
    {'id': 142, 'code': 'KYHCTCS2', 'name': 'Khoa Y Dược Cổ Truyền CS2', 'icon': '🌿'},
    {'id': 182, 'code': 'COVID_KHUB', 'name': 'Khoa điều trị Covid19 - Khu B', 'icon': '🦠'},
    {'id': 202, 'code': 'KKB_CS2', 'name': 'Khoa Khám bệnh CS2', 'icon': '🩺'},
    {'id': 203, 'code': 'KCC_CS2', 'name': 'Khoa Cấp Cứu CS2', 'icon': '🚨'},
    {'id': 210, 'code': 'CDHA_CS2', 'name': 'Khoa Chẩn đoán hình ảnh CS2', 'icon': '🩻'},
    {'id': 211, 'code': 'TDCN_CS2', 'name': 'Khoa Thăm dò chức năng CS2', 'icon': '📊'},
    {'id': 223, 'code': 'DTCCLUUCS2', 'name': 'Cấp Cứu Lưu Cơ Sở 2', 'icon': '🚨'},
    {'id': 242, 'code': 'KDYCS2', 'name': 'Khoa Y Học Cổ Truyền CS2', 'icon': '🌿'},
    {'id': 262, 'code': 'KRHM_CS2', 'name': 'Khoa Răng Hàm Mặt CS2', 'icon': '🦷'},
    {'id': 282, 'code': 'KTMH_CS2', 'name': 'Khoa Tai Mũi Họng CS2', 'icon': '👂'},
    {'id': 283, 'code': 'KM_CS2', 'name': 'Khoa Mắt CS2', 'icon': '👁️'},
    {'id': 302, 'code': 'KNTH_CS2', 'name': 'Khoa Nội tổng hợp CS2', 'icon': '🫀'},
    {'id': 322, 'code': 'NOILK', 'name': 'Khoa Lão học', 'icon': '👴'},
    {'id': 342, 'code': 'KNGOAITH_CS2', 'name': 'Khoa Ngoại tổng hợp CS2', 'icon': '🩻'},
    {'id': 362, 'code': 'COVID_NHI', 'name': 'Khu điều trị Covid-19 3A', 'icon': '🦠'},
    {'id': 382, 'code': 'DVSS', 'name': 'Khoa Sơ sinh', 'icon': '👶'},
    {'id': 422, 'code': 'DVHH', 'name': 'Khoa Nội hô hấp', 'icon': '🫁'},
    {'id': 442, 'code': 'KDTPN', 'name': 'Khu ĐT Phạm Nhân', 'icon': '🔒'},
    {'id': 462, 'code': 'KCG', 'name': 'Khoa Khám Chuyên Gia', 'icon': '🩺'},
    {'id': 502, 'code': 'DTTN', 'name': 'Khu Điều Trị Trong Ngày', 'icon': '🏥'},
    // v2.47.0: thêm các khoa phát hiện từ data thật (500 BN từ EMR-Checker)
    {'id': 522, 'code': 'KSKCB', 'name': 'Khoa Khám sức khỏe cán bộ', 'icon': '🩺'},
  ];

  /// Danh sách PHÒNG (buồng) đầy đủ 53 buồng - từ ảnh chụp danh sách BV (2026-07-07)
  /// v2.35.12: id = ROOM_ID thật, deptId = DEPARTMENT_ID
  /// Mỗi entry = 1 buồng thật trong BV
  static const List<Map<String, dynamic>> rooms = [
    // Cấp Cứu Lưu (id 71) - 2 buồng
    {'id': 218, 'code': 'CKCCL', 'name': 'Phòng Cấp Cứu Lưu', 'deptId': 71, 'icon': '🚨'},
    {'id': 219, 'code': 'CC_Luu', 'name': 'Cấp Cứu Lưu', 'deptId': 71, 'icon': '🚨'},
    // Cấp Cứu Lưu Cơ Sở (id 223)
    {'id': 1820, 'code': 'DTCCLuuCS', 'name': 'Điều trị cấp cứu lưu', 'deptId': 223, 'icon': '🚨'},
    // Hồi Sức Tích Cực (id 29) - 2 buồng
    {'id': 223, 'code': 'DT_HSTCCD', 'name': 'Điều Trị Hồi Sức Tích Cực', 'deptId': 29, 'icon': '⚡'},
    {'id': 3322, 'code': 'DTBNCV', 'name': 'Điều Trị Bệnh Nhân Covid', 'deptId': 29, 'icon': '🦠'},
    // Khoa Cấp Cứu (id 22 HSCC)
    {'id': 224, 'code': 'DT_CC', 'name': 'Điều Trị Khoa Cấp Cứu', 'deptId': 22, 'icon': '🚨'},
    // Khoa Chấn thương (id 33 NGCT)
    {'id': 232, 'code': 'DT_NCT', 'name': 'Điều Trị Ngoại Chấn Thương', 'deptId': 33, 'icon': '🦴'},
    // Khoa điều trị Covid19 (id 182 COVID_KHUB)
    {'id': 1726, 'code': 'DT_COVID_KHUB', 'name': 'Điều trị hồi sức Covid', 'deptId': 182, 'icon': '🦠'},
    // Khoa Gây mê hồi sức (id 40 PTGMHS)
    {'id': 239, 'code': 'DT_GMHS', 'name': 'Điều Trị Gây Mê Hồi Sức', 'deptId': 40, 'icon': '💉'},
    // Khoa Kiểm Soát (id 53 KSNK)
    {'id': 230, 'code': 'DT_KSNK', 'name': 'Điều Trị Kiểm Soát Nhiễm Khuẩn', 'deptId': 53, 'icon': '🦠'},
    // Khoa Khám bệnh (id 45 KKB) - 3 buồng
    {'id': 228, 'code': 'DTNgT', 'name': 'Điều Trị Ngoại Trú KKB', 'deptId': 45, 'icon': '🩺'},
    {'id': 220, 'code': 'DT_DTTYC', 'name': 'Điều Trị Theo Yêu Cầu', 'deptId': 24, 'icon': '🩺'},
    {'id': 4242, 'code': 'DTKPS', 'name': 'Điều Trị Phụ Sản (DTYC)', 'deptId': 24, 'icon': '🤰'},
    // Khoa Lão học (id 322 NOILK)
    {'id': 2345, 'code': 'DT_DVNLK', 'name': 'Điều Trị Khoa Lão', 'deptId': 322, 'icon': '👴'},
    // Khoa Mắt (id 32 KM)
    {'id': 231, 'code': 'DT_KM', 'name': 'Điều Trị Khoa Mắt', 'deptId': 32, 'icon': '👁️'},
    // Khoa Nội hô hấp (id 422 DVHH)
    {'id': 3222, 'code': 'DTKHH', 'name': 'Điều Trị Khoa Nội Hô Hấp', 'deptId': 422, 'icon': '🫁'},
    // Khoa Nội tim mạch (id 36 NTM)
    {'id': 237, 'code': 'DT_NTM', 'name': 'Điều Trị Nội Tim Mạch', 'deptId': 36, 'icon': '❤️'},
    // Khoa Nội tổng hợp (id 37 KNTH) - 5 buồng
    {'id': 1083, 'code': 'DTHHLS', 'name': 'Điều Trị Huyết Học Lâm Sàng', 'deptId': 37, 'icon': '🩸'},
    {'id': 3882, 'code': 'DTTH', 'name': 'Điều Trị Tiêu hóa', 'deptId': 37, 'icon': '🫁'},
    {'id': 3883, 'code': 'DTNT', 'name': 'Điều Trị Nội Tiết', 'deptId': 37, 'icon': '💉'},
    {'id': 238, 'code': 'DT_NTH', 'name': 'Điều Trị Nội Tổng Hợp', 'deptId': 37, 'icon': '🫀'},
    // Khoa Nội thận - tiết niệu (id 31 NTTN)
    {'id': 236, 'code': 'DT_TTN', 'name': 'Điều Trị Nội Thận Tiết Niệu', 'deptId': 31, 'icon': '🫘'},
    // Khoa Ngoại tổng hợp (id 34 NGTH) - 2 buồng
    {'id': 233, 'code': 'DT_NgTH', 'name': 'Điều Trị Ngoại Tổng Hợp', 'deptId': 34, 'icon': '🩻'},
    {'id': 2330, 'code': 'DT_NgTH_2', 'name': 'Điều trị Ngoại Tổng Hợp 2', 'deptId': 34, 'icon': '🩻'},
    // Khoa Ngoại thận - tiết niệu (id 102 DVNTTN)
    {'id': 3182, 'code': 'DT_NGTTN', 'name': 'Điều trị Khoa Ngoại thận', 'deptId': 102, 'icon': '🩻'},
    // Khoa Ngoại thần kinh (id 26 DVNTK)
    {'id': 221, 'code': 'DT_NgTK', 'name': 'Điều Trị Khoa Ngoại Thần Kinh', 'deptId': 26, 'icon': '🧠'},
    // Khoa Nhi (id 35 KN)
    {'id': 234, 'code': 'DT_KN', 'name': 'Điều Trị Khoa Nhi', 'deptId': 35, 'icon': '👶'},
    // Khoa Phụ sản (id 38 KPS) - 2 buồng
    {'id': 582, 'code': 'BB_KPS', 'name': 'Buồng bệnh_Khoa sản - DTYC', 'deptId': 38, 'icon': '🤰'},
    {'id': 240, 'code': 'DT_PS', 'name': 'Điều Trị Khoa Phụ Sản', 'deptId': 38, 'icon': '🤰'},
    // Khoa Phụ sản_CCS (id 23 CCS)
    {'id': 225, 'code': 'DT_CCS', 'name': 'Điều Trị Khoa Cấp Cứu Sản', 'deptId': 23, 'icon': '🤰'},
    // Khoa Răng - Hàm - Mặt (id 41 KRHM) - 3 buồng
    {'id': 241, 'code': 'DT_K_RHM', 'name': 'Điều Trị Khoa RHM', 'deptId': 41, 'icon': '🦷'},
    {'id': 242, 'code': 'DT_NGT_RHM', 'name': 'Ngoại Trú Răng Hàm Mặt', 'deptId': 41, 'icon': '🦷'},
    {'id': 2420, 'code': 'NGT_RHM_2', 'name': 'Ngoại trú Răng Hàm Mặt (CS)', 'deptId': 41, 'icon': '🦷'},
    // Khoa Sơ sinh (id 382 DVSS)
    {'id': 3086, 'code': 'DT_DVSS', 'name': 'Điều trị Đơn vị Sơ sinh', 'deptId': 382, 'icon': '👶'},
    // Khoa Tai - Mũi - Họng (id 42 KTMH)
    {'id': 243, 'code': 'DT_TMH', 'name': 'Điều Trị Tai Mũi Họng', 'deptId': 42, 'icon': '👂'},
    // Khoa Tim Mạch Can Thiệp (id 27 DVTMCT)
    {'id': 222, 'code': 'DT_DVTMCT', 'name': 'Điều Trị Khoa Tim Mạch Can Thiệp', 'deptId': 27, 'icon': '❤️'},
    // Khoa Thần kinh (id 30 NTK)
    {'id': 235, 'code': 'DT_NTK', 'name': 'Điều Trị Nội Thần Kinh', 'deptId': 30, 'icon': '🧠'},
    // Khoa Thận Nhân Tạo (id 39 KTNT) - 217 BN ngoại trú
    {'id': 245, 'code': 'NGTR_TNT', 'name': 'Phòng Ngoại Trú Thận Nhân Tạo', 'deptId': 39, 'icon': '🫘'},
    // Khoa Truyền Nhiễm (id 43 KTN)
    {'id': 246, 'code': 'DT_TN', 'name': 'Điều Trị Khoa Truyền Nhiễm', 'deptId': 43, 'icon': '🦠'},
    // Khoa Ung bướu (id 46 KUB) - 2 buồng
    {'id': 247, 'code': 'DT_UB', 'name': 'Điều Trị Khoa Ung Bướu', 'deptId': 46, 'icon': '🎗️'},
    {'id': 3282, 'code': 'DTNTUB', 'name': 'Phòng Ngoại Trú Ung Bướu', 'deptId': 46, 'icon': '🎗️'},
    // Khoa Y dược cổ truyền (id 44 KYHCT) - 4 buồng
    {'id': 1502, 'code': 'DTYHCTCS2', 'name': 'Điều Trị YHCT-Cơ sở 2', 'deptId': 142, 'icon': '🌿'},
    {'id': 248, 'code': 'DT_PHCN', 'name': 'Điều Trị PHCN', 'deptId': 44, 'icon': '🌿'},
    {'id': 249, 'code': 'DT_YDTT', 'name': 'Điều Trị YHCT', 'deptId': 44, 'icon': '🌿'},
    {'id': 250, 'code': 'NTYHCT', 'name': 'Phòng Ngoại Trú YHCT', 'deptId': 44, 'icon': '🌿'},
    // Khoa Y Học Cổ (id 242)
    {'id': 2500, 'code': 'NTYHCT_CS2', 'name': 'Phòng Ngoại Trú YHCT CS2', 'deptId': 242, 'icon': '🌿'},
    // Khu điều trị Covid-19 3A (id 362 COVID_NHI)
    {'id': 2547, 'code': 'DTCVNHI', 'name': 'Điều trị Covid-19 3A', 'deptId': 362, 'icon': '🦠'},
    // khu ĐT Phạm Nhân (id 442 KDTPN)
    {'id': 3342, 'code': 'DTPN', 'name': 'Điều Trị Phạm Nhân', 'deptId': 442, 'icon': '🔒'},
    // Khu Giao Thông Vận Tải (id 122 GTVT)
    {'id': 1423, 'code': 'DT_GTVT', 'name': 'Điều Trị Giao Thông Vận Tải', 'deptId': 122, 'icon': '🚗'},
    // Khu Nội Tổng Hợp (Mới) (id 123 NTHCL)
    {'id': 1422, 'code': 'DT_NTHCL', 'name': 'Điều Trị Khu Nội Tổng Hợp (Mới)', 'deptId': 123, 'icon': '🫀'},
    // Phòng Thu Phí (id 65 PTP)
    {'id': 1542, 'code': 'BBVP', 'name': 'Viện phí nhập cồn', 'deptId': 65, 'icon': '💰'},
    // YC_ Khoa Nhi (id 482)
    {'id': 3602, 'code': 'BDTKN', 'name': 'YC_Điều Trị Khoa Nhi', 'deptId': 482, 'icon': '👶'},
  ];

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Pagination
  static const int defaultPageSize = 100;

  // Cache Duration
  static const Duration cacheDuration = Duration(minutes: 30);

  // Storage Keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
  static const String keyLoginName = 'login_name';
  static const String keyDepartmentId = 'department_id';
  static const String keyDepartmentName = 'department_name';
  static const String keyRoomId = 'room_id';
  static const String keyRoomName = 'room_name';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyVpnConnected = 'vpn_connected';
}

/// HIS Service Types
enum HisServiceType {
  acs('ACS', 'Xác thực', 'acs'),
  mch('MCH', 'Nghiệp vụ Khám chữa bệnh', 'mch'),
  mos('MOS', 'Hệ thống Y tế', 'mos'),
  emr('EMR', 'Bệnh án Điện tử', 'emr'),
  sda('SDA', 'Danh mục Quản trị', 'sda'),
  sar('SAR', 'Báo cáo Thống kê', 'sar'),
  mrs('MRS', 'Tổng hợp Bệnh án', 'mrs'),
  lis('LIS', 'Hệ thống Xét nghiệm', 'lis'),
  fss('FSS', 'Hệ thống Tài chính', 'fss'),
  pacs('PACS', 'Hệ thống PACS', 'pacs');

  final String code;
  final String name;
  final String key;

  const HisServiceType(this.code, this.name, this.key);

  String getBaseUrl() {
    switch (this) {
      case HisServiceType.acs: return AppConstants.acsBaseUrl;
      case HisServiceType.mch: return AppConstants.mchBaseUrl;
      case HisServiceType.mos: return AppConstants.mosBaseUrl;
      case HisServiceType.emr: return AppConstants.emrBaseUrl;
      case HisServiceType.sda: return AppConstants.sdaBaseUrl;
      case HisServiceType.sar: return AppConstants.sarBaseUrl;
      case HisServiceType.mrs: return AppConstants.mrsBaseUrl;
      case HisServiceType.lis: return AppConstants.lisBaseUrl;
      case HisServiceType.fss: return AppConstants.fssBaseUrl;
      case HisServiceType.pacs: return AppConstants.pacsBaseUrl;
    }
  }
}
