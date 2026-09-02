// HisConfigService v3.0.62
// v3.0.62: Port từ HIS_ICU v2.35.13
//   + Thêm thongkeBaseUrl + 6 sub-endpoints (login/home/insurance-check/insurance-search/emr-index/emr-search)
//   + Đổi port MOS 1408→1429 (theo v2.35.13 verified)
//   + Đổi port OCR 1429→1425 (lấy chỗ trống vì 1429 đã dùng cho MOS)
//   + Restore script: nếu port sai, dùng restore_v361.bat
// Quản lý cấu hình HIS (URL Backend + tài khoản + khoa)
// Lưu vào SharedPreferences để giữ qua các lần mở app
import 'package:shared_preferences/shared_preferences.dart';

// v3.0.62: Thêm thongkeBaseUrl + 6 sub-endpoints (port từ HIS_ICU v2.35.13)
class HisConfigPreset {
  final String label;
  final String bvbmUrl;
  final String emrUrl;
  final String mosUrl;
  final String sdaUrl;
  final String sarUrl;
  final String fssUrl;
  final String lisUrl;
  final String ocrUrl;
  // v3.0.57: Thêm 4 services mới
  final String dmsUrl;     // 1425 - DMS Medilink HL7
  final String emrWebUrl;  // 1530 - EMR Web Oracle DB (on-demand)
  final String redisUrl;   // 8335 - Redis Cache
  final String vvaUrl;     // 8926 - VVA Backend
  // v3.0.62: Thongke public - 6 sub-endpoints (từ HIS_ICU v2.35.13)
  final String thongkeBaseUrl;          // http://thongke.benhvienninhthuan.vn:8080
  final String thongkeLoginUrl;         // /login
  final String thongkeHomeUrl;          // /home
  final String thongkeInsuranceCheckUrl;// /insurance/check-card
  final String thongkeInsuranceSearchUrl; // /insurance/medicine-search
  final String thongkeEmrIndexUrl;      // /emr/index
  final String thongkeEmrSearchUrl;     // /emr/index/search
  const HisConfigPreset({
    required this.label,
    required this.bvbmUrl,
    required this.emrUrl,
    required this.mosUrl,
    required this.sdaUrl,
    required this.sarUrl,
    required this.fssUrl,
    required this.lisUrl,
    required this.ocrUrl,
    this.dmsUrl = 'http://172.16.9.6:1425/',
    this.emrWebUrl = 'http://172.16.9.6:1530/',
    this.redisUrl = 'http://172.16.9.6:8335/',
    this.vvaUrl = 'http://172.16.9.6:8926/',
    this.thongkeBaseUrl = 'http://thongke.benhvienninhthuan.vn:8080',
    this.thongkeLoginUrl = '/login',
    this.thongkeHomeUrl = '/home',
    this.thongkeInsuranceCheckUrl = '/insurance/check-card',
    this.thongkeInsuranceSearchUrl = '/insurance/medicine-search',
    this.thongkeEmrIndexUrl = '/emr/index',
    this.thongkeEmrSearchUrl = '/emr/index/search',
  });
}

/// v2.76.3: Cách hiển thị tên BN
/// BS chọn 1 trong các chế độ trong Settings
enum NameField {
  /// Tên có dấu - từ HIS Pro uppercase (có thể bị mojibake)
  tdlPatientName,

  /// Tên không dấu - từ HIS Pro (sạch, không lỗi font)
  tdlPatientUnsignedName,

  /// Tên đã verify - từ HIS Pro (chuẩn nhất, có thể thiếu)
  virPatientName,

  /// Tên tiếng Việt từ Data public (HIS Desktop API)
  tenBenhNhan,

  /// Tên từ field legacy BV
  hotenbn,
}

extension NameFieldX on NameField {
  String get key {
    switch (this) {
      case NameField.tdlPatientName:
        return 'tdl_patient_name';
      case NameField.tdlPatientUnsignedName:
        return 'tdl_patient_unsigned_name';
      case NameField.virPatientName:
        return 'vir_patient_name';
      case NameField.tenBenhNhan:
        return 'ten_benh_nhan';
      case NameField.hotenbn:
        return 'hotenbn';
    }
  }

