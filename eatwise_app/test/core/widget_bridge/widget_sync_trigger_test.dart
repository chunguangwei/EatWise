import 'package:eatwise/core/widget_bridge/widget_sync_service.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/fasting/presentation/fasting_presentation_test_helper.dart';
import '../../features/fasting/tz_test_helper.dart';
import 'widget_sync_service_test.dart';

/// 小组件刷新触发链测试（《规格-M2》§8：与通知 reschedule 同一触发链）。
///
/// 经 ProviderContainer 覆写 home_widget 网关为替身，验证「启动/延长/
/// 手动结束/到点迁移」均触发共享容器写入与 updateWidget。
void main() {
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  late FakeClock clock;
  late InMemoryFastingCycleStore cycleStore;
  late FakeHomeWidgetGateway gateway;
  late SharedPreferences prefs;

  Future<ProviderContainer> buildContainer() async {
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        fastingCycleStoreProvider.overrideWithValue(cycleStore),
        fastingNotificationSchedulerProvider.overrideWithValue(
          RecordingFastingScheduler(
            service: FakeNotificationService(),
            locationResolver: () => bjt,
          ),
        ),
        fastingClockProvider.overrideWithValue(clock.call),
        deviceLocationProvider.overrideWithValue(bjt),
        homeWidgetGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 等 unawaited 的 sync 微任务落地。
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    cycleStore = InMemoryFastingCycleStore();
    gateway = FakeHomeWidgetGateway();
  });

  test('启动（build）：写入状态 + 锚点 UTC 毫秒并触发 updateWidget', () async {
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    clock = FakeClock(bjtUtc(28, 0));
    final container = await buildContainer();

    container.read(fastingTimerControllerProvider);
    await flush();

    expect(gateway.saved[WidgetDataKeys.state], 'fasting');
    expect(
      gateway.saved[WidgetDataKeys.targetAnchorUtcMs],
      bjtUtc(28, 4) * 1000,
    );
    expect(gateway.updateCalls, 1);
  });

  test('延长：锚点后移 30min 并再次刷新小组件', () async {
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    clock = FakeClock(bjtUtc(28, 0));
    final container = await buildContainer();
    container.read(fastingTimerControllerProvider);
    await flush();

    container.read(fastingTimerControllerProvider.notifier).extend();
    await flush();

    expect(gateway.saved[WidgetDataKeys.state], 'fastingExtended');
    expect(
      gateway.saved[WidgetDataKeys.targetAnchorUtcMs],
      (bjtUtc(28, 4) + 30 * 60) * 1000,
    );
    expect(gateway.saved[WidgetDataKeys.extendedMinutes], 30);
    expect(gateway.updateCalls, 2);
  });

  test('手动结束断食：状态转 eating、锚点切到进食窗口结束', () async {
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    clock = FakeClock(bjtUtc(28, 0));
    final container = await buildContainer();
    container.read(fastingTimerControllerProvider);
    await flush();

    container.read(fastingTimerControllerProvider.notifier).endFast();
    await flush();

    expect(gateway.saved[WidgetDataKeys.state], 'eating');
    // 进食终点 = 破窗时刻(08:00 本地) + 计划进食窗长 8h = 16:00 本地
    // （封顶本周期窗末 20:00；C3 修复后规则）。
    expect(
      gateway.saved[WidgetDataKeys.targetAnchorUtcMs],
      bjtUtc(28, 8) * 1000,
    );
    expect(gateway.updateCalls, 2);
  });

  test('tick 到点迁移：fasting → eating，小组件随迁移刷新', () async {
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    clock = FakeClock(bjtUtc(28, 0));
    final container = await buildContainer();
    container.read(fastingTimerControllerProvider);
    await flush();

    // 拨到进食窗口到点（本地 12:00 = UTC 04:00）。
    clock.now = bjtUtc(28, 4);
    container.read(fastingTimerControllerProvider.notifier).tick();
    await flush();

    expect(gateway.saved[WidgetDataKeys.state], 'eating');
    expect(
      gateway.saved[WidgetDataKeys.targetAnchorUtcMs],
      bjtUtc(28, 12) * 1000,
    );
    expect(gateway.updateCalls, 2);
  });
}
