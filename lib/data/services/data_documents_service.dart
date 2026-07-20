// DataDocumentsService v2.32 - Optimize PDF loading
// - Pre-download tất cả phiếu song song ngay khi gọi getSignedDocuments
// - Streaming Dio download với progress callback
// - Auto-retry 2 lần nếu fail (timeout / network)
// - Cache in-memory + persist ra disk (downloaded/)
// - Status enum: notLoaded / loading(progress) / ready / error
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
import '../api/thongke_auth_service.dart' show ThongkeAuthService;

enum DocStatus { notLoaded, loading, ready, error }

/// Error type classifier - để UI biết nên retry hay mở web
enum DocErrorType { unknown, network, serverFs, serverAuth, notPdf, timeout, empty }

DocErrorType classifyError(String? error, int? statusCode) {
  if (error == null) return DocErrorType.unknown;
  final e = error.toLowerCase();
  if (e.contains('impossible to create') || e.contains('root directory') ||
      e.contains('\\\\10.') || e.contains('fss1') || e.contains('backend')) {
    return DocErrorType.serverFs;
  }
  if (e.contains('session') || e.contains('login') || e.contains('unauthorized') ||
      e.contains('csrf') || statusCode == 401) {
    return DocErrorType.serverAuth;
  }
  if (e.contains('not pdf') || e.contains('not a pdf') || e.contains('html')) {
    return DocErrorType.notPdf;
  }
  if (e.contains('timeout') || e.contains('timed out')) {
    return DocErrorType.timeout;
  }
  if (e.contains('connection') || e.contains('socket') || e.contains('network')) {
    return DocErrorType.network;
  }
  if (e.contains('empty') || e.contains('0 bytes')) {
    return DocErrorType.empty;
  }
  return DocErrorType.unknown;
}

class DataDocument {
  final String documentCode;
  final String numericId;
  final String name;
  final String type;
  final String date;
  final String treatmentCode;
  final String shareUrl;
  final String pdfUrl;

  /// Loading state
  DocStatus status;
  double progress; // 0.0 - 1.0
  String? error;
  DocErrorType errorType;
  Uint8List? bytes;
  String? cachedPath; // local file path if saved

  /// Number of bytes
  int sizeBytes;
  int totalBytes;

  /// Notify UI when state changes
  final _stateController = StreamController<void>.broadcast();
  Stream<void> get onChange => _stateController.stream;
  void _notify() => _stateController.add(null);

  DataDocument({
    required this.documentCode,
    required this.numericId,
    required this.name,
    required this.type,
    required this.date,
    required this.treatmentCode,
    required this.shareUrl,
    required this.pdfUrl,
    this.status = DocStatus.notLoaded,
    this.progress = 0,
    this.error,
    this.errorType = DocErrorType.unknown,
    this.bytes,
    this.cachedPath,
    this.sizeBytes = 0,
    this.totalBytes = 0,
  });

  String get displayDate => date;
  String get displayType => type;

  String get prettySize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  void dispose() {
    _stateController.close();
  }
}

class DataDocumentsService {
  static final DataDocumentsService instance = DataDocumentsService._();
  DataDocumentsService._();

  final Map<String, DataDocument> _docs = {};  // documentCode -> DataDocument
  final Map<String, String> _fileCache = {};  // documentCode -> local file path
  Dio? _dio;
  int _maxParallel = 3;  // parallel downloads
  int _maxRetries = 2;

  /// Lấy danh sách phiếu + pre-fetch tất cả PDF (non-blocking)
  /// Returns initial list ngay (status=loading cho mỗi doc)
  /// Sau đó update qua stream onChange
  Future<List<DataDocument>> loadAll(String treatmentCode) async {
    // 1. Lấy list
    final list = await _fetchList(treatmentCode);
    if (list == null || list.isEmpty) {
      return [];
    }

    // 2. Cache in registry
    for (final d in list) {
      _docs[d.documentCode] = d;
    }

    // 3. Pre-download tất cả song song (giới hạn _maxParallel)
    unawaited(_prefetchAll(list));

    return list;
  }

