// UploadLogService v3.0.37 - Comprehensive EMR upload logging
// Theo spec BS yêu cầu 2026-07-17:
// - Log request (endpoint, method, body, treatmentCode, user)
// - Log response (httpStatus, contentType, success, message)
// - Log retry (attempt#, error, delay)
// - Log metrics (durationMs, retryCount, fileSize)
// - Export log dạng JSON để gửi IT BV
//
// Path: /storage/emulated/0/Android/data/<pkg>/files/Documents/logs/upload_YYYY_MM_DD.log
//
// Format mỗi dòng (human-readable):
// 2026-07-17 09:12:31 | POST | CreateByTdo | User=nemk | Treatment=000002128160 | HTTP=200 | Success=false | Message="Permission denied" | Duration=3200ms | Retry=1
//
// Format export (JSON line per record):
// {"timestamp":"2026-07-17T09:12:31Z","type":"request","endpoint":"/api/EmrDocument/CreateByTdo","method":"POST","documentTypeId":20,"treatmentCode":"000002128160","user":"nemk"}
// {"timestamp":"2026-07-17T09:12:31Z","type":"response","httpStatus":200,"contentType":"application/json","success":false,"message":"Permission denied","durationMs":3200}
// {"timestamp":"2026-07-17T09:12:32Z","type":"retry","attempt":1,"error":"timeout","delayMs":2000}
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:his_mobile/data/models/audit_info.dart';

class UploadLogService {
  static final UploadLogService instance = UploadLogService._();
  UploadLogService._();

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _ts(DateTime t) =>
      '${t.year}-${_pad(t.month)}-${_pad(t.day)} ${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}';

  String _tsIso(DateTime t) => t.toUtc().toIso8601String();

  String _filename(DateTime t) => 'upload_${t.year}_${_pad(t.month)}_${_pad(t.day)}.log';

