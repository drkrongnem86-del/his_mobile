// v3.0.160: HisProxyTokenService - REFACTORED thành wrapper của AutoTokenService
//
// Trước (v3.0.82-v3.0.159): gọi proxy server http://{PC_IP}:9999/get-his-token
// Bây giờ (v3.0.160): gọi trực tiếp AutoTokenService (login API → renew → hardcoded)
// - Bỏ proxy server (BS không cần)
// - Tự cập nhật token từ nhiều nguồn
//
// Interface giữ nguyên để các file cũ (treatment_history_service.dart,
// treatment_history_screen.dart) không phải sửa nhiều.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:his_mobile/data/api/thongke_auth_service.dart';
import 'package:his_mobile/data/services/auto_token_service.dart';

class HisProxyTokenStatus {
  final bool reachable;
  final bool hasToken;
  final String? token;
  final String? tokenPreview;
  final int? tokenLength;
  final String? source;
  final String? sourceFile;
  final String? foundAt;
  final int? ageSeconds;
  final String? error;
  final String? pcUrl;

  const HisProxyTokenStatus({
    required this.reachable,
    this.hasToken = false,
    this.token,
    this.tokenPreview,
    this.tokenLength,
    this.source,
    this.sourceFile,
    this.foundAt,
    this.ageSeconds,
    this.error,
    this.pcUrl,
  });

  factory HisProxyTokenStatus.unreachable(String url, String error) =>
      HisProxyTokenStatus(reachable: false, pcUrl: url, error: error);
}

class HisProxyTokenService {
  static final HisProxyTokenService instance = HisProxyTokenService._();
  HisProxyTokenService._();

  /// Auto-fetch on 401? (default true)
  Future<bool> get autoFetchEnabled async {
    return await AutoTokenService.instance.isAutoLoginEnabled();
  }

  Future<void> setAutoFetchEnabled(bool enabled) async {
    await AutoTokenService.instance.setAutoLoginEnabled(enabled);
  }

  /// Lấy URL "proxy" (giữ tên cũ cho tương thích) - hiện tại chỉ là nhãn
  Future<String> getProxyUrl() async {
    return 'auto://auto-token-service';
  }

  /// Set URL proxy (no-op v3.0.160)
  Future<void> setProxyUrl(String url) async {
    // no-op
  }

  /// Ping - check if AutoTokenService available (always true)
  Future<HisProxyTokenStatus> ping({String? url}) async {
    return HisProxyTokenStatus(reachable: true, pcUrl: 'auto://auto-token-service');
  }

  /// Lấy token status từ AutoTokenService
  Future<HisProxyTokenStatus> getStatus({String? url}) async {
    final token = AutoTokenService.instance.currentToken;
    final lastFetch = AutoTokenService.instance.lastFetchTime;
    final ageSec = lastFetch != null
        ? DateTime.now().difference(lastFetch).inSeconds
        : null;
    return HisProxyTokenStatus(
      reachable: true,
      hasToken: token != null,
      token: token,
      tokenPreview: token != null && token.length >= 12
          ? '${token.substring(0, 12)}...'
          : null,
      tokenLength: token?.length,
      source: AutoTokenService.instance.currentSource.name,
      sourceFile: 'auto_token_service',
      foundAt: lastFetch?.toIso8601String(),
      ageSeconds: ageSec,
      pcUrl: 'auto://auto-token-service',
    );
  }

  /// Lấy token qua AutoTokenService và lưu vào ThongkeAuthService
  /// Returns: token string nếu OK, null nếu fail
  Future<String?> fetchAndSaveToken({String? url}) async {
    try {
      final result = await AutoTokenService.instance.fetchToken(forceRefresh: true);
      if (result.success && result.token != null) {
        await ThongkeAuthService.instance.setHisProToken(
          result.token!,
          source: result.source.name,
        );
        await ThongkeAuthService.instance.loadHisProToken();
        debugPrint('✅ Token fetched & saved (${result.token!.length} chars) from ${result.source.name}');
        return result.token;
      }
      debugPrint('❌ fetchAndSaveToken: ${result.message}');
      return null;
    } catch (e) {
      debugPrint('❌ fetchAndSaveToken error: $e');
      return null;
    }
  }

  /// Last fetch timestamp
  Future<DateTime?> getLastFetchTime() async {
    return AutoTokenService.instance.lastFetchTime;
  }
}
