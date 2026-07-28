import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:timezone/timezone.dart' as tz;

/// 断食窗口提醒调度器（《规格-M2 断食计时状态机》§7，D-09）。
///
/// 重排触发器统一收敛到单一 [FastingNotificationScheduler.reschedule]
/// 入口（§7.2.3：任何状态迁移
/// 副作用、方案生效、延长、手动结束、时区变更、校时、App 前台、设备重启）。
/// 每次重排「先 cancelAll 再重建」（§7.2.5），避免时区变化后旧通知
/// 在错误时刻触发（T14）。

/// 重排原因（§7.2.3 触发器清单，用于结果回执与诊断日志）。
enum RescheduleReason {
  /// 状态机任意迁移的副作用（§2.3 迁移表「重排通知」）。
  stateTransition,

  /// 方案变更（T12，次日生效；当日锚点不动但仍对账重排）。
  planChange,

  /// 新方案生效（T13 PLAN_ACTIVATE）。
  planActivate,

  /// 延长（T5/T6，锚点后移）。
  extensionApplied,

  /// 手动结束断食（T3/T4/T9）。
  manualEndFast,

  /// 系统时区变化（T14：UTC 锚点不变，通知全部重排，D-09）。
  timezoneChange,

  /// 系统时间被回拨/拨快（T15）。
  clockChanged,

  /// App 启动/回前台对账补排（T16）。
  appForeground,

  /// Android 设备重启后重排（§6-B14）。
  bootCompleted,
}

/// 通知文案解析器：计划项 → 标题/正文。
///
/// 文案必须走 i18n key（D-15，禁止硬编码）；生产实现由
/// `fasting_notification_texts.dart` 的 slang 适配器提供，测试可注入替身。
typedef FastingNotificationTextResolver =
    ({String title, String body}) Function(
      PlannedFastingNotification notification,
    );

/// 一次重排的结果回执。
final class RescheduleResult {
  const RescheduleResult({
    required this.reason,
    required this.permissionStatus,
    required this.degraded,
    required this.plan,
  });

  /// 本次重排触发原因。
  final RescheduleReason reason;

  /// 重排时的通知权限状态。
  final NotificationPermissionStatus permissionStatus;

  /// 降级标志：权限被拒（或未确定）时为 true——通知未排程但计时不阻断，
  /// UI 据此展示 App 内顶部横幅引导开启（D-09 / 合规 §3.1）。
  final bool degraded;

  /// 本次生成的计划（权限降级时为空列表）。
  final List<PlannedFastingNotification> plan;

  /// 实际排程条数。
  int get scheduledCount => plan.length;
}

/// 断食通知调度器。注入时钟与时区解析器，纯逻辑可全量单测。
class FastingNotificationScheduler {
  FastingNotificationScheduler({
    required this.notifications,
    required this.textResolver,
    required this.channel,
    required this.locationResolver,
    int Function()? nowUtcSec,
  }) : _nowUtcSec =
           nowUtcSec ??
           (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);

  /// 底层通知服务（抽象接口，测试可注入替身）。
  final NotificationService notifications;

  /// 文案解析器（i18n 适配层）。
  final FastingNotificationTextResolver textResolver;

  /// 目标通知渠道。
  final NotificationChannelConfig channel;

  /// 设备当前时区解析器（时区变化后重排时取新值，T14）。
  final tz.Location Function() locationResolver;

  final int Function() _nowUtcSec;

  /// 全量重排（单一入口，§7.2.3）。
  ///
  /// - [plan] 为 null（NO_PLAN）时仅清空已有通知；
  /// - [extensionMinutes] 为当前周期累计延长（D-10，默认 0）；
  /// - [eatSoonLeadSec] 为进食开始提前量（D-09 默认 15min，设置可调）。
  ///
  /// 权限被拒时不抛异常、不排程，返回 [RescheduleResult.degraded] = true
  /// （合规 §3：权限拒绝降级，核心计时不阻断）。
  Future<RescheduleResult> reschedule({
    required FastingPlan? plan,
    int extensionMinutes = 0,
    RescheduleReason reason = RescheduleReason.stateTransition,
    int eatSoonLeadSec = 15 * 60,
  }) async {
    // §7.2.5：重排前先 cancelAll 再重建（时区变化后旧通知在错误时刻触发）。
    await notifications.cancelAll();

    final status = await notifications.permissionStatus();

    // NO_PLAN 或权限降级：清空后即返回，不阻断业务。
    if (plan == null || status != NotificationPermissionStatus.granted) {
      return RescheduleResult(
        reason: reason,
        permissionStatus: status,
        degraded: plan != null,
        plan: const [],
      );
    }

    final items = buildFastingNotificationPlan(
      plan: plan,
      nowUtcSec: _nowUtcSec(),
      location: locationResolver(),
      eatSoonLeadSec: eatSoonLeadSec,
      extensionMinutes: extensionMinutes,
    );

    for (final item in items) {
      final text = textResolver(item);
      await notifications.scheduleZoned(
        ScheduledNotification(
          id: item.id,
          title: text.title,
          body: text.body,
          channel: channel,
          triggerAtUtcSec: item.triggerAtUtcSec,
        ),
      );
    }

    return RescheduleResult(
      reason: reason,
      permissionStatus: status,
      degraded: false,
      plan: items,
    );
  }
}
