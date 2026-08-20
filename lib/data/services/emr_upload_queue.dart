// EmrUploadQueue v3.0.37 - Persistent queue cho pending retries
// Theo spec BS 2026-07-17:
//   Khi mất mạng BV: push fail → enqueue pendingRetry
//   Khi có mạng lại: tự động retry
//
// Lưu local với SharedPreferences (JSON list)
// Mỗi entry: {docId, treatmentCode, documentName, documentTypeId, pdfPath, attempt, lastError, enqueuedAt, nextRetryAt}
//
// State machine:
//   draft → uploaded → signed → signedReal (success terminal)
//     ↓         ↓         ↓
//   failed   failed    failed
//     ↓         ↓         ↓
//   pendingRetry (chờ retry)
//     ↓ (VPN OK)
//   retry → success hoặc failed
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/core/services/connection_service.dart';
import 'package:his_mobile/data/services/emr_retry_service.dart';
import 'package:his_mobile/data/services/upload_log_service.dart';
import 'package:his_mobile/data/api/emr_push_service.dart';

class PendingUpload {
  final String docId;
  final String treatmentCode;
  final String documentName;
  final int documentTypeId;
  final String pdfPath; // local file path
  final int attempt;
  final String? lastError;
  final DateTime enqueuedAt;
  final DateTime nextRetryAt;
  final int? fileSize;

  PendingUpload({
    required this.docId,
    required this.treatmentCode,
    required this.documentName,
    required this.documentTypeId,
    required this.pdfPath,
    this.attempt = 0,
    this.lastError,
    required this.enqueuedAt,
    required this.nextRetryAt,
    this.fileSize,
  });

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'treatmentCode': treatmentCode,
        'documentName': documentName,
        'documentTypeId': documentTypeId,
        'pdfPath': pdfPath,
        'attempt': attempt,
        'lastError': lastError,
        'enqueuedAt': enqueuedAt.toIso8601String(),
        'nextRetryAt': nextRetryAt.toIso8601String(),
        'fileSize': fileSize,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        docId: j['docId'] as String,
        treatmentCode: j['treatmentCode'] as String,
        documentName: j['documentName'] as String,
        documentTypeId: (j['documentTypeId'] as num).toInt(),
        pdfPath: j['pdfPath'] as String,
        attempt: (j['attempt'] as num?)?.toInt() ?? 0,
        lastError: j['lastError'] as String?,
        enqueuedAt: DateTime.parse(j['enqueuedAt'] as String),
        nextRetryAt: DateTime.parse(j['nextRetryAt'] as String),
        fileSize: (j['fileSize'] as num?)?.toInt(),
      );

  PendingUpload copyWith({
    int? attempt,
    String? lastError,
    DateTime? nextRetryAt,
  }) =>
      PendingUpload(
        docId: docId,
        treatmentCode: treatmentCode,
        documentName: documentName,
        documentTypeId: documentTypeId,
        pdfPath: pdfPath,
        attempt: attempt ?? this.attempt,
        lastError: lastError ?? this.lastError,
        enqueuedAt: enqueuedAt,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
        fileSize: fileSize,
      );
}

class EmrUploadQueue {
  static final EmrUploadQueue instance = EmrUploadQueue._();
  EmrUploadQueue._();

  static const _kQueueKey = 'emr_upload_queue_v1';
  Timer? _retryTimer;
  bool _processing = false;
  void Function(PendingUpload, bool success)? onUploadResult;

