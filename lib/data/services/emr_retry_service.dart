// EmrRetryService v3.0.37 - Retry logic theo spec BS
// Chỉ retry với lỗi mạng:
//   ✅ timeout
//   ✅ socket exception
//   ✅ mất VPN
// Không retry:
//   ❌ 401
//   ❌ Success=false (permission denied, validation)
//   ❌ HTTP 4xx khác
//
// Pseudo:
//   maxRetry = 3
//   delays = [1s, 2s, 4s] (exponential backoff)
//   for (i=0; i<3; i++) {
//     try { upload(); break; }
//     catch (e) {
//       if (!isRetryable(e)) break; // không retry
//       await Future.delayed(delays[i]);
//     }
//   }
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/services/upload_log_service.dart';

class RetryResult<T> {
  final T? data;
  final bool success;
  final int attempts;
  final int totalDurationMs;
  final String? lastError;
  final bool wasRetried;

  RetryResult({
    this.data,
    required this.success,
    required this.attempts,
    required this.totalDurationMs,
    this.lastError,
    this.wasRetried = false,
  });

  bool get isRetryableFailure => !success && lastError != null;
}

class EmrRetryService {
  static final EmrRetryService instance = EmrRetryService._();
  EmrRetryService._();

  /// Số lần retry tối đa (3 lần = 1 lần đầu + 3 retry)
  static const int maxRetries = 3;

  /// Delay theo exponential backoff: 1s, 2s, 4s
  static const List<int> backoffDelaysMs = [1000, 2000, 4000];

  /// Check lỗi có phải network/retryable không
  bool isRetryableError(Object? error) {
    if (error == null) return false;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return true; // timeout
        case DioExceptionType.connectionError:
          return true; // mất VPN, socket error
        case DioExceptionType.badCertificate:
          return true; // có thể retry
        case DioExceptionType.cancel:
          return false;
        case DioExceptionType.badResponse:
          // Retry với 5xx (server error), không retry 4xx (client error)
          final code = error.response?.statusCode ?? 0;
          return code >= 500 && code < 600;
        case DioExceptionType.unknown:
          // Check message
          final msg = error.message?.toLowerCase() ?? '';
          if (msg.contains('socket') || msg.contains('timeout') ||
              msg.contains('connection') || msg.contains('vpn') ||
              msg.contains('network')) {
            return true;
          }
          return false;
      }
    }
    // Non-Dio error
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') || msg.contains('timeout') ||
        msg.contains('connection') || msg.contains('vpn') ||
        msg.contains('network')) {
      return true;
    }
    return false;
  }

  /// Retry với exponential backoff
  /// [task] là hàm async trả về T
  /// [endpoint] để log
  /// Trả về RetryResult<T>
  Future<RetryResult<T>> executeWithRetry<T>({
    required Future<T> Function() task,
    required String endpoint,
  }) async {
    final sw = Stopwatch()..start();
    T? result;
    String? lastError;
    int attempt = 0;
    bool wasRetried = false;

    for (attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        result = await task();
        sw.stop();
        // Success → log metric
        await UploadLogService.instance.logMetric(
          endpoint: endpoint,
          outcome: 'SUCCESS',
          durationMs: sw.elapsedMilliseconds,
          retryCount: attempt,
        );
        return RetryResult<T>(
          data: result,
          success: true,
          attempts: attempt + 1,
          totalDurationMs: sw.elapsedMilliseconds,
          wasRetried: wasRetried,
        );
      } catch (e) {
        lastError = e.toString();
        final retryable = isRetryableError(e);
        debugPrint('EmrRetry[$endpoint] attempt ${attempt + 1} failed: ${e.runtimeType}: $lastError (retryable=$retryable)');
        if (!retryable) {
          // Không retry - log + return failure ngay
          sw.stop();
          await UploadLogService.instance.logMetric(
            endpoint: endpoint,
            outcome: 'FAILED',
            durationMs: sw.elapsedMilliseconds,
            retryCount: attempt,
          );
          return RetryResult<T>(
            data: null,
            success: false,
            attempts: attempt + 1,
            totalDurationMs: sw.elapsedMilliseconds,
            lastError: lastError,
            wasRetried: wasRetried,
          );
        }
        if (attempt >= maxRetries) {
          // Hết retry
          sw.stop();
          await UploadLogService.instance.logMetric(
            endpoint: endpoint,
            outcome: 'FAILED',
            durationMs: sw.elapsedMilliseconds,
            retryCount: attempt,
          );
          return RetryResult<T>(
            data: null,
            success: false,
            attempts: attempt + 1,
            totalDurationMs: sw.elapsedMilliseconds,
            lastError: lastError,
            wasRetried: wasRetried,
          );
        }
        // Retry
        wasRetried = true;
        final delay = backoffDelaysMs[attempt];
        await UploadLogService.instance.logRetry(
          endpoint: endpoint,
          attempt: attempt + 1,
          error: lastError,
          delayMs: delay,
          nextAction: 'delay',
        );
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    sw.stop();
    return RetryResult<T>(
      data: result,
      success: false,
      attempts: attempt,
      totalDurationMs: sw.elapsedMilliseconds,
      lastError: lastError,
      wasRetried: wasRetried,
    );
  }
}