  String get label => name; // Tên enum là tiếng Việt-friendly

  String get description {
    switch (this) {
      case NameField.tdlPatientName:
        return 'Tên có dấu từ HIS Pro (vd: "Nguyễn Văn A")';
      case NameField.tdlPatientUnsignedName:
        return 'Tên không dấu từ HIS Pro (vd: "Nguyen Van A") - sạch nhất';
      case NameField.virPatientName:
        return 'Tên đã verify từ HIS Pro';
      case NameField.tenBenhNhan:
        return 'Tên tiếng Việt từ Data public';
      case NameField.hotenbn:
        return 'Tên từ field legacy BV';
    }
  }
}

class HisConfig {
  // Mode: 'public_vpn' | 'lan'
  final String mode;
  // URLs
  final String bvbmUrl; // Backend (login + DS BN)
  final String acsUrl;  // Auth (1401)
  final String emrUrl;  // EMR (1417)
  // v3.0.62: Đổi port MOS 1408 → 1429 (theo HIS_ICU v2.35.13 verified)
  final String mosUrl;  // MOS / Data (1429 v3.0.62, cũ 1408)
  final String sarUrl;  // SAR / Reports (1409)
  final String sdaUrl;  // SDA / System (1410)
  final String fssUrl;  // FSS / File (1405)
  final String lisUrl;  // LIS / Lab (1419)
  // v3.0.62: Đổi port OCR 1429 → 1425 (lấy chỗ trống vì 1429 đã dùng cho MOS)
  final String ocrUrl;  // OCR / MCH (1425 v3.0.62, cũ 1429)
  // v3.0.57: Thêm 4 services mới
  final String dmsUrl;     // 1425 - DMS Medilink HL7
  final String emrWebUrl;  // 1530 - EMR Web Oracle DB (on-demand)
  final String redisUrl;   // 8335 - Redis Cache
  final String vvaUrl;     // 8926 - VVA Backend
  // v3.0.62: Thongke public - 6 sub-endpoints (từ HIS_ICU v2.35.13)
  final String thongkeBaseUrl;             // http://thongke.benhvienninhthuan.vn:8080
  final String thongkeLoginUrl;            // /login
  final String thongkeHomeUrl;             // /home
  final String thongkeInsuranceCheckUrl;   // /insurance/check-card
  final String thongkeInsuranceSearchUrl;  // /insurance/medicine-search
  final String thongkeEmrIndexUrl;         // /emr/index
  final String thongkeEmrSearchUrl;        // /emr/index/search
  // v2.76.0: Cục KCB gateway (Bộ Y tế)
  final String kcbBaseUrl;     // vd: https://prod.kcb.vn
  final String kcbToken;        // Bearer token (optional)
  final String kcbHospitalCode; // vd: bvdkninhthuan
  final bool useKcbForEmr;      // true = push EMR qua Cục KCB
  // User
  final String loginName;
  final String password;
  final int defaultDeptId; // Mã khoa (mặc định 22)
  final String defaultDeptName; // Tên khoa
  // v2.76.3: Cách hiển thị tên BN
  final NameField nameField;     // Ưu tiên field để hiển thị tên