  /// Lấy tất cả pending uploads
  Future<List<PendingUpload>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => PendingUpload.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('EmrUploadQueue.getAll error: $e');
      return [];
    }
  }

  /// Lưu queue
  Future<void> _save(List<PendingUpload> list) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_kQueueKey, raw);
  }

  /// Enqueue 1 phiếu pending retry
  Future<void> enqueue(PendingUpload item) async {
    final list = await getAll();
    // Check duplicate (same docId)
    list.removeWhere((p) => p.docId == item.docId);
    list.add(item);
    await _save(list);
    await UploadLogService.instance.logQueueEvent(
      event: 'enqueue',
      docId: item.docId,
      treatmentCode: item.treatmentCode,
      reason: item.lastError,
    );
    debugPrint('EmrUploadQueue.enqueue: ${item.docId} (queue size: ${list.length})');
    _scheduleRetry();
  }

  /// Xóa khỏi queue
  Future<void> remove(String docId) async {
    final list = await getAll();
    list.removeWhere((p) => p.docId == docId);
    await _save(list);
    await UploadLogService.instance.logQueueEvent(event: 'dequeue', docId: docId);
    debugPrint('EmrUploadQueue.remove: $docId');
  }

  /// Update attempt + nextRetryAt
  Future<void> updateAttempt(String docId, int attempt, String? lastError) async {
    final list = await getAll();
    final idx = list.indexWhere((p) => p.docId == docId);
    if (idx >= 0) {
      // Exponential backoff: 30s, 1m, 2m, 4m
      final delaysSec = [30, 60, 120, 240];
      final delaySec = delaysSec[attempt.clamp(0, delaysSec.length - 1)];
      list[idx] = list[idx].copyWith(
        attempt: attempt,
        lastError: lastError,
        nextRetryAt: DateTime.now().add(Duration(seconds: delaySec)),
      );
      await _save(list);
    }
  }

  /// Lên lịch retry (sau khi có mạng)
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () => _processQueue());
  }

  /// Xử lý queue - retry tất cả pending
  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      final list = await getAll();
      if (list.isEmpty) {
        debugPrint('EmrUploadQueue: queue empty');
        return;
      }
      // Check VPN/connection
      final conn = ConnectionService.instance;
      // isLan || isVpn = mode đã config (LAN nội bộ hoặc Public VPN)
      if (!conn.isLan && !conn.isVpn) {
        debugPrint('EmrUploadQueue: no mode configured → skip');
        _scheduleRetry(); // thử lại sau
        return;
      }
      final now = DateTime.now();
      for (final item in list) {
        if (item.nextRetryAt.isAfter(now)) {
          debugPrint('EmrUploadQueue: ${item.docId} chưa đến giờ retry (${item.nextRetryAt})');
          continue;
        }
        debugPrint('EmrUploadQueue: retrying ${item.docId} (attempt ${item.attempt})');
        final success = await _retryItem(item);
        if (success) {
          await remove(item.docId);
          onUploadResult?.call(item, true);
        } else {
          await updateAttempt(item.docId, item.attempt + 1, 'Network error');
          onUploadResult?.call(item, false);
        }
      }
    } finally {
      _processing = false;
    }
  }

  /// Retry 1 item - thực sự push lên EMR qua EmrPushService
  /// v3.0.156: Trước đây chỉ return true mà không push → bug nghiêm trọng,
  /// queue tự xóa mọi item sau retry đầu tiên dù chưa thực sự push thành công.
  /// Fix: gọi trực tiếp EmrPushService.pushPdfToEmrUnsignedWithApi.
  Future<bool> _retryItem(PendingUpload item) async {
    try {
      // Load PDF bytes
      final file = File(item.pdfPath);
      if (!await file.exists()) {
        debugPrint('EmrUploadQueue: PDF not found: ${item.pdfPath}');
        return false;
      }
      final pdfBytes = await file.readAsBytes();
      debugPrint('EmrUploadQueue._retryItem: pushing ${item.docId} (${pdfBytes.length}B) to EMR...');

      // Gọi EmrPushService.pushPdfToEmrUnsignedWithApi (đã có sẵn ở data/api/emr_push_service.dart)
      final emrResult = await EmrPushService.instance.pushPdfToEmrUnsignedWithApi(
        pdfBytes: pdfBytes,
        treatmentCode: item.treatmentCode,
        documentName: item.documentName,
        documentTypeId: item.documentTypeId,
        roomCode: 'PKCC',  // Hardcode cho Phòng Khám Cấp Cứu
        roomTypeCode: 'XL',
        workingDeptName: 'Khoa Cấp Cứu',
        departmentCode: 'HSCC',
        useFss: false,
      );

      if (emrResult.success) {
        debugPrint('EmrUploadQueue._retryItem: SUCCESS docCode=${emrResult.documentCode}');
        return true;
      } else {
        debugPrint('EmrUploadQueue._retryItem: FAILED: ${emrResult.error}');
        return false;
      }
    } catch (e) {
      debugPrint('EmrUploadQueue._retryItem: EXCEPTION: $e');
      return false;
    }
  }

  /// Trigger process queue manually
  void triggerProcess() => _scheduleRetry();

  /// Đếm pending
  Future<int> count() async {
    final list = await getAll();
    return list.length;
  }

  /// Clear all
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQueueKey);
    debugPrint('EmrUploadQueue: cleared');
  }
}
