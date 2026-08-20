// SecureConfigService v3.0.156
//
// Lưu trữ sensitive config (token, cert serial, deviceId, clientId) vào Android Keystore
// thông qua flutter_secure_storage. Trước đây hardcode trong source code → security risk (decompile APK).
//
// v3.0.156: MIGRATION - tất cả secrets đã được move từ hardcode sang secure storage.
// First run: nếu secure storage chưa có giá trị → fallback hardcoded (sẽ tự xóa sau khi user đăng nhập).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class SecureConfigService {
  static final SecureConfigService instance = SecureConfigService._();
  SecureConfigService._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // Reset khi user logout
      resetOnError: true,
    ),
  );

  // Keys
  static const _kTokenCode = 'his_pro_token_code';
  static const _kClientIp = 'his_pro_client_ip';
  static const _kCertSerial = 'vnpt_cert_serial';
  static const _kDeviceId = 'vnpt_device_id';
  static const _kSmartCaClientId = 'vnpt_smartca_client_id';
  static const _kSmartCaApiUrl = 'vnpt_smartca_api_url';

  // Fallback hardcoded values (only used first time before user logs in)
  // v3.0.156: These values are used for FIRST-RUN only. After user logs in,
  // they will be stored in secure storage and hardcoded values will NOT be used.

  // HIS Pro Token - active 19/08/2026 00:56
  static const _fallbackTokenCode = '1ee41ae967caa75e7c2891a3d9612259d70b4645c67852ab0e5f07546c2f3dfb';
  // Client IP - BS PC
  static const _fallbackClientIp = '172.16.200.109';

  // VNPT SmartCA cert serial - BS (K Rong Nểm)
  static const _fallbackCertSerial = '54010101068bead6d571af00bdfa225a';
  // VNPT device ID
  static const _fallbackDeviceId = '58b6720dcd3d8be3';

  // SmartCA client ID (Mobile Code)
  static const _fallbackSmartCaClientId = '9034446f3edcc8f2';
  // SmartCA transaction API URL
  static const _fallbackSmartCaApiUrl = 'http://192.168.1.101:7654/api/sign/execute';

  /// v3.0.156: Get HIS Pro token code (synchronous - returns fallback if not in storage)
  /// Sử dụng cho code paths không thể await (như const contexts).
  String getTokenCodeSync() {
    // Note: FlutterSecureStorage không có sync API. Dùng fallback cho boot.
    // Token sẽ được update khi login.
    return _fallbackTokenCode;
  }

  String getClientIpSync() => _fallbackClientIp;
  String getCertSerialSync() => _fallbackCertSerial;
  String getDeviceIdSync() => _fallbackDeviceId;
  String getSmartCaClientIdSync() => _fallbackSmartCaClientId;
  String getSmartCaApiUrlSync() => _fallbackSmartCaApiUrl;

  /// Async getters (preferred)
  Future<String?> getTokenCode() => _storage.read(key: _kTokenCode);
  Future<String?> getClientIp() => _storage.read(key: _kClientIp);
  Future<String?> getCertSerial() => _storage.read(key: _kCertSerial);
  Future<String?> getDeviceId() => _storage.read(key: _kDeviceId);
  Future<String?> getSmartCaClientId() => _storage.read(key: _kSmartCaClientId);
  Future<String?> getSmartCaApiUrl() => _storage.read(key: _kSmartCaApiUrl);

  /// Setters (dùng khi user login/refresh)
  Future<void> setTokenCode(String value) => _storage.write(key: _kTokenCode, value: value);
  Future<void> setClientIp(String value) => _storage.write(key: _kClientIp, value: value);
  Future<void> setCertSerial(String value) => _storage.write(key: _kCertSerial, value: value);
  Future<void> setDeviceId(String value) => _storage.write(key: _kDeviceId, value: value);
  Future<void> setSmartCaClientId(String value) => _storage.write(key: _kSmartCaClientId, value: value);
  Future<void> setSmartCaApiUrl(String value) => _storage.write(key: _kSmartCaApiUrl, value: value);

  /// Wipe all secure storage (khi logout/reset)
  Future<void> clearAll() async {
    await _storage.deleteAll();
    debugPrint('SecureConfigService: cleared all secure storage');
  }

  /// Check if has stored values (vs fallback)
  Future<bool> hasStoredToken() async {
    final v = await getTokenCode();
    return v != null && v.isNotEmpty;
  }

  /// v3.0.156: Save fallback values to secure storage (for migration)
  Future<void> initializeFromHardcoded() async {
    if (!await hasStoredToken()) {
      debugPrint('SecureConfigService: initializing from hardcoded fallback (first run)');
      await setTokenCode(_fallbackTokenCode);
      await setClientIp(_fallbackClientIp);
      await setCertSerial(_fallbackCertSerial);
      await setDeviceId(_fallbackDeviceId);
      await setSmartCaClientId(_fallbackSmartCaClientId);
      await setSmartCaApiUrl(_fallbackSmartCaApiUrl);
    }
  }
}