  const HisConfig({
    this.mode = 'public_vpn',
    this.bvbmUrl = 'http://117.2.25.67:3000',
    this.acsUrl = 'http://172.16.9.6:1401/',
    this.emrUrl = 'http://172.16.9.6:1417/',
    // v3.0.62: 1408 → 1429 (HIS_ICU v2.35.13 verified)
    this.mosUrl = 'http://172.16.9.6:1429/',
    this.sarUrl = 'http://172.16.9.6:1409/',
    this.sdaUrl = 'http://172.16.9.6:1410/',
    this.fssUrl = 'http://172.16.9.6:1405/',
    this.lisUrl = 'http://172.16.9.6:1419/',
    // v3.0.62: 1429 → 1425 (lấy chỗ trống vì 1429 đã dùng cho MOS)
    this.ocrUrl = 'http://172.16.9.6:1425/',
    this.dmsUrl = 'http://172.16.9.6:1425/',
    this.emrWebUrl = 'http://172.16.9.6:1530/',
    this.redisUrl = 'http://172.16.9.6:8335/',
    this.vvaUrl = 'http://172.16.9.6:8926/',
    // v3.0.62: Thongke public endpoints (từ HIS_ICU v2.35.13)
    this.thongkeBaseUrl = 'http://thongke.benhvienninhthuan.vn:8080',
    this.thongkeLoginUrl = '/login',
    this.thongkeHomeUrl = '/home',
    this.thongkeInsuranceCheckUrl = '/insurance/check-card',
    this.thongkeInsuranceSearchUrl = '/insurance/medicine-search',
    this.thongkeEmrIndexUrl = '/emr/index',
    this.thongkeEmrSearchUrl = '/emr/index/search',
    this.kcbBaseUrl = 'https://kcb.vn',
    this.kcbToken = '',
    this.kcbHospitalCode = 'bvdkninhthuan',
    this.useKcbForEmr = true,
    this.loginName = 'nemk',
    this.password = '',
    this.defaultDeptId = 22,
    this.defaultDeptName = 'Khoa Cấp Cứu',
    this.nameField = NameField.tdlPatientUnsignedName, // mặc định: tên không dấu (sạch)
  });

  HisConfig copyWith({
    String? mode,
    String? bvbmUrl,
    String? acsUrl,
    String? emrUrl,
    String? mosUrl,
    String? sarUrl,
    String? sdaUrl,
    String? fssUrl,
    String? lisUrl,
    String? ocrUrl,
    String? dmsUrl,
    String? emrWebUrl,
    String? redisUrl,
    String? vvaUrl,
    String? thongkeBaseUrl,
    String? thongkeLoginUrl,
    String? thongkeHomeUrl,
    String? thongkeInsuranceCheckUrl,
    String? thongkeInsuranceSearchUrl,
    String? thongkeEmrIndexUrl,
    String? thongkeEmrSearchUrl,
    String? kcbBaseUrl,
    String? kcbToken,
    String? kcbHospitalCode,
    bool? useKcbForEmr,
    String? loginName,
    String? password,
    int? defaultDeptId,
    String? defaultDeptName,
    NameField? nameField,
  }) {
    return HisConfig(
      mode: mode ?? this.mode,
      bvbmUrl: bvbmUrl ?? this.bvbmUrl,
      acsUrl: acsUrl ?? this.acsUrl,
      emrUrl: emrUrl ?? this.emrUrl,
      mosUrl: mosUrl ?? this.mosUrl,
      sarUrl: sarUrl ?? this.sarUrl,
      sdaUrl: sdaUrl ?? this.sdaUrl,
      fssUrl: fssUrl ?? this.fssUrl,
      lisUrl: lisUrl ?? this.lisUrl,
      ocrUrl: ocrUrl ?? this.ocrUrl,
      dmsUrl: dmsUrl ?? this.dmsUrl,
      emrWebUrl: emrWebUrl ?? this.emrWebUrl,
      redisUrl: redisUrl ?? this.redisUrl,
      vvaUrl: vvaUrl ?? this.vvaUrl,
      thongkeBaseUrl: thongkeBaseUrl ?? this.thongkeBaseUrl,
      thongkeLoginUrl: thongkeLoginUrl ?? this.thongkeLoginUrl,
      thongkeHomeUrl: thongkeHomeUrl ?? this.thongkeHomeUrl,
      thongkeInsuranceCheckUrl: thongkeInsuranceCheckUrl ?? this.thongkeInsuranceCheckUrl,
      thongkeInsuranceSearchUrl: thongkeInsuranceSearchUrl ?? this.thongkeInsuranceSearchUrl,
      thongkeEmrIndexUrl: thongkeEmrIndexUrl ?? this.thongkeEmrIndexUrl,
      thongkeEmrSearchUrl: thongkeEmrSearchUrl ?? this.thongkeEmrSearchUrl,
      kcbBaseUrl: kcbBaseUrl ?? this.kcbBaseUrl,
      kcbToken: kcbToken ?? this.kcbToken,
      kcbHospitalCode: kcbHospitalCode ?? this.kcbHospitalCode,
      useKcbForEmr: useKcbForEmr ?? this.useKcbForEmr,
      loginName: loginName ?? this.loginName,
      password: password ?? this.password,
      defaultDeptId: defaultDeptId ?? this.defaultDeptId,
      defaultDeptName: defaultDeptName ?? this.defaultDeptName,
      nameField: nameField ?? this.nameField,
    );
  }
}

