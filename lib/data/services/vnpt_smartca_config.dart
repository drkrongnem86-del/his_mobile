// v3.0.28: Cấu hình VNPT SmartCA
// Lưu CLIENT_ID, URL backend, environment
//
// BS cần cung cấp:
//   1. CLIENT_ID (Mobile Code) - VNPT gửi qua email khi BV đăng ký partner
//   2. URL backend trả tranId - server BV cung cấp
//   3. Environment: PRODUCTION hoặc DEVELOPMENT

import 'package:his_mobile/core/security/secure_config_service.dart';

class VnptSmartcaConfig {
  /// v3.0.26: CLIENT_ID (Mobile Code) của BV Ninh Thuận - verified 2026-07-16
  // v3.0.156: Read from SecureConfigService (Android Keystore)
  // Hardcoded fallback removed - use SecureConfigService.getSmartCaClientId()
  static String get clientId => SecureConfigService.instance.getSmartCaClientIdSync();

  /// v3.0.55: URL service ký HIS Pro (C# service chạy trên PC BS port 7654)
  /// - Service này wrap workflow ký thật của HIS Pro desktop:
  ///   App mobile -> HTTP service -> WCF SignProcessor -> KyDienTu.dll -> USB Token
  /// - Service file: hispro_sign_server.exe (compile từ hispro_sign_server.cs)
  /// - Workflow verified ngày 19/7/2026: PDF có PKCS#7 detached signature + cert VNPT SmartCA
  /// - Yêu cầu: HIS Pro desktop + SignAdapter.exe chạy nền (WCF port 8090 listen)
  /// - Có thể override qua Settings (key: vnpt_smartca_url)
  // v3.0.156: Read from SecureConfigService
  static String get transactionApiUrl => SecureConfigService.instance.getSmartCaApiUrlSync();

  /// v3.0.51: Deep link mở app VNPT SmartCA trên điện thoại
  /// Format: vnptsmartca://sign?tranId=<tranId>
  /// Sau khi user ký xong, app VNPT SmartCA sẽ callback về app HIS Mobile
  static const String vnptAppDeepLink = 'vnptsmartca://sign';

  /// v3.0.51: Deep link callback khi VNPT SmartCA ký xong
  /// Format: hismobile://vnpt-callback?tranId=<tranId>&status=success
  static const String callbackDeepLink = 'hismobile://vnpt-callback';

  /// v3.0.26: Environment - PRODUCTION cho app thật, DEVELOPMENT cho test
  static const String environment = 'PRODUCTION';

  /// v3.0.26: Cert serial của BS (từ SmartCA VNPT - verified 2026-07-16 từ ảnh)
  // v3.0.156: Read from SecureConfigService
  static String get certSerial => SecureConfigService.instance.getCertSerialSync();
}
