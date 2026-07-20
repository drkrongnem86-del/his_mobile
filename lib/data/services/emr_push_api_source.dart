// v3.0.42: Chọn nguồn API push EMR - đơn giản hóa, chỉ 2 options
// - hisPro: HIS Pro 1417 (mặc định, ai cũng dùng được) - thông qua proxy/tunnel
// - mockLocal: Mock server local trong app (test offline, không cần server)
//
// Phân quyền:
//   - User thường → thấy 2 options: hisPro + mockLocal
//   - User `nemk` (admin) → thấy thêm 1 option: bvbmWorkaround (push tạm qua BVBM Gateway)
//
// Smart default (v3.0.42):
//   1. Nếu Mock bật → mockLocal (test offline)
//   2. Nếu không có gì → hisPro (mặc định)
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/data_service.dart';
import 'package:his_mobile/data/services/mock_emr_server.dart';

/// Các nguồn API để push EMR (v3.0.42 - chỉ 2 options chính)
enum EmrPushApiSource {
  /// HIS Pro 1417 - mặc định, ai cũng dùng được
  /// Dùng TokenCode headers qua proxy/auto-bootstrap từ HIS Pro session
  hisPro('🏥 HIS Pro 1417', 'Đẩy thẳng lên EMR BV (mặc định)'),

  /// Mock server local trong app - test offline
  /// Lưu phiếu vào SharedPreferences + PDF vào app docs folder
  mockLocal('🧪 Mock (offline)', 'Test offline - không cần server'),

  /// v3.0.42: HIS Pro 8080 (public) - cho fallback khi VPN chưa lên
  /// Dùng endpoint public 113.163.187.3:8080 (Data API công khai)
  public('🌍 Public 8080', 'API công khai (fallback)');

  final String label;
  final String description;
  const EmrPushApiSource(this.label, this.description);

  static EmrPushApiSource fromIndex(int i) {
    if (i < 0 || i >= values.length) return EmrPushApiSource.hisPro;
    return values[i];
  }
}

/// Singleton quản lý API selection + role-based visibility
class EmrApiSelectorService {
  static final EmrApiSelectorService instance = EmrApiSelectorService._();
  EmrApiSelectorService._();

  static const _kSelectedKey = 'emr_push_api_source_idx';

  /// Username admin (được phép thấy tất cả API)
  static const String adminUsername = 'nemk';

  /// Lấy username hiện tại
  String? _getCurrentUsername() {
    final thongkeUser = ThongkeAuthService().currentUsername;
    if (thongkeUser != null && thongkeUser.isNotEmpty) return thongkeUser;
    final dataUser = DataService.instance.userName;
    if (dataUser != null && dataUser.isNotEmpty) return dataUser;
    return null;
  }

  /// Check user hiện tại có phải admin (`nemk`) không
  bool isAdmin() {
    final username = _getCurrentUsername();
    if (username == null || username.isEmpty) return false;
    return username.toLowerCase().trim() == adminUsername.toLowerCase();
  }

  /// v3.0.57: Phân quyền hiển thị API sources
  /// - User `nemk` (admin) → thấy 3 options: hisPro + mockLocal + public
  /// - User khác → chỉ thấy 2 options: hisPro + public (bỏ mockLocal)
  /// - Trước đó: ai cũng thấy 3 options → user thường thấy Mock không cần thiết
  List<EmrPushApiSource> visibleSources() {
    if (isAdmin()) {
      return EmrPushApiSource.values.toList();
    }
    return [EmrPushApiSource.hisPro, EmrPushApiSource.public];
  }

  /// Lấy API source hiện tại
  /// v3.0.42: Ưu tiên Mock (nếu bật) > HIS Pro (mặc định)
  Future<EmrPushApiSource> getSelected() async {
    if (await MockEmrServer.instance.isEnabled()) {
      debugPrint('EmrApiSelector: Mock enabled → mockLocal');
      return EmrPushApiSource.mockLocal;
    }
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kSelectedKey) ?? EmrPushApiSource.hisPro.index;
    return EmrPushApiSource.fromIndex(idx);
  }

  /// Lưu API source
  Future<bool> setSelected(EmrPushApiSource src) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSelectedKey, src.index);
    debugPrint('EmrApiSelector: setSelected=$src');
    return true;
  }
}
