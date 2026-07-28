import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../tz_test_helper.dart';
import 'fasting_presentation_test_helper.dart';

/// FastingTimerController 单测（假时钟 + 内存存储 + 可断言调度器）。
///
/// 时间线约定：Asia/Shanghai，方案 16:8（进食 12:00–20:00 本地）；
/// 2026-07-28 本地 12:00 = UTC 04:00，本地 20:00 = UTC 12:00。
void main() {
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  late FakeClock clock;
  late InMemoryFastingCycleStore cycleStore;
  late RecordingFastingScheduler scheduler;
  late SharedPreferences prefs;

  Future<ProviderContainer> buildContainer() async {
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        fastingCycleStoreProvider.overrideWithValue(cycleStore),
        fastingNotificationSchedulerProvider.overrideWithValue(scheduler),
        fastingClockProvider.overrideWithValue(clock.call),
        deviceLocationProvider.overrideWithValue(bjt),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() async {
    cycleStore = InMemoryFastingCycleStore();
    scheduler = RecordingFastingScheduler(
      service: FakeNotificationService(),
      locationResolver: () => bjt,
    );
  });

  group('状态解析（注入时钟）', () {
    test('无方案 → NO_PLAN，无快照', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      clock = FakeClock(bjtUtc(28, 0));
      final container = await buildContainer();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.noPlan);
      expect(state.snapshot, isNull);
      expect(state.plan, isNull);
    });

    test('断食中：倒计时 = 距进食窗口开始，归属日 = 当日（跨午夜次日窗口）', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      // 本地 07-28 08:00（UTC 00:00）：断食中，距 12:00 还有 4h。
      clock = FakeClock(bjtUtc(28, 0));
      final container = await buildContainer();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.fasting);
      expect(state.snapshot!.countdownSec, 4 * 3600);
      expect(state.snapshot!.attributionPreview, const LocalDate(2026, 7, 28));
      expect(state.cycle!.extendedMinutes, 0);
    });

    test('进食中：倒计时 = 距进食窗口结束', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      // 本地 07-28 14:00（UTC 06:00）：进食中，距 20:00 还有 6h。
      clock = FakeClock(bjtUtc(28, 6));
      final container = await buildContainer();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.eating);
      expect(state.snapshot!.countdownSec, 6 * 3600);
      expect(state.cycle, isNull);
    });
  });

  group('延长（D-10，T5/T6/T7）', () {
    test('延长 30min：锚点后移、状态转 fastingExtended、落盘、按扩展量重排', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      clock = FakeClock(bjtUtc(28, 0));
      final container = await buildContainer();

      final ok = container
          .read(fastingTimerControllerProvider.notifier)
          .extend();

      expect(ok, isTrue);
      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.fastingExtended);
      expect(state.cycle!.extendedMinutes, 30);
      expect(state.snapshot!.countdownSec, 4 * 3600 + 30 * 60);
      // 落盘：重启可还原
      expect(cycleStore.loadActiveCycle()!.extendedMinutes, 30);
      // reschedule：extensionApplied + 30min
      expect(scheduler.rescheduleCalls, hasLength(1));
      expect(
        scheduler.rescheduleCalls.single.reason,
        RescheduleReason.extensionApplied,
      );
      expect(scheduler.rescheduleCalls.single.extensionMinutes, 30);
      expect(scheduler.rescheduleCalls.single.plan, FastingPlan.plan16x8);
    });

    test('累计 4h 上限：第 9 次返回 false（按钮置 disabled，T7）', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      clock = FakeClock(bjtUtc(28, 0));
      final container = await buildContainer();
      final controller = container.read(
        fastingTimerControllerProvider.notifier,
      );

      for (var i = 0; i < 8; i++) {
        expect(controller.extend(), isTrue, reason: '第 ${i + 1} 次应成功');
      }
      expect(controller.extend(), isFalse);
      expect(
        container.read(fastingTimerControllerProvider).cycle!.extendedMinutes,
        240,
      );
    });

    test('重启恢复：持久化的延长周期在新容器中还原', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      clock = FakeClock(bjtUtc(28, 0));
      final container1 = await buildContainer();
      container1.read(fastingTimerControllerProvider.notifier).extend();
      container1.dispose();

      // 模拟杀进程重开：新容器 + 同一持久化存储。
      final container2 = await buildContainer();
      final state = container2.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.fastingExtended);
      expect(state.cycle!.extendedMinutes, 30);
    });
  });

  group('结束断食（D-08，T3/T4）', () {
    test('提前 ≤15min → COMPLETED_EARLY_PASS 达标，庆祝 + 重排', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      // 本地 11:46（UTC 03:46）：提前 14min。
      clock = FakeClock(bjtUtc(28, 3, 46));
      final container = await buildContainer();
      container.read(fastingTimerControllerProvider.notifier).endFast();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.eating);
      expect(state.celebrating, isTrue);
      expect(state.lastClosedRecord!.result, CycleResult.completedEarlyPass);
      expect(state.lastClosedRecord!.qualified, isTrue);
      expect(state.lastClosedRecord!.date, '2026-07-28');
      expect(cycleStore.loadActiveCycle(), isNull);
      expect(
        scheduler.rescheduleCalls.single.reason,
        RescheduleReason.manualEndFast,
      );
    });

    test('提前 >15min → BROKEN_EARLY 不达标，不庆祝', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      // 本地 11:44（UTC 03:44）：提前 16min。
      clock = FakeClock(bjtUtc(28, 3, 44));
      final container = await buildContainer();
      container.read(fastingTimerControllerProvider.notifier).endFast();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.lastClosedRecord!.result, CycleResult.brokenEarly);
      expect(state.lastClosedRecord!.qualified, isFalse);
      expect(state.celebrating, isFalse);
    });

    test('进食态调用 endFast 被防御性丢弃（T11）', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      clock = FakeClock(bjtUtc(28, 6)); // 进食中
      final container = await buildContainer();
      container.read(fastingTimerControllerProvider.notifier).endFast();

      expect(
        container.read(fastingTimerControllerProvider).state,
        FastingState.eating,
      );
      expect(scheduler.rescheduleCalls, isEmpty);
    });
  });

  group('tick（归零自动关闭 + 重启对账）', () {
    test('倒计时跨过零点 → COMPLETED_ON_TIME + 庆祝 + 重排 + 转进食态', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      // 本地 11:59:59（UTC 03:59:59）：下一秒归零。
      clock = FakeClock(bjtUtc(28, 3, 59, 59));
      final container = await buildContainer();
      // 先触发 build（03:59:59 落点 fasting），再拨钟到点。
      container.read(fastingTimerControllerProvider);
      clock.now = bjtUtc(28, 4); // 本地 12:00 到点
      container.read(fastingTimerControllerProvider.notifier).tick();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.eating);
      expect(state.celebrating, isTrue);
      expect(state.lastClosedRecord!.result, CycleResult.completedOnTime);
      expect(
        scheduler.rescheduleCalls.single.reason,
        RescheduleReason.stateTransition,
      );
    });

    test('tick 未到点：仅刷新倒计时，无副作用', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      clock = FakeClock(bjtUtc(28, 0));
      final container = await buildContainer();
      clock.now = bjtUtc(28, 0, 1);
      container.read(fastingTimerControllerProvider.notifier).tick();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.fasting);
      expect(state.snapshot!.countdownSec, 4 * 3600 - 60);
      expect(scheduler.rescheduleCalls, isEmpty);
    });

    test('重启对账：离线期间跨过窗口边界，持久化周期按 T2 补关闭', () async {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
      // 持久化周期：计划结束 = 本地 12:00（UTC 04:00）已过。
      cycleStore.saveActiveCycle(
        ActiveCycleSnapshot(
          startUtc: bjtUtc(27, 12),
          plannedEndUtc: bjtUtc(28, 4),
          eatWindowEndUtc: bjtUtc(28, 12),
          extendedMinutes: 0,
        ),
      );
      // 重开时刻：本地 13:00（UTC 05:00），离线跨过了 12:00。
      clock = FakeClock(bjtUtc(28, 5));
      final container = await buildContainer();

      final state = container.read(fastingTimerControllerProvider);
      expect(state.state, FastingState.eating);
      expect(state.celebrating, isTrue); // 达标周期补庆祝
      expect(state.lastClosedRecord!.result, CycleResult.completedOnTime);
      expect(state.lastClosedRecord!.date, '2026-07-28');
      expect(cycleStore.loadActiveCycle(), isNull);
    });
  });
}
