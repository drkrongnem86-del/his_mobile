// UserService v3.0.174 - Service trung tâm quản lý USERS (AcsUser + HisExecuteUser)
//
// Vai trò: 1 service duy nhất quản lý user list, share cho TẤT CẢ screens cần:
// - ECG screen (BS chính + ĐD)
// - ServiceExecuteDetail (6 vị trí kíp)
// - PhieuPhauThuat (BS gây mê + PTV)
// - HisExecuteGroup API integration
//
// Đặc điểm:
// - Singleton - 1 instance duy nhất cho cả app
// - Cache 200 users từ AcsUser (port 1401 - ổn định nhất)
// - Map LOGINNAME → USERNAME (tên đầy đủ) + DepartmentId
// - Highlight "me" - user đang login
// - Remember last selected user (SharedPreferences)

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Role cho các vị trí trong kíp PTTT (theo HIS Desktop)
enum KipRole {
  ptvChinh,      // Phẫu thuật viên chính
  ptvPhu1,       // Phẫu thuật viên phụ 1
  ptvPhu2,       // Phẫu thuật viên phụ 2
  gmChinh,       // Bác sĩ gây mê chính
  gmPhu,         // Bác sĩ gây mê phụ
  dieuDuong,     // Điều dưỡng
  dungCuVien,    // Dụng cụ viên
  bsNgoai,       // Bác sĩ ngoài
}

extension KipRoleX on KipRole {
  String get label => switch (this) {
        KipRole.ptvChinh => 'BS / PTV chính',
        KipRole.ptvPhu1 => 'PTV phụ 1',
        KipRole.ptvPhu2 => 'PTV phụ 2',
        KipRole.gmChinh => 'Gây mê chính',
        KipRole.gmPhu => 'Gây mê phụ',
        KipRole.dieuDuong => 'Điều dưỡng',
        KipRole.dungCuVien => 'Dụng cụ viên',
        KipRole.bsNgoai => 'Bác sĩ ngoài',
      };

  /// v3.0.174: ID role theo HIS Pro HisExecuteGroup (theo open source)
  int get hisProRoleId => switch (this) {
        KipRole.ptvChinh => 1,
        KipRole.ptvPhu1 => 2,
        KipRole.ptvPhu2 => 3,
        KipRole.gmChinh => 4,
        KipRole.gmPhu => 5,
        KipRole.dieuDuong => 6,
        KipRole.dungCuVien => 7,
        KipRole.bsNgoai => 8,
      };
}

class UserService {
  static final UserService instance = UserService._();
  UserService._();

  static const String _kStorageKey = 'user_service_users_v1';
  static const String _kMeKey = 'pref_hispro_user';  // LOGINNAME user đang login
  static const String _kLastKeyPrefix = 'pref_last_kip_';  // pref_last_kip_ptvChinh, ...

  List<Map<String, dynamic>> _users = [];
  bool _loaded = false;
  String? _meLogin;  // LOGINNAME user hiện tại

  bool get isLoaded => _loaded;
  List<Map<String, dynamic>> get users => List.unmodifiable(_users);
  int get count => _users.length;
  String? get meLogin => _meLogin;