class HisConfigService {
  HisConfigService._();
  static final HisConfigService instance = HisConfigService._();

  HisConfig _config = const HisConfig();
  HisConfig get config => _config;

  // v3.0.49: 3 preset cho 3 chế độ mạng
  // Mode "Public VPN" - external qua internet (cần OpenVPN)
  // Mode "LAN nội bộ" - WiFi nội bộ BV
  // Mode "Proxy qua PC" - qua PC BS (cần chạy his_proxy_server.py port 9999)
  // v3.0.62: Đổi port MOS 1408→1429 + OCR 1429→1425 (theo HIS_ICU v2.35.13)
  // v3.0.93: Sửa link BVBM → dùng IP public 113.163.187.3 (DataService publicBaseUrl)
  //   + sửa FSS/LIS về LAN (qua VPN) - đỡ rối
  static const HisConfigPreset presetPublicVpn = HisConfigPreset(
    label: 'Public VPN',
    bvbmUrl: 'http://113.163.187.3:3000',  // v3.0.93: Public IP (Y Tế Số / Data public)
    emrUrl: 'http://172.16.9.6:1417',      // HIS Pro EMR (LAN, qua VPN tunnel)
    mosUrl: 'http://172.16.9.6:1429',      // v3.0.62: 1408→1429
    sdaUrl: 'http://172.16.9.6:1410',
    sarUrl: 'http://172.16.9.6:1409',
    fssUrl: 'http://172.16.9.6:1405',
    lisUrl: 'http://172.16.9.6:1419',
    ocrUrl: 'http://172.16.9.6:1425',      // v3.0.62: 1429→1425
  );

  static const HisConfigPreset presetLan = HisConfigPreset(
    label: 'LAN nội bộ',
    bvbmUrl: 'http://172.16.1.12:3000',    // BVBM gateway nội bộ
    emrUrl: 'http://172.16.9.6:1417',
    mosUrl: 'http://172.16.9.6:1429',      // v3.0.62: 1408→1429
    sdaUrl: 'http://172.16.9.6:1410',
    sarUrl: 'http://172.16.9.6:1409',
    fssUrl: 'http://172.16.9.6:1405',
    lisUrl: 'http://172.16.9.6:1419',
    ocrUrl: 'http://172.16.9.6:1425',      // v3.0.62: 1429→1425
  );

  // v3.0.49: Proxy qua PC BS (chạy his_proxy_server.py port 9999)
  // PC BS IP: 172.16.200.109 - proxy forward tới HIS Pro LAN 172.16.9.6
  // Phone gọi qua WiFi/LAN tới PC, PC forward với token đúng
  // v3.0.62: Đổi port proxy theo backend mới (1429 cho MOS, 1425 cho OCR)
  static const HisConfigPreset presetProxyPc = HisConfigPreset(
    label: 'Proxy qua PC',
    bvbmUrl: 'http://172.16.200.109:9999/proxy/bvbm',
    emrUrl: 'http://172.16.200.109:9999/proxy/emr',
    mosUrl: 'http://172.16.200.109:9999/proxy/mos',  // 1429 backend
    sdaUrl: 'http://172.16.200.109:9999/proxy/sda',
    sarUrl: 'http://172.16.200.109:9999/proxy/sar',
    fssUrl: 'http://172.16.200.109:9999/proxy/fss',
    lisUrl: 'http://172.16.200.109:9999/proxy/lis',
    ocrUrl: 'http://172.16.200.109:9999/proxy/ocr',  // 1425 backend
  );

