import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../fasting/presentation/fasting_presentation_test_helper.dart';
import '../fasting/tz_test_helper.dart';

class _Source implements ReportsDataSource {
  @override
  Future<List<DailyNutritionCache>> nutritionRange(
    String from,
    String to,
  ) async => [];
  @override
  Future<List<FastingRecord>> fastingRange(String from, String to) async => [];
  @override
  Future<List<FastingRecord>> fastingAll() async => [];
  @override
  Future<Map<String, double>> weightRange(String from, String to) async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late tz.Location location;
  late FakeClock clock;
  setUpAll(() async {
    await initTestTimeZones();
    location = tz.getLocation('Asia/Shanghai');
  });
  Future<ProviderContainer> setup({
    required int now,
    bool plan = true,
    bool staleStore = false,
  }) async {
    SharedPreferences prefs;
    if (plan) {
      prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    } else {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    }
    final store = InMemoryFastingCycleStore();
    if (staleStore) {
      store.saveActiveCycle(
        ActiveCycleSnapshot.fromCycle(
          FastCycle(
            startUtc: bjtUtc(27, 12),
            plannedEndUtc: bjtUtc(28, 4),
            eatWindowEndUtc: bjtUtc(28, 12),
          ),
        ),
      );
    }
    clock = FakeClock(now);
    final container = ProviderContainer(
      overrides: [
        reportsNowProvider.overrideWithValue(DateTime(2026, 7, 28)),
        reportsDataSourceProvider.overrideWithValue(_Source()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        fastingCycleStoreProvider.overrideWithValue(store),
        deviceLocationProvider.overrideWithValue(location),
        fastingClockProvider.overrideWithValue(clock.call),
        fastingStreakHookProvider.overrideWithValue((_) {}),
        fastingNotificationSchedulerProvider.overrideWithValue(
          RecordingFastingScheduler(
            service: FakeNotificationService(),
            locationResolver: () => location,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(fastingTimerControllerProvider);
    await container.read(reportFastingProvider.future);
    return container;
  }

  test('晚间启动归属明日的周期不得标成今天进行中', () async {
    final c = await setup(now: bjtUtc(28, 14));
    expect(c.read(fastingDayStatesProvider).last, FastingDayState.noRecord);
  });
  test('今日归属的真实周期显示进行中', () async {
    final c = await setup(now: bjtUtc(28, 0));
    expect(c.read(fastingDayStatesProvider).last, FastingDayState.inProgress);
  });
  test('计时器无方案时忽略存储残留', () async {
    final c = await setup(now: bjtUtc(28, 0), plan: false, staleStore: true);
    expect(c.read(fastingDayStatesProvider).last, FastingDayState.noRecord);
  });
  test('报告已打开后新周期状态变化立即更新，无需改记录表', () async {
    final c = await setup(now: bjtUtc(28, 0), plan: false);
    final subscription = c.listen(fastingDayStatesProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(c.read(fastingDayStatesProvider).last, FastingDayState.noRecord);
    c
        .read(onboardingStoreProvider)
        .saveActivePlan(
          ActivePlanSnapshot(
            plan: FastingPlan.plan16x8,
            initialState: 'fasting',
            startedAtUtc: bjtUtc(27, 12),
          ),
        );
    c.read(planVersionProvider.notifier).state++;
    c.read(fastingTimerControllerProvider);
    await c.pump();
    expect(c.read(fastingDayStatesProvider).last, FastingDayState.inProgress);
    c.read(fastingTimerControllerProvider.notifier).endFast();
    await c.pump();
    expect(c.read(fastingDayStatesProvider).last, FastingDayState.noRecord);
  });
}
