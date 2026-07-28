/// 本地通知封装（D-09，《规格-M2 断食计时状态机》§7）的公共类型。
///
/// 双端能力桥接见《技术选型与双端架构》§3：iOS UNUserNotificationCenter /
/// Android NotificationChannel，统一经 flutter_local_notifications（D-17）。
library;

/// 通知权限状态。
///
/// 合规（《合规-隐私与合规方案》§3）：权限被拒绝后核心计时链路必须可用，
/// 调用方依据本状态做降级（App 内顶部横幅引导，D-09），不得中断业务。
enum NotificationPermissionStatus {
  /// 已授权（iOS authorized/provisional；Android areNotificationsEnabled）。
  granted,

  /// 已拒绝。
  denied,

  /// 未询问过或平台无法查询（按未授权处理，但不阻断业务）。
  notDetermined,
}

/// Android 通知渠道定义（API 26+ 强制；iOS 侧忽略）。
///
/// 渠道名/描述是用户可见文案，必须走 i18n（D-15），由调用方解析后传入。
final class NotificationChannelConfig {
  const NotificationChannelConfig({
    required this.id,
    required this.name,
    this.description,
  });

  /// 渠道 id（稳定，不随语言变化）。
  final String id;

  /// 渠道名（系统设置页可见，i18n 文案）。
  final String name;

  /// 渠道描述（系统设置页可见，i18n 文案）。
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is NotificationChannelConfig &&
      other.id == id &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(id, name, description);

  @override
  String toString() => 'NotificationChannelConfig($id)';
}

/// 一条待排程的定时通知。
final class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.channel,
    required this.triggerAtUtcSec,
    this.payload,
  });

  /// 通知 id（双端 int32；调用方保证在排程窗口内唯一且可复现）。
  final int id;

  /// 标题（i18n 文案，通常 App 名）。
  final String title;

  /// 正文（i18n 文案）。
  final String body;

  /// 目标渠道。
  final NotificationChannelConfig channel;

  /// 触发时刻（UTC epoch 秒）。落地时按设备当前时区换算为本地墙钟
  /// （D-07：UTC 存储本地渲染），夏令时切换由 zonedSchedule 时区语义兜底
  /// （《规格-M2》§6-B11）。
  final int triggerAtUtcSec;

  /// 点击通知时的负载（路由深链等，可选）。
  final String? payload;

  @override
  String toString() =>
      'ScheduledNotification(id: $id, triggerAtUtcSec: $triggerAtUtcSec)';
}