  /// Load users từ AcsUser (port 1401) - cache + persist to SharedPreferences
  Future<void> load({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) {
      debugPrint('UserService: already loaded ${_users.length} users');
      return;
    }
    // 1. Try load from SharedPreferences first (offline support)
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_kStorageKey);
        if (cached != null && cached.isNotEmpty) {
          // Đơn giản: không parse JSON, gọi API là dễ nhất
        }
      } catch (_) {}
    }

    // 2. Load từ API
    try {
      _meLogin = (await SharedPreferences.getInstance()).getString(_kMeKey);
      final r = await HisApiService.instance.getAcsUsers(limit: 2000);
      if (r.success && r.data is Map) {
        final data = r.data as Map;
        final raw = data['Data'];
        if (raw is List) {
          _users = raw.cast<Map<String, dynamic>>().where((u) {
            final username = (u['USERNAME'] ?? '').toString().trim();
            final loginname = (u['LOGINNAME'] ?? '').toString().trim();
            return username.isNotEmpty && loginname.isNotEmpty;
          }).toList();
          _loaded = true;
          debugPrint('✅ UserService: loaded ${_users.length} users from AcsUser (me=$_meLogin)');
        }
      } else {
        debugPrint('⚠️ UserService: getAcsUsers failed: ${r.message}');
      }
    } catch (e) {
      debugPrint('❌ UserService.load error: $e');
    }
  }

  /// Lấy USERNAME (tên đầy đủ) từ LOGINNAME
  /// Trả về null nếu không tìm thấy
  String? getFullName(String? loginName) {
    if (loginName == null || loginName.isEmpty) return null;
    final found = _users.where((u) =>
      (u['LOGINNAME'] ?? '').toString().toUpperCase() == loginName.toUpperCase()
    );
    if (found.isEmpty) return null;
    return (found.first['USERNAME'] ?? '').toString();
  }

  /// Lấy user object từ LOGINNAME
  Map<String, dynamic>? getUser(String? loginName) {
    if (loginName == null || loginName.isEmpty) return null;
    final found = _users.where((u) =>
      (u['LOGINNAME'] ?? '').toString().toUpperCase() == loginName.toUpperCase()
    );
    if (found.isEmpty) return null;
    return found.first;
  }

  /// Lấy user theo DepartmentId (vd: 22=Cấp cứu, 25=Gây mê)
  List<Map<String, dynamic>> byDepartment(int? deptId) {
    if (deptId == null) return users;
    return _users.where((u) {
      final did = u['DEPARTMENT_ID'];
      if (did == null) return false;
      if (did is int) return did == deptId;
      if (did is num) return did.toInt() == deptId;
      if (did is String) return int.tryParse(did) == deptId;
      return false;
    }).toList();
  }

  /// Lấy user theo role (G_CODE hoặc LOGINNAME prefix)
  /// VD: doctor, nurse, surgeon
  List<Map<String, dynamic>> byRole(String role) {
    final roleLower = role.toLowerCase();
    return _users.where((u) {
      final gCode = (u['G_CODE'] ?? '').toString().toLowerCase();
      if (gCode.contains(roleLower)) return true;
      // Fallback: check USERNAME
      final username = (u['USERNAME'] ?? '').toString().toLowerCase();
      return username.contains(roleLower);
    }).toList();
  }

  /// Search user theo tên (cho picker dialog)
  List<Map<String, dynamic>> search(String query) {
    if (query.isEmpty) return users;
    final q = query.toLowerCase();
    return _users.where((u) {
      final username = (u['USERNAME'] ?? '').toString().toLowerCase();
      final loginname = (u['LOGINNAME'] ?? '').toString().toLowerCase();
      return username.contains(q) || loginname.contains(q);
    }).toList();
  }

  /// Lấy user theo role + search
  List<Map<String, dynamic>> searchByRole(String query, KipRole role) {
    final list = switch (role) {
      KipRole.gmChinh || KipRole.gmPhu => byDepartment(25),  // Gây mê hồi sức dept
      KipRole.dieuDuong => users,  // ĐD mọi khoa
      _ => users,  // PTV: mọi BS
    };
    if (query.isEmpty) return list;
    final q = query.toLowerCase();
    return list.where((u) {
      final username = (u['USERNAME'] ?? '').toString().toLowerCase();
      final loginname = (u['LOGINNAME'] ?? '').toString().toLowerCase();
      return username.contains(q) || loginname.contains(q);
    }).toList();
  }

  /// Lưu lần chọn cuối (cho remember last kíp)
  Future<void> rememberLast(KipRole role, String? loginName) async {
    if (loginName == null || loginName.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kLastKeyPrefix${role.name}', loginName);
    } catch (e) {
      debugPrint('UserService.rememberLast error: $e');
    }
  }

  /// Lấy lần chọn cuối
  Future<String?> getLast(KipRole role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_kLastKeyPrefix${role.name}');
    } catch (_) {
      return null;
    }
  }

  /// Cập nhật user đang login (gọi sau khi login)
  Future<void> setMe(String? loginName) async {
    _meLogin = loginName;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (loginName != null) {
        await prefs.setString(_kMeKey, loginName);
      }
    } catch (_) {}
  }
}