  Future<Directory> _getLogDir() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final logs = Directory('${base.path}/logs');
      if (!await logs.exists()) {
        await logs.create(recursive: true);
      }
      return logs;
    } catch (e) {
      return Directory.systemTemp.createTempSync('his_logs');
    }
  }

  /// Ghi 1 dòng raw (internal - dùng bởi các method log* bên dưới)
  Future<void> _writeRaw(String line) async {
    try {
      final dir = await _getLogDir();
      final file = File('${dir.path}/${_filename(DateTime.now())}');
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      debugPrint('UploadLog: $line');
    } catch (e) {
      debugPrint('UploadLog write error: $e');
    }
  }

  // ============================================================
  // v3.0.37: Log request (gọi TRƯỚC khi gọi API)
  // ============================================================
  Future<void> logRequest({
    required String endpoint,
    required String method,
    String? treatmentCode,
    int? documentTypeId,
    String? documentName,
    String? user,
    int? fileSize,
  }) async {
    final ts = DateTime.now();
    // Human-readable
    final line = '${_ts(ts)} | $method | $endpoint | '
        'User=${user ?? "?"} | '
        'Treatment=${treatmentCode ?? "?"} | '
        'DocType=${documentTypeId ?? "?"} | '
        'FileSize=${fileSize ?? 0}B | '
        'Name=${documentName ?? "?"}';
    await _writeRaw(line);
    // JSON for export
    await _writeJson({
      'timestamp': _tsIso(ts),
      'type': 'request',
      'endpoint': endpoint,
      'method': method,
      'treatmentCode': treatmentCode,
      'documentTypeId': documentTypeId,
      'documentName': documentName,
      'user': user,
      'fileSize': fileSize,
    });
  }

  // ============================================================
  // v3.0.37: Log response (gọi SAU khi nhận response)
  // ============================================================
  Future<void> logResponse({
    required String endpoint,
    required int httpStatus,
    String? contentType,
    required bool success,
    String? message,
    String? documentCode,
    int? documentId,
    int? durationMs,
    int? retryCount,
    String? body,  // v3.0.48: thêm body để debug CreateByTdo silent fail
  }) async {
    final ts = DateTime.now();
    final bodyPreview = body != null && body.isNotEmpty
        ? (body.length > 200 ? '${body.substring(0, 200)}...' : body)
        : '';
    final line = '${_ts(ts)} | RESPONSE | $endpoint | '
        'HTTP=$httpStatus | '
        'CT=${contentType ?? "?"} | '
        'Success=$success | '
        'Message=${_quote(message)} | '
        'DocCode=${documentCode ?? "-"} | '
        'Duration=${durationMs ?? 0}ms | '
        'Retry=${retryCount ?? 0}'
        '${bodyPreview.isNotEmpty ? " | Body=$bodyPreview" : ""}';
    await _writeRaw(line);
    await _writeJson({
      'timestamp': _tsIso(ts),
      'type': 'response',
      'endpoint': endpoint,
      'httpStatus': httpStatus,
      'contentType': contentType,
      'success': success,
      'message': message,
      'documentCode': documentCode,
      'documentId': documentId,
      'durationMs': durationMs,
      'retryCount': retryCount,
      'body': body,  // full body trong JSON log
    });
  }

  // ============================================================
  // v3.0.37: Log retry (gọi mỗi lần retry)
  // ============================================================
  Future<void> logRetry({
    required String endpoint,
    required int attempt,
    required String error,
    required int delayMs,
    String? nextAction, // "delay" | "giveup" | "success"
  }) async {
    final ts = DateTime.now();
    final line = '${_ts(ts)} | RETRY#$attempt | $endpoint | '
        'Error=${_quote(error)} | '
        'Delay=${delayMs}ms | '
        'Next=${nextAction ?? "?"}';
    await _writeRaw(line);
    await _writeJson({
      'timestamp': _tsIso(ts),
      'type': 'retry',
      'endpoint': endpoint,
      'attempt': attempt,
      'error': error,
      'delayMs': delayMs,
      'nextAction': nextAction,
    });
  }

  // ============================================================
  // v3.0.37: Log metric (cuối mỗi lần push - thành công hoặc thất bại)
  // ============================================================
  Future<void> logMetric({
    required String endpoint,
    required String outcome, // SUCCESS | FAILED | PENDING_RETRY
    required int durationMs,
    int? retryCount,
    int? fileSize,
  }) async {
    final ts = DateTime.now();
    final line = '${_ts(ts)} | METRIC | $endpoint | '
        'Outcome=$outcome | '
        'Duration=${durationMs}ms | '
        'Retry=${retryCount ?? 0} | '
        'FileSize=${fileSize ?? 0}B';
    await _writeRaw(line);
    await _writeJson({
      'timestamp': _tsIso(ts),
      'type': 'metric',
      'endpoint': endpoint,
      'outcome': outcome,
      'durationMs': durationMs,
      'retryCount': retryCount,
      'fileSize': fileSize,
    });
  }

  // ============================================================
  // v3.0.37: Log queue event (pendingRetry state)
  // ============================================================
  Future<void> logQueueEvent({
    required String event, // "enqueue" | "dequeue" | "expire"
    required String docId,
    String? treatmentCode,
    String? reason,
  }) async {
    final ts = DateTime.now();
    final line = '${_ts(ts)} | QUEUE | $event | '
        'DocId=$docId | '
        'Treatment=${treatmentCode ?? "?"} | '
        'Reason=${_quote(reason)}';
    await _writeRaw(line);
    await _writeJson({
      'timestamp': _tsIso(ts),
      'type': 'queue',
      'event': event,
      'docId': docId,
      'treatmentCode': treatmentCode,
      'reason': reason,
    });
  }

  // Helper
  String _quote(String? s) {
    if (s == null) return '""';
    final escaped = s.replaceAll('"', '\\"').replaceAll('\n', '\\n');
    return '"$escaped"';
  }

  Future<void> _writeJson(Map<String, dynamic> data) async {
    try {
      final dir = await _getLogDir();
      final jsonFile = File('${dir.path}/${_filename(DateTime.now())}.jsonl');
      final jsonStr = jsonEncode(data);
      await jsonFile.writeAsString('$jsonStr\n', mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('UploadLog JSON write error: $e');
    }
  }

  /// Ghi entry theo AuditInfo (backward-compat với code cũ)
  Future<void> log(AuditInfo audit) async {
    try {
      final ts = audit.uploadedAt ?? DateTime.now();
      final status = audit.status ?? 'unknown';
      // Map status to outcome
      String outcome;
      switch (status.toLowerCase()) {
        case 'success': case 'signed': case 'signed_real':
          outcome = 'SUCCESS'; break;
        case 'failed': case 'error':
          outcome = 'FAILED'; break;
        default:
          outcome = status.toUpperCase();
      }
      await logResponse(
        endpoint: audit.status == 'failed' ? 'audit' : 'audit',
        httpStatus: 0,
        contentType: 'audit',
        success: outcome == 'SUCCESS',
        message: audit.errorMessage,
        documentCode: audit.documentCode,
        retryCount: null,
        durationMs: 0,
      );
    } catch (e) {
      debugPrint('UploadLog.legacy error: $e');
    }
  }

  /// Đọc log hôm nay (human-readable)
  Future<List<String>> readToday() async {
    try {
      final dir = await _getLogDir();
      final file = File('${dir.path}/${_filename(DateTime.now())}');
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      return content.split('\n').where((l) => l.isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }

  /// Export log hôm nay thành JSON string (gửi IT BV)
  Future<String> exportTodayAsJson() async {
    try {
      final dir = await _getLogDir();
      final jsonFile = File('${dir.path}/${_filename(DateTime.now())}.jsonl');
      if (!await jsonFile.exists()) return '[]';
      final content = await jsonFile.readAsString();
      // Parse thành array
      final lines = content.split('\n').where((l) => l.isNotEmpty);
      final list = <Map<String, dynamic>>[];
      for (final l in lines) {
        try {
          final m = jsonDecode(l) as Map<String, dynamic>;
          list.add(m);
        } catch (_) {}
      }
      return const JsonEncoder.withIndent('  ').convert(list);
    } catch (e) {
      return '[]';
    }
  }

  /// Path file log hôm nay (cho UI "Chia sẻ log")
  Future<String> getLogFilePath() async {
    final dir = await _getLogDir();
    return '${dir.path}/${_filename(DateTime.now())}.log';
  }

  Future<String> getJsonLogFilePath() async {
    final dir = await _getLogDir();
    return '${dir.path}/${_filename(DateTime.now())}.jsonl';
  }

  /// v3.0.42: Xóa toàn bộ log (cả .log và .jsonl các ngày)
  /// BS dùng khi log đầy, hoặc trước khi gửi IT file mới
  Future<bool> clearAll() async {
    try {
      final dir = await _getLogDir();
      if (await dir.exists()) {
        final files = dir.listSync();
        for (final f in files) {
          try {
            if (f is File) await f.delete();
          } catch (_) {}
        }
      }
      return true;
    } catch (e) {
      debugPrint('UploadLogService.clearAll error: $e');
      return false;
    }
  }

  /// Format entry cho UI
  String formatEntry(String raw) => raw; // đã format sẵn

  /// Đếm số event hôm nay (cho badge UI)
  Future<Map<String, int>> getTodayStats() async {
    final lines = await readToday();
    int success = 0, failed = 0, retry = 0, request = 0, response = 0, metric = 0;
    for (final l in lines) {
      if (l.contains(' | REQUEST | ')) request++;
      else if (l.contains(' | RESPONSE | ')) {
        response++;
        if (l.contains('Success=true')) success++;
        else if (l.contains('Success=false')) failed++;
      } else if (l.contains(' | RETRY#')) retry++;
      else if (l.contains(' | METRIC | ')) metric++;
    }
    return {
      'request': request,
      'response': response,
      'success': success,
      'failed': failed,
      'retry': retry,
      'metric': metric,
    };
  }
}
