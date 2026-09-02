// SecureStorageService v3.0.34 - Lưu token vào Android Keystore / iOS Keychain
// Thay thế SharedPreferences plaintext cho Bearer token
//
// Lưu ý: SharedPreferences vẫn dùng cho config khác (URL, theme, dept...)
//          vì không cần bảo mật cao
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._();
  SecureStorageService._();

  // Android: EncryptedSharedPreferences (AES)
  // iOS: Keychain
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  /// Keys
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kCustomBearer = 'custom_bearer';

  /// Save Bearer access token (sau khi login thật)
  Future<void> saveAccessToken(String token) async {
    try {
      await _storage.write(key: _kAccessToken, value: token);
      debugPrint('SecureStorage: saved access_token (${token.length} chars)');
    } catch (e) {
      debugPrint('SecureStorage saveAccessToken error: $e');
    }
  }

  /// Read access token
  Future<String?> readAccessToken() async {
    try {
      return await _storage.read(key: _kAccessToken);
    } catch (e) {
      debugPrint('SecureStorage readAccessToken error: $e');
      return null;
    }
  }

  /// Save refresh token (do backend quản lý)
  Future<void> saveRefreshToken(String token) async {
    try {
      await _storage.write(key: _kRefreshToken, value: token);
      debugPrint('SecureStorage: saved refresh_token');
    } catch (e) {
      debugPrint('SecureStorage saveRefreshToken error: $e');
    }
  }

  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _kRefreshToken);
    } catch (e) {
      debugPrint('SecureStorage readRefreshToken error: $e');
      return null;
    }
  }

  /// Save custom bearer (override hardcode)
  Future<void> saveCustomBearer(String token) async {
    try {
      await _storage.write(key: _kCustomBearer, value: token);
    } catch (e) {
      debugPrint('SecureStorage saveCustomBearer error: $e');
    }
  }

  Future<String?> readCustomBearer() async {
    try {
      return await _storage.read(key: _kCustomBearer);
    } catch (e) {
      debugPrint('SecureStorage readCustomBearer error: $e');
      return null;
    }
  }

  /// v3.0.40: Save generic String key-value
  Future<void> save(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecureStorage save($key) error: $e');
    }
  }

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SecureStorage read($key) error: $e');
      return null;
    }
  }

  Future<void> saveInt(String key, int value) async {
    await save(key, value.toString());
  }

  Future<int?> readInt(String key) async {
    final v = await read(key);
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SecureStorage delete($key) error: $e');
    }
  }

  /// Clear all tokens (logout)
  Future<void> clearAll() async {
    try {
      await _storage.delete(key: _kAccessToken);
      await _storage.delete(key: _kRefreshToken);
      await _storage.delete(key: _kCustomBearer);
      debugPrint('SecureStorage: cleared all tokens');
    } catch (e) {
      debugPrint('SecureStorage clearAll error: $e');
    }
  }
}
