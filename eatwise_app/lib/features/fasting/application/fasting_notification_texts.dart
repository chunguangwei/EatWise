import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_plan.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';

/// 断食通知文案的 slang 适配器（D-15：文案全部走 i18n key，禁止硬编码）。
///
/// 复用既有 `notification.fasting.*` key（进食前提醒/进食到点/断食开始），
/// 标题用 `common.appName`。

/// 断食提醒通知渠道 id（稳定，不随语言变化）。
const String fastingReminderChannelId = 'fasting_reminders';

/// 断食提醒通知渠道（Android 系统设置页可见）。
///
/// TODO(i18n)：渠道名/描述文案已备于 `i18n/strings_*.i18n.json（notify.* 已合并）`
/// （`notify.channel.fastingReminders.*`），当前 slang.yaml `namespaces: false`
/// 下命名空间文件不参与生成（多文件同 locale 为后者覆盖语义），
/// 待共享配置启用命名空间或将 notify key 合并进 strings_* 后切换，
/// 暂以 App 名兜底。
NotificationChannelConfig fastingReminderChannel(Translations t) {
  return NotificationChannelConfig(
    id: fastingReminderChannelId,
    name: t.common.appName,
  );
}

/// 由当前 [Translations] 生成通知文案解析器。
FastingNotificationTextResolver slangFastingNotificationTextResolver(
  Translations t,
) {
  final locale = t.$meta.locale;
  return (PlannedFastingNotification notification) {
    final body = switch (notification.kind) {
      FastingNotificationKind.eatSoon => t.notification.fasting.eatSoon,
      FastingNotificationKind.eatStart => t.notification.fasting.eatStart(
        date: formatAttributionDate(
          notification.attributionDate ?? _fallbackDate(notification),
          locale: locale,
        ),
      ),
      FastingNotificationKind.fastStart => t.notification.fasting.fastStart,
    };
    return (title: t.common.appName, body: body);
  };
}

/// 归属日缺省兜底：正常路径 eatStart 必带归属日，防御为空时不崩。
LocalDate _fallbackDate(PlannedFastingNotification notification) {
  final dt = DateTime.fromMillisecondsSinceEpoch(
    notification.triggerAtUtcSec * 1000,
    isUtc: true,
  );
  return LocalDate(dt.year, dt.month, dt.day);
}

/// 打卡归属日短格式（「本次断食计入 X 月 X 日」的日期部分）。
///
/// zh-CN：`7月28日`；en：`Jul 28`。属日期格式化规则而非文案，
/// 随通知文案的 locale 走。
String formatAttributionDate(LocalDate date, {required AppLocale locale}) {
  switch (locale) {
    case AppLocale.zhCn:
      return '${date.month}月${date.day}日';
    case AppLocale.en:
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}';
  }
}
