import 'dart:async';

import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';

/// 平台系统事件（《规格-M2 断食计时状态机》§2.2 事件枚举的调度相关子集）。
enum FastingSystemEvent {
  /// 系统时区变化（T14：iOS `NSSystemTimeZoneDidChangeNotification` /
  /// Android `ACTION_TIMEZONE_CHANGED`）。
  timezoneChanged,

  /// 系统时间被回拨/拨快（T15：Android `ACTION_TIME_CHANGED`；
  /// iOS 无公开回调，前台启动时校时）。
  clockChanged,

  /// Android 设备重启完成（§6-B14：BOOT_COMPLETED 后重排全部通知）。
  bootCompleted,
}

/// 平台事件源抽象。
///
/// TODO(平台桥接)：生产实现经 MethodChannel/EventChannel 监听原生广播——
/// - iOS：`NSSystemTimeZoneDidChangeNotification`（Darwin notification）；
/// - Android：`ACTION_TIMEZONE_CHANGED` / `ACTION_TIME_CHANGED` /
///   `BOOT_COMPLETED`（Manifest 已声明 RECEIVE_BOOT_COMPLETED，
///   插件侧 ScheduledNotificationBootReceiver 负责重启后恢复已排程通知，
///   本事件用于 App 侧全量重排兜底）。
/// 时区变化时原生侧需上报 IANA 时区名，由桥接层调用
/// `tz.setLocalLocation(tz.getLocation(name))` 更新 timezone 包本地时区
/// 后再派发事件（需要时区名查询能力，如 flutter_native_timezone，选型待定）。
abstract class FastingSystemEventSource {
  Stream<FastingSystemEvent> get events;
}

/// 系统事件 → 重排原因 的映射（§2.2 事件 → §7.2.3 触发器）。
RescheduleReason rescheduleReasonForSystemEvent(FastingSystemEvent event) {
  return switch (event) {
    FastingSystemEvent.timezoneChanged => RescheduleReason.timezoneChange,
    FastingSystemEvent.clockChanged => RescheduleReason.clockChanged,
    FastingSystemEvent.bootCompleted => RescheduleReason.bootCompleted,
  };
}

/// 「系统事件 → 通知重排」绑定器（T14/T15/B14）。
///
/// 「先 cancelAll 再重建」由 [FastingNotificationScheduler.reschedule]
/// 内部保证（§7.2.5），本类只负责事件到重排原因的映射与入口收敛。
class FastingNotificationEventBinder {
  FastingNotificationEventBinder({
    required this.scheduler,
    required this.source,
    required this.planProvider,
    int Function()? extensionMinutesProvider,
  }) : _extensionMinutesProvider = extensionMinutesProvider ?? (() => 0);

  /// 通知调度器。
  final FastingNotificationScheduler scheduler;

  /// 平台事件源。
  final FastingSystemEventSource source;

  /// 当前断食方案提供者（null = NO_PLAN）。
  final FastingPlan? Function() planProvider;

  final int Function() _extensionMinutesProvider;

  StreamSubscription<FastingSystemEvent>? _subscription;

  /// 开始监听。重复调用安全（先取消旧订阅）。
  void start() {
    unawaited(_subscription?.cancel());
    _subscription = source.events.listen(_onEvent);
  }

  /// 停止监听。
  Future<void> stop() => _subscription?.cancel() ?? Future.value();

  void _onEvent(FastingSystemEvent event) {
    unawaited(
      scheduler.reschedule(
        plan: planProvider(),
        extensionMinutes: _extensionMinutesProvider(),
        reason: rescheduleReasonForSystemEvent(event),
      ),
    );
  }
}
