// v2.47.0: Navigation helpers - safe pop/push tránh black screen
// Black screen xảy ra khi:
//  1. Navigator.pop/push synchronous trong cùng frame → race
//  2. context đã unmounted (build khác) → null check
//  3. push ngay sau pop mà pop chưa xong
//
// → Dùng Future.delayed(50ms) + check context.mounted
import 'package:flutter/material.dart';

extension SafeNavigator on BuildContext {
  /// Pop an toàn - tránh black screen khi back
  void safePop<T>([T? result]) {
    if (!mounted) return;
    if (Navigator.of(this).canPop()) {
      Navigator.of(this).pop(result);
    }
  }

  /// Pop an toàn sau 1 frame - tránh race với push ngay sau
  void safePopDelayed<T>([T? result, Duration delay = const Duration(milliseconds: 50)]) {
    if (!mounted) return;
    Future.delayed(delay, () {
      if (!mounted) return;
      if (Navigator.of(this).canPop()) {
        Navigator.of(this).pop(result);
      }
    });
  }

  /// Push an toàn - wrap MaterialPageRoute với Builder
  Future<T?> safePush<T>(WidgetBuilder builder) {
    if (!mounted) return Future.value(null);
    return Navigator.of(this).push<T>(
      MaterialPageRoute<T>(builder: builder),
    );
  }

  /// Push an toàn với tên route - dùng khi không muốn route cụ thể
  Future<T?> safePushWidget<T>(Widget page) {
    if (!mounted) return Future.value(null);
    return Navigator.of(this).push<T>(
      MaterialPageRoute<T>(builder: (_) => page),
    );
  }
}
