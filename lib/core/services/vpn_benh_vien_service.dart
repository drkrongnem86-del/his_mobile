// VpnBenhVienService v3.0.76 - Native OpenVPN client (ics-openvpn via openvpn_flutter)
// Quáº£n lÃ½ káº¿t ná»‘i VPN tháº­t, khÃ´ng qua external app.
// v3.0.96: Default password láº¥y tá»« Credentials (XOR-encoded) - KHÃ”NG cÃ³ plaintext
// User cÃ³ thá»ƒ Ä‘á»•i user/pass khÃ¡c qua UI (Settings â†’ VPN Bá»‡nh viá»‡n).
// Password Ä‘Æ°á»£c mask kiá»ƒu ***** khi hiá»ƒn thá»‹ trÃªn UI (lÆ°u SharedPrefs váº«n lÃ  plain text).
// v3.0.93:
//   - onAppPaused(): báº¯t Ä‘áº§u Ä‘áº¿m 5 phÃºt (timer)
//   - onAppResumed(): náº¿u cÃ²n < 5p thÃ¬ há»§y timer, quÃ¡ 5p thÃ¬ tá»± ngáº¯t VPN
//   - startAppPausedTimer(Duration): cáº¥u hÃ¬nh thá»i gian auto-disconnect
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, ChangeNotifier;
import 'package:flutter/services.dart' show rootBundle;
import 'package:his_mobile/core/security/credentials.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnBenhVienService extends ChangeNotifier {
  VpnBenhVienService._();
  static final VpnBenhVienService instance = VpnBenhVienService._();

  // Default credentials - load sáºµn cho user máº·c Ä‘á»‹nh
  // v3.0.96: Password láº¥y tá»« Credentials (XOR-encoded) - KHÃ”NG cÃ³ plaintext
  static const String _kDefaultUser = Credentials.defaultNemkLogin;
  static final String _kDefaultPass = Credentials.vpnNemkPassword;
  static const String _kConfigAsset = 'assets/vpn/nemk_vpn.ovpn';
  static const String _kConfigName = 'sslvpn-nemk-client-config.ovpn';

  // Storage keys
  static const String _kStoredUser = 'vpn_bv_user';
  static const String _kStoredPass = 'vpn_bv_pass';
  static const String _kStoredAutoDisconnect = 'vpn_bv_auto_disconnect_sec';

  // v3.0.93: Default 5 phÃºt auto-disconnect khi app á»Ÿ background
  static const Duration _kDefaultAutoDisconnect = Duration(minutes: 5);

  // v3.0.76: Real OpenVPN engine tá»« openvpn_flutter package
  late final OpenVPN _engine = OpenVPN(
    onVpnStatusChanged: _onVpnStatusChanged,
    onVpnStageChanged: _onVpnStageChanged,
  );
  bool _initialized = false;

  // State - dÃ¹ng VPNStage enum tá»« openvpn_flutter
  VPNStage? _stage;
  VpnStatus? _vpnStatus;
  String? _lastError;
  bool _busy = false;

  VPNStage? get stage => _stage;
  VpnStatus? get vpnStatus => _vpnStatus;
  String? get lastError => _lastError;

  /// v3.0.76: Tráº¡ng thÃ¡i VPN tháº­t (dá»±a trÃªn VPNStage)
  /// VPNStage.connected: Ä‘Ã£ káº¿t ná»‘i tháº­t
  /// VPNStage.connecting/authenticating/...: Ä‘ang káº¿t ná»‘i
  /// VPNStage.disconnected: Ä‘Ã£ ngáº¯t
  /// VPNStage.error/denied: lá»—i
  bool get isConnected => _stage == VPNStage.connected;
  bool get isConnecting =>
      _stage == VPNStage.connecting ||
      _stage == VPNStage.authenticating ||
      _stage == VPNStage.authentication ||
      _stage == VPNStage.prepare ||
      _stage == VPNStage.wait_connection ||
      _stage == VPNStage.tcp_connect ||
      _stage == VPNStage.udp_connect ||
      _stage == VPNStage.assign_ip ||
      _stage == VPNStage.resolve ||
      _stage == VPNStage.get_config ||
      _stage == VPNStage.vpn_generate_config;
  bool get isDisconnected => _stage == VPNStage.disconnected || _stage == null;
  bool get isError => _stage == VPNStage.error || _stage == VPNStage.denied;

  String get statusLabel {
    if (_lastError != null) return 'Lá»—i: $_lastError';
    final s = _stage;
    if (s == null) return 'ChÆ°a khá»Ÿi táº¡o';
    switch (s) {
      case VPNStage.connected: return 'ÄÃ£ káº¿t ná»‘i';
      case VPNStage.disconnected: return 'ChÆ°a káº¿t ná»‘i';
      case VPNStage.connecting: return 'Äang káº¿t ná»‘i...';
      case VPNStage.authenticating: return 'Äang xÃ¡c thá»±c...';
      case VPNStage.authentication: return 'Äang xÃ¡c thá»±c...';
      case VPNStage.prepare: return 'Äang chuáº©n bá»‹...';
      case VPNStage.disconnecting: return 'Äang ngáº¯t káº¿t ná»‘i...';
      case VPNStage.error: return 'Lá»—i VPN';
      case VPNStage.denied: return 'Bá»‹ tá»« chá»‘i (cáº¥p quyá»n VPN?)';
      case VPNStage.exiting: return 'Äang thoÃ¡t...';
      default: return s.toString().split('.').last;
    }
  }

  // Cached credentials
  String? _cachedUser;
  String? _cachedPass;

  // v3.0.93: Auto-disconnect timer (khi app á»Ÿ background quÃ¡ lÃ¢u)
  Timer? _autoDisconnectTimer;
  DateTime? _pausedAt;
  Duration _autoDisconnectAfter = _kDefaultAutoDisconnect;
  bool _wasConnectedBeforePause = false;

  String get currentUser => _cachedUser ?? _kDefaultUser;
  String get currentPass => _cachedPass ?? _kDefaultPass;

  /// v3.0.93: True náº¿u user/pass lÃ  default (khÃ´ng hiá»ƒn thá»‹ password trÃªn UI)
  bool get isUsingDefaultAccount {
    return (_cachedUser ?? _kDefaultUser) == _kDefaultUser &&
        (_cachedPass ?? _kDefaultPass) == _kDefaultPass;
  }

  /// v3.0.76: Mask password cho UI hiá»ƒn thá»‹
  String get maskedPassword {
    final p = currentPass;
    if (p.isEmpty) return '';
    return '*' * p.length;
  }

  /// v3.0.93: Auto-disconnect duration (máº·c Ä‘á»‹nh 5 phÃºt)
  Duration get autoDisconnectAfter => _autoDisconnectAfter;

  /// v3.0.93: True náº¿u Ä‘ang Ä‘áº¿m giá» auto-disconnect
  bool get isAutoDisconnectPending => _autoDisconnectTimer != null;

  /// v3.0.93: Sá»‘ giÃ¢y cÃ²n láº¡i trÆ°á»›c khi tá»± ngáº¯t (null náº¿u khÃ´ng Ä‘áº¿m)
  int? get remainingAutoDisconnectSeconds {
    if (_pausedAt == null) return null;
    final elapsed = DateTime.now().difference(_pausedAt!);
    final remaining = _autoDisconnectAfter - elapsed;
    if (remaining.isNegative) return 0;
    return remaining.inSeconds;
  }

  /// v3.0.76: Initialize engine - pháº£i gá»i 1 láº§n trÆ°á»›c khi connect
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedUser = prefs.getString(_kStoredUser);
    _cachedPass = prefs.getString(_kStoredPass);
    // v3.0.93: Load auto-disconnect duration tá»« prefs
    final autoDisconnectSec = prefs.getInt(_kStoredAutoDisconnect);
    if (autoDisconnectSec != null && autoDisconnectSec > 0) {
      _autoDisconnectAfter = Duration(seconds: autoDisconnectSec);
    }
    if (_initialized) {
      notifyListeners();
      return;
    }
    try {
      await _engine.initialize(
        localizedDescription: 'HIS Mobile VPN - Bá»‡nh viá»‡n',
      );
      _initialized = true;
      // Láº¥y stage hiá»‡n táº¡i (náº¿u VPN Ä‘ang cháº¡y tá»« trÆ°á»›c)
      final curStage = await _engine.stage();
      _stage = curStage;
      debugPrint('VpnBenhVienService: OpenVPN engine initialized, stage=$curStage');
    } catch (e) {
      debugPrint('VpnBenhVienService: init error: $e');
    }
    notifyListeners();
  }

  void _onVpnStatusChanged(VpnStatus? status) {
    debugPrint('VPN status: $status');
    _vpnStatus = status;
    notifyListeners();
  }

  void _onVpnStageChanged(VPNStage stage, String rawStage) {
    debugPrint('VPN stage: $stage, raw: $rawStage');
    _stage = stage;
    // Náº¿u stage lÃ  error/denied â†’ lÆ°u error
    if (stage == VPNStage.error || stage == VPNStage.denied) {
      _lastError = 'VPN stage: ${stage.toString().split('.').last} (raw: $rawStage)';
    } else {
      _lastError = null;
    }
    if (stage == VPNStage.connected || stage == VPNStage.disconnected) {
      _busy = false;
    }
    notifyListeners();
  }

  /// v3.0.76: Káº¿t ná»‘i VPN vá»›i credentials hiá»‡n táº¡i
  Future<bool> connect() async {
    if (_busy) return false;
    if (isConnected) return true;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await init();
      final config = await rootBundle.loadString(_kConfigAsset);
      await _engine.connect(
        config,
        _kConfigName,
        username: currentUser,
        password: currentPass,
        bypassPackages: const [],
        certIsRequired: false,
      );
      return true;
    } catch (e) {
      _lastError = e.toString();
      _busy = false;
      notifyListeners();
      debugPrint('VpnBenhVienService: connect error: $e');
      return false;
    }
  }

  /// v3.0.76: Ngáº¯t káº¿t ná»‘i VPN
  void disconnect() {
    try {
      _engine.disconnect();
    } catch (e) {
      debugPrint('VpnBenhVienService: disconnect error: $e');
    }
    _busy = false;
    notifyListeners();
  }

  /// v3.0.76: LÆ°u credentials má»›i (khi user Ä‘á»•i user/pass)
  Future<void> setCredentials(String user, String pass) async {
    _cachedUser = user;
    _cachedPass = pass;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStoredUser, user);
      await prefs.setString(_kStoredPass, pass);
    } catch (e) {
      debugPrint('VpnBenhVienService: setCredentials error: $e');
    }
    notifyListeners();
  }

  /// v3.0.76: Reset vá» default credentials (xÃ³a stored)
  Future<void> resetToDefault() async {
    _cachedUser = null;
    _cachedPass = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kStoredUser);
      await prefs.remove(_kStoredPass);
    } catch (e) {
      debugPrint('VpnBenhVienService: resetToDefault error: $e');
    }
    notifyListeners();
  }

  // ========== v3.0.93: Auto-disconnect sau khi app á»Ÿ background ==========

  /// App vá»«a vÃ o background (paused) - báº¯t Ä‘áº§u Ä‘áº¿m giá» auto-disconnect
  void onAppPaused() {
    if (!isConnected) {
      _wasConnectedBeforePause = false;
      return;
    }
    _wasConnectedBeforePause = true;
    _pausedAt = DateTime.now();
    _autoDisconnectTimer?.cancel();
    _autoDisconnectTimer = Timer(_autoDisconnectAfter, () {
      debugPrint('VpnBenhVienService: auto-disconnect after ${_autoDisconnectAfter.inMinutes} min in background');
      if (isConnected) {
        disconnect();
        _lastError = 'Auto-disconnect: app á»Ÿ background quÃ¡ ${_autoDisconnectAfter.inMinutes} phÃºt';
      }
      _autoDisconnectTimer = null;
      _pausedAt = null;
      notifyListeners();
    });
    debugPrint('VpnBenhVienService: app paused, auto-disconnect in ${_autoDisconnectAfter.inMinutes} min');
    notifyListeners();
  }

  /// App vá»«a resume (foreground láº¡i) - há»§y timer náº¿u chÆ°a quÃ¡ háº¡n
  void onAppResumed() {
    if (_autoDisconnectTimer != null) {
      _autoDisconnectTimer!.cancel();
      _autoDisconnectTimer = null;
      _pausedAt = null;
      _wasConnectedBeforePause = false;
      debugPrint('VpnBenhVienService: app resumed, cancelled auto-disconnect');
      notifyListeners();
    }
  }

  /// Cáº­p nháº­t thá»i gian auto-disconnect (phÃºt, 0 = táº¯t)
  Future<void> setAutoDisconnectMinutes(int minutes) async {
    if (minutes < 0) minutes = 0;
    _autoDisconnectAfter = Duration(minutes: minutes);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kStoredAutoDisconnect, minutes * 60);
    } catch (e) {
      debugPrint('VpnBenhVienService: setAutoDisconnectMinutes error: $e');
    }
    notifyListeners();
  }
}
