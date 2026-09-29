import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/fasting/presentation/fasting_home_page.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/fasting/presentation/plan_progress_bar.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/data/health_gateway.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:visibility_detector/visibility_detector.dart';

import '../tz_test_helper.dart';
import 'fasting_presentation_test_helper.dart';

/// 薄荷走查 P0 widget 测试：首页「今日预算」行（无记录/正常/超支/带运动）
/// 与「方案进度」条（未设目标不渲染/正常/未记录体重）。
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
  DailyNutritionCache? todayCache;
  HealthSyncController? healthController;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    clock = FakeClock(bjtUtc(28, 0)); // 本地 08:00，断食中
    cycleStore = InMemoryFastingCycleStore();
    scheduler = RecordingFastingScheduler(
      service: FakeNotificationService(),
      locationResolver: () => bjt,
    );
    todayCache = null;
    healthController = null;
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (c, s) => const FastingHomePage()),
        GoRoute(
          path: '/record',
          builder: (c, s) => const Scaffold(body: Text('RECORD_STUB')),
        ),
        GoRoute(
          path: '/data',
          builder: (c, s) => const Scaffold(body: Text('DATA_STUB')),
        ),
      ],
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            fastingCycleStoreProvider.overrideWithValue(cycleStore),
            fastingNotificationSchedulerProvider.overrideWithValue(scheduler),
            fastingClockProvider.overrideWithValue(clock.call),
            deviceLocationProvider.overrideWithValue(bjt),
            todayNutritionCacheProvider.overrideWith(
              (ref) => Stream<DailyNutritionCache?>.value(todayCache),
            ),
            if (healthController != null)
              healthSyncControllerProvider.overrideWith(
                (ref) => healthController!,
              ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  DailyNutritionCache cacheWithKcal(double kcal) {
    return DailyNutritionCache(
      userId: 'anonymous',
      date: '2026-07-28',
      entryCount: 2,
      kcal: kcal,
      proteinG: 50,
      carbG: 100,
      fatG: 30,
      isLocalEstimate: true,
      updatedAtUtc: '2026-07-28T00:00:00Z',
    );
  }

  group('今日指标网格（UI 重构：原预算行升级为四张 MetricCard）', () {
    testWidgets('无记录：引导态说明行「今日还未记录 · 目标 2000 千卡」', (tester) async {
      await pumpHome(tester);

      expect(find.text('今日还未记录 · 目标 2000 千卡'), findsOneWidget);
      expect(find.textContaining('还可吃'), findsNothing);
      // 四卡标签齐备（华为看板 2 列网格）。
      expect(find.text('今日热量'), findsOneWidget);
      expect(find.text('运动消耗'), findsOneWidget);
      expect(find.text('今日饮水'), findsOneWidget);
      expect(find.text('今日步数'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('正常：热量卡大数字 800 + 说明行「还可吃 1200 千卡」', (tester) async {
      todayCache = cacheWithKcal(800);
      await pumpHome(tester);

      expect(find.text('800'), findsOneWidget);
      expect(find.text('还可吃 1200 千卡'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('超支：说明行「已超 300 千卡」（目标 2000）', (tester) async {
      todayCache = cacheWithKcal(2300);
      await pumpHome(tester);

      expect(find.text('2300'), findsOneWidget);
      expect(find.text('已超 300 千卡'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('带运动：运动消耗卡展示合并值 250 + 合计说明', (tester) async {
      todayCache = cacheWithKcal(800);
      healthController = await readyHealthController(
        steps: 8000,
        activeEnergyKcal: 250,
      );
      await pumpHome(tester);

      expect(find.text('250'), findsOneWidget);
      expect(find.text('系统活动 + 手动运动合计'), findsOneWidget);
      // 步数卡：系统步数 8000 + 目标进度行（默认目标 5000 步）。
      expect(find.text('8000'), findsOneWidget);
      expect(find.textContaining('/ 5000 步'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('窄屏：四卡渲染不溢出、说明行完整不截断', (tester) async {
      // 280 逻辑宽（目标兜底 2000）：MetricCard 大数字 FittedBox 收缩、
      // 说明行 maxLines=2，必须完整呈现（真机「运…」走查同类回归）。
      tester.view.physicalSize = const Size(280 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      todayCache = cacheWithKcal(1916);
      healthController = await readyHealthController(
        steps: 8000,
        activeEnergyKcal: 250,
      );
      await pumpHome(tester);

      expect(find.text('1916'), findsOneWidget);
      expect(find.text('还可吃 84 千卡'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('方案进度条', () {
    // 指标网格的 MetricCard 也渲染 LinearProgressIndicator——进度条断言
    // 必须锚定 PlanProgressBar 子树（UI 重构后全树按类型查找会误中）。
    Finder planLpi() => find.descendant(
      of: find.byType(PlanProgressBar),
      matching: find.byType(LinearProgressIndicator),
    );

    testWidgets('未设目标：不渲染（保持首页简洁）', (tester) async {
      await pumpHome(tester);

      expect(find.textContaining('已减'), findsNothing);
      expect(planLpi(), findsNothing); // 组件在树但空渲染（目标未设）

      await unmount(tester);
    });

    testWidgets('正常：第 1 周 · 已减 4.0 kg / 目标 10.0 kg（80→76，目标 70）', (
      tester,
    ) async {
      SharedPreferencesOnboardingStore(
        prefs,
      ).saveProfile(const OnboardingProfile(weightKg: 80, targetWeightKg: 70));
      await WeightLogStore(prefs).save('2026-07-28', 76);
      await pumpHome(tester);

      expect(find.text('第 1 周 · 已减 4.0 kg / 目标 10.0 kg'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(planLpi());
      expect(indicator.value, moreOrLessEquals(0.4, epsilon: 1e-6));

      await unmount(tester);
    });

    testWidgets('未记录体重：已减 0.0 kg（按档案体重计）', (tester) async {
      SharedPreferencesOnboardingStore(
        prefs,
      ).saveProfile(const OnboardingProfile(weightKg: 80, targetWeightKg: 70));
      await pumpHome(tester);

      expect(find.text('第 1 周 · 已减 0.0 kg / 目标 10.0 kg'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(planLpi());
      expect(indicator.value, 0.0);

      await unmount(tester);
    });

    testWidgets('涨称负向：距目标还差 11.0 kg，进度条归零', (tester) async {
      SharedPreferencesOnboardingStore(
        prefs,
      ).saveProfile(const OnboardingProfile(weightKg: 80, targetWeightKg: 70));
      await WeightLogStore(prefs).save('2026-07-28', 81);
      await pumpHome(tester);

      expect(find.text('第 1 周 · 距目标还差 11.0 kg'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(planLpi());
      expect(indicator.value, 0.0);

      await unmount(tester);
    });
  });
}

/// 测试健康网关（不触平台通道；固定返回注入的今日数据）。
final class _StubHealthGateway implements HealthGateway {
  _StubHealthGateway({this.steps, this.activeEnergyKcal});

  final int? steps;
  final double? activeEnergyKcal;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasAuthorization() async => true;

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<void> revokeAuthorization() async {}

  @override
  Future<int?> getTodaySteps(DateTime now) async => steps;

  @override
  Future<double?> getTodayActiveEnergyKcal(DateTime now) async =>
      activeEnergyKcal;

  @override
  Future<double?> getLatestWeightKg(DateTime now) async => null;
}

/// 经 enable() 真实链路走到 ready 态的控制器（stub 网关返回固定快照）。
Future<HealthSyncController> readyHealthController({
  int? steps,
  double? activeEnergyKcal,
}) async {
  final controller = HealthSyncController(
    gateway: _StubHealthGateway(
      steps: steps,
      activeEnergyKcal: activeEnergyKcal,
    ),
    consentStore: InMemoryExerciseSyncConsentStore(),
  );
  await controller.enable();
  return controller;
}
