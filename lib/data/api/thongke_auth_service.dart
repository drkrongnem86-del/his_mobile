import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/core/security/credentials.dart';
import 'package:his_mobile/data/api/his_catalog_service.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/core/utils/vietnamese.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HIS Pro Auth Service (renamed from ThongkeAuthService for compatibility).
/// v2.35: Tất cả link/data bây giờ đi qua HIS Pro VPN trực tiếp (qua OpenVPN BV).
/// Class này giữ tên cũ để không phải sửa hết import trong toàn bộ codebase,
/// nhưng backend đã chuyển sang `http://172.16.9.6:1401/` (HIS Pro AcsBaseUri).
///
/// Y Tế Số cũng dùng endpoint này - bypass thongke public (bị lỗi FS).
class ThongkeAuthService {
  // Singleton - để giữ state giữa các screen
  static final ThongkeAuthService instance = ThongkeAuthService._();

  /// HIS Pro AcsBaseUri - thay thế thongke public
  /// v2.75.2: dynamic - lấy từ HisConfigService
  static String get baseUrl => ConnectionService.instance.acsUrl
      .replaceAll(RegExp(r'/$'), '')
      .replaceFirst(':1401/', ':1401');
  /// v2.38.8: Public Data API endpoint - có BN PK cấp cứu HSCC/CCS
  /// (113.163.187.3:8080 = thongke.benhvienninthuan.vn:8080 public IP)
  static const String publicBaseUrl = 'http://113.163.187.3:8080';
  /// v3.0.79: HIS Pro thật (port 1408 MOS) - có ICD_CODE/ICD_NAME/ICD_TEXT đầy đủ.
  /// Port này KHÁC với mosUrl (1429): mosUrl 1429 = Mới (v3.0.62) trả 404 cho
  /// HisTreatment/GetLView và các API TreatmentHistory. Port 1408 (legacy) mới
  /// có các API: GetLView, GetView, Get, GetDHisSereServ2, GetDynamic.
  /// v3.0.79: hardcode port 1408 thay vì dynamic từ mosUrl (vì mosUrl 1429 bị 404).
  /// Lấy host từ mosUrl (172.16.9.6 LAN hoặc 117.2.25.67 public VPN) nhưng ép port 1408.
  static String get hisProBaseUrl {
    final mos = ConnectionService.instance.mosUrl.replaceAll(RegExp(r'/$'), '');
    // Extract host (e.g., "http://172.16.9.6" từ "http://172.16.9.6:1429")
    final uri = Uri.parse(mos);
    return '${uri.scheme}://${uri.host}:1408';
  }
  static const String _kHisProToken = 'hispro_bearer_token';
  static const String _kHisProTokenSavedAt = 'hispro_token_saved_at';
  // v3.0.93: Track source của token (emrscan / hisproxy / manual / file / embedded)
  static const String _kHisProTokenSource = 'hispro_token_source';
  static const String _kUsername = 'hispro_username';
  static const String _kEmail = 'hispro_email';
  static const String _kRecentUsers = 'hispro_recent_users';
  static const int _kMaxRecent = 5;
  // v3.0.90: Token expiry window (HIS Pro tokens typically valid 1 hour)
  static const Duration _hisProTokenMaxAge = Duration(hours: 1);

  /// v3.0.93: Các nguồn token được hỗ trợ
  /// - hisproxy: Auto-fetch từ HIS desktop proxy (port 9999, đọc log file)
  /// - manual: User paste tay từ Settings
  /// - file: Đọc từ file local trên thiết bị
  /// - embedded: Token mặc định XOR-embedded trong code
  /// - unknown: Không rõ (legacy)
  static const String _kSrcHisProxy = 'hisproxy';
  static const String _kSrcManual = 'manual';
  static const String _kSrcFile = 'file';
  static const String _kSrcEmbedded = 'embedded';
  static const String _kSrcUnknown = 'unknown';

  /// v2.52.0: Embedded default token (XOR + Base64) — auto-load khi không có token
  /// Mục đích: Bác sĩ mở app → tự động có ICD cho 218 BN HSCC mà KHÔNG cần paste
  /// Token này được BS verify work ngày 2026-07-09; nếu BV rotate, BS paste token mới
  /// qua Settings → EMR Sync (1 lần, app sẽ cache lại).
  static const String _kEmbeddedTokenXor =
      'VquHGSm53694QtX1gEUOcnO2WU/LiAurD9I2nRXisvU=';
  static const String _kEmbeddedXorKey =
      'BV_NINH_THUAN_HISPRO_2026';

  /// v2.52.0: Decode embedded token trong code (che mắt, không phải security)
  static String? _decodeEmbeddedToken() {
    try {
      final xored = base64.decode(_kEmbeddedTokenXor);
      final key = utf8.encode(_kEmbeddedXorKey);
      final bytes = List<int>.generate(
        xored.length,
        (i) => xored[i] ^ key[i % key.length],
      );
      final token = utf8.decode(bytes);
      if (token.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(token)) {
        return token;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  late Dio _dio;
  late CookieJar _cookieJar;
  bool _initialized = false;

  String? _cachedUsername;
  String? _cachedEmail;
  String? _cachedDepartmentCode;
  String? _cachedDepartmentName;

  // Private constructor cho singleton
  ThongkeAuthService._();

  // Factory constructor — giữ back-compat với code cũ `ThongkeAuthService()`
  factory ThongkeAuthService() => instance;

  /// Khởi tạo service với persistent cookie storage.
  /// PHẢI được gọi từ main() trước khi runApp().
  Future<void> initPersistence() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cookiesDir = Directory('${dir.path}/cookies');
      if (!await cookiesDir.exists()) {
        await cookiesDir.create(recursive: true);
      }
      _cookieJar = PersistCookieJar(
        ignoreExpires: false,
        storage: FileStorage('${cookiesDir.path}/thongke_cookies'),
      );
      print('ThongkeAuthService: cookies persist at ${cookiesDir.path}');
    } catch (e) {
      print('ThongkeAuthService: persist error, fallback in-memory: $e');
      _cookieJar = CookieJar();
    }

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'User-Agent': 'HIS-Mobile/2.14.1',
      },
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
    _initialized = true;
  }

  /// Test xem cookies còn valid không (gọi /home, nếu 200 + body có username → OK)
  Future<bool> isSessionValid() async {
    if (!_initialized) return false;
    try {
      final resp = await _dio.get('$baseUrl/home',
          options: Options(validateStatus: (s) => s != null && s < 500));
      if (resp.statusCode != 200 || !resp.realUri.toString().contains('/home')) {
        return false;
      }
      final body = resp.data.toString();
      return body.contains('hidden-xs') || body.contains('data-toggle="dropdown"');
    } catch (_) {
      return false;
    }
  }

  String? get currentUsername => _cachedUsername;
  String? get currentEmail => _cachedEmail;
  String? get currentDepartmentCode => _cachedDepartmentCode;
  String? get currentDepartmentName => _cachedDepartmentName;

  // ============== v2.47.0: HIS Pro thật (port 1408) - lấy ICD ==============
  String? _hisProToken;
  final Map<String, Map<String, dynamic>> _icdCache = {};

