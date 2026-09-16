import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/fasting/presentation/fasting_home_page.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:visibility_detector/visibility_detector.dart';

import '../tz_test_helper.dart';
import 'fasting_presentation_test_helper.dart';

/// 断食计时主页 widget 测试：断食/进食两态渲染、倒计时 tick、归属日文案、
/// 结束断食/延长动作链路、无方案 CTA、mini signal-card 空态与三态、
/// reduced-motion 降级、双语切换。
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

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    // 组件级曝光埋点（ExposureTracker）：即时分发可视回调，避免插件默认
    // 500ms 聚合 Timer 在卸载时未决。
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    clock = FakeClock(bjtUtc(28, 0)); // 本地 08:00，断食中，剩 4h
    cycleStore = InMemoryFastingCycleStore();
    scheduler = RecordingFastingScheduler(
      service: FakeNotificationService(),
      locationResolver: () => bjt,
    );
    todayCache = null;
  });

  GoRouter buildRouter() {
    return GoRouter(
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
        GoRoute(
          path: '/onboarding',
          builder: (c, s) => const Scaffold(body: Text('ONBOARDING_STUB')),
        ),
      ],
    );
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Widget app = TranslationProvider(
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
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildRouter(),
        ),
      ),
    );
    if (reduceMotion) {
      app = MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: app,
      );
    }
    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 卸载页面：取消每秒 tick 的周期 Timer，避免收尾判定 Timer 未决。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('断食中：绿弧环 + 倒计时 + 状态文案 + 归属日 + 双按钮可用', (tester) async {
    await pumpHome(tester);

    expect(find.text('04:00:00'), findsOneWidget);
    expect(find.text('断食中'), findsOneWidget);
    expect(find.text('本次断食计入 7月28日'), findsOneWidget);
    expect(find.text('16:8 · 进食窗口 12:00–20:00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '结束断食'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '延长'))
          .onPressed,
      isNotNull,
    );
    // 空态信号卡（今日无记录，不出现误导性信号灯）
    expect(find.text('今天还没记录，记一笔后信号灯会亮起来'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('进食中：状态文案切换，双按钮置灰（T11）', (tester) async {
    clock.now = bjtUtc(28, 6); // 本地 14:00，进食中
    await pumpHome(tester);

    expect(find.text('06:00:00'), findsOneWidget);
    expect(find.text('进食窗口中'), findsOneWidget);
    // 进食态无进行中断食：归属日文案用将来时（走查 B-9）。
    expect(find.text('下一段断食将计入 7月29日'), findsOneWidget);
    expect(find.textContaining('本次断食计入'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '结束断食'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '延长'))
          .onPressed,
      isNull,
    );

    await unmount(tester);
  });

  testWidgets('每秒 tick：倒计时逐秒刷新', (tester) async {
    clock.now = bjtUtc(28, 3, 59, 58); // 本地 11:59:58，剩 2s
    await pumpHome(tester);
    expect(find.text('00:00:02'), findsOneWidget);

    clock.now = bjtUtc(28, 3, 59, 59);
    await tester.pump(const Duration(seconds: 1)); // 触发 ticker
    expect(find.text('00:00:01'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('结束断食：调领域逻辑 + 触发 reschedule + 破壳庆祝（达标）', (tester) async {
    clock.now = bjtUtc(28, 3, 46); // 提前 14min，容差内达标
    await pumpHome(tester);

    await tester.tap(find.text('结束断食'));
    await tester.pump();
    // 两步确认弹窗（P3）：确认后才执行结束逻辑
    await tester.tap(find.text('确认结束'));
    await tester.pump();
    // 破壳庆祝：文案切「断食完成！…」
    expect(find.text('断食完成！身体悄悄做了次大扫除 ✨'), findsOneWidget);
    expect(
      scheduler.rescheduleCalls.last.reason,
      RescheduleReason.manualEndFast,
    );

    // 动画播完自动收尾 → 进食态
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('断食完成！身体悄悄做了次大扫除 ✨'), findsNothing);
    expect(find.text('进食窗口中'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('延长：+30min 徽标 + reschedule(extensionApplied)；4h 上限置灰', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.text('延长'));
    await tester.pump();
    expect(find.text('已延长 +30 分钟'), findsOneWidget);
    expect(find.text('断食中 · 已延长'), findsOneWidget);
    expect(
      scheduler.rescheduleCalls.last.reason,
      RescheduleReason.extensionApplied,
    );
    expect(scheduler.rescheduleCalls.last.extensionMinutes, 30);

    await unmount(tester);

    // 已达 4h 上限的持久化周期：按钮 disabled + 提示（T7）
    cycleStore.saveActiveCycle(
      ActiveCycleSnapshot(
        startUtc: bjtUtc(27, 12),
        plannedEndUtc: bjtUtc(28, 8),
        eatWindowEndUtc: bjtUtc(28, 16),
        extendedMinutes: 240,
      ),
    );
    await pumpHome(tester);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '延长'))
          .onPressed,
      isNull,
    );
    expect(find.text('单次最多延长 4 小时'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('无方案态：引导 CTA 卡跳 /onboarding', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    await pumpHome(tester);

    expect(find.text('还未开始断食方案'), findsOneWidget);
    await tester.tap(find.text('选择你的断食方案'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ONBOARDING_STUB'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('mini signal-card 三态：色+图标+文字三重编码', (tester) async {
    // 目标：热量 2000 / 蛋白 100 / 碳水 200 / 脂肪 60（seedActivePlanPrefs）
    // 摄入：热量 2000（100% 绿）/ 蛋白 80（80% 黄）/ 碳水 100（50% 红）
    todayCache = const DailyNutritionCache(
      userId: 'u',
      date: '2026-07-28',
      entryCount: 3,
      kcal: 2000,
      proteinG: 80,
      carbG: 100,
      fatG: 60,
      isLocalEstimate: true,
      updatedAtUtc: '2026-07-28T00:00:00Z',
    );
    await pumpHome(tester);

    expect(find.text('达标'), findsOneWidget); // 绿：热量
    expect(find.text('适量提醒'), findsOneWidget); // 黄：蛋白质
    expect(find.text('警示'), findsOneWidget); // 红：碳水
    expect(find.text('蛋白质'), findsOneWidget);
    expect(find.text('碳水'), findsOneWidget);
    expect(find.text('热量'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('reduced-motion：庆祝降级为静态徽章淡入，点按关闭', (tester) async {
    clock.now = bjtUtc(28, 3, 46);
    await pumpHome(tester, reduceMotion: true);

    await tester.tap(find.text('结束断食'));
    await tester.pump();
    await tester.tap(find.text('确认结束'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 淡入完成
    expect(find.text('断食完成 ✨'), findsOneWidget);
    // 无迸发动画文案（完整动效路径的标题不出现）
    expect(find.text('断食完成！身体悄悄做了次大扫除 ✨'), findsNothing);

    await tester.tap(find.text('断食完成 ✨'));
    await tester.pump();
    expect(find.text('断食完成 ✨'), findsNothing);
    expect(find.text('进食窗口中'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('双语切换：英文界面渲染（D-15）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpHome(tester);

    expect(find.text('Fasting'), findsOneWidget);
    expect(find.text('End fast'), findsOneWidget);
    expect(find.text('Extend'), findsOneWidget);
    expect(find.text('This fast counts toward Jul 28'), findsOneWidget);
    expect(find.text('16:8 · Eating window 12:00–20:00'), findsOneWidget);

    await unmount(tester);
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  testWidgets('FAB 跳记录（/record）', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('RECORD_STUB'), findsOneWidget);

    await unmount(tester);
  });
}
