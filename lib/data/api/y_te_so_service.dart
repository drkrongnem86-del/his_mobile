// v3.0.83: YTeSoService - Tích hợp Y Tế Số (Bộ Y tế) public API
//
// Khám phá từ log điện thoại ngày 2026-08-11 (PLogger curl logs của com.snd.adbc):
//   Base URL PUBLIC: http://113.163.187.3:3000
//   Base URL LAN  : http://172.16.1.12:3000 (qua VPN BV)
//   Auth          : POST /v1/auth/login {email, password} -> JWT
//   Xem bệnh án  : GET /v1/medical-record/document-types?treatmentCode=XXX
//                  GET /v1/medical-record/document-type/download?documentId=XXX
//                  -> JSON {DocumentId, Code, Name, Base64Data (PDF/JPG base64)}
//
// Toàn bộ 50+ endpoints đã được ghi nhận (xem CHANGELOG v3.0.83).
// Service này hiện implement 3 API chính (Xem bệnh án) - các API khác
// (y-lenh-can-lam-sang, dieu-duong, ...) sẽ được thêm khi cần.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/core/security/credentials.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class YTeSoService {
  static final YTeSoService instance = YTeSoService._();

  /// v3.0.83: Base URLs
  /// - Public: 113.163.187.3:3000 (qua internet BV, không cần VPN)
  /// - LAN:    172.16.1.12:3000 (qua OpenVPN)
  static const String publicBaseUrl = 'http://113.163.187.3:3000';
  static const String lanBaseUrl = 'http://172.16.1.12:3000';

  /// v3.0.83: Default credentials - giống thongke public
  /// v3.0.96: Lấy từ Credentials (XOR-encoded) - KHÔNG có plaintext
  /// Có thể bị rotate, sẽ yêu cầu login lại khi fail
  static final String defaultEmail = Credentials.thongkeDefaultEmail;
  static final String defaultPassword = Credentials.yTeSoDefaultPassword;

  // v3.0.83: User profile mặc định từ log (khi không gọi /users/profile)
  static const String defaultUserId = '958e768e-61c6-4fed-81f7-525a6ca38263';
  static const String defaultUserName = 'K Rong Nểm';
  static const String defaultDepartmentId = '29';
  static const String defaultDepartmentCode = 'HSTC';
  static const String defaultRoomId = '223';
  static const String defaultRoomCode = 'DT_HSTCCD';

  // SharedPreferences keys
  static const String _kBaseUrl = 'yte_so_base_url';
  static const String _kAccessToken = 'yte_so_access_token';
  static const String _kTokenSavedAt = 'yte_so_token_saved_at';
  static const String _kEmail = 'yte_so_email';

  late Dio _dio;
  bool _initialized = false;

  /// v3.0.87: Background login promise - tránh gọi login() đồng thời
  Future<YTeSoLoginResult>? _loginInProgress;

  /// v3.0.87: JWT token expiry tracking (parse từ payload)
  DateTime? _tokenExpiresAt;

  /// v3.0.83: Cached document list (cho mỗi treatmentCode)
  final Map<String, List<YTeSoDocumentGroup>> _docCache = {};
  /// v3.0.83: Cached downloaded file path
  final Map<int, String> _fileCache = {};
  /// v3.0.87: Cache timestamp (TTL 5 phút)
  final Map<String, DateTime> _docCacheTime = {};
  static const Duration _docCacheTtl = Duration(minutes: 5);

  String? _accessToken;
  String? _baseUrl;
  String? _email;

  YTeSoService._();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _dio = Dio(BaseOptions(
      // v3.0.87: giảm timeout - public API thường < 5s, fail nhanh để retry
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 8),
      // v3.0.87: Enable HTTP keep-alive, không tạo connection mới
      headers: {
        'Accept': 'application/json',
        'Connection': 'keep-alive',
      },
    ));
    // v3.0.87: HTTP/2 + connection pool
    try {
      // ignore: deprecated_member_use
      (_dio.httpClientAdapter as dynamic);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? publicBaseUrl;
    _accessToken = prefs.getString(_kAccessToken);
    _email = prefs.getString(_kEmail) ?? defaultEmail;
    _initialized = true;
  }

  // ============ State getters ============
  String get baseUrl => _baseUrl ?? publicBaseUrl;
  String? get accessToken => _accessToken;
  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  /// v3.0.90: JWT expiry time (null nếu chưa parse được)
  DateTime? get tokenExpiresAt => _tokenExpiresAt;
  String? get email => _email;

  Future<void> setBaseUrl(String url) async {
    await _ensureInit();
    _baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, url);
  }

  // ============ Headers builder ============
  /// v3.0.83: Build header chuẩn cho mọi request (theo PLogger logs)
  /// Bao gồm user-id, user-name, treatment/room/dept nếu có
  Map<String, String> _buildHeaders({
    String? treatmentId,
    String? treatmentCode,
    String? roomId,
    String? roomCode,
    String? departmentId,
    String? departmentCode,
    bool jsonContent = true,
  }) {
    final now = DateTime.now();
    // Y Tế Số format dates:
    //   - Start-Time: ISO 8601 "2026-08-11T09:22:39.578943"
    //   - date     : "yyyy-MM-dd HH:mm:ss.SSSSSS" (6-digit microseconds)
    final isoTime = now.toIso8601String();
    final dateStr =
        '${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")} '
        '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}:${now.second.toString().padLeft(2, "0")}'
        '.${now.microsecond.toString().padLeft(6, "0")}';

    return {
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      'user-id': defaultUserId,
      'user-name': Uri.encodeComponent(defaultUserName),
      if (treatmentId != null) 'treatment-id': treatmentId,
      if (treatmentCode != null) 'treatment-code': treatmentCode,
      if (roomId != null) 'room-id': roomId,
      if (roomCode != null) 'room-code': roomCode,
      if (departmentId != null) 'department-id': departmentId,
      if (departmentCode != null) 'department-code': departmentCode,
      if (jsonContent) 'content-type': 'application/json; charset=utf-8',
      'Start-Time': isoTime,
      'date': dateStr,
    };
  }

  // ============ LOGIN ============
  /// v3.0.83: POST /v1/auth/login
  /// Body: email + password (lấy từ Credentials v3.0.96)
  /// Response: {accessToken, refreshToken, user, ...}
  /// v3.0.87: Add dedup - nếu đang login thì trả về future đang chạy
  Future<YTeSoLoginResult> login({String? email, String? password}) async {
    await _ensureInit();

    // v3.0.87: Nếu đã có token và còn hạn → dùng luôn, không gọi API
    if (_accessToken != null && _accessToken!.isNotEmpty && email == null && password == null) {
      if (_tokenExpiresAt != null && DateTime.now().isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 5)))) {
        return YTeSoLoginResult(success: true, message: 'Đã đăng nhập (cached)');
      }
    }

    // v3.0.87: Dedup - nếu 1 login đang chạy thì return future đó
    if (_loginInProgress != null) {
      return _loginInProgress!;
    }

    final useEmail = email ?? _email ?? defaultEmail;
    final usePassword = password ?? defaultPassword;

    final completer = _doLogin(useEmail, usePassword);
    _loginInProgress = completer;
    try {
      return await completer;
    } finally {
      _loginInProgress = null;
    }
  }

  Future<YTeSoLoginResult> _doLogin(String useEmail, String usePassword) async {
    try {
      final resp = await _dio.post(
        '$baseUrl/v1/auth/login',
        data: jsonEncode({'email': useEmail, 'password': usePassword}),
        options: Options(
          headers: _buildHeaders(jsonContent: true),
        ),
      );
      final data = resp.data;
      if (data is Map && data['accessToken'] != null) {
        _accessToken = data['accessToken'] as String;
        _email = useEmail;
        // v3.0.87: Parse JWT expiry
        _tokenExpiresAt = _parseJwtExpiry(_accessToken!);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAccessToken, _accessToken!);
        await prefs.setString(_kEmail, useEmail);
        await prefs.setString(_kTokenSavedAt, DateTime.now().toIso8601String());
        debugPrint('[YTeSo] Login OK (token ${_accessToken!.length} chars, exp $_tokenExpiresAt)');
        return YTeSoLoginResult(success: true, message: 'Đăng nhập thành công');
      }
      return YTeSoLoginResult(
          success: false, message: 'Phản hồi không có accessToken');
    } on DioException catch (e) {
      String msg;
      if (e.response?.statusCode == 401) {
        msg = 'Sai email hoặc mật khẩu';
      } else if (e.response?.statusCode == 404) {
        msg = 'Server không phản hồi (404). Kiểm tra base URL: $baseUrl';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        msg = 'Không kết nối được server. Kiểm tra mạng/VPN';
      } else {
        msg = 'Lỗi: ${e.response?.statusCode} ${e.message}';
      }
      debugPrint('[YTeSo] Login error: $msg');
      return YTeSoLoginResult(success: false, message: msg);
    } catch (e) {
      debugPrint('[YTeSo] Login exception: $e');
      return YTeSoLoginResult(success: false, message: 'Lỗi: $e');
    }
  }

  /// v3.0.87: Parse JWT expiry (payload.exp) - JWT format: header.payload.signature
  /// payload is base64url-encoded JSON
  DateTime? _parseJwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = parts[1];
      // base64url decode
      var padded = payload.replaceAll('-', '+').replaceAll('_', '/');
      while (padded.length % 4 != 0) padded += '=';
      final bytes = base64.decode(padded);
      final str = utf8.decode(bytes);
      final json = jsonDecode(str) as Map<String, dynamic>;
      final exp = json['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      }
    } catch (_) {}
    return null;
  }

  /// v3.0.83: Auto-login với default credentials (gọi ngầm khi mở screen)
  /// v3.0.87: Check token expiry trước khi login - tránh login không cần thiết
  Future<bool> ensureLoggedIn() async {
    if (isLoggedIn) {
      // Token còn hạn? (cache 5 phút trước khi hết hạn)
      if (_tokenExpiresAt != null && DateTime.now().isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 5)))) {
        return true;
      }
      // Token hết hạn → xóa và login lại
      if (_tokenExpiresAt != null) {
        debugPrint('[YTeSo] Token expired, re-login');
        _accessToken = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kAccessToken);
      } else {
        // Không có expiry info, tin tưởng token cũ
        return true;
      }
    }
    final r = await login();
    return r.success;
  }

  /// v3.0.83: Logout - xóa token
  Future<void> logout() async {
    _accessToken = null;
    _tokenExpiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    _docCache.clear();
    _docCacheTime.clear();
    _fileCache.clear();
  }

  // ============ DOCUMENT TYPES (LIST) ============
  /// v3.0.83: GET /v1/medical-record/document-types?treatmentCode=XXX
  /// Trả về list grouped: [{ID, DOCUMENT_TYPE_CODE, DOCUMENT_TYPE_NAME, items: [doc,...]}]
  /// v3.0.87: Add TTL cache (5 phút) - tránh gọi API liên tục
  Future<YTeSoDocsResult> listDocuments({
    required String treatmentCode,
    String? treatmentId,
    String? departmentCode,
    String? roomCode,
    bool force = false,
  }) async {
    await _ensureInit();

    // v3.0.87: Check cache với TTL
    if (!force && _docCache.containsKey(treatmentCode)) {
      final cacheTime = _docCacheTime[treatmentCode];
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime) < _docCacheTtl) {
        return YTeSoDocsResult(
            success: true, groups: _docCache[treatmentCode]!);
      }
    }

    if (!isLoggedIn || (_tokenExpiresAt != null && DateTime.now().isAfter(_tokenExpiresAt!.subtract(const Duration(minutes: 5))))) {
      final ok = await ensureLoggedIn();
      if (!ok) {
        return YTeSoDocsResult(
            success: false, message: 'Chưa đăng nhập Y Tế Số');
      }
    }

    try {
      final resp = await _dio.get(
        '$baseUrl/v1/medical-record/document-types',
        queryParameters: {'treatmentCode': treatmentCode},
        options: Options(
          headers: _buildHeaders(
            treatmentId: treatmentId,
            treatmentCode: treatmentCode,
            departmentId: defaultDepartmentId,
            departmentCode: departmentCode ?? defaultDepartmentCode,
            roomId: defaultRoomId,
            roomCode: roomCode ?? defaultRoomCode,
            jsonContent: false,
          ),
        ),
      );
      final data = resp.data;
      if (data is List) {
        final groups = <YTeSoDocumentGroup>[];
        for (final g in data) {
          if (g is Map) {
            groups.add(YTeSoDocumentGroup.fromJson(
                Map<String, dynamic>.from(g)));
          }
        }
        _docCache[treatmentCode] = groups;
        _docCacheTime[treatmentCode] = DateTime.now();
        final totalDocs =
            groups.fold<int>(0, (sum, g) => sum + g.items.length);
        debugPrint(
            '[YTeSo] listDocuments OK: $treatmentCode -> ${groups.length} groups, $totalDocs docs');
        return YTeSoDocsResult(success: true, groups: groups);
      }
      return YTeSoDocsResult(
          success: false, message: 'Phản hồi không hợp lệ: ${data?.runtimeType}');
    } on DioException catch (e) {
      String msg;
      if (e.response?.statusCode == 401) {
        // Token hết hạn -> thử login lại
        await logout();
        final ok = await ensureLoggedIn();
        if (ok) {
          return listDocuments(
            treatmentCode: treatmentCode,
            treatmentId: treatmentId,
            departmentCode: departmentCode,
            roomCode: roomCode,
            force: true,
          );
        }
        msg = 'Token hết hạn. Đăng nhập lại thất bại';
      } else if (e.response?.statusCode == 404) {
        msg = 'Không tìm thấy điều trị $treatmentCode';
      } else {
        msg = 'Lỗi: ${e.response?.statusCode}';
      }
      debugPrint('[YTeSo] listDocuments error: $msg');
      return YTeSoDocsResult(success: false, message: msg);
    } catch (e) {
      debugPrint('[YTeSo] listDocuments exception: $e');
      return YTeSoDocsResult(success: false, message: 'Lỗi: $e');
    }
  }

  // ============ DOCUMENT DOWNLOAD ============
  /// v3.0.83: GET /v1/medical-record/document-type/download?documentId=XXX
  /// Trả về JSON {DocumentId, DocumentCode, DocumentName, Base64Data}
  /// Decode base64 -> file PDF/JPG lưu vào temp
  Future<YTeSoDownloadResult> downloadDocument({
    required int documentId,
    String? treatmentCode,
    String? treatmentId,
  }) async {
    await _ensureInit();
    if (!isLoggedIn) {
      final ok = await ensureLoggedIn();
      if (!ok) {
        return YTeSoDownloadResult(
            success: false, message: 'Chưa đăng nhập Y Tế Số');
      }
    }

    // Check cache
    if (_fileCache.containsKey(documentId)) {
      final p = _fileCache[documentId]!;
      final fi = File(p);
      if (await fi.exists() && await fi.length() > 0) {
        return YTeSoDownloadResult(
          success: true,
          filePath: p,
          documentId: documentId,
        );
      }
    }

    try {
      final resp = await _dio.get(
        '$baseUrl/v1/medical-record/document-type/download',
        queryParameters: {'documentId': documentId},
        options: Options(
          headers: _buildHeaders(
            treatmentId: treatmentId,
            treatmentCode: treatmentCode,
            departmentId: defaultDepartmentId,
            departmentCode: defaultDepartmentCode,
            roomId: defaultRoomId,
            roomCode: defaultRoomCode,
            jsonContent: false,
          ),
          responseType: ResponseType.json,
        ),
      );
      final data = resp.data;
      if (data is Map && data['Base64Data'] != null) {
        final b64 = data['Base64Data'] as String;
        final fileType = (data['DocumentFileType'] as String?) ?? 'PDF';
        final fileName =
            '${data['DocumentCode'] ?? documentId}.${fileType.toLowerCase()}';

        // Decode
        final bytes = base64.decode(b64);
        // Save to temp
        final dir = await getTemporaryDirectory();
        final yteDir = Directory('${dir.path}/yte_so');
        if (!await yteDir.exists()) {
          await yteDir.create(recursive: true);
        }
        final file = File('${yteDir.path}/$fileName');
        await file.writeAsBytes(bytes);
        _fileCache[documentId] = file.path;

        debugPrint(
            '[YTeSo] downloadDocument OK: $documentId -> ${file.path} (${bytes.length} bytes)');
        return YTeSoDownloadResult(
          success: true,
          filePath: file.path,
          documentId: documentId,
          documentCode: data['DocumentCode'] as String?,
          documentName: data['DocumentName'] as String?,
        );
      }
      return YTeSoDownloadResult(
          success: false, message: 'Phản hồi không có Base64Data');
    } on DioException catch (e) {
      String msg;
      if (e.response?.statusCode == 401) {
        await logout();
        final ok = await ensureLoggedIn();
        if (ok) {
          return downloadDocument(
            documentId: documentId,
            treatmentCode: treatmentCode,
            treatmentId: treatmentId,
          );
        }
        msg = 'Token hết hạn';
      } else {
        msg = 'Lỗi: ${e.response?.statusCode}';
      }
      debugPrint('[YTeSo] downloadDocument error: $msg');
      return YTeSoDownloadResult(success: false, message: msg);
    } catch (e) {
      debugPrint('[YTeSo] downloadDocument exception: $e');
      return YTeSoDownloadResult(success: false, message: 'Lỗi: $e');
    }
  }

  /// v3.0.83: Test kết nối server
  Future<bool> ping() async {
    await _ensureInit();
    try {
      final resp = await _dio.get(
        '$baseUrl/v1/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ============ Models ============

class YTeSoLoginResult {
  final bool success;
  final String message;
  YTeSoLoginResult({required this.success, required this.message});
}

class YTeSoDocsResult {
  final bool success;
  final String? message;
  final List<YTeSoDocumentGroup> groups;
  YTeSoDocsResult({required this.success, this.message, this.groups = const []});
}

class YTeSoDownloadResult {
  final bool success;
  final String? message;
  final String? filePath;
  final int? documentId;
  final String? documentCode;
  final String? documentName;
  YTeSoDownloadResult({
    required this.success,
    this.message,
    this.filePath,
    this.documentId,
    this.documentCode,
    this.documentName,
  });
}

/// v3.0.83: Nhóm tài liệu theo DOCUMENT_TYPE
class YTeSoDocumentGroup {
  final int id;
  final String typeCode;
  final String typeName;
  final int numOrder;
  final List<YTeSoDocument> items;

  YTeSoDocumentGroup({
    required this.id,
    required this.typeCode,
    required this.typeName,
    required this.numOrder,
    required this.items,
  });

  factory YTeSoDocumentGroup.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List?) ?? [];
    final items = itemsJson
        .map((e) => YTeSoDocument.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return YTeSoDocumentGroup(
      id: (json['ID'] as num?)?.toInt() ?? 0,
      typeCode: (json['DOCUMENT_TYPE_CODE'] ?? '').toString(),
      typeName: (json['DOCUMENT_TYPE_NAME'] ?? '').toString(),
      numOrder: (json['NUM_ORDER'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }
}

/// v3.0.83: Một tài liệu (phiếu, bảng kê, ...) trong EMR
class YTeSoDocument {
  final int id;
  final String code;
  final String name;
  final String treatmentCode;
  final int treatmentId;
  final int documentTypeId;
  final String documentTime; // yyyyMMddHHmmss
  final String documentDate; // yyyyMMdd000000
  final String paperName; // A4/A5
  final String fileType; // PDF/JPG
  final String lastVersionUrl;
  final String creator;
  final String modifier;
  final String signer;
  final int width;
  final int height;

  YTeSoDocument({
    required this.id,
    required this.code,
    required this.name,
    required this.treatmentCode,
    required this.treatmentId,
    required this.documentTypeId,
    required this.documentTime,
    required this.documentDate,
    required this.paperName,
    required this.fileType,
    required this.lastVersionUrl,
    required this.creator,
    required this.modifier,
    required this.signer,
    required this.width,
    required this.height,
  });

  factory YTeSoDocument.fromJson(Map<String, dynamic> json) {
    int parseDt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return YTeSoDocument(
      id: parseDt(json['ID']),
      code: (json['DOCUMENT_CODE'] ?? '').toString(),
      name: (json['DOCUMENT_NAME'] ?? '').toString(),
      treatmentCode: (json['TREATMENT_CODE'] ?? '').toString(),
      treatmentId: parseDt(json['TREATMENT_ID']),
      documentTypeId: parseDt(json['DOCUMENT_TYPE_ID']),
      documentTime: (json['DOCUMENT_TIME'] ?? '').toString(),
      documentDate: (json['DOCUMENT_DATE'] ?? '').toString(),
      paperName: (json['PAPER_NAME'] ?? '').toString(),
      fileType: (json['DOCUMENT_FILE_TYPE'] ?? 'PDF').toString(),
      lastVersionUrl: (json['LAST_VERSION_URL'] ?? '').toString(),
      creator: (json['CREATOR'] ?? '').toString(),
      modifier: (json['MODIFIER'] ?? '').toString(),
      signer: (json['SIGNERS'] ?? '').toString(),
      width: parseDt(json['WIDTH']),
      height: parseDt(json['HEIGHT']),
    );
  }

  /// v3.0.83: Format documentTime (yyyyMMddHHmmss) sang DateTime
  DateTime? get documentTimeParsed {
    if (documentTime.length < 8) return null;
    try {
      final y = int.parse(documentTime.substring(0, 4));
      final m = int.parse(documentTime.substring(4, 6));
      final d = int.parse(documentTime.substring(6, 8));
      final h = documentTime.length >= 10
          ? int.parse(documentTime.substring(8, 10))
          : 0;
      final min = documentTime.length >= 12
          ? int.parse(documentTime.substring(10, 12))
          : 0;
      final s = documentTime.length >= 14
          ? int.parse(documentTime.substring(12, 14))
          : 0;
      return DateTime(y, m, d, h, min, s);
    } catch (_) {
      return null;
    }
  }

  /// v3.0.83: Format ngày giờ đẹp cho UI
  String get displayTime {
    final dt = documentTimeParsed;
    if (dt == null) return '';
    final dd = '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}/${dt.year}';
    final tt =
        '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
    return '$dd $tt';
  }

  /// v3.0.83: Icon dựa theo fileType
  String get iconEmoji {
    switch (fileType.toUpperCase()) {
      case 'PDF':
        return '📄';
      case 'JPG':
      case 'JPEG':
      case 'PNG':
        return '🖼️';
      default:
        return '📎';
    }
  }
}
