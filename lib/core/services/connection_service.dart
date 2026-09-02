// ConnectionService v2.75.1
// Wrapper cho HisConfigService - lấy base URLs theo config đã lưu
import 'package:his_mobile/core/services/his_config_service.dart';

class ConnectionService {
  ConnectionService._();
  static final ConnectionService instance = ConnectionService._();

  /// Lấy base URL theo config hiện tại
  /// v2.75.4: Đảm bảo URL luôn có trailing slash
  String _fix(String url) => url.endsWith('/') ? url : '$url/';
  String get acsUrl => _fix(HisConfigService.instance.config.acsUrl);
  String get mosUrl => _fix(HisConfigService.instance.config.mosUrl);
  String get emrUrl => _fix(HisConfigService.instance.config.emrUrl);
  String get sdaUrl => _fix(HisConfigService.instance.config.sdaUrl);
  String get sarUrl => _fix(HisConfigService.instance.config.sarUrl);
  String get fssUrl => _fix(HisConfigService.instance.config.fssUrl);
  String get lisUrl => _fix(HisConfigService.instance.config.lisUrl);
  String get ocrUrl => _fix(HisConfigService.instance.config.ocrUrl);
  String get bvbmUrl => HisConfigService.instance.config.bvbmUrl;

  /// Mode (legacy API - giữ để tương thích)
  String get mode => HisConfigService.instance.config.mode;
  bool get isLan => mode == 'lan';
  bool get isVpn => mode == 'public_vpn';
  bool get isProxy => mode == 'proxy';
  String get modeLabel => isLan ? 'LAN nội bộ' : (isProxy ? 'Proxy qua PC' : 'Public VPN');
  String get modeDesc => isLan
      ? '172.16.1.12 - WiFi nội bộ BV'
      : isProxy
          ? '172.16.200.109:9999 - qua PC BS (cần chạy his_proxy_server.py)'
          : '117.2.25.67 - qua VPN';

  /// Load (no-op - HisConfigService đã load)
  Future<void> load() async {
    // HisConfigService đã load từ main.dart
  }

  /// Set mode + tự động áp dụng preset URL
  Future<void> setMode(String mode) async {
    final preset = mode == 'lan'
        ? HisConfigService.presetLan
        : mode == 'proxy'
            ? HisConfigService.presetProxyPc
            : HisConfigService.presetPublicVpn;
    final c = HisConfigService.instance.config.copyWith(
      mode: mode,
      bvbmUrl: preset.bvbmUrl,
      emrUrl: preset.emrUrl,
      mosUrl: preset.mosUrl,
      sdaUrl: preset.sdaUrl,
      sarUrl: preset.sarUrl,
      fssUrl: preset.fssUrl,
      lisUrl: preset.lisUrl,
      ocrUrl: preset.ocrUrl,
    );
    await HisConfigService.instance.save(c);
  }

  /// ACS URL candidates (Public VPN + LAN) - thử lần lượt khi login
  List<String> get acsUrlCandidates => [
        HisConfigService.presetPublicVpn.bvbmUrl,
        HisConfigService.presetLan.bvbmUrl,
        acsUrl, // current
      ];
}
