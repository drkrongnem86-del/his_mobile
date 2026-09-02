// TokenSyncService v3.0.165 - Service trung tâm quản lý HIS Pro token
//
// Vai trò: 1 điểm duy nhất để quản lý token, áp dụng cho TẤT CẢ services cần dùng:
// - HisApiService (procedure room, ECG, treatment history)
// - HisProApiService (EMR push, mọi nơi cần call HIS Pro API)
// - AutoTokenService (multi-source fetch)
//
// Đặc điểm:
// - Singleton - 1 instance duy nhất cho cả app
// - BroadcastStream<TokenEvent> - mọi screen subscribe được, tự cập nhật khi token đổi
// - setToken() - apply token ngay cho cả 2 API services + broadcast cho listeners
// - autoFetchToken() - gọi AutoTokenService.fetchToken() + apply
// - Lưu vào SharedPreferences (key: his_pro_token_override) để các screen mở sau load lại

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:his_mobile/data/api/his_api_service.dart';
import 'package:his_mobile/data/api/his_pro_api_service.dart';
import 'package:his_mobile/data/services/auto_token_service.dart';

/// Loại event broadcast khi token thay đổi
enum TokenEventType {
  fetched,   // Token vừa được auto-fetch từ multi-source
  manual,    // User vừa paste token thủ công
  cleared,   // Token bị xóa
  loaded,    // Token vừa load từ SharedPreferences
}

/// Event payload broadcast khi token đổi
class TokenEvent {
  final TokenEventType type;
  final String? token;
  final String? source;       // TokenSource name (loginApi, renewApi, hardcoded, cached, manual)
  final String? message;
  final DateTime timestamp;

  TokenEvent({
    required this.type,
    this.token,
    this.source,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class TokenSyncService {
  static final TokenSyncService instance = TokenSyncService._();
  TokenSyncService._();

  static const String _kStorageKey = 'his_pro_token_override';

  // StreamController broadcast cho listeners
  final _controller = StreamController<TokenEvent>.broadcast();
  Stream<TokenEvent> get stream => _controller.stream;

  String? _currentToken;
  String? _currentSource;
  DateTime? _lastUpdated;

  String? get currentToken => _currentToken;
  String? get currentSource => _currentSource;
  DateTime? get lastUpdated => _lastUpdated;

  bool get hasToken => _currentToken != null && _currentToken!.isNotEmpty;

  /// Token đã cũ quá (>1 giờ) → cần refresh
  bool get isStale {
    if (_lastUpdated == null) return true;
    return DateTime.now().difference(_lastUpdated!) > const Duration(hours: 1);
  }

  /// Load token từ SharedPreferences + apply cho services
  /// Gọi khi app start (main.dart) hoặc khi mở screen cần token
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kStorageKey);
      if (token != null && token.isNotEmpty) {
        await setToken(token, source: 'cached', eventType: TokenEventType.loaded, broadcast: true);
        debugPrint('✅ [TokenSync] Loaded from storage: ${token.substring(0, 8)}…');
      } else {
        debugPrint('ℹ️ [TokenSync] No token in storage');
      }
    } catch (e) {
      debugPrint('❌ [TokenSync] loadFromStorage error: $e');
    }
  }

  /// Set token + apply cho tất cả services + broadcast
  /// - Gọi khi: user paste manual, auto-fetch thành công, hoặc load từ storage
  Future<void> setToken(
    String token, {
    String? source,
    TokenEventType eventType = TokenEventType.manual,
    bool broadcast = true,
  }) async {
    if (token.isEmpty) {
      await clearToken(broadcast: broadcast);
      return;
    }
    _currentToken = token;
    _currentSource = source;
    _lastUpdated = DateTime.now();

    // 1. Lưu vào SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStorageKey, token);
    } catch (e) {
      debugPrint('❌ [TokenSync] save storage error: $e');
    }

    // 2. Apply cho HisApiService (procedure room, ECG, treatment history,...)
    try {
      HisApiService.instance.setAuthToken(token);
    } catch (e) {
      debugPrint('❌ [TokenSync] setAuthToken error: $e');
    }