  /// Load config từ SharedPreferences (gọi lúc app init)
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _config = HisConfig(
      mode: prefs.getString('cfg_mode') ?? 'public_vpn',
      bvbmUrl: prefs.getString('cfg_bvbm_url') ?? const HisConfig().bvbmUrl,
      acsUrl: prefs.getString('cfg_acs_url') ?? 'http://172.16.9.6:1401/',
      emrUrl: prefs.getString('cfg_emr_url') ?? const HisConfig().emrUrl,
      mosUrl: prefs.getString('cfg_mos_url') ?? const HisConfig().mosUrl,
      sarUrl: prefs.getString('cfg_sar_url') ?? const HisConfig().sarUrl,
      sdaUrl: prefs.getString('cfg_sda_url') ?? const HisConfig().sdaUrl,
      fssUrl: prefs.getString('cfg_fss_url') ?? const HisConfig().fssUrl,
      lisUrl: prefs.getString('cfg_lis_url') ?? const HisConfig().lisUrl,
      ocrUrl: prefs.getString('cfg_ocr_url') ?? const HisConfig().ocrUrl,
      dmsUrl: prefs.getString('cfg_dms_url') ?? const HisConfig().dmsUrl,
      emrWebUrl: prefs.getString('cfg_emr_web_url') ?? const HisConfig().emrWebUrl,
      redisUrl: prefs.getString('cfg_redis_url') ?? const HisConfig().redisUrl,
      vvaUrl: prefs.getString('cfg_vva_url') ?? const HisConfig().vvaUrl,
      // v3.0.62: Thongke public endpoints
      thongkeBaseUrl: prefs.getString('cfg_thongke_base_url') ?? const HisConfig().thongkeBaseUrl,
      thongkeLoginUrl: prefs.getString('cfg_thongke_login_url') ?? const HisConfig().thongkeLoginUrl,
      thongkeHomeUrl: prefs.getString('cfg_thongke_home_url') ?? const HisConfig().thongkeHomeUrl,
      thongkeInsuranceCheckUrl: prefs.getString('cfg_thongke_insurance_check_url') ?? const HisConfig().thongkeInsuranceCheckUrl,
      thongkeInsuranceSearchUrl: prefs.getString('cfg_thongke_insurance_search_url') ?? const HisConfig().thongkeInsuranceSearchUrl,
      thongkeEmrIndexUrl: prefs.getString('cfg_thongke_emr_index_url') ?? const HisConfig().thongkeEmrIndexUrl,
      thongkeEmrSearchUrl: prefs.getString('cfg_thongke_emr_search_url') ?? const HisConfig().thongkeEmrSearchUrl,
      kcbBaseUrl: prefs.getString('cfg_kcb_base_url') ?? const HisConfig().kcbBaseUrl,
      kcbToken: prefs.getString('cfg_kcb_token') ?? '',
      kcbHospitalCode: prefs.getString('cfg_kcb_hospital') ?? 'bvdkninhthuan',
      useKcbForEmr: prefs.getBool('cfg_use_kcb_for_emr') ?? true,
      loginName: prefs.getString('cfg_login_name') ?? 'nemk',
      password: prefs.getString('cfg_password') ?? '',
      defaultDeptId: prefs.getInt('cfg_default_dept_id') ?? 22,
      defaultDeptName:
          prefs.getString('cfg_default_dept_name') ?? 'Khoa Cấp Cứu',
      nameField: NameField.values.firstWhere(
        (e) => e.key == prefs.getString('cfg_name_field'),
        orElse: () => NameField.tdlPatientUnsignedName,
      ),
    );
  }

  /// Save config + notify listeners
  Future<void> save(HisConfig c) async {
    _config = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cfg_mode', c.mode);
    await prefs.setString('cfg_bvbm_url', c.bvbmUrl);
    await prefs.setString('cfg_acs_url', c.acsUrl);
    await prefs.setString('cfg_emr_url', c.emrUrl);
    await prefs.setString('cfg_mos_url', c.mosUrl);
    await prefs.setString('cfg_sar_url', c.sarUrl);
    await prefs.setString('cfg_sda_url', c.sdaUrl);
    await prefs.setString('cfg_fss_url', c.fssUrl);
    await prefs.setString('cfg_lis_url', c.lisUrl);
    await prefs.setString('cfg_ocr_url', c.ocrUrl);
    // v3.0.57: 4 services mới
    await prefs.setString('cfg_dms_url', c.dmsUrl);
    await prefs.setString('cfg_emr_web_url', c.emrWebUrl);
    await prefs.setString('cfg_redis_url', c.redisUrl);
    await prefs.setString('cfg_vva_url', c.vvaUrl);
    // v3.0.62: 7 thongke endpoints
    await prefs.setString('cfg_thongke_base_url', c.thongkeBaseUrl);
    await prefs.setString('cfg_thongke_login_url', c.thongkeLoginUrl);
    await prefs.setString('cfg_thongke_home_url', c.thongkeHomeUrl);
    await prefs.setString('cfg_thongke_insurance_check_url', c.thongkeInsuranceCheckUrl);
    await prefs.setString('cfg_thongke_insurance_search_url', c.thongkeInsuranceSearchUrl);
    await prefs.setString('cfg_thongke_emr_index_url', c.thongkeEmrIndexUrl);
    await prefs.setString('cfg_thongke_emr_search_url', c.thongkeEmrSearchUrl);
    await prefs.setString('cfg_kcb_base_url', c.kcbBaseUrl);
    await prefs.setString('cfg_kcb_token', c.kcbToken);
    await prefs.setString('cfg_kcb_hospital', c.kcbHospitalCode);
    await prefs.setBool('cfg_use_kcb_for_emr', c.useKcbForEmr);
    await prefs.setString('cfg_login_name', c.loginName);
    await prefs.setString('cfg_password', c.password);
    await prefs.setInt('cfg_default_dept_id', c.defaultDeptId);
    await prefs.setString('cfg_default_dept_name', c.defaultDeptName);
    await prefs.setString('cfg_name_field', c.nameField.key);
  }

  /// Apply preset to current config
  Future<void> applyPreset(HisConfigPreset preset) async {
    final c = _config.copyWith(
      bvbmUrl: preset.bvbmUrl,
      emrUrl: preset.emrUrl,
      mosUrl: preset.mosUrl,
      sdaUrl: preset.sdaUrl,
      sarUrl: preset.sarUrl,
      fssUrl: preset.fssUrl,
      lisUrl: preset.lisUrl,
      ocrUrl: preset.ocrUrl,
      dmsUrl: preset.dmsUrl,
      emrWebUrl: preset.emrWebUrl,
      redisUrl: preset.redisUrl,
      vvaUrl: preset.vvaUrl,
      // v3.0.62: Apply thongke URLs from preset
      thongkeBaseUrl: preset.thongkeBaseUrl,
      thongkeLoginUrl: preset.thongkeLoginUrl,
      thongkeHomeUrl: preset.thongkeHomeUrl,
      thongkeInsuranceCheckUrl: preset.thongkeInsuranceCheckUrl,
      thongkeInsuranceSearchUrl: preset.thongkeInsuranceSearchUrl,
      thongkeEmrIndexUrl: preset.thongkeEmrIndexUrl,
      thongkeEmrSearchUrl: preset.thongkeEmrSearchUrl,
    );
    await save(c);
  }

  /// Reset về default
  Future<void> reset() async {
    await save(const HisConfig());
  }

  /// v2.76.3: Update NameField (cách hiển thị tên BN)
  Future<void> updateNameField(NameField field) async {
    final c = _config.copyWith(nameField: field);
    await save(c);
  }
}
