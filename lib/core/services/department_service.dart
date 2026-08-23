// DepartmentService v2.66.0 - Load danh sách khoa từ HIS Pro HisDepartment/Get
// Port 1401 (ACS) - endpoint: /api/HisDepartment/Get
// Pattern copy từ HisProApiService.get() - dùng Bearer token + base64 param
// Cache SharedPreferences + fallback hardcode 52 khoa từ AppConstants
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:his_mobile/core/constants/app_constants.dart';
import 'package:his_mobile/core/utils/mojibake_fixer.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DepartmentService {
  static final DepartmentService instance = DepartmentService._();
  DepartmentService._();

  static const _cacheKey = 'his_departments_cache_v1';
  List<Map<String, dynamic>> _departments = [];
  bool _loaded = false;

  List<Map<String, dynamic>> get departments => _departments;
  bool get loaded => _loaded;
  int get count => _departments.length;

  /// v2.66.0: Load departments - ưu tiên cache, fallback gọi API, fallback hardcode
  Future<void> load() async {
    // 1. Thử cache trước
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final List data = jsonDecode(cached) as List;
        _departments = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (_departments.isNotEmpty) {
          _loaded = true;
          debugPrint('✅ Departments from cache: ${_departments.length}');
          return;
        }
      } catch (_) {}
    }

    // 2. Gọi API HisDepartment/Get (nếu đã login HIS Pro)
    if (HisProApiService.instance.isLoggedIn) {
      final ok = await _fetchFromApi();
      if (ok) {
        _loaded = true;
        return;
      }
    }

    // 3. Fallback hardcode AppConstants.departments (52 khoa)
    _departments = List<Map<String, dynamic>>.from(AppConstants.departments);
    _loaded = true;
    debugPrint('⚠ Departments fallback hardcode: ${_departments.length}');
  }

  /// v2.66.0: Gọi API /api/HisDepartment/Get (port 1401)
  /// Returns true nếu thành công
  Future<bool> _fetchFromApi() async {    try {
      final api = HisProApiService.instance;
      // Endpoint: ${acsBaseUrl}api/HisDepartment/Get
      final url = '${ConnectionService.instance.acsUrl}api/HisDepartment/Get';
      final r = await api.get(url, {
        'IS_ACTIVE': 1,
      }, limit: 200);
      if (!r.success || r.data == null) {
        debugPrint('HisDepartment/Get failed: ${r.message}');
        return false;
      }
      final data = r.data;
      if (data is! Map) return false;
      final root = data;
      // Response: {"Success": true, "Data": [{"ID": 22, "DEPARTMENT_CODE": "HSCC", "DEPARTMENT_NAME": "Khoa Cấp Cứu"}, ...]}
      if (root['Success'] != true) return false;
      final list = root['Data'];
      if (list is! List) return false;

      final mapped = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is Map) {
          final id = (item['ID'] ?? item['id'])?.toString();
          final code = (item['DEPARTMENT_CODE'] ?? item['department_code'] ?? '').toString();
          final name = (item['DEPARTMENT_NAME'] ?? item['department_name'] ?? '').toString();
          if (id != null && code.isNotEmpty) {
            mapped.add({
              'id': id,
              'code': code,
              'name': name,
            });
          }
        }
      }

      if (mapped.isNotEmpty) {
        // v2.86.0: Fallback tên từ AppConstants nếu API trả về tên không dấu
        // (một số API trả "Khoa Noi than" thay vì "Khoa Nội thận")
        // v2.91.0: Mở rộng - thử match theo code, id, và một số alias
        // v2.92.0: Mạnh hơn - fixVietnameseMojibake + manual mapping + tìm theo partial name
        for (int i = 0; i < mapped.length; i++) {
          final m = mapped[i];
          var apiName = m['name']?.toString() ?? '';
          // 1. Thử fix mojibake trước
          final fixedMojibake = fixVietnameseMojibake(apiName);
          if (fixedMojibake != apiName && _hasVietnameseDiacritics(fixedMojibake)) {
            apiName = fixedMojibake;
            debugPrint('🔧 Moijibake fix khoa "${m['code']}": "$apiName"');
          }
          // 2. Manual mapping cho 1 số tên phổ biến
          apiName = _manualDeptNameFix(m['code']?.toString() ?? '', apiName);
          // 3. Fallback từ AppConstants
          if (!_hasVietnameseDiacritics(apiName) || apiName.isEmpty) {
            final fixedName = _findNameInAppConstants(
              m['code']?.toString() ?? '',
              m['id']?.toString() ?? '',
            );
            if (fixedName != null) {
              apiName = fixedName;
              debugPrint('🔧 Fallback khoa "${m['code']}" → "$fixedName"');
            }
          }
          mapped[i] = {...m, 'name': apiName};
        }
        _departments = mapped;
        // Lưu cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(mapped));
        debugPrint('✅ Departments from API: ${mapped.length}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('HisDepartment/Get exception: $e');
    return false;
    }
  }

  /// v2.66.0: Gọi API /api/HisDepartment/Get (port 1401)

  /// v2.66.0: Refresh lại từ API (kéo xuống refresh)
  Future<bool> refresh() async {
    if (!HisProApiService.instance.isLoggedIn) {
      debugPrint('Cannot refresh departments - not logged in HIS Pro');
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    final ok = await _fetchFromApi();
    if (ok) _loaded = true;
    return ok;
  }

  /// v2.66.0: Tìm khoa theo ID (cho PatientCard, HomeScreen)
  Map<String, dynamic>? findById(String? id) {
    if (id == null) return null;
    try {
      return _departments.firstWhere(
        (d) => d['id'].toString() == id,
        orElse: () => {},
      );
    } catch (_) {
      return null;
    }
  }

  /// v2.66.0: Tìm khoa theo code
  Map<String, dynamic>? findByCode(String? code) {
    if (code == null) return null;
    try {
      return _departments.firstWhere(
        (d) => d['code']?.toString().toUpperCase() == code.toUpperCase(),
        orElse: () => {},
      );
    } catch (_) {
      return null;
    }
  }

  /// v2.86.0: Helper - check tên có dấu tiếng Việt không
  /// (API trả "Khoa Noi than" không dấu → fallback từ AppConstants)
  static bool _hasVietnameseDiacritics(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạằắẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]').hasMatch(s);
  }

  /// v2.91.0: Tìm tên khoa trong AppConstants theo code hoặc id
  /// Trả về null nếu không tìm thấy
  String? _findNameInAppConstants(String code, String id) {
    // 1. Tìm theo code (case-insensitive)
    for (final d in AppConstants.departments) {
      if (d['code']?.toString().toUpperCase() == code.toUpperCase()) {
        final n = d['name']?.toString();
        if (n != null && n.isNotEmpty && _hasVietnameseDiacritics(n)) return n;
      }
    }
    // 2. Tìm theo id
    for (final d in AppConstants.departments) {
      if (d['id']?.toString() == id) {
        final n = d['name']?.toString();
        if (n != null && n.isNotEmpty && _hasVietnameseDiacritics(n)) return n;
      }
    }
    // 3. Tìm theo deptId (cho department list phụ)
    for (final d in AppConstants.departments) {
      if (d['deptId']?.toString() == id) {
        final n = d['name']?.toString();
        if (n != null && n.isNotEmpty && _hasVietnameseDiacritics(n)) return n;
      }
    }
    // 4. Tìm theo partial name (lowercase contains)
    if (code.isNotEmpty) {
      final codeUpper = code.toUpperCase();
      for (final d in AppConstants.departments) {
        final dCode = d['code']?.toString().toUpperCase() ?? '';
        if (dCode.contains(codeUpper) || codeUpper.contains(dCode)) {
          final n = d['name']?.toString();
          if (n != null && n.isNotEmpty && _hasVietnameseDiacritics(n)) return n;
        }
      }
    }
    return null;
  }

  /// v2.92.0: Manual fix cho 1 số tên khoa thường gặp không dấu
  /// (API thỉnh thoảng trả về tên mà AppConstants không có)
  static const Map<String, String> _manualDeptNames = {
    'HSCC': 'Khoa Cấp Cứu',
    'CCS': 'Khoa Phụ sản - Cấp Cứu Sản',
    'DTCCLuu': 'Khoa Cấp Cứu Lưu',
    'KCC_CS2': 'Khoa Cấp Cứu Cơ Sở 2',
    'DTCCLUUCS2': 'Cấp Cứu Lưu Cơ Sở 2',
    'HSCCL': 'Khoa Hồi Sức Cấp Cứu Lưu',
    'CCSVL': 'Khoa Cấp Cứu Sản Văn Lâm',
    'NTTN': 'Khoa Nội thận - Tiết niệu',
    'DVNTTN': 'Khoa Ngoại thận - Tiết niệu',
    'NTK': 'Khoa Thần kinh',
    'DVNTK': 'Khoa Ngoại Thần kinh',
    'NTM': 'Khoa Nội Tim mạch',
    'DVTMCT': 'Khoa Tim Mạch Can Thiệp',
    'KNTH': 'Khoa Nội Tổng hợp',
    'KKB': 'Khoa Khám bệnh',
    'KPS': 'Khoa Phụ sản',
    'KKB_CS2': 'Khoa Khám bệnh Cơ Sở 2',
    'CDHA_CS2': 'Khoa Chẩn đoán Hình ảnh Cơ Sở 2',
    'TDCN_CS2': 'Khoa Thăm dò Chức năng Cơ Sở 2',
    'KDYCS2': 'Khoa Y Học Cổ Truyền Cơ Sở 2',
    'KRHM_CS2': 'Khoa Răng Hàm Mặt Cơ Sở 2',
    'KTMH_CS2': 'Khoa Tai Mũi Họng Cơ Sở 2',
    'KM_CS2': 'Khoa Mắt Cơ Sở 2',
    'KNTH_CS2': 'Khoa Nội Tổng hợp Cơ Sở 2',
    'KNGOAITH_CS2': 'Khoa Ngoại Tổng hợp Cơ Sở 2',
    'NOILK': 'Khoa Lão học',
    'DVSS': 'Khoa Sơ sinh',
    'DVHH': 'Khoa Nội Hô hấp',
    'KCG': 'Khoa Khám Chuyên Gia',
    'KSKCB': 'Khoa Khám Sức khỏe Cán bộ',
    'KDTTHVN': 'Khoa Điều Trị Tổng Hợp Văn Lâm',
    'KYHCT': 'Khoa Y Dược Cổ Truyền - Phục hồi Chức năng',
    'KYHCTCS2': 'Khoa Y Dược Cổ Truyền Cơ Sở 2',
    'COVID_KHUB': 'Khoa Điều trị Covid-19 - Khu B',
    'KSNK': 'Khoa Kiểm Soát Nhiễm Khuẩn',
    'KUB': 'Khoa Ung bướu (Điều trị tia xạ)',
    'KTNT': 'Khoa Thận Nhân Tạo',
    'PTGMHS': 'Khoa Gây Mê Hồi Sức',
    'KRHM': 'Khoa Răng - Hàm - Mặt',
    'KTMH': 'Khoa Tai - Mũi - Họng',
    'KTN': 'Khoa Truyền Nhiễm',
    'KM': 'Khoa Mắt',
    'NGCT': 'Khoa Chấn thương Chỉnh hình',
    'NGTH': 'Khoa Ngoại Tổng hợp',
    'KN': 'Khoa Nhi',
    'DTYC': 'Khoa Khám bệnh - Chữa bệnh theo Yêu cầu',
  };

  /// v2.92.0: Manual fix tên khoa theo code (trước khi fallback AppConstants)
  String _manualDeptNameFix(String code, String currentName) {
    if (code.isEmpty) return currentName;
    final manual = _manualDeptNames[code.toUpperCase()];
    if (manual != null && !_hasVietnameseDiacritics(currentName)) {
      return manual;
    }
    return currentName;
  }
}