    // 3. Apply cho HisProApiService (EMR push, setCustomBearer)
    try {
      await HisProApiService.instance.setCustomBearer(token);
    } catch (e) {
      debugPrint('❌ [TokenSync] setCustomBearer error: $e');
    }

    debugPrint('✅ [TokenSync] Token applied: ${token.substring(0, 8)}… (source=$source, event=$eventType)');

    // 4. Broadcast cho listeners
    if (broadcast) {
      _controller.add(TokenEvent(
        type: eventType,
        token: token,
        source: source,
        message: 'Token updated from $source',
      ));
    }
  }

  /// Xóa token (clear storage + clear services)
  Future<void> clearToken({bool broadcast = true}) async {
    _currentToken = null;
    _currentSource = null;
    _lastUpdated = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kStorageKey);
    } catch (e) {
      debugPrint('❌ [TokenSync] clear storage error: $e');
    }

    try {
      HisApiService.instance.clearAuthToken();
    } catch (_) {}
    try {
      await HisProApiService.instance.clearCustomBearer();
    } catch (_) {}

    debugPrint('🗑️ [TokenSync] Token cleared');

    if (broadcast) {
      _controller.add(TokenEvent(
        type: TokenEventType.cleared,
        message: 'Token cleared',
      ));
    }
  }

  /// Auto-fetch token từ multi-source (proxy → login API → renew → hardcoded)
  /// Returns: TokenEvent với kết quả
  /// - Token vẫn valid (< 1 giờ) → return current ngay, không fetch
  /// - Token stale hoặc rỗng → gọi AutoTokenService
  Future<TokenEvent> autoFetchToken({bool force = false}) async {
    if (!force && hasToken && !isStale) {
      debugPrint('ℹ️ [TokenSync] Token vẫn fresh (< 1 giờ), skip auto-fetch');
      return TokenEvent(
        type: TokenEventType.loaded,
        token: _currentToken,
        source: _currentSource ?? 'cached',
        message: 'Token vẫn còn hiệu lực',
      );
    }

    try {
      final result = await AutoTokenService.instance.fetchToken(forceRefresh: force);
      if (result.success && result.token != null) {
        await setToken(
          result.token!,
          source: result.source.name,
          eventType: TokenEventType.fetched,
          broadcast: true,
        );
        return TokenEvent(
          type: TokenEventType.fetched,
          token: result.token,
          source: result.source.name,
          message: 'Auto-fetched: ${result.source.name}',
        );
      } else {
        return TokenEvent(
          type: TokenEventType.fetched,
          message: result.message ?? 'Auto-fetch failed',
        );
      }
    } catch (e) {
      debugPrint('❌ [TokenSync] autoFetchToken error: $e');
      return TokenEvent(
        type: TokenEventType.fetched,
        message: 'Error: $e',
      );
    }
  }

  /// Apply thủ công (user paste) - save + broadcast
  Future<TokenEvent> setManualToken(String token) async {
    if (token.length < 60) {
      return TokenEvent(
        type: TokenEventType.manual,
        message: 'Token phải >= 60 ký tự hex (hiện tại: ${token.length})',
      );
    }
    await setToken(
      token,
      source: 'manual',
      eventType: TokenEventType.manual,
      broadcast: true,
    );
    return TokenEvent(
      type: TokenEventType.manual,
      token: token,
      source: 'manual',
      message: 'Token pasted manually',
    );
  }

  /// Subscribe lắng nghe thay đổi token (gọi trong initState, cancel trong dispose)
  StreamSubscription<TokenEvent> listen(void Function(TokenEvent) onEvent) {
    return _controller.stream.listen(onEvent);
  }

  /// Đóng stream (gọi khi app dispose - thường không cần)
  void dispose() {
    _controller.close();
  }

  /// Mask token để hiển thị (an toàn)
  String get maskedToken {
    if (_currentToken == null || _currentToken!.isEmpty) return '— chưa đặt —';
    if (_currentToken!.length < 16) return _currentToken!;
    return '${_currentToken!.substring(0, 8)}…${_currentToken!.substring(_currentToken!.length - 8)}';
  }

  /// Format thời gian update token (e.g. "5 phút trước", "2 giờ trước")
  String get lastUpdatedLabel {
    if (_lastUpdated == null) return '—';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }
}
