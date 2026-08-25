// Credentials v3.0.96 - Tất cả sensitive credentials được mã hóa XOR
//
// ⚠️ Bảo mật: XOR với key cố định KHÔNG phải secure encryption - chỉ đủ để:
//   1. Không ai grep code thấy plaintext
//   2. Không hiện trong string extraction từ APK
//   3. Nếu ai đó xem được source code, phải decode mới biết
//
// Để bảo mật thật sự → dùng native keystore (Android Keystore / iOS Keychain)
// hoặc fetch từ server. Với app nội bộ BV, XOR là đủ.
//
// Key được rotate theo version - mỗi version dùng key khác nhau
// (chỉ cần đổi key này là invalid hết các bản build cũ nếu lộ)

import 'dart:convert';

class Credentials {
  // Key XOR (đổi key này để rotate - chỉ cần đổi 1 dòng)
  static const String _xorKey = 'BV_NINH_THUAN_2026_XOR_V96';

  /// Decode XOR-encoded string
  static String _decode(String encodedB64) {
    try {
      final xored = base64.decode(encodedB64);
      final key = utf8.encode(_xorKey);
      final bytes = List<int>.generate(
        xored.length,
        (i) => xored[i] ^ key[i % key.length],
      );
      return utf8.decode(bytes);
    } catch (_) {
      return '';
    }
  }

  /// Encode plain string (helper - chỉ dùng lúc dev, không gọi runtime)
  static String encode(String plain) {
    final bytes = utf8.encode(plain);
    final key = utf8.encode(_xorKey);
    final xored = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ key[i % key.length],
    );
    return base64.encode(xored);
  }

  // ============ VPN (openvpn_flutter) ============
  /// OpenVPN password cho account mặc định (BS Ninh Thuận)
  /// XOR-encoded - dùng Credentials.encode() để regenerate nếu cần rotate
  static final String vpnNemkPassword = _decode('ATgrOis4JisUe2dw');

  // ============ Y Tế Số (Bộ Y tế) public API ============
  /// Y Tế Số default password (cùng với thongke public)
  /// XOR-encoded
  static final String yTeSoDefaultPassword = _decode('c2ZteQ==');

  // ============ Thongke public API (Data public) ============
  /// Thongke public default email
  /// XOR-encoded
  static final String thongkeDefaultEmail = _decode('LDMyJQ==');

  /// Thongke public default password
  /// XOR-encoded
  static final String thongkeDefaultPassword = _decode('c2ZteQ==');

  // ============ Default HIS login (nemk/1027) ============
  // v3.0.177: Tất cả nơi hardcode 'nemk' / '1027' đều tham chiếu qua đây
  // - Login screen cũng dùng giá trị này làm default
  // - Khi user nhập user/pass mới ở login chính → sẽ override qua setActiveNemkCredentials()
  static const String defaultNemkLogin = 'nemk';
  static const String defaultNemkPassword = '1027';

  // v3.0.177: Active credentials - được set bởi login screen khi user nhập
  // Tất cả chỗ dùng credentials nên đọc currentNemkLogin / currentNemkPassword
  // (không dùng defaultNemkLogin trực tiếp) để sync với login state
  static String _activeNemkLogin = defaultNemkLogin;
  static String _activeNemkPassword = defaultNemkPassword;

  /// Lấy username hiện tại (sync với login nếu user đã đăng nhập)
  static String get currentNemkLogin => _activeNemkLogin;
  static String get currentNemkPassword => _activeNemkPassword;

  /// Set credentials khi user đăng nhập thành công (gọi từ login_screen)
  /// Sau khi gọi, tất cả chỗ dùng `Credentials.currentNemkLogin` sẽ thấy giá trị mới
  static void setActiveNemkCredentials({required String login, required String password}) {
    _activeNemkLogin = login;
    _activeNemkPassword = password;
  }

  /// Reset về default (khi logout)
  static void resetActiveNemkCredentials() {
    _activeNemkLogin = defaultNemkLogin;
    _activeNemkPassword = defaultNemkPassword;
  }
}

/// Khi cần dùng 1 trong các credentials, gọi:
/// ```dart
/// import 'package:his_mobile/core/security/credentials.dart';
/// final pass = Credentials.vpnNemkPassword;
/// ```
///
/// KHÔNG gán plaintext credentials vào biến static const trong code nữa.
