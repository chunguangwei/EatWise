import 'dart:async';

import 'package:flutter/widgets.dart';

/// 登录用户的前台同步：普通下行按分钟节流，待上传记录每 30 秒重试。
/// 条件变化由订阅方调用 [updateConditions]；订阅方销毁时须 [dispose]。
class ForegroundSyncObserver extends WidgetsBindingObserver {
  ForegroundSyncObserver({
    required this.isLoggedIn,
    required this.triggerSync,
    this.hasPending = _noPending,
    AppLifecycleState initialState = AppLifecycleState.resumed,
    DateTime Function()? now,
  }) : _foreground = initialState == AppLifecycleState.resumed,
       _now = now ?? DateTime.now;

  static bool _noPending() => false;

  final bool Function() isLoggedIn;
  final bool Function() hasPending;
  final void Function() triggerSync;
  final DateTime Function() _now;

  static const Duration minInterval = Duration(minutes: 1);
  static const Duration retryInterval = Duration(seconds: 30);

  DateTime _lastTriggered = DateTime.fromMillisecondsSinceEpoch(0);
  bool _foreground;
  bool _disposed = false;
  Timer? _retryTimer;

  bool get _shouldRetry =>
      !_disposed && _foreground && isLoggedIn() && hasPending();

  /// 激活待上传条件时立即重试；后续计数变化保留既有重试时钟。
  void updateConditions() {
    if (!_shouldRetry) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(retryInterval, (_) {
      // 即使订阅通知尚未到达，也再次核对登录与 pending，防止匿名上行。
      if (!_shouldRetry) {
        updateConditions();
        return;
      }
      _trigger();
    });
    _trigger();
  }

  void _trigger() {
    _lastTriggered = _now();
    triggerSync();
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_shouldRetry) {
      updateConditions();
      return;
    }
    updateConditions();
    if (!_foreground || !isLoggedIn()) return;
    if (_now().difference(_lastTriggered) < minInterval) return;
    _trigger();
  }
}