  /// Lấy list phiếu (gọi Data /treatment-result/index/search)
  Future<List<DataDocument>?> _fetchList(String treatmentCode) async {
    try {
      final dio = await _getDio();
      final r = await dio.get(
        '${ThongkeAuthService.baseUrl}/treatment-result/index/search?treatment_code=$treatmentCode',
        options: Options(
          headers: {
            'Accept': 'text/html,application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '${ThongkeAuthService.baseUrl}/emr/index',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode != 200) {
        return null;
      }
      return _parseDocumentsHtml(r.data.toString(), treatmentCode);
    } catch (e) {
      return null;
    }
  }

  /// Pre-fetch all PDFs in parallel (limit _maxParallel)
  Future<void> _prefetchAll(List<DataDocument> docs) async {
    // First check cache files (persistent)
    for (final d in docs) {
      await _tryLoadFromCache(d);
    }

    // Filter to only not-loaded docs
    final pending = docs.where((d) =>
      d.status == DocStatus.notLoaded || d.status == DocStatus.error
    ).toList();

    // Download in chunks
    for (int i = 0; i < pending.length; i += _maxParallel) {
      final chunk = pending.skip(i).take(_maxParallel).toList();
      await Future.wait(chunk.map(_downloadOne));
    }
  }

  /// Try to load from local cache (if exists)
  Future<void> _tryLoadFromCache(DataDocument d) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${d.numericId.isEmpty ? d.documentCode : d.numericId}.pdf');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 100) {  // sanity check
          d.bytes = bytes;
          d.cachedPath = file.path;
          d.sizeBytes = bytes.length;
          d.totalBytes = bytes.length;
          d.status = DocStatus.ready;
          d.progress = 1.0;
          d._notify();
        }
      }
    } catch (_) {}
  }

  /// Download 1 PDF với retry + progress
  Future<void> _downloadOne(DataDocument d) async {
    if (d.status == DocStatus.ready) return;
    d.status = DocStatus.loading;
    d.progress = 0;
    d.error = null;
    d.errorType = DocErrorType.unknown;
    d._notify();

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final dio = await _getDio();
        final r = await dio.get(
          d.pdfUrl,
          options: Options(
            headers: {
              'Accept': 'application/pdf,text/html',
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': '${ThongkeAuthService.baseUrl}/treatment-result/index/search',
            },
            responseType: ResponseType.bytes,
            validateStatus: (s) => s != null && s < 500,
            receiveTimeout: const Duration(seconds: 90),
            sendTimeout: const Duration(seconds: 30),
          ),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              d.progress = received / total;
              d.sizeBytes = received;
              d.totalBytes = total;
              d._notify();
            }
          },
        );
        if (r.statusCode == 200 && r.data != null) {
          final raw = r.data is Uint8List
              ? r.data as Uint8List
              : Uint8List.fromList(r.data as List<int>);
          final ct = r.headers.value('content-type') ?? '';

          // Check it's actually a PDF (not HTML error page)
          if (raw.length > 100 && _looksLikePdf(raw)) {
            d.bytes = raw;
            d.sizeBytes = raw.length;
            d.totalBytes = raw.length;
            d.progress = 1.0;
            d.status = DocStatus.ready;
            d.error = null;
            d.errorType = DocErrorType.unknown;

            // Save to disk cache
            try {
              final dir = await _getCacheDir();
              final file = File('${dir.path}/${d.numericId.isEmpty ? d.documentCode : d.numericId}.pdf');
              await file.writeAsBytes(raw);
              d.cachedPath = file.path;
            } catch (_) {}

            d._notify();
            return;
          } else {
            // Not a PDF - capture actual body
            String body;
            try {
              body = utf8.decode(raw, allowMalformed: true);
            } catch (_) {
              body = '(binary)';
            }
            // Trim and limit
            if (body.length > 200) body = body.substring(0, 200) + '...';
            d.error = body.isEmpty ? 'Server trả về rỗng' : body;
            d.errorType = classifyError(body, r.statusCode);
            // For FS errors and auth errors, no point retrying
            if (d.errorType == DocErrorType.serverFs || d.errorType == DocErrorType.serverAuth) {
              d.status = DocStatus.error;
              d._notify();
              return;
            }
          }
        } else {
          d.error = 'HTTP ${r.statusCode}';
          d.errorType = classifyError(d.error, r.statusCode);
          if (d.errorType == DocErrorType.serverAuth) {
            d.status = DocStatus.error;
            d._notify();
            return;
          }
        }
      } catch (e) {
        d.error = e.toString();
        d.errorType = classifyError(d.error, null);
      }
      // wait before retry
      if (attempt < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    d.status = DocStatus.error;
    d._notify();
  }

  /// Check bytes look like PDF (%PDF magic)
  bool _looksLikePdf(Uint8List b) {
    if (b.length < 5) return false;
    return b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46; // %PDF
  }

  /// Public API: get bytes for a doc (from cache or wait for download)
  Future<Uint8List?> getBytes(String documentCode) async {
    final d = _docs[documentCode];
    if (d == null) return null;
    if (d.status == DocStatus.ready && d.bytes != null) return d.bytes;
    if (d.status == DocStatus.error) {
      // Try retry
      await _downloadOne(d);
    }
    return d.bytes;
  }

  /// Force retry a failed doc
  Future<void> retry(String documentCode) async {
    final d = _docs[documentCode];
    if (d == null) return;
    await _downloadOne(d);
  }

  /// Stream progress for a specific doc
  Stream<void> watch(String documentCode) {
    final d = _docs[documentCode];
    if (d == null) return const Stream.empty();
    return d.onChange;
  }

  /// Get a doc by code
  DataDocument? get(String documentCode) => _docs[documentCode];

  /// Clear all caches
  Future<void> clearCache() async {
    _docs.clear();
    _fileCache.clear();
    try {
      final dir = await _getCacheDir();
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          try { await f.delete(); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Dispose
  void dispose() {
    for (final d in _docs.values) {
      d.dispose();
    }
    _docs.clear();
  }

  // ===========================================================
  // Private helpers
  // ===========================================================

  Future<Dio> _getDio() async {
    if (_dio != null) return _dio!;
    final dir = await getApplicationDocumentsDirectory();
    final cookiesDir = '${dir.path}/cookies';
    final cookieJar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('$cookiesDir/thongke_cookies'),
    );
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 500,
      headers: {'User-Agent': 'HIS-Mobile/2.32.0'},
    ));
    _dio!.interceptors.add(CookieManager(cookieJar));
    return _dio!;
  }

  Future<Directory> _getCacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/pdf_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  List<DataDocument> _parseDocumentsHtml(String html, String treatmentCode) {
    final results = <DataDocument>[];
    final docMatches = RegExp(
      r'document_code=([^&]+)&(?:amp;)?treatment_code=([^"&]+)',
    ).allMatches(html);

    final seenCodes = <String>{};
    int idx = 0;
    for (final m in docMatches) {
      final docCode = m.group(1)!;
      final trCode = m.group(2)!;
      if (seenCodes.contains(docCode)) continue;
      seenCodes.add(docCode);
      idx++;

      String numericId = '';
      try { numericId = utf8.decode(base64Decode(docCode)); } catch (_) {}

      final mPos = m.start;
      final trStart = html.lastIndexOf('<tr', mPos);
      final trEnd = html.indexOf('</tr>', mPos);
      String rowHtml = '';
      if (trStart >= 0 && trEnd > trStart) {
        rowHtml = html.substring(trStart, trEnd);
      }

      final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(rowHtml)
          .map((c) => c.group(1) ?? '')
          .map((c) => c.replaceAll(RegExp(r'<[^>]+>'), ' ').trim())
          .toList();

      final name = cells.length > 1 ? cells[1] : 'Văn bản #$idx';
      final type = cells.length > 2 ? cells[2] : '';
      final date = cells.length > 3 ? cells[3] : '';

      results.add(DataDocument(
        documentCode: docCode,
        numericId: numericId,
        name: name,
        type: type,
        date: date,
        treatmentCode: trCode,
        shareUrl: '${ThongkeAuthService.baseUrl}/index/view-doc?document_code=$docCode&treatment_code=$trCode',
        pdfUrl: '${ThongkeAuthService.baseUrl}/index/view-doc?document_code=$docCode&treatment_code=$trCode&type=pdf',
      ));
    }
    return results;
  }
}