  /// Lưu/đọc HIS Pro Bearer token (lấy từ log D:\Nem\HISPRO_THAT\Logs\LogSystem.txt)
  /// v3.0.93: Thêm [source] để track token đến từ đâu (emrscan/hisproxy/manual/...)
  Future<void> setHisProToken(String token, {String source = _kSrcManual}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHisProToken, token.trim());
    // v3.0.90: Lưu timestamp để check expiry
    await prefs.setString(_kHisProTokenSavedAt, DateTime.now().toIso8601String());
    // v3.0.93: Lưu source
    await prefs.setString(_kHisProTokenSource, source);
    _hisProToken = token.trim();
  }

  String? get hisProToken => _hisProToken;
  bool get hasHisProToken => (_hisProToken ?? '').isNotEmpty;

  /// v3.0.93: Lấy source hiện tại của token (emrscan/hisproxy/manual/file/embedded/unknown)
  Future<String> getTokenSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHisProTokenSource) ?? _kSrcUnknown;
  }

  /// v3.0.93: Text tiếng Việt ngắn gọn cho source
  Future<String> getTokenSourceText() async {
    final src = await getTokenSource();
    switch (src) {
      case _kSrcHisProxy: return 'HIS Proxy';
      case _kSrcManual: return 'Thủ công';
      case _kSrcFile: return 'File local';
      case _kSrcEmbedded: return 'Mặc định';
      default: return '—';
    }
  }

  /// v3.0.93: Icon phù hợp cho source
  Future<String> getTokenSourceIcon() async {
    final src = await getTokenSource();
    switch (src) {
      case _kSrcHisProxy: return '🖥️'; // HIS desktop proxy
      case _kSrcManual: return '✋'; // User paste tay
      case _kSrcFile: return '📁'; // File local
      case _kSrcEmbedded: return '🔒'; // Token mặc định
      default: return '❓';
    }
  }

  /// v3.0.90: Lấy thời điểm token được lưu (null nếu chưa có)
  Future<DateTime?> getHisProTokenSavedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kHisProTokenSavedAt);
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// v3.0.90: Tuổi token (Duration since saved). Null nếu chưa lưu.
  Future<Duration?> getHisProTokenAge() async {
    final saved = await getHisProTokenSavedAt();
    if (saved == null) return null;
    return DateTime.now().difference(saved);
  }

  /// v3.0.90: True nếu token còn hạn (< 1h)
  Future<bool> isHisProTokenFresh() async {
    final age = await getHisProTokenAge();
    if (age == null) return false;
    return age < _hisProTokenMaxAge;
  }

  /// v3.0.90: Format tuổi token thành chuỗi tiếng Việt
  Future<String> hisProTokenAgeText() async {
    final age = await getHisProTokenAge();
    if (age == null) return 'chưa rõ';
    if (age.inMinutes < 1) return 'vừa lưu';
    if (age.inMinutes < 60) return '${age.inMinutes} phút trước';
    if (age.inHours < 24) return '${age.inHours} giờ trước';
    return '${age.inDays} ngày trước';
  }

  /// v3.0.90: Cảnh báo nếu token sắp hết hạn
  Future<bool> isHisProTokenExpired() async {
    final age = await getHisProTokenAge();
    if (age == null) return true; // chưa có = coi như hết hạn
    return age >= _hisProTokenMaxAge;
  }

  /// v2.47.0: Lấy ICD/mặt bệnh cho 1 treatment từ HIS Pro thật (port 1408)
  /// Trả về: {icd_code, icd_name, icd_sub_codes, icd_text, department_in, in_time, ...}
  /// Cache trong RAM (key = treatment_code) để tap lần 2 không cần fetch
  Future<Map<String, dynamic>?> fetchHisProIcd(String treatmentCode) async {
    if (treatmentCode.isEmpty) return null;
    if (_icdCache.containsKey(treatmentCode)) return _icdCache[treatmentCode];
    if (!hasHisProToken) {
      debugPrint('⚠ fetchHisProIcd: chưa có HIS Pro token');
      return null;
    }
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Authorization': 'Bearer $_hisProToken',
          '___ipAddress': '127.0.0.1',
          'Accept': 'application/json',
        },
      ));
      // v2.50.0: Dùng `api/HisTreatment/Get` (BS verified work) với TREATMENT_CODE__EXACT
      final paramData = {
        'CommonParam': {'LanguageCode': 'VI', 'Now': 0, 'HasException': false, 'Start': 0, 'Limit': 5},
        'ApiData': {
          'IS_INCLUEDE_DELETED': false,
          'TREATMENT_CODE__EXACT': treatmentCode,
          'DATA_DOMAIN_FILTER': false,
        }
      };
      final param = base64Encode(utf8.encode(jsonEncode(paramData)));
      final r = await dio.get(
        '$hisProBaseUrl/api/HisTreatment/Get',
        queryParameters: {'param': param},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (r.statusCode != 200) {
        debugPrint('⚠ fetchHisProIcd ${r.statusCode}');
        return null;
      }
      final data = r.data;
      if (data is! Map || data['Success'] != true) return null;
      final list = data['Data'];
      if (list is! List || list.isEmpty) return null;
      final item = list.first as Map;
      final result = {
        'icd_code': item['ICD_CODE'] ?? '',
        'icd_name': item['ICD_NAME'] ?? '',
        'icd_sub_codes': item['ICD_SUB_CODE'] ?? '',
        'icd_text': item['ICD_TEXT'] ?? '',
        'department_id': item['LAST_DEPARTMENT_ID'],
        'department_name': item['LAST_DEPARTMENT_NAME'] ?? item['TREATMENT_DEPARTMENT_NAME'] ?? '',
        'in_time': item['IN_TIME'],
        'doctor_name': item['DOCTOR_USERNAME'] ?? item['END_DEPARTMENT_HEAD_USERNAME'] ?? '',
        'treatment_day_count': item['TREATMENT_DAY_COUNT'] ?? 0,
        'end_type': item['TREATMENT_END_TYPE_NAME'] ?? '',
        'result': item['TREATMENT_RESULT_NAME'] ?? '',
        'patient_gender': item['TDL_PATIENT_GENDER_NAME'] ?? '',
      };
      _icdCache[treatmentCode] = result;
      debugPrint('✅ ICD cho $treatmentCode: ${result['icd_name']}');
      return result;
    } catch (e) {
      debugPrint('fetchHisProIcd error: $e');
      return null;
    }
  }

  /// v2.60.0: Batch fetch ICD cho nhiều BN (background, không block UI)
  /// Tăng batch từ 50 -> 200 + retry 1 lần nếu fail
  Future<Map<String, Map<String, dynamic>>> batchFetchIcd(
    List<String> treatmentCodes, {
    int batchSize = 200,
  }) async {
    if (!hasHisProToken || treatmentCodes.isEmpty) return {};
    final results = <String, Map<String, dynamic>>{};
    final codes = treatmentCodes.take(batchSize).toList();
    debugPrint('🔄 batchFetchIcd: ${codes.length} BN (size=$batchSize)');
    // Run with controlled concurrency (10 parallel)
    int i = 0;
    while (i < codes.length) {
      final batch = codes.skip(i).take(10).toList();
      final futures = batch.map((c) async {
        var icd = await fetchHisProIcd(c);
        // Retry 1 lần nếu fail (server có thể đang load)
        if (icd == null) {
          await Future.delayed(const Duration(milliseconds: 200));
          icd = await fetchHisProIcd(c);
        }
        if (icd != null) results[c] = icd;
      });
      await Future.wait(futures, eagerError: false);
      i += 10;
      // Add small delay between batches
      if (i < codes.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    debugPrint('✅ batchFetchIcd: ${results.length}/${codes.length} có ICD');
    return results;
  }

  /// Lấy token từ SharedPreferences + tự động quét file local
  /// v2.50.0: Tự động đọc file hispro_token.txt từ /sdcard/Download hoặc app dir
  /// - User drop file vào phone qua USB/cloud → app tự lấy token
  /// - Hoặc từ SharedPreferences (nếu user paste tay 1 lần)
  /// v2.52.0: FALLBACK xuống embedded default token (XOR-encoded) để auto hiện ICD
  /// ưu tiên: SharedPreferences > file local > embedded default
  /// v3.0.90: Khi load từ file/embedded, set savedAt = now (vì coi như "vừa lấy")
  /// v3.0.93: Set source khi load từ file/embedded (nếu chưa có source)
  Future<void> loadHisProToken() async {
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString(_kHisProToken);
    final hasSavedAt = prefs.getString(_kHisProTokenSavedAt) != null;
    final existingSource = prefs.getString(_kHisProTokenSource);
    _hisProToken = fromPrefs;
    // Nếu chưa có token, thử đọc file local
    if ((_hisProToken ?? '').isEmpty) {
      _hisProToken = await _readTokenFromFile();
      if (_hisProToken != null) {
        // v3.0.90: Lưu cả token + savedAt khi lấy từ file
        await prefs.setString(_kHisProToken, _hisProToken!);
        await prefs.setString(_kHisProTokenSavedAt, DateTime.now().toIso8601String());
        // v3.0.93: Đánh dấu source là 'file'
        if (existingSource == null) {
          await prefs.setString(_kHisProTokenSource, _kSrcFile);
        }
      }
    }
    // v2.52.0: Fallback cuối cùng — embedded default token (BS không cần paste)
    if ((_hisProToken ?? '').isEmpty) {
      _hisProToken = _decodeEmbeddedToken();
      if (_hisProToken != null) {
        debugPrint('✅ Loaded embedded default HIS Pro token (v2.52.0)');
        // Cache luôn vào SharedPreferences để các lần sau khỏi decode
        await prefs.setString(_kHisProToken, _hisProToken!);
        await prefs.setString(_kHisProTokenSavedAt, DateTime.now().toIso8601String());
        // v3.0.93: Đánh dấu source là 'embedded'
        await prefs.setString(_kHisProTokenSource, _kSrcEmbedded);
      }
    } else if (!hasSavedAt) {
      // v3.0.90: Có token từ prefs nhưng thiếu savedAt → set = now
      await prefs.setString(_kHisProTokenSavedAt, DateTime.now().toIso8601String());
    } else if (existingSource == null && (_hisProToken ?? '').isNotEmpty) {
      // v3.0.93: Có token từ prefs nhưng thiếu source (legacy data) → mặc định 'manual'
      await prefs.setString(_kHisProTokenSource, _kSrcManual);
    }
    debugPrint('HIS Pro token loaded: ${_hisProToken != null ? "OK (len=${_hisProToken!.length})" : "null"}');
  }

  /// v2.50.0: Đọc token từ file local (auto-detect)
  /// Tìm file hispro_token.txt ở các vị trí phổ biến
  Future<String?> _readTokenFromFile() async {
    final paths = <String>[
      '/sdcard/Download/hispro_token.txt',
      '/sdcard/Documents/hispro_token.txt',
      '/storage/emulated/0/Download/hispro_token.txt',
    ];
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) {
          final content = (await f.readAsString()).trim();
          if (content.isNotEmpty && content.length >= 60) {
            debugPrint('✅ Token loaded from $path');
            return content;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Gọi khi user chọn khoa trong HomeScreen - để hiện thị trên Settings,
  /// Banner, Xem bệnh án — không cần truyền qua nhiều widget.
  void setCurrentDepartment(String? code, String? name) {
    _cachedDepartmentCode = code;
    _cachedDepartmentName = name;
  }

  Future<List<RecentUser>> getRecentUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentUsers) ?? [];
    return list.map(RecentUser.fromPrefString).toList();
  }

  Future<void> _addRecentUser(RecentUser u) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentUsers) ?? [];
    list.removeWhere((s) => s.split('|').first == u.email);
    list.insert(0, u.toPrefString());
    while (list.length > _kMaxRecent) {
      list.removeLast();
    }
    await prefs.setStringList(_kRecentUsers, list);
  }

  /// Xóa 1 user khỏi danh sách recent.
  Future<List<RecentUser>> removeRecentUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentUsers) ?? [];
    list.removeWhere((s) => s.split('|').first == email);
    await prefs.setStringList(_kRecentUsers, list);
    return list.map(RecentUser.fromPrefString).toList();
  }

  /// Xóa toàn bộ danh sách recent.
  Future<void> clearRecentUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecentUsers);
  }

  /// Login với HIS Pro VPN qua AcsToken/Authorize (WCF-style)
  /// v2.35: Replace hoàn toàn Laravel-style auth
  Future<ThongkeLoginResult> login(String email, String password) async {
    try {
      // Step 1: Get device LAN IP
      String ip = '127.0.0.1';
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
          includeLinkLocal: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              ip = addr.address;
              break;
            }
          }
          if (ip != '127.0.0.1') break;
        }
      } catch (_) {}

      // Step 2: Build param (base64 JSON)
      final param = base64Encode(utf8.encode(jsonEncode({
        'CommonParam': {
          'Messages': [], 'BugCodes': [], 'MessageCodes': [],
          'LanguageCode': 'VI', 'Now': 0, 'HasException': false,
        },
        'ApiData': {
          'LOGIN_NAME': email,
          'APPLICATION_CODE': 'HIS',
          'APP_VERSION': '2.35.0',
        },
      })));

      // Step 3: Call /api/AcsToken/Authorize
      final headers = <String, dynamic>{};
      headers['ipAddress'] = ip;
      headers['Accept'] = 'application/json';
      headers['Content-Type'] = 'application/json; charset=utf-8';

      final authResp = await _dio.get(
        '$baseUrl/api/AcsToken/Authorize',
        queryParameters: {'param': param},
        options: Options(headers: headers, receiveTimeout: const Duration(seconds: 15)),
      );

      if (authResp.statusCode == 404) {
        return ThongkeLoginResult(false,
          'HTTP 404 — Server HIS Pro VPN trả về 404 cho AcsToken/Authorize.\n\n'
          'Có thể:\n'
          '• Bạn chưa bật OpenVPN (profile Profile BV) — phải kết nối LAN BV\n'
          '• Sai endpoint / sai IP (đang dùng $baseUrl)\n'
          '• Tường lửa chặn port 1401\n\n'
          'Mở OpenVPN Connect → kết nối Profile BV rồi thử lại.');
      }

      if (authResp.statusCode != 200) {
        return ThongkeLoginResult(false, 'Lỗi kết nối HIS Pro VPN (HTTP ${authResp.statusCode})');
      }

      // Step 4: Phân tích response - chỉ cần xác nhận HTTP 200 là login OK
      // (Y Tế Số cũng chỉ gọi AcsToken/Authorize, response lấy ModuleInRoles làm quyền.
      // Token thật được cache local, không truyền qua HTTP từ server.)
      final body = authResp.data;
      final bodyLen = body?.toString().length ?? 0;

      // Best-effort trích xuất username từ response
      String? userFromBody;
      if (body is Map) {
        final data = body['Data'];
        if (data is Map) {
          userFromBody = (data['LoginName'] ?? data['LOGINNAME'] ?? data['loginname'] ?? data['Username'] ?? data['USERNAME'])?.toString();
        }
        if (userFromBody == null) {
          userFromBody = (body['LoginName'] ?? body['LOGINNAME'] ?? body['Username'] ?? body['USERNAME'])?.toString();
        }
      }

      final username = (userFromBody != null && userFromBody.isNotEmpty) ? userFromBody : email;

      // Step 5: Lưu state - login OK
      _cachedUsername = username;
      _cachedEmail = email;

      final prefs = await SharedPreferences.getInstance();
      // Lưu login name làm session marker (server xác thực qua IP + loginname + password)
      await prefs.setString('hispro_loginname', email);
      await prefs.setString('hispro_authorized', '1');
      await prefs.setString('hispro_authorized_at', DateTime.now().toIso8601String());
      await prefs.setString(_kUsername, username);
      await prefs.setString(_kEmail, email);
      await _addRecentUser(RecentUser(email: email, name: username));

      return ThongkeLoginResult(true,
        'Đăng nhập HIS Pro VPN thành công\n'
        '(Server trả $bodyLen chars — đã cấp quyền, không cần token)',
        username: username);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return ThongkeLoginResult(false, 'HTTP 404 — endpoint không tồn tại trên server. Đã bật OpenVPN chưa?');
      }
      return ThongkeLoginResult(false, 'Lỗi mạng: ${e.message ?? e.toString()}');
    } catch (e) {
      return ThongkeLoginResult(false, 'Lỗi: $e');
    }
  }
  
  // Legacy Laravel-style login - kept for back-compat, not used anymore
  Future<ThongkeLoginResult> _loginLaravelLegacy(String email, String password) async {
    try {
      // 1. GET /login - CookieManager tự lưu XSRF + session cookies
      final getResp = await _dio.get('$baseUrl/login');
      if (getResp.statusCode != 200) {
        return ThongkeLoginResult(false, 'Không truy cập được Thongke (HTTP ${getResp.statusCode})');
      }
      _captureResponseCookies(getResp);  // cache cookies for X-XSRF-TOKEN

      // 2. Lấy _token từ form HTML
      final html = getResp.data?.toString() ?? '';
      final csrfMatch = RegExp("name=[\"']_token[\"'][^>]+value=[\"']([^\"']+)").firstMatch(html)
          ?? RegExp("value=[\"']([^\"']+)[\"'][^>]+name=[\"']_token[\"']").firstMatch(html);
      if (csrfMatch == null) {
        return ThongkeLoginResult(false, 'Không tìm thấy CSRF token trong form');
      }
      final csrf = csrfMatch.group(1);

      // 3. POST /login với FormData
      // X-XSRF-TOKEN: lấy từ cache cookies (CookieManager sẽ tự gửi Cookie header)
      final xsrf = _getCookieValue('XSRF-TOKEN');
      // URL-encode cho header X-XSRF-TOKEN (Laravel sẽ URL-decode)
      final xsrfHeader = xsrf != null ? Uri.encodeComponent(xsrf) : '';

      final response = await _dio.post(
        '$baseUrl/login',
        data: FormData.fromMap({
          '_token': csrf,
          'email': email,
          'password': password,
          'remember': 'on',
        }),
        options: Options(
          headers: {
            'Referer': '$baseUrl/login',
            'X-XSRF-TOKEN': xsrfHeader,
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
      );
      _captureResponseCookies(response);

      // 419 = CSRF mismatch, 422 = wrong creds, 200/302-with-/home = success
      if (response.statusCode == 419) {
        return ThongkeLoginResult(false, 'Phiên hết hạn (CSRF 419) - thử lại');
      }
      if (response.statusCode == 422) {
        return ThongkeLoginResult(false, 'Sai tên đăng nhập hoặc mật khẩu');
      }

      final finalUrl = response.realUri.toString();
      String body = response.data is String
          ? response.data as String
          : (response.data is List<int>
              ? utf8.decode(response.data as List<int>)
              : response.data?.toString() ?? '');

      // Nếu response là 302 (Laravel redirect) và Dio chưa tự follow,
      // tự gọi /home thủ công với cookies (CookieManager sẽ tự gửi)
      if (response.statusCode == 302 || finalUrl.contains('/login')) {
        final location = response.headers.value('location') ?? '/home';
        final redirectUrl = location.startsWith('http')
            ? location
            : '$baseUrl$location';

        final homeResp = await _dio.get(redirectUrl);
        _captureResponseCookies(homeResp);
        body = homeResp.data?.toString() ?? '';
        if (homeResp.statusCode != 200 || !homeResp.realUri.toString().contains('/home')) {
          return ThongkeLoginResult(false, 'Sai tên đăng nhập hoặc mật khẩu');
        }
      } else if (!finalUrl.contains('/home') && response.statusCode != 200) {
        return ThongkeLoginResult(false, 'Đăng nhập thất bại (HTTP ${response.statusCode})');
      }

      // Lấy username từ response body (nếu body rỗng, fetch /home)
      var username = _parseUsername(body);
      if (username == null) {
        try {
          final homeResp = await _dio.get('$baseUrl/home');
          _captureResponseCookies(homeResp);
          body = homeResp.data?.toString() ?? '';
          username = _parseUsername(body);
        } catch (_) {}
      }
      username ??= email;
      _cachedUsername = username;
      _cachedEmail = email;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUsername, username);
      await prefs.setString(_kEmail, email);
      await _addRecentUser(RecentUser(email: email, name: username));

      return ThongkeLoginResult(true, 'Đăng nhập thành công', username: username);
    } on DioException catch (e) {
      return ThongkeLoginResult(false, 'Lỗi mạng: ${e.message}');
    } catch (e) {
      return ThongkeLoginResult(false, 'Lỗi: $e');
    }
  }

  /// Live username lookup.
  /// v2.57.0: phân biệt 3 trạng thái - exists / notExists / unknown
  Future<UsernameLookupResult> lookupUsername(String email) async {
    if (email.trim().length < 2) {
      return UsernameLookupResult.unknown(reason: 'empty');
    }
    try {
      // 1. GET /login (CookieManager tự lưu cookies)
      final getResp = await _dio.get('$baseUrl/login');
      if (getResp.statusCode != 200) {
        return UsernameLookupResult.unknown(reason: 'GET /login status ${getResp.statusCode}');
      }
      _captureResponseCookies(getResp);

      final html = getResp.data?.toString() ?? '';
      final csrfMatch = RegExp("name=[\"']_token[\"'][^>]+value=[\"']([^\"']+)").firstMatch(html)
          ?? RegExp("value=[\"']([^\"']+)[\"'][^>]+name=[\"']_token[\"']").firstMatch(html);
      if (csrfMatch == null) {
        return UsernameLookupResult.unknown(reason: 'no CSRF token');
      }
      final csrf = csrfMatch.group(1);

      final xsrf = _getCookieValue('XSRF-TOKEN');
      final xsrfHeader = xsrf != null ? Uri.encodeComponent(xsrf) : '';

      final response = await _dio.post(
        '$baseUrl/login',
        data: FormData.fromMap({
          '_token': csrf,
          'email': email.trim(),
          'password': '__lookup_dummy_password__',
        }),
        options: Options(
          headers: {
            'Referer': '$baseUrl/login',
            'X-XSRF-TOKEN': xsrfHeader,
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 419) {
        return UsernameLookupResult.unknown(reason: 'CSRF expired');
      }
      if (response.statusCode == 422) {
        // Thongke server trả 422 với message "Đăng nhập thất bại" cho CẢ 2 trường hợp:
        // - User tồn tại + sai password
        // - User không tồn tại
        // → Phân tích message để biết rõ
        String? errorMsg;
        if (response.data is Map) {
          final m = response.data as Map;
          if (m['errors'] is Map) {
            final errs = m['errors'] as Map;
            if (errs['email'] is List && (errs['email'] as List).isNotEmpty) {
              errorMsg = (errs['email'] as List).first.toString();
            }
          }
          if (errorMsg == null && m['message'] is String) {
            errorMsg = m['message'] as String;
          }
        }
        // Server confirm rõ "user không tồn tại"
        if (errorMsg != null && (
            errorMsg.toLowerCase().contains('không tồn tại') ||
            errorMsg.toLowerCase().contains('not found') ||
            errorMsg.toLowerCase().contains('does not exist'))) {
          return UsernameLookupResult.notFound(reason: errorMsg);
        }
        // Còn lại: default = user tồn tại (BV thường tạo account sẵn)
        return UsernameLookupResult.foundButWrongPassword();
      }
      // 302 = server tưởng login thật (dummy password) nhưng user tồn tại
      if (response.statusCode == 302) {
        return UsernameLookupResult.foundButWrongPassword();
      }
      // 200 với cookie login thành công
      if (response.statusCode == 200) {
        return UsernameLookupResult.foundButWrongPassword();
      }
      // Còn lại: HTTP status bất thường → unknown
      return UsernameLookupResult.unknown(reason: 'HTTP ${response.statusCode}');
    } catch (e) {
      return UsernameLookupResult.unknown(reason: 'Exception: $e');
    }
  }

  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // In-memory CookieJar bị reset khi app restart → chỉ check user info đã lưu
      final savedUser = prefs.getString(_kUsername);
      // v2.47.0: Đồng thời load HIS Pro token
      await loadHisProToken();
      if (savedUser == null) {
        return false;
      }
      // Thử gọi /home — CookieManager sẽ gửi cookies (nếu còn trong session này)
      final resp = await _dio.get(
        '$baseUrl/home',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (resp.statusCode == 200 && resp.realUri.toString().contains('/home')) {
        final username = _parseUsername(resp.data?.toString() ?? '') ?? savedUser;
        _cachedUsername = username;
        _cachedEmail = prefs.getString(_kEmail);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _cachedUsername = null;
    _cachedEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUsername);
    await prefs.remove(_kEmail);
    // Xóa cookies
    await _cookieJar.deleteAll();
  }

  // ===================================================================
  // Private helpers
  // ===================================================================

  /// Lấy raw value của cookie từ CookieJar (sync version).
  /// Dùng cookie manager's URI to get applicable cookies.
  String? _getCookieValue(String name) {
    // loadForRequest is async; we'll cache via last response instead
    return _lastResponseCookies[name];
  }

  /// Cache cookies từ response cuối cùng (sync, set bởi interceptor)
  Map<String, String> _lastResponseCookies = {};

  /// Lưu cookies từ response.Set-Cookie header
  void _captureResponseCookies(Response? response) {
    if (response == null) return;
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    for (final line in raw) {
      final semi = line.indexOf(';');
      final pair = (semi >= 0 ? line.substring(0, semi) : line).trim();
      final eq = pair.indexOf('=');
      if (eq > 0) {
        _lastResponseCookies[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
      }
    }
  }

  String? _parseUsername(String html) {
    if (html.isEmpty) return null;
    // Pattern 1 (AdminLTE cũ): <span class="hidden-xs">NAME</span>
    final m1 = RegExp(r'<span[^>]+class="[^"]*hidden-xs[^"]*"[^>]*>([^<]{3,40})</span>').firstMatch(html);
    if (m1 != null) {
      final v = m1.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // Pattern 2: <a data-toggle="dropdown" href="">NAME<span class="caret">
    // (AdminLTE mới + Bootstrap 3 - dùng cho user gemksm và nhiều user khác)
    final m2 = RegExp(r'data-toggle="dropdown"[^>]*>\s*([^<]{3,50}?)\s*<span[^>]*class="caret"').firstMatch(html);
    if (m2 != null) {
      final v = m2.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // Pattern 3: class="user-panel"... <p>NAME</p>
    final m3 = RegExp(r'class="user-panel"[^>]*>.*?<p[^>]*>([^<]{3,50})</p>', dotAll: true).firstMatch(html);
    if (m3 != null) {
      final v = m3.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // Pattern 4: class="dropdown-toggle"... NAME
    final m4 = RegExp(r'class="dropdown-toggle"[^>]*>\s*<[^>]*>([^<]{3,50})</').firstMatch(html);
    if (m4 != null) {
      final v = m4.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Lấy danh sách BN từ Data (dùng cookies đã login).
  /// Returns List<Map> hoặc null nếu lỗi.
  ///
  /// v2.22 fix: trước đây chỉ filter dept trên client + chỉ lấy BN trong ngày →
  /// nhiều khoa (đặc biệt ICU/HSTC) không có BN nào trong ngày đó vì BN nằm đa ngày,
  /// dẫn đến hiện data fake từ PatientSeed mà không có tên thật.
  /// Giờ:
  ///  - Window 14 ngày gần nhất (đủ dài cho ICU nội trú đa ngày, không timeout)
  ///  - Server-side filter: department[] (URL-encoded $department), treatment_type[]=03 (nội trú)
  ///  - Client-side lọc "đang nằm viện" = out_time null/empty (vì server không hỗ trợ)
  Future<List<Map<String, dynamic>>?> fetchPatients({
    DateTime? date,
    String? treatmentCode,
    String? department,
    int start = 0,
    int length = 500,
  }) async {
    try {
      // Window 14 ngày (từ 13 ngày trước đến hôm nay) cho nội trú + ngoại trú.
      // 7 ngày đôi khi quá ngắn với ICU, 30 ngày server timeout.
      final today = date ?? DateTime.now();
      final from = today.subtract(const Duration(days: 13));
      final fmt = (DateTime dt) =>
          '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final dateFrom = fmt(from);
      final dateTo = fmt(today);

      final params = <String, String>{
        'dateType': 'in',           // date_in (ngày vào viện)
        'date_from': dateFrom,
        'date_to': dateTo,
        'length': '$length',
        'start': '$start',
      };
      if (treatmentCode != null && treatmentCode.isNotEmpty) {
        params['treatment_code'] = treatmentCode;
      }
      if (department != null && department.isNotEmpty) {
        // Server chỉ chấp nhận filter server-side qua param `department[]` (multi-value).
        // VD: department[]=HSCC thuần tuý khi URL-encoded: department%5B%5D=HSCC
        // Dùng cách này thay vì client-filter, giảm payload 99% và lấy đúng BN.
        params['department[]'] = department;
        // Nội trú (treatment_type 03) kèm theo để chỉ lấy BN đang nằm.
        params['treatment_type[]'] = '03';
      }

      // Build URL manually để đảm bảo department[]%5B%5D encoding đúng
      // (Dio có thể tự encode nhưng tốt nhất viết rõ để tránh surprise).
      final qp = <String>[];
      qp.add('dateType=in');
      qp.add('date_from=$dateFrom');
      qp.add('date_to=$dateTo');
      qp.add('length=$length');
      qp.add('start=$start');
      if (treatmentCode != null && treatmentCode.isNotEmpty) {
        qp.add('treatment_code=${Uri.encodeQueryComponent(treatmentCode)}');
      }
      if (department != null && department.isNotEmpty) {
        // Server filter: department[] đúng (kể cả PK HSCC type=01 lẫn HSTC type=03)
        // KHÔNG gửi treatment_type[]=03 vì nhiều khoa (HSCC, KKB, DTCCLuu...) là
        // "Khám" (01) chứ không phải "Nội trú" (03). Nếu ép type=03 sẽ trả rỗng.
        qp.add('department%5B%5D=${Uri.encodeQueryComponent(department)}');
      }
      final url = '$baseUrl/emr/index/get-list-emr-treatment?${qp.join('&')}';

      final r = await _dio.get(
        url,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/emr/index',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (r.statusCode == 200 && r.data is Map) {
        final m = r.data as Map;
        if (m['data'] is List) {
          var list = List<Map<String, dynamic>>.from(m['data'] as List);

          // Defensive client-filter: đảm bảo chỉ trả BN đúng dept
          // (server đã filter qua department[], nhưng nếu có edge case thì vẫn lọc lại).
          if (department != null && department.isNotEmpty) {
            list = list.where((p) =>
                p['department_code']?.toString() == department).toList();
          }
          // KHÔNG lọc out_time: hiện TẤT CẢ BN trong khoa trong window 14 ngày
          // (kể cả đã ra viện trong kỳ này) — đúng ngữ nghĩa Y Tế Số hiển thị.
          // BN đang nằm thì out_time null/empty, BN đã ra viện thì có out_time.
          // Cách sort: ưu tiên BN đang nằm (out_time empty) lên đầu, sau đó theo
          // ngày vào giảm dần → BS dễ thấy ca đang điều trị.
          list.sort((a, b) {
            final aOut = (a['out_time']?.toString() ?? '').trim();
            final bOut = (b['out_time']?.toString() ?? '').trim();
            final aActive = aOut.isEmpty || aOut == '-' || aOut == 'null';
            final bActive = bOut.isEmpty || bOut == '-' || bOut == 'null';
            if (aActive != bActive) {
              return aActive ? -1 : 1; // active lên đầu
            }
            return 0; // giữ nguyên thứ tự
          });

          return list;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// v2.38.8: Login tới Data public API (113.163.187.3:8080) để lấy cookies cho fetch BN.
  /// Endpoint này có BN PK cấp cứu HSCC/CCS - không cần VPN.
  /// Returns username nếu thành công, null nếu fail.
  Future<String?> loginToPublic({
    required String email,
    required String password,
  }) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final jar = CookieJar();
      dio.interceptors.add(CookieManager(jar));

      // GET /login → lấy CSRF token từ HTML + XSRF cookie
      final r1 = await dio.get('$publicBaseUrl/login');
      String csrf = '';
      final m = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(r1.data ?? '');
      if (m != null) csrf = m.group(1) ?? '';
      if (csrf.isEmpty) {
        debugPrint('Public login: no CSRF token found');
        return null;
      }

      // POST /login với cookie + XSRF header
      final cookies1 = await jar.loadForRequest(Uri.parse('$publicBaseUrl/login'));
      final xsrfCookie1 = cookies1.firstWhere(
        (c) => c.name == 'XSRF-TOKEN',
        orElse: () => Cookie('XSRF-TOKEN', ''),
      );
      final xsrfToken = Uri.encodeQueryComponent(xsrfCookie1.value);
      final r2 = await dio.post(
        '$publicBaseUrl/login',
        data: {'email': email, 'password': password, '_token': csrf},
        options: Options(
          headers: {
            'X-XSRF-TOKEN': xsrfToken,
            'Referer': '$publicBaseUrl/login',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r2.statusCode == 302 || r2.statusCode == 200) {
// Check if we got session cookie
      final cookies = await jar.loadForRequest(Uri.parse(publicBaseUrl));
      if (cookies.any((c) => c.name == 'qlbv_session')) {
          debugPrint('Public login OK, cookies: ${cookies.length}');
          return email;
        }
      }
      debugPrint('Public login failed: ${r2.statusCode}');
      return null;
    } catch (e) {
      debugPrint('Public login error: $e');
      return null;
    }
  }

  /// v2.40.0: Lấy BN từ Data PUBLIC (113.163.187.3:8080) - CÓ BN PK CẤP CỨU HSCC/CCS!
  /// Endpoint: /emr-checker/emr-checker-list (server-side DataTables)
  ///
  /// v2.40.0 BREAKTHROUGH: Server respects param `department_catalog` (NOT `department_id`!)
  /// - `department_catalog=22` → server filters → total=13
  /// - `department_id=22` → server IGNORES → total=1000
  /// Param name MATTERS.
  ///
  /// Date format: 'YYYY-MM-DD HH:mm:ss' (web format, not just YYYY-MM-DD)
  ///
  /// v3.0.96: Default credentials lấy từ Credentials (XOR-encoded) - không lộ trong code
  Future<List<Map<String, dynamic>>?> fetchPatientsPublic({
    String? email,                 // default: từ Credentials
    String? password,              // default: từ Credentials
    int? departmentCatalogId,      // PRIMARY: server filter (22=HSCC, 23=CCS, ...)
    String? department,            // fallback dept code for client-side filter
    String? treatmentCode,         // search by treatment code (server supports)
    int? patientTypeId,            // server filter (1=BHYT, 6=Kham suc khoe, 42=Vien phi)
    int? treatmentTypeId,          // server filter (1=Kham, 2=DT ngoai tru, 3=DT noi tru)
    String filterType = 'date_in', // 'date_in' / 'date_out' / 'date_payment' / etc
    DateTime? from,
    DateTime? to,
    int length = 100,              // default 100 (UI can paginate)
    int start = 0,
  }) async {
    try {
      // v3.0.96: Lấy từ Credentials (XOR-encoded) thay vì hardcode
      final _email = email ?? Credentials.thongkeDefaultEmail;
      final _pwd = password ?? Credentials.thongkeDefaultPassword;

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ));
      final jar = CookieJar();
      dio.interceptors.add(CookieManager(jar));

      // Step 1: Login
      final r1 = await dio.get('$publicBaseUrl/login');
      String csrf = '';
      final m = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(r1.data ?? '');
      if (m != null) csrf = m.group(1) ?? '';
      if (csrf.isEmpty) {
        debugPrint('Public fetch: no CSRF token');
        return null;
      }

      final cookies1 = await jar.loadForRequest(Uri.parse('$publicBaseUrl/login'));
      final xsrf1 = cookies1.firstWhere(
        (c) => c.name == 'XSRF-TOKEN',
        orElse: () => Cookie('XSRF-TOKEN', ''),
      ).value;

      final r2 = await dio.post(
        '$publicBaseUrl/login',
        data: {'email': _email, 'password': _pwd, '_token': csrf},
        options: Options(
          headers: {
            'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf1),
            'Referer': '$publicBaseUrl/login',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r2.statusCode != 302) {
        debugPrint('Public login failed: ${r2.statusCode} (email=$_email)');
        return null;
      }

      // Step 2: Build query params (web-compatible)
      // v2.40.0: Use department_catalog (NOT department_id) - server respects this
      // v3.0.89: Normalize "Hôm nay" - server expects from <= to, both ở start/end of day
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      // Auto-detect: nếu from == to (cùng 1 ngày, cùng giờ) → mở rộng to đến cuối ngày
      DateTime fromDt, toDt;
      if (from != null && to != null &&
          from!.year == to!.year && from!.month == to!.month && from!.day == to!.day) {
        fromDt = DateTime(from!.year, from!.month, from!.day);
        toDt = DateTime(to!.year, to!.month, to!.day, 23, 59, 59);
      } else {
        fromDt = from ?? todayStart.subtract(const Duration(days: 13));
        toDt = to ?? todayEnd;
      }
      String two(int n) => n.toString().padLeft(2, '0');
      // Web format: 'YYYY-MM-DD HH:mm:ss' - server expects this exact format
      String fmtDt(DateTime dt) {
        return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
      }
      // v2.45.0: Map all 6 filterType options to web date_type values
      // in -> date_in, out -> date_out, payment -> date_payment, etc.
      String filterParam = filterType;
      switch (filterType) {
        case 'in': filterParam = 'date_in'; break;
        case 'out': filterParam = 'date_out'; break;
        case 'payment': filterParam = 'date_payment'; break;
        case 'intruction': filterParam = 'date_intruction'; break;
        case 'create': filterParam = 'date_create'; break;
        case 'update': filterParam = 'date_update'; break;
      }

      final params = <String, String>{
        'date_from': fmtDt(fromDt),
        'date_to': fmtDt(toDt),
        'date_type': filterParam,  // web uses 'date_type' (not 'filter_type')
        'length': '$length',
        'start': '$start',
      };

      // v2.40.0: Server respects these param names
      if (departmentCatalogId != null) {
        params['department_catalog'] = '$departmentCatalogId';
      }
      if (patientTypeId != null) {
        params['patient_type'] = '$patientTypeId';
      }
      if (treatmentTypeId != null) {
        params['treatment_type'] = '$treatmentTypeId';
      }
      if (treatmentCode != null && treatmentCode.isNotEmpty) {
        params['treatment_code'] = treatmentCode;
      }

      final queryStr = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final url = '$publicBaseUrl/emr-checker/emr-checker-list?$queryStr';

      // Fresh XSRF
      final cookies3 = await jar.loadForRequest(Uri.parse(publicBaseUrl));
      final xsrf3 = cookies3.firstWhere(
        (c) => c.name == 'XSRF-TOKEN',
        orElse: () => Cookie('XSRF-TOKEN', ''),
      ).value;

      final r3 = await dio.get(url, options: Options(headers: {
        'Referer': '$publicBaseUrl/emr-checker/emr-checker-index',
        'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf3),
      }));

      if (r3.statusCode != 200) {
        debugPrint('Public fetch failed: ${r3.statusCode}');
        return null;
      }
      if (r3.data is! Map) return null;

      final items = (r3.data['data'] as List?) ?? [];
      final list = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is Map) {
          // Map response fields từ EMR-checker (lowercase + last_department)
          final p = <String, dynamic>{
            'ID': raw['treatment_code'], // dùng treatment_code làm ID
            'TDL_TREATMENT_CODE': raw['treatment_code'],
            'TDL_PATIENT_CODE': raw['tdl_patient_code'],
            'TDL_PATIENT_UNSIGNED_NAME': raw['tdl_patient_name'] ?? '',
            'TDL_PATIENT_NAME': raw['tdl_patient_name'],
            'TDL_PATIENT_DOB': raw['tdl_patient_dob'],
            'TDL_PATIENT_ADDRESS': raw['tdl_patient_address'],
            'TDL_PATIENT_PHONE': raw['tdl_patient_phone'] ?? raw['tdl_patient_mobile'],
            'TDL_PATIENT_RELATIVE_MOBILE': raw['tdl_patient_relative_mobile'] ?? raw['tdl_patient_relative_phone'],
            'TDL_HEIN_CARD_NUMBER': raw['tdl_hein_card_number'],
            'TREATMENT_TYPE_NAME': raw['treatment_type_name'],
            'PATIENT_TYPE_NAME': raw['patient_type_name'],
            'IN_TIME': raw['in_time'],
            'OUT_TIME': raw['out_time'],
            'LAST_DEPARTMENT_RAW': raw['last_department'],  // v2.39.0: keep raw for client filter
            'DEPARTMENT_CODE': _deptNameToCode(raw['last_department']),
            'DEPARTMENT_NAME': raw['last_department'],
            'IS_BHYT': (raw['patient_type_name'] ?? '').toString().contains('BHYT'),
            'IS_PAUSE': false,
            'treatment_code': raw['treatment_code'],
            'tdl_patient_name': raw['tdl_patient_name'],
            '_DATA_SOURCE': 'PUBLIC_EMR_CHECKER',
          };
          list.add(p);
        }
      }

      // v2.39.0: CLIENT-SIDE filter by department code (server ignores dept param)
      var filtered = list;
      if (department != null && department.isNotEmpty) {
        filtered = list.where((p) {
          final code = p['DEPARTMENT_CODE']?.toString() ?? '';
          if (code == department) return true;
          // Fallback: match by last_department raw text
          final raw = p['LAST_DEPARTMENT_RAW']?.toString() ?? '';
          return _deptRawMatchesCode(raw, department);
        }).toList();
        debugPrint('Public fetch: ${list.length} → filtered to ${filtered.length} for $department');
      } else {
        debugPrint('Public fetch OK: ${list.length} BN (all depts)');
      }
      return filtered;
    } catch (e) {
      debugPrint('Public fetch error: $e');
      return null;
    }
  }

  /// v2.39.0: Map `last_department` raw text → dept code (HSCC/CCS/...)
  /// Used for client-side filtering since server ignores dept_id param.
  bool _deptRawMatchesCode(String raw, String code) {
    final r = raw.toLowerCase();
    switch (code) {
      case 'HSCC':
        return r.contains('cấp cứu') && !r.contains('lưu') && !r.contains('phụ sản') && !r.contains('cs2') && !r.contains('cơ sở 2');
      case 'KCC_CS2':
        // Khoa Cấp cứu Cơ sở 2
        return (r.contains('cấp cứu') || r.contains('hscc')) && (r.contains('cs2') || r.contains('cơ sở 2'));
      case 'DTCCLuu':
        return r.contains('lưu') || r.contains('dự trữ');
      case 'DTCCLUUCS2':
        return r.contains('lưu') && (r.contains('cs2') || r.contains('cơ sở 2'));
      case 'CCS':
        return r.contains('ccs') || (r.contains('cấp cứu') && r.contains('phụ')) || r.contains('cấp cứu sản');
      case 'KPS':
        return r.contains('phụ sản') && !r.contains('cấp');
      case 'HSTC':
        return r.contains('hồi sức tích cực') || r.contains('hstc');
      case 'NTK':
        return r.contains('nội thần kinh') || r.contains('thần kinh');
      case 'NTTN':
        return r.contains('nội tổng hợp') || r.contains('dvntk') || r.contains('nội tiêu hóa');
      case 'NTM':
        return r.contains('nội tiết') || r.contains('tiểu đường') || r.contains('ntm');
      case 'NTKN':
        return r.contains('nội thận') || r.contains('thận') || r.contains('lọc máu');
      case 'KN':
        return r.contains('nhi') && !r.contains('sơ sinh');
      case 'KM':
        return r.contains('mắt') || r.contains('km');
      case 'KRHM':
        return (r.contains('răng') && r.contains('hàm')) || r.contains('krhm') || r.contains('rhm');
      case 'KTMH':
        return (r.contains('tai') && r.contains('mũi') && r.contains('họng')) || r.contains('ktmh') || r.contains('tmh');
      case 'KUB':
        return r.contains('ung bướu') || r.contains('kub');
      case 'KYHCT':
        return (r.contains('y học cổ truyền') || r.contains('yhct') || r.contains('cổ truyền') || r.contains('phục hồi')) && !r.contains('cs2');
      case 'KYHCTCS2':
        return (r.contains('y học cổ truyền') || r.contains('yhct') || r.contains('cổ truyền')) && (r.contains('cs2') || r.contains('cơ sở 2'));
      case 'NGTH':
        return r.contains('ngoại thận') || r.contains('tiết niệu');
      case 'NGCT':
        return r.contains('ngoại chấn thương') || r.contains('chấn thương');
      case 'KSNK':
        return r.contains('nhiễm khuẩn') || r.contains('ksnk');
      case 'PTGMHS':
        return r.contains('gây mê') || r.contains('phẫu thuật') || r.contains('ptgmhs');
      case 'KKB':
        return r.contains('khám bệnh') || r.contains('kkb') || r.contains('khám chuyên gia') || r.contains('khám sức khỏe cán bộ');
      case 'KKB_CS2':
        return r.contains('khám bệnh') && (r.contains('cs2') || r.contains('cơ sở 2'));
      case 'DTYC':
        return r.contains('yêu cầu') || r.contains('dtyc');
      default:
        // v2.47.0: Catch-all - nếu code chưa được map, KHÔNG filter (để BN hiện ra thay vì ẩn)
        return true;
    }
  }

  /// Map department code → ID (HSCC=22, CCS=23, etc.)
  int? _deptCodeToId(String code) {
    final map = {
      'HSCC': 22, 'CCS': 23, 'DTYC': 24, 'DVNTK': 26, 'DVTMCT': 27,
      'HSTC': 29, 'NTK': 30, 'NTTN': 31, 'KM': 32, 'NGCT': 33,
      'NGTH': 34, 'KN': 35, 'NTM': 36, 'KNTH': 37, 'KPS': 38,
      'KTNT': 39, 'PTGMHS': 40, 'KRHM': 41, 'KTMH': 42, 'KTN': 43,
      'KYHCT': 44, 'KKB': 45, 'KUB': 46, 'KSNK': 53, 'PTP': 65,
      'HSCCL': 68, 'CCSVL': 69, 'KDTTHVN': 70, 'DTCCLuu': 71,
    };
    return map[code];
  }

  /// Map department name từ EMR-checker → code
  String _deptNameToCode(String? name) {
    if (name == null || name.isEmpty) return '';
    if (name.contains('Cấp Cứu') && !name.contains('Lưu') && !name.contains('Phụ sản')) return 'HSCC';
    // v2.45.0: "Khoa Phụ sản" (KPS id=38) has data, "Khoa Phụ sản_CCS" (CCS id=23) returns 0
    // Map "Phụ sản" -> KPS (default), chi map "CCS" neu ten co "CCS"
    if (name.contains('CCS') || name.contains('Cấp Cứu Sản')) return 'CCS';
    if (name.contains('Phụ sản')) return 'KPS';  // v2.45.0: KPS thay vi CCS
    if (name.contains('Lưu')) return 'DTCCLuu';
    if (name.contains('Hồi Sức') || name.contains('HSTC')) return 'HSTC';
    return '';
  }

  // ============================================================
  // v2.38.9: CATALOG APIs - Tích hợp danh mục từ menu trái Data
  // Endpoints: /category/bhyt/fetch-*, /khth/get-*, /danh-muc/*
  // ============================================================

  /// Helper: Login + gọi 1 GET endpoint trên publicBaseUrl, trả về Map JSON
  /// Dùng chung cho các catalog API (medicine, CLS, supply, staff, bed, equipment, DVKT)
  /// v3.0.77: Robust hơn - thử nhiều pattern CSRF + fallback không CSRF
  Future<Map<String, dynamic>?> _publicCatalogCall({
    required String endpoint,
    required String email,
    required String password,
    Map<String, String>? params,
  }) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json, text/html, */*',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ));
      final jar = CookieJar();
      dio.interceptors.add(CookieManager(jar));

      // Step 1: GET /login để lấy CSRF + session cookies
      final r1 = await dio.get('$publicBaseUrl/login');
      String csrf = '';
      final html = r1.data?.toString() ?? '';
      // v3.0.77: Thử nhiều pattern CSRF (Laravel 8-10 dùng _token, một số dùng csrf-token)
      final patterns = [
        RegExp(r'name="_token"\s+value="([^"]+)"'),
        RegExp(r'<meta\s+name="csrf-token"\s+content="([^"]+)"'),
        RegExp(r'"csrfToken"\s*:\s*"([^"]+)"'),
        RegExp(r'name="csrf_token"\s+value="([^"]+)"'),
      ];
      for (final p in patterns) {
        final m = p.firstMatch(html);
        if (m != null) {
          csrf = m.group(1) ?? '';
          if (csrf.isNotEmpty) break;
        }
      }
      if (csrf.isEmpty) {
        // v3.0.77: Không có CSRF - vẫn thử gọi API trực tiếp (một số API không cần CSRF)
        debugPrint('Catalog login: no CSRF found in /login, will try direct call');
      }

      // Step 2: Login (nếu có CSRF)
      if (csrf.isNotEmpty) {
        final cookies1 = await jar.loadForRequest(Uri.parse('$publicBaseUrl/login'));
        final xsrf1 = cookies1.firstWhere(
          (c) => c.name == 'XSRF-TOKEN',
          orElse: () => Cookie('XSRF-TOKEN', ''),
        ).value;

        final r2 = await dio.post(
          '$publicBaseUrl/login',
          data: {'email': email, 'password': password, '_token': csrf},
          options: Options(
            headers: {
              'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf1),
              'Referer': '$publicBaseUrl/login',
            },
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (r2.statusCode != 302) {
          debugPrint('Catalog login fail: ${r2.statusCode} (${r2.statusMessage})');
          // v3.0.77: Vẫn thử gọi API (một số trang cho public access)
        }
      }

      // Step 3: Gọi endpoint
      String queryStr = '';
      if (params != null && params.isNotEmpty) {
        queryStr = '?' + params.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
      }
      final url = endpoint.startsWith('http')
          ? '$endpoint$queryStr'
          : '$publicBaseUrl$endpoint$queryStr';

      final cookies3 = await jar.loadForRequest(Uri.parse(publicBaseUrl));
      final xsrf3 = cookies3.firstWhere(
        (c) => c.name == 'XSRF-TOKEN',
        orElse: () => Cookie('XSRF-TOKEN', ''),
      ).value;

      final r3 = await dio.get(url, options: Options(headers: {
        'Referer': '$publicBaseUrl${endpoint.split('?').first}',
        'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf3),
      }));

      if (r3.statusCode != 200) {
        debugPrint('Catalog fetch fail: ${r3.statusCode} $url');
        return null;
      }
      if (r3.data is! Map) return null;
      return r3.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Catalog call error: $e');
      return null;
    }
  }

  /// Kết quả trả về cho 1 catalog call
  /// - items: List<Map> các row
  /// - total: tổng số records
  /// - error: lỗi nếu có
  CatalogFetchResult _parseCatalogResponse(Map<String, dynamic>? resp, String catalogName) {
    if (resp == null) {
      return CatalogFetchResult(items: const [], total: 0, error: 'No response');
    }
    final items = (resp['data'] as List?) ?? [];
    final total = (resp['recordsTotal'] ?? items.length) as int;
    debugPrint('$catalogName: $total records, got ${items.length}');
    return CatalogFetchResult(
      items: items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
      total: total,
      error: null,
    );
  }

  /// v2.38.9: Danh mục THUỐC BHYT (4924 items)
  /// Endpoint: /category/bhyt/fetch-medicine-catalog
  /// Sample fields: ma_thuoc, ten_hoat_chat, ten_thuoc, don_vi_tinh, ham_luong,
  ///                duong_dung, ma_duong_dung, dang_bao_che, so_dang_ky, so_luong, don_gia
  Future<CatalogFetchResult> fetchMedicineCatalogPublic({
    required String email,
    required String password,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/category/bhyt/fetch-medicine-catalog',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'Medicine');
  }

  /// v2.38.9: Danh mục DỊCH VỤ / CLS (8393 items)
  /// Endpoint: /category/bhyt/fetch-service-catalog
  /// Sample fields: ma_dich_vu, ten_dich_vu, don_gia, quy_trinh, cskcb_cgkt, cskcb_cls
  Future<CatalogFetchResult> fetchClsCatalogPublic({
    required String email,
    required String password,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/category/bhyt/fetch-service-catalog',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'CLS');
  }

  /// v2.38.9: Danh mục VẬT TƯ Y TẾ (1142 items)
  /// Endpoint: /category/bhyt/fetch-medical-supply-catalog
  /// Sample fields: ma_vat_tu, nhom_vat_tu, ten_vat_tu, ma_hieu, quy_cach, hang_sx, nuoc_sx, don_gia
  Future<CatalogFetchResult> fetchMedicalSupplyCatalogPublic({
    required String email,
    required String password,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/category/bhyt/fetch-medical-supply-catalog',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'Supply');
  }

  /// v2.38.9: Danh mục NHÂN VIÊN Y TẾ (762 items)
  /// Endpoint: /category/bhyt/fetch-medical-staff
  /// Sample fields: ma_bhxh, ho_ten, ma_khoa, ten_khoa, macchn, ngaycap_cchn, noicap_cchn
  Future<CatalogFetchResult> fetchMedicalStaffCatalogPublic({
    required String email,
    required String password,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/category/bhyt/fetch-medical-staff',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'Staff');
  }

  /// v2.38.9: Danh mục KHOA - GIƯỜNG (49 items)
  /// Endpoint: /category/bhyt/fetch-department-bed-catalog
  /// Sample fields: ma_khoa, ten_khoa, ban_kham, giuong_pd, giuong_2015, giuong_tk, giuong_hstc, giuong_hscc
  Future<CatalogFetchResult> fetchDepartmentBedCatalogPublic({
    required String email,
    required String password,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/category/bhyt/fetch-department-bed-catalog',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'DeptBed');
  }

  /// v2.38.9: Danh mục THIẾT BỊ Y TẾ (1094 items)
  /// Endpoint: /category/bhyt/fetch-equipment-catalog
  /// Sample fields: ky_hieu, ten_tb, congty_sx, nuoc_sx, nam_sx, nam_sd, ma_may, so_luu_hanh
  Future<CatalogFetchResult> fetchEquipmentCatalogPublic({
    required String email,
    required String password,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/category/bhyt/fetch-equipment-catalog',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'Equipment');
  }

  /// v2.38.9: Danh sách DỊCH VỤ KỸ THUẬT đã dùng (7535 records với date filter)
  /// Endpoint: /khth/get-dvkt
  /// Sample fields: tdl_treatment_code, tdl_patient_name, tdl_patient_dob,
  ///                tdl_service_name, tdl_intruction_time, hein_card_number,
  ///                tdl_request_username, amount, price, execute_room_name
  Future<CatalogFetchResult> fetchDvktCatalogPublic({
    required String email,
    required String password,
    String? dateFrom,  // YYYY-MM-DD
    String? dateTo,
    String? search,
    int start = 0,
    int length = 100,
  }) async {
    final params = <String, String>{
      'draw': '1',
      'start': '$start',
      'length': '$length',
    };
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) {
      params['search[value]'] = search;
    }
    final resp = await _publicCatalogCall(
      endpoint: '/khth/get-dvkt',
      email: email,
      password: password,
      params: params,
    );
    return _parseCatalogResponse(resp, 'DVKT');
  }

  /// v2.60.0: Danh mục ICD-10 codes (paginates, cần fetch all hoặc theo keyword)
  /// Endpoint: /khth/get-danh-muc-icd (returns List, not DataTable format)
  /// Sample: {id: "A40.8", text: "A40.8 - Nhiễm trùng hệ thống do liên cầu khác"}
  /// v2.60.0: Search case-insensitive + fallback HisCatalogService (174+) nếu public fail
  /// v2.60.0: External fallback: https://icd.kcb.vn/icd-10/icd10 (BV Vạn Ninh)
  /// v2.98.2: Update URL → https://icd.kcb.vn/icd-10-tt06/icd10-tt06 (TT06 Bộ Y tế)
  /// v2.98.4: URL cũ không khả dụng → dùng https://tracuu-icd10.web.app/ (web app Firebase)
  Future<List<Map<String, dynamic>>> fetchIcdCodesPublic({
    required String email,
    required String password,
    String? search,
  }) async {
    // v2.64.0: Ưu tiên HIS Pro cache (174+ items, nhanh - không qua network)
    // Fallback: public API chậm → chỉ gọi khi cache rỗng
    final fromCache = await _fallbackIcd(search);
    if (fromCache.isNotEmpty) {
      debugPrint('ICD từ HIS Pro cache: ${fromCache.length}');
      return fromCache;
    }

    // Cache rỗng → gọi public API (chậm, có thể fail)
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ));
      final jar = CookieJar();
      dio.interceptors.add(CookieManager(jar));

      // Login
      final r1 = await dio.get('$publicBaseUrl/login');
      String csrf = '';
      final m = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(r1.data ?? '');
      if (m != null) csrf = m.group(1) ?? '';
      if (csrf.isEmpty) return await _fallbackIcd(search);
      final cookies1 = await jar.loadForRequest(Uri.parse('$publicBaseUrl/login'));
      final xsrf1 = cookies1.firstWhere(
        (c) => c.name == 'XSRF-TOKEN',
        orElse: () => Cookie('XSRF-TOKEN', ''),
      ).value;

      await dio.post(
        '$publicBaseUrl/login',
        data: {'email': email, 'password': password, '_token': csrf},
        options: Options(headers: {
          'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf1),
          'Referer': '$publicBaseUrl/login',
        }, validateStatus: (s) => s != null && s < 500),
      );

      final cookies3 = await jar.loadForRequest(Uri.parse(publicBaseUrl));
      final xsrf3 = cookies3.firstWhere(
        (c) => c.name == 'XSRF-TOKEN',
        orElse: () => Cookie('XSRF-TOKEN', ''),
      ).value;

      // ICD trả về list, có thể phân trang — get all + filter local
      final allItems = <Map<String, dynamic>>[];
      String? lastId;  // for pagination
      
      for (int i = 0; i < 50; i++) {  // max 50 pages
        final r = await dio.get(
          '$publicBaseUrl/khth/get-danh-muc-icd',
          queryParameters: {
            if (lastId != null) 'q': lastId,
          },
          options: Options(headers: {
            'Referer': '$publicBaseUrl/khth/dich-vu-ky-thuat-index',
            'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf3),
            'X-Requested-With': 'XMLHttpRequest',
          }),
        );
        if (r.statusCode != 200) break;
        final data = r.data;
        if (data is! List || data.isEmpty) break;
        int lastSizeBefore = allItems.length;
        for (final item in data) {
          if (item is Map) {
            final id = item['id']?.toString() ?? '';
            final text = item['text']?.toString() ?? '';
            if (search == null || search.isEmpty ||
                id.toLowerCase().contains(search.toLowerCase()) ||
                text.toLowerCase().contains(search.toLowerCase())) {
              allItems.add(Map<String, dynamic>.from(item));
            }
            lastId = id;
          }
        }
        // Stop if no new items
        if (allItems.length == lastSizeBefore) break;
        // Stop if less than 50 (last page)
        if (data.length < 50) break;
      }

      debugPrint('ICD codes: fetched ${allItems.length}');
      // v2.60.0: Nếu public API trả 0 items → fallback HisCatalogService
      if (allItems.isEmpty) {
        debugPrint('ICD public returned 0, falling back to HisCatalogService...');
        return await _fallbackIcd(search);
      }
      return allItems;
    } catch (e) {
      debugPrint('ICD fetch error: $e, falling back...');
      return await _fallbackIcd(search);
    }
  }

  /// v2.60.0: Fallback ICD search dùng HisCatalogService (174+ items đã cache)
  /// Hoặc fallback online từ https://tracuu-icd10.web.app/ (web app Firebase - 12.000+ mã ICD)
  Future<List<Map<String, dynamic>>> _fallbackIcd(String? search) async {
    try {
      final q = (search ?? '').toLowerCase().trim();
      // v2.75.6: Diacritic-insensitive search
      final qNoDiac = removeDiacritics(q);
      final fromCatalog = HisCatalogService.instance.icds
          .where((item) {
            if (q.isEmpty) return true;
            if (item.code.toLowerCase().contains(q)) return true;
            if (item.name.toLowerCase().contains(q)) return true;
            if (qNoDiac.isNotEmpty &&
                removeDiacritics(item.name.toLowerCase()).contains(qNoDiac)) {
              return true;
            }
            return false;
          })
          .take(500)
          .map((item) => {
                'id': item.code,
                'text': '${item.code} - ${item.name}',
                'source': 'HIS_PRO_CACHE',
              })
          .toList();
      debugPrint('ICD fallback (HIS_PRO_CACHE): ${fromCatalog.length}');
      // Nếu vẫn 0 (HIS Pro chưa cache), thử fetch online từ kcb.vn
      if (fromCatalog.isEmpty) {
        debugPrint('ICD fallback to https://tracuu-icd10.web.app/ (web app Firebase)...');
        // v2.98.4: tracuu-icd10.web.app là web app (HTML) - không dùng được cho JSON API
        // BS sẽ tra cứu qua webview từ UI (Tiện ích → ICD-10 → "Mở web tra cứu")
        debugPrint('⚠ ICD web app không có JSON API - trả empty list, dùng webview từ UI');
        return [];
      }
      return fromCatalog;
    } catch (e) {
      debugPrint('ICD fallback error: $e');
      return [];
    }
  }

  // ============================================================
  // v2.40.0: DROPDOWN CATALOGS - load cho filter UI giong web
  // ============================================================

  /// v2.40.0: Load danh sách departments cho dropdown "Khoa/Phòng/TT"
  /// Endpoint: /index/category-department-catalog
  /// Returns: [{id: 22, department_code: "HSCC", department_name: "Khoa Cấp Cứu"}, ...]
  Future<List<Map<String, dynamic>>> fetchDepartmentCatalog() async {
    try {
      final result = await _publicCatalogCall(
        endpoint: '/index/category-department-catalog',
        email: Credentials.thongkeDefaultEmail,
        password: Credentials.thongkeDefaultPassword,
      );
      if (result == null) return [];
      final data = (result['data'] as List?) ?? [];
      if (data.isNotEmpty) return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      // If 'data' is empty, response might BE the list directly
      if (result.containsKey('id')) {
        return [Map<String, dynamic>.from(result)];
      }
      return [];
    } catch (e) {
      debugPrint('fetchDepartmentCatalog error: $e');
      return [];
    }
  }

  /// v2.40.0: Load patient types cho dropdown "Đối tượng"
  /// Endpoint: /index/category-patient-type
  /// Returns: [{id: 1, patient_type_code: "01", patient_type_name: "BHYT"}, ...]
  Future<List<Map<String, dynamic>>> fetchPatientTypeCatalog() async {
    try {
      final result = await _publicCatalogCall(
        endpoint: '/index/category-patient-type',
        email: Credentials.thongkeDefaultEmail,
        password: Credentials.thongkeDefaultPassword,
      );
      if (result == null) return [];
      final data = (result['data'] as List?) ?? [];
      if (data.isNotEmpty) return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (result.containsKey('id')) return [Map<String, dynamic>.from(result)];
      return [];
    } catch (e) {
      debugPrint('fetchPatientTypeCatalog error: $e');
      return [];
    }
  }

  /// v2.40.0: Load treatment types cho dropdown "Diện điều trị"
  /// Endpoint: /index/category-treatment-type
  /// Returns: [{id: 1, treatment_type_code: "01", treatment_type_name: "Khám"}, ...]
  Future<List<Map<String, dynamic>>> fetchTreatmentTypeCatalog() async {
    try {
      final result = await _publicCatalogCall(
        endpoint: '/index/category-treatment-type',
        email: Credentials.thongkeDefaultEmail,
        password: Credentials.thongkeDefaultPassword,
      );
      if (result == null) return [];
      final data = (result['data'] as List?) ?? [];
      if (data.isNotEmpty) return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (result.containsKey('id')) return [Map<String, dynamic>.from(result)];
      return [];
    } catch (e) {
      debugPrint('fetchTreatmentTypeCatalog error: $e');
      return [];
    }
  }

  /// v2.40.0: SMART SEARCH - tìm BN theo tên/mã ĐT/mã BN (server-side)
  /// Search qua endpoint /emr-checker/emr-checker-list với keyword param
  Future<List<Map<String, dynamic>>> searchPatientsPublic({
    required String keyword,
    DateTime? from,
    DateTime? to,
    int length = 50,
  }) async {
    if (keyword.trim().isEmpty) return [];

    try {
      // Use same login flow as fetchPatientsPublic
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest'},
      ));
      final jar = CookieJar();
      dio.interceptors.add(CookieManager(jar));

      // Login
      final r1 = await dio.get('$publicBaseUrl/login');
      final csrf = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(r1.data ?? '')?.group(1) ?? '';
      if (csrf.isEmpty) return [];
      final cookies1 = await jar.loadForRequest(Uri.parse('$publicBaseUrl/login'));
      final xsrf1 = cookies1.firstWhere((c) => c.name == 'XSRF-TOKEN', orElse: () => Cookie('XSRF-TOKEN', '')).value;
      final r2 = await dio.post('$publicBaseUrl/login',
          data: {'email': Credentials.thongkeDefaultEmail, 'password': Credentials.thongkeDefaultPassword, '_token': csrf},
          options: Options(headers: {
            'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf1),
            'Referer': '$publicBaseUrl/login',
          }, validateStatus: (s) => s != null && s < 500));
      if (r2.statusCode != 302) return [];

      // Search with keyword via treatment_code (server supports this)
      final today = DateTime.now();
      final fromDt = from ?? today.subtract(const Duration(days: 365));  // Search wider
      final toDt = to ?? today;
      String two(int n) => n.toString().padLeft(2, '0');
      String fmtDt(DateTime dt) => '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';

      final params = <String, String>{
        'date_from': fmtDt(fromDt),
        'date_to': fmtDt(toDt),
        'date_type': 'date_in',
        'treatment_code': keyword,  // server supports searching by treatment_code
        'length': '$length',
        'start': '0',
      };

      final queryStr = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final url = '$publicBaseUrl/emr-checker/emr-checker-list?$queryStr';

      final cookies3 = await jar.loadForRequest(Uri.parse(publicBaseUrl));
      final xsrf3 = cookies3.firstWhere((c) => c.name == 'XSRF-TOKEN', orElse: () => Cookie('XSRF-TOKEN', '')).value;

      final r3 = await dio.get(url, options: Options(headers: {
        'Referer': '$publicBaseUrl/emr-checker/emr-checker-index',
        'X-XSRF-TOKEN': Uri.encodeQueryComponent(xsrf3),
      }));
      if (r3.statusCode != 200 || r3.data is! Map) return [];

      final items = (r3.data['data'] as List?) ?? [];
      return items.whereType<Map>().map((m) {
        return {
          'ID': m['treatment_code'],
          'TDL_TREATMENT_CODE': m['treatment_code'],
          'TDL_PATIENT_CODE': m['tdl_patient_code'],
          'TDL_PATIENT_UNSIGNED_NAME': m['tdl_patient_name'] ?? '',
          'TDL_PATIENT_NAME': m['tdl_patient_name'],
          'TDL_PATIENT_DOB': m['tdl_patient_dob'],
          'TDL_HEIN_CARD_NUMBER': m['tdl_hein_card_number'],
          'TREATMENT_TYPE_NAME': m['treatment_type_name'],
          'PATIENT_TYPE_NAME': m['patient_type_name'],
          'DEPARTMENT_NAME': m['last_department'],
          'IN_TIME': m['in_time'],
          '_DATA_SOURCE': 'PUBLIC_SEARCH',
        };
      }).toList();
    } catch (e) {
      debugPrint('searchPatientsPublic error: $e');
      return [];
    }
  }
}

/// v2.38.9: Kết quả trả về cho 1 catalog call
class CatalogFetchResult {
  final List<Map<String, dynamic>> items;
  final int total;
  final String? error;

  CatalogFetchResult({
    required this.items,
    required this.total,
    this.error,
  });

  bool get hasError => error != null;
  bool get isEmpty => items.isEmpty;
}

class ThongkeLoginResult {
  final bool success;
  final String message;
  final String? username;

  ThongkeLoginResult(this.success, this.message, {this.username});
}

class UsernameLookupResult {
  /// v2.57.0: 3 trạng thái rõ ràng
  /// - exists=true  → user có trên server (chắc chắn)
  /// - exists=false → user KHÔNG có trên server (chắc chắn - server báo rõ)
  /// - exists=null  → không kiểm tra được (server lỗi/mạng) → BÁO KHÔNG RÕ
  final bool? userExists;
  final bool? wrongPasswordHint;
  final String? reason;

  const UsernameLookupResult._(this.userExists, this.wrongPasswordHint, this.reason);

  factory UsernameLookupResult.foundButWrongPassword() =>
      const UsernameLookupResult._(true, true, null);
  factory UsernameLookupResult.notFound({String? reason}) =>
      UsernameLookupResult._(false, null, reason);
  factory UsernameLookupResult.unknown({String? reason}) =>
      UsernameLookupResult._(null, null, reason);
}

class RecentUser {
  final String email;
  final String name;
  final DateTime lastUsed;

  RecentUser({required this.email, required this.name, DateTime? lastUsed})
      : lastUsed = lastUsed ?? DateTime.now();

  String toPrefString() => '$email|$name|${lastUsed.millisecondsSinceEpoch}';

  factory RecentUser.fromPrefString(String s) {
    final parts = s.split('|');
    final email = parts.length > 0 ? parts[0] : '';
    final name = parts.length > 1 ? parts[1] : email;
    final ts = parts.length > 2 ? int.tryParse(parts[2]) : null;
    return RecentUser(
      email: email,
      name: name,
      lastUsed: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now(),
    );
  }
}
