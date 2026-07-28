import 'package:eatwise/core/notification/notification_types.dart';

/// 本地通知服务抽象接口（《规格-M2》§7，D-09）。
///
/// 对外只暴露抽象，便于 application 层以测试替身注入；
/// 生产实现见 `LocalNotificationService`（flutter_local_notifications 封装）。
abstract class NotificationService {
  /// 初始化插件并（Android）注册通知渠道。
  ///
  /// [channel] 为默认渠道；后续 [scheduleZoned]/[showNow] 未显式指定
  /// 渠道时使用。渠道名/描述为 i18n 文案，由调用方解析后传入。
  Future<void> initialize({NotificationChannelConfig? channel});

  /// 申请通知权限（用时申请，合规 §3：不随启动一股脑申请）。
  ///
  /// iOS：UNUserNotificationCenter alert/badge/sound；
  /// Android 13+：POST_NOTIFICATIONS 运行时权限；Android <13 恒已授权。
  Future<NotificationPermissionStatus> requestPermission();

  /// 查询当前通知权限状态（不触发系统弹窗）。
  Future<NotificationPermissionStatus> permissionStatus();

  /// 立即展示一条通知。
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    NotificationChannelConfig? channel,
    String? payload,
  });

  /// 排程一条定时通知（设备时区感知的 zonedSchedule）。
  ///
  /// Android 12+ 未授予 SCHEDULE_EXACT_ALARM 时自动降级为不精确闹钟
  /// （合规 §3.2：提醒可能延迟数分钟，不阻断计时）。
  Future<void> scheduleZoned(ScheduledNotification notification);

  /// 取消全部已排程/已展示通知（全量重排前先调用，《规格-M2》§7.2.5）。
  Future<void> cancelAll();
}
