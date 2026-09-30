import 'package:flutter/widgets.dart';

/// 前台回切同步触发器（2026-09-30 真机走查：同一账号 Android 记的记录，
/// iOS 要杀掉 App 重开才出现——旧口径 syncNow 只有冷启动/登录/本地记账
/// 动作触发，iOS 用户不杀进程，回前台没有任何同步机会）。
///
/// `AppLifecycleState.resumed` 时触发一轮 RecordSyncEngine.syncNow
///（先上行 pending 再增量下行；引擎自身在途去抖），[minInterval] 最小
/// 间隔节流（前台高频切换不重复打全量推拉），仅登录态（与 main 冷启动
/// 触发块同口径——匿名态下行通道本就关闭）。
///
/// 依赖以回调注入（生产在 main.dart 接线到 ProviderContainer），
/// 便于单测不装配引擎。
class ForegroundSyncObserver extends WidgetsBindingObserver {
  ForegroundSyncObserver({
    required this.isLoggedIn,
    required this.triggerSync,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 登录态判定（匿名态下行通道关闭，不触发）。
  final bool Function() isLoggedIn;

  /// 同步触发回调（生产接线 RecordSyncEngine.syncNow）。
  final void Function() triggerSync;

  final DateTime Function() _now;

  /// 最小触发间隔。
  static const Duration minInterval = Duration(minutes: 1);

  DateTime _lastTriggered = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!isLoggedIn()) return;
    final now = _now();
    if (now.difference(_lastTriggered) < minInterval) return;
    _lastTriggered = now;
    triggerSync();
  }
}
