import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_plan.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:intl/intl.dart' show DateFormat;

/// 断食通知文案的 slang 适配器（D-15：文案全部走 i18n key，禁止硬编码）。
///
/// 复用既有 `notification.fasting.*` key（进食前提醒/进食到点/断食开始），
/// 标题用 `common.appName`。

/// 断食提醒通知渠道 id（稳定，不随语言变化）。
const String fastingReminderChannelId = 'fasting_reminders';

/// 断食提醒通知渠道（Android 系统设置页可见）。
///
/// 渠道名/描述走 i18n key `notify.channel.fastingReminders.*`（D-15；
/// 已随 strings_* 深合并生成，`namespaces: false` 下同文件 key 均参与生成）。
NotificationChannelConfig fastingReminderChannel(Translations t) {
  return NotificationChannelConfig(
    id: fastingReminderChannelId,
    name: t.notify.channel.fastingReminders.name,
    description: t.notify.channel.fastingReminders.description,
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
/// 走 intl 的 locale 短日期（zh-CN：`7月28日`；en：`Jul 28`），
/// 随通知文案的 locale 走；日期符号数据未就绪时（如纯 Dart 单测未加载
/// flutter_localizations）回退到等价的手写格式，保证不崩。
String formatAttributionDate(LocalDate date, {required AppLocale locale}) {
  final dt = DateTime(date.year, date.month, date.day);
  try {
    return DateFormat.MMMd(locale.languageTag.replaceAll('-', '_')).format(dt);
  } on Object {
    // 防御：intl 日期符号未初始化时按locale手写兜底（输出与 intl 一致）。
    return switch (locale) {
      AppLocale.zhCn => '${date.month}月${date.day}日',
      AppLocale.en => '${_enMonthAbbr[date.month - 1]} ${date.day}',
    };
  }
}

/// 英文月份缩写（formatAttributionDate 兜底路径用）。
const List<String> _enMonthAbbr = <String>[
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
