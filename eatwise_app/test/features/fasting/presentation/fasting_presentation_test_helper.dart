import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 断食计时 presentation 层测试共享替身与工具。

/// 通知服务替身：记录调用序列与已排程通知（权限默认已授权）。
final class FakeNotificationService implements NotificationService {
  final List<String> calls = <String>[];
  final List<ScheduledNotification> scheduled = <ScheduledNotification>[];
  NotificationPermissionStatus permission =
      NotificationPermissionStatus.granted;

  @override
  Future<void> initialize({NotificationChannelConfig? channel}) async {
    calls.add('initialize');
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    calls.add('requestPermission');
    return permission;
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    calls.add('permissionStatus');
    return permission;
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    NotificationChannelConfig? channel,
    String? payload,
  }) async {
    calls.add('showNow');
  }

  @override
  Future<void> scheduleZoned(ScheduledNotification notification) async {
    calls.add('scheduleZoned');
    scheduled.add(notification);
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    scheduled.clear();
  }
}

/// 可断言的调度器：记录每次 reschedule 的入参（方案/延长量/原因），
/// 底层走真实 [FastingNotificationScheduler] + [FakeNotificationService]。
final class RecordingFastingScheduler extends FastingNotificationScheduler {
  RecordingFastingScheduler({
    required this.service,
    required super.locationResolver,
    super.nowUtcSec,
  }) : super(
         notifications: service,
         textResolver: (n) => (title: 'T', body: n.kind.name),
         channel: const NotificationChannelConfig(id: 'test', name: 'T'),
       );

  final FakeNotificationService service;

  final List<
    ({FastingPlan? plan, int extensionMinutes, RescheduleReason reason})
  >
  rescheduleCalls =
      <({FastingPlan? plan, int extensionMinutes, RescheduleReason reason})>[];

  @override
  Future<RescheduleResult> reschedule({
    required FastingPlan? plan,
    int extensionMinutes = 0,
    RescheduleReason reason = RescheduleReason.stateTransition,
    int eatSoonLeadSec = 15 * 60,
  }) {
    rescheduleCalls.add((
      plan: plan,
      extensionMinutes: extensionMinutes,
      reason: reason,
    ));
    return super.reschedule(
      plan: plan,
      extensionMinutes: extensionMinutes,
      reason: reason,
      eatSoonLeadSec: eatSoonLeadSec,
    );
  }
}

/// 假时钟（UTC epoch 秒，测试可自由拨动）。
final class FakeClock {
  FakeClock(this.now);

  int now;

  int call() => now;
}

/// 测试基准：Asia/Shanghai（UTC+8）下 2026-07-28 的 UTC epoch 秒换算。
/// 方案 16:8（进食 12:00–20:00 本地）：
/// - 进食窗口开始 = 本地 12:00 = UTC 04:00；
/// - 进食窗口结束 = 本地 20:00 = UTC 12:00（前一日 20:00 = UTC 27 日 12:00
///   断食开始）。
int bjtUtc(int day, int hour, [int minute = 0, int second = 0]) {
  return DateTime.utc(
        2026,
        7,
        day,
        hour,
        minute,
        second,
      ).millisecondsSinceEpoch ~/
      1000;
}

/// 向 SharedPreferences 写入活动方案与营养目标（模拟 M1 一键启动后的状态）。
Future<SharedPreferences> seedActivePlanPrefs({
  required int startedAtUtc,
  int targetKcal = 2000,
  int proteinG = 100,
  int carbG = 200,
  int fatG = 60,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final store = SharedPreferencesOnboardingStore(prefs);
  store.saveActivePlan(
    ActivePlanSnapshot(
      plan: FastingPlan.plan16x8,
      initialState: 'fasting',
      startedAtUtc: startedAtUtc,
    ),
  );
  store.saveNutritionGoal(
    NutritionGoalSnapshot(
      targetKcal: targetKcal,
      proteinG: proteinG,
      carbG: carbG,
      fatG: fatG,
      usedFallback: false,
      configVersion: '1.0.0',
    ),
  );
  store.markOnboardingCompleted();
  return prefs;
}
