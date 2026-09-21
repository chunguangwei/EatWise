import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart'
    show fastingCycleStoreProvider, fastingNotificationSchedulerProvider;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/data/water_reminder_store.dart';
import 'package:eatwise/features/record/domain/water_reminder_plan.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show waterLogRepositoryProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 喝水提醒装配层（application）：开关存储 + 渠道/文案 + 排程计划生成器。
///
/// 计划生成为 `water_reminder_plan.dart` 纯函数；本层只做「读开关/方案/
/// 当日水量 → 生成 ScheduledNotification」。排程动作由
/// [FastingNotificationScheduler] 的 extraPlanner 挂载（全 App 通知
/// cancelAll 单入口，避免多调度器互删）。

/// 开关存储（prefs 未注入时内存兜底，与 settings_providers 同口径）。
final waterReminderStoreProvider = Provider<WaterReminderStore>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } on Object {
    prefs = null;
  }
  return WaterReminderStore(prefs);
});

/// 喝水提醒开关（UI 响应式包装：翻转即重排通知 + 落盘）。
final waterReminderEnabledProvider =
    StateNotifierProvider<WaterReminderEnabledController, bool>((ref) {
      return WaterReminderEnabledController(
        ref.watch(waterReminderStoreProvider),
      );
    });

final class WaterReminderEnabledController extends StateNotifier<bool> {
  WaterReminderEnabledController(this._store) : super(_store.isEnabled);

  final WaterReminderStore _store;

  void setEnabled(bool value) {
    if (value == state) return;
    state = value;
    _store.setEnabled(value);
  }
}

/// 触发一轮「含喝水计划」的全量通知重排（喝水入账/开关翻转入口）。
///
/// 走断食调度器单入口：plan 取当前生效方案（null 时重排只清空，与
/// NO_PLAN 语义一致）；失败静默（提醒降级不阻断记录主流程）。
void rescheduleWaterReminders(WidgetRef ref) {
  try {
    final plan = ref.read(onboardingStoreProvider).loadActivePlan()?.plan;
    // 延长中的断食：重排必须带上累计延长量，否则 eatSoon/eatStart 锚点
    // 会被挪回未延息的旧时刻（与 controller._reschedule 同口径）。
    final extensionMinutes =
        ref
            .read(fastingCycleStoreProvider)
            .loadActiveCycle()
            ?.extendedMinutes ??
        0;
    unawaited(() async {
      try {
        await ref
            .read(fastingNotificationSchedulerProvider)
            .reschedule(
              plan: plan,
              extensionMinutes: extensionMinutes,
              reason: RescheduleReason.waterIntake,
            );
      } on Object {
        // 防御：reschedule 是异步的，同步 try 拦不住其中的插件异常
        //（测试/桌面端 FlutterLocalNotificationsPlatform 未初始化）。
      }
    }());
  } on Object {
    // 防御：通知链路未装配时跳过。
  }
}

/// 喝水提醒通知渠道 id（稳定，不随语言变化）。
const String waterReminderChannelId = 'water_reminders';

/// 喝水提醒通知渠道（Android 系统设置页可见；名称/描述走 i18n，D-15）。
NotificationChannelConfig waterReminderChannel(Translations t) {
  return NotificationChannelConfig(
    id: waterReminderChannelId,
    name: t.notify.channel.waterReminders.name,
    description: t.notify.channel.waterReminders.description,
  );
}

/// 计划项 → 已排程通知（标题 App 名，正文带建议量与当日剩余量插值）。
NotificationServiceWaterText slangWaterReminderText(
  Translations t,
  PlannedWaterReminder reminder,
) {
  return (
    title: t.common.appName,
    body: t.notification.water.hourly(
      ml: reminder.suggestedMl,
      remaining: reminder.remainingMl,
    ),
  );
}

/// 喝水提醒文案元组（避免裸 record 类型漂移）。
typedef NotificationServiceWaterText = ({String title, String body});

/// 排程计划生成器：开关关 / 无生效方案 / 权限降级（调用方保证）时为空。
///
/// 挂 [FastingNotificationScheduler.extraPlanner]：每次断食重排（启动、
/// 回前台、方案变更、喝水入账、系统事件）都会带一轮喝水计划重建——
/// 「达标即停发」与「建议量随剩余量收敛」都靠这条重排链生效。
final waterReminderExtraPlannerProvider =
    Provider<Future<List<ScheduledNotification>> Function()>((ref) {
      return () async {
        final store = ref.read(waterReminderStoreProvider);
        if (!store.isEnabled) return const <ScheduledNotification>[];
        final plan = ref.read(onboardingStoreProvider).loadActivePlan()?.plan;
        if (plan == null) return const <ScheduledNotification>[];
        final location = ref.read(deviceLocationProvider);
        final nowUtcSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        final today = localDateOf(nowUtcSec, location);
        final todayKey =
            '${today.year.toString().padLeft(4, '0')}-'
            '${today.month.toString().padLeft(2, '0')}-'
            '${today.day.toString().padLeft(2, '0')}';
        final alreadyMl = await ref
            .read(waterLogRepositoryProvider)
            .totalForDate(todayKey);
        final t = LocaleSettings.currentLocale.buildSync();
        final channel = waterReminderChannel(t);
        return buildWaterReminderPlan(
          plan: plan,
          alreadyMl: alreadyMl,
          nowUtcSec: nowUtcSec,
          location: location,
          goalMl: WaterLogRepository.dailyGoalMl,
        ).map((r) {
          final text = slangWaterReminderText(t, r);
          return ScheduledNotification(
            id: r.id,
            title: text.title,
            body: text.body,
            channel: channel,
            triggerAtUtcSec: r.triggerAtUtcSec,
          );
        }).toList();
      };
    });
