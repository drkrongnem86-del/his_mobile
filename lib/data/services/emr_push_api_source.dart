// v3.0.42: Chá»n nguá»“n API push EMR - Ä‘Æ¡n giáº£n hÃ³a, chá»‰ 2 options
// - hisPro: HIS Pro 1417 (máº·c Ä‘á»‹nh, ai cÅ©ng dÃ¹ng Ä‘Æ°á»£c) - thÃ´ng qua proxy/tunnel
// - mockLocal: Mock server local trong app (test offline, khÃ´ng cáº§n server)
//
// PhÃ¢n quyá»n:
//   - User thÆ°á»ng â†’ tháº¥y 2 options: hisPro + mockLocal
//   - User `nemk` (admin) â†’ tháº¥y thÃªm 1 option: bvbmWorkaround (push táº¡m qua BVBM Gateway)
//
// Smart default (v3.0.42):
//   1. Náº¿u Mock báº­t â†’ mockLocal (test offline)
//   2. Náº¿u khÃ´ng cÃ³ gÃ¬ â†’ hisPro (máº·c Ä‘á»‹nh)
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/services/mock_emr_server.dart';

import 'package:his_mobile/core/security/credentials.dart';
/// CÃ¡c nguá»“n API Ä‘á»ƒ push EMR (v3.0.42 - chá»‰ 2 options chÃ­nh)
enum EmrPushApiSource {
  /// HIS Pro 1417 - máº·c Ä‘á»‹nh, ai cÅ©ng dÃ¹ng Ä‘Æ°á»£c
  /// DÃ¹ng TokenCode headers qua proxy/auto-bootstrap tá»« HIS Pro session
  hisPro('ðŸ¥ HIS Pro 1417', 'Äáº©y tháº³ng lÃªn EMR BV (máº·c Ä‘á»‹nh)'),

  /// Mock server local trong app - test offline
  /// LÆ°u phiáº¿u vÃ o SharedPreferences + PDF vÃ o app docs folder
  mockLocal('ðŸ§ª Mock (offline)', 'Test offline - khÃ´ng cáº§n server'),

  /// v3.0.42: HIS Pro 8080 (public) - cho fallback khi VPN chÆ°a lÃªn
  /// DÃ¹ng endpoint public 113.163.187.3:8080 (Data API cÃ´ng khai)
  public('ðŸŒ Public 8080', 'API cÃ´ng khai (fallback)');

  final String label;
  final String description;
  const EmrPushApiSource(this.label, this.description);

  static EmrPushApiSource fromIndex(int i) {
    if (i < 0 || i >= values.length) return EmrPushApiSource.hisPro;
    return values[i];
  }
}

/// Singleton quáº£n lÃ½ API selection + role-based visibility
class EmrApiSelectorService {
  static final EmrApiSelectorService instance = EmrApiSelectorService._();
  EmrApiSelectorService._();

  static const _kSelectedKey = 'emr_push_api_source_idx';

  /// Username admin (Ä‘Æ°á»£c phÃ©p tháº¥y táº¥t cáº£ API)
  static const String adminUsername = Credentials.defaultNemkLogin;

  /// Láº¥y username hiá»‡n táº¡i
  String? _getCurrentUsername() {
    final thongkeUser = ThongkeAuthService().currentUsername;
    if (thongkeUser != null && thongkeUser.isNotEmpty) return thongkeUser;
    final dataUser = DataService.instance.userName;
    if (dataUser != null && dataUser.isNotEmpty) return dataUser;
    return null;
  }

  /// Check user hiá»‡n táº¡i cÃ³ pháº£i admin (`nemk`) khÃ´ng
  bool isAdmin() {
    final username = _getCurrentUsername();
    if (username == null || username.isEmpty) return false;
    return username.toLowerCase().trim() == adminUsername.toLowerCase();
  }

  /// v3.0.57: PhÃ¢n quyá»n hiá»ƒn thá»‹ API sources
  /// - User `nemk` (admin) â†’ tháº¥y 3 options: hisPro + mockLocal + public
  /// - User khÃ¡c â†’ chá»‰ tháº¥y 2 options: hisPro + public (bá» mockLocal)
  /// - TrÆ°á»›c Ä‘Ã³: ai cÅ©ng tháº¥y 3 options â†’ user thÆ°á»ng tháº¥y Mock khÃ´ng cáº§n thiáº¿t
  List<EmrPushApiSource> visibleSources() {
    if (isAdmin()) {
      return EmrPushApiSource.values.toList();
    }
    return [EmrPushApiSource.hisPro, EmrPushApiSource.public];
  }

  /// Láº¥y API source hiá»‡n táº¡i
  /// v3.0.42: Æ¯u tiÃªn Mock (náº¿u báº­t) > HIS Pro (máº·c Ä‘á»‹nh)
  Future<EmrPushApiSource> getSelected() async {
    if (await MockEmrServer.instance.isEnabled()) {
      debugPrint('EmrApiSelector: Mock enabled â†’ mockLocal');
      return EmrPushApiSource.mockLocal;
    }
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kSelectedKey) ?? EmrPushApiSource.hisPro.index;
    return EmrPushApiSource.fromIndex(idx);
  }

  /// LÆ°u API source
  Future<bool> setSelected(EmrPushApiSource src) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSelectedKey, src.index);
    debugPrint('EmrApiSelector: setSelected=$src');
    return true;
  }
}
