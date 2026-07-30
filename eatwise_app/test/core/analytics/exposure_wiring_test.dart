import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/fasting_record.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_cycle_store.dart';
import 'package:eatwise/features/fasting/presentation/fasting_home_page.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/nutrition/presentation/signal_cards.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/presentation/recommendation_screen.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:eatwise/features/social/presentation/post_card.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:visibility_detector/visibility_detector.dart';

import '../../features/fasting/presentation/fasting_presentation_test_helper.dart';
import '../../features/fasting/tz_test_helper.dart';

/// 录制型假通道：收集上报批次。
final class _RecordingClient implements AnalyticsClient {
  final List<AnalyticsEvent> sent = <AnalyticsEvent>[];

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    sent.addAll(batch);
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

void main() {
  late _RecordingClient client;
  late AnalyticsService service;

  setUpAll(() async {
    // 时区数据库加载走真实文件 IO，须在 FakeAsync 之外（setUpAll）完成。
    await initTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    client = _RecordingClient();
    service = AnalyticsService(
      consentStore: InMemoryConsentStore(analyticsGranted: true),
      queueStore: InMemoryEventQueueStore(),
      context: AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
      ),
      clients: <AnalyticsClient>[client],
    );
  });

  List<AnalyticsEvent> eventsNamed(String name) =>
      client.sent.where((e) => e.name == name).toList();

  Widget wrap(Widget home, {List<Override> overrides = const <Override>[]}) {
    return TranslationProvider(
      child: ProviderScope(
        overrides: <Override>[
          analyticsServiceProvider.overrideWithValue(service),
          ...overrides,
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
  }

  testWidgets('首页 mini signal-card：三卡逐一曝光（mini_signal_card_expose）', (
    tester,
  ) async {
    const signal = DailySignal(
      hasData: true,
      verdicts: <NutrientType, SignalVerdict>{
        NutrientType.protein: SignalVerdict(
          zone: SignalZone.green,
          subZone: SignalSubZone.green,
        ),
        NutrientType.carb: SignalVerdict(
          zone: SignalZone.yellow,
          subZone: SignalSubZone.yellowLow,
        ),
        NutrientType.kcal: SignalVerdict(
          zone: SignalZone.red,
          subZone: SignalSubZone.redHigh,
        ),
        NutrientType.fat: SignalVerdict(
          zone: SignalZone.green,
          subZone: SignalSubZone.green,
        ),
      },
      adviceKeys: <String>[],
      configVersion: '1',
    );
    await tester.pumpWidget(
      wrap(
        Scaffold(body: MiniSignalCards(onTap: () {})),
        overrides: <Override>[todaySignalsProvider.overrideWithValue(signal)],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await service.flush();

    final events = eventsNamed('mini_signal_card_expose');
    expect(events, hasLength(3));
    expect(
      events.map((e) => e.properties['nutrient']),
      containsAll(<Object?>['protein', 'carb', 'calorie']),
    );
    expect(
      events.map((e) => e.properties['signal_level']),
      containsAll(<Object?>['green', 'yellow', 'red']),
    );
  });

  testWidgets('数据页信号灯四卡：signal_card_expose 带建议模板键（建议并入）', (tester) async {
    const intake = DailyIntake(
      entryCount: 3,
      kcal: 2000,
      proteinG: 80,
      carbG: 100,
      fatG: 60,
    );
    const goal = NutritionGoal(
      bmr: null,
      tdee: null,
      targetKcal: 2000,
      proteinG: 100,
      carbG: 200,
      fatG: 60,
      usedFallback: false,
      configVersion: '1',
    );
    final signal = evaluateDailySignals(
      intake,
      goal,
      NutritionRuleConfig.defaults,
    );
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: SignalCardsGrid(
              intake: intake,
              signal: signal,
              goal: goal,
              mealSegment: MealSegment.dinner,
              exposureDateKey: '0',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await service.flush();

    final events = eventsNamed('signal_card_expose');
    expect(events, hasLength(4));
    expect(
      events.map((e) => e.properties['nutrient']),
      containsAll(<Object?>['protein', 'carb', 'fat', 'calorie']),
    );
    for (final event in events) {
      expect(
        event.properties['signal_level'],
        isIn(<String>['green', 'yellow', 'red']),
      );
      // 模板 key = 规则库 i18n key（nutrition.signalCard.advice.*）。
      expect(
        (event.properties['advice_template_id'] as String).startsWith(
          'nutrition.signalCard.advice.',
        ),
        isTrue,
      );
    }
  });

  testWidgets('社区打卡流卡片：community_post_expose（post_id 哈希去重）', (tester) async {
    final post = ServerPost(
      id: 'p-1',
      text: '今日打卡',
      imageUrls: const <String>[],
      streakDaysAtPost: 3,
      likeCount: 0,
      likedByMe: false,
      auditStatus: 'approved',
      isAuthor: false,
      authorNickname: '阿明',
      createdAtUtc: DateTime.utc(2026, 7, 28, 2),
    );
    Widget app() => wrap(
      Scaffold(
        body: ListView(
          children: <Widget>[PostCard(item: FeedItem(post: post))],
        ),
      ),
      overrides: <Override>[
        socialNowProvider.overrideWithValue(() => DateTime.utc(2026, 7, 28, 8)),
      ],
    );
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 重建同卡（重进列表）：同 postId 同 session 不重复计。
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await service.flush();

    final events = eventsNamed('community_post_expose');
    expect(events, hasLength(1));
    expect(
      events.single.properties['post_id_hash'],
      anonymizedContentId('p-1'),
    );
    expect(events.single.properties['is_own_post'], false);
    expect(events.single.properties['has_image'], false);
  });

  testWidgets('方案推荐页：主卡 onboard_plan_recommend_expose + 备选卡曝光', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (c, s) => const RecommendationScreen()),
      ],
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            analyticsServiceProvider.overrideWithValue(service),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 兜底推荐 16:8（主）+ 14:10（备选）；备选卡确保进入视口。
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await service.flush();

    final recommend = eventsNamed('onboard_plan_recommend_expose');
    expect(recommend, hasLength(1));
    expect(recommend.single.properties['main_plan'], '16_8');
    expect(recommend.single.properties['alt_plan'], '14_10');

    final altCards = eventsNamed('onboard_plan_card_expose');
    expect(altCards, hasLength(1));
    expect(altCards.single.properties['plan_id'], '14_10');
    expect(altCards.single.properties['slot'], 'alt');
  });

  testWidgets('首页里程碑徽章：badge_reach 展示时曝光（milestone/streak_days）', (
    tester,
  ) async {
    final bjt = tz.getLocation('Asia/Shanghai');
    final prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    final clock = FakeClock(bjtUtc(28, 0));
    // 预置 6 天连胜（07-22 ~ 07-27）；第 7 天经真实 onFastClosed 达标，
    // 解锁里程碑 7 → 徽章滑入 → 组件级曝光上报 badge_reach。
    final engine = StreakEngine();
    for (var d = 22; d <= 27; d++) {
      engine.applyDayAchieved('2026-07-$d', today: '2026-07-28');
    }
    final streakStore = InMemoryStreakLocalStore()..saveEngine(engine);
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (c, s) => const FastingHomePage()),
      ],
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            analyticsServiceProvider.overrideWithValue(service),
            sharedPreferencesProvider.overrideWithValue(prefs),
            fastingCycleStoreProvider.overrideWithValue(
              InMemoryFastingCycleStore(),
            ),
            fastingNotificationSchedulerProvider.overrideWithValue(
              RecordingFastingScheduler(
                service: FakeNotificationService(),
                locationResolver: () => bjt,
              ),
            ),
            fastingClockProvider.overrideWithValue(clock.call),
            deviceLocationProvider.overrideWithValue(bjt),
            streakLocalStoreProvider.overrideWithValue(streakStore),
            streakTodayProvider.overrideWithValue(() => '2026-07-28'),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();

    // 第 7 天达标 → justUnlockedMilestone=7 → 徽章滑入。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FastingHomePage)),
      listen: false,
    );
    await container
        .read(streakControllerProvider.notifier)
        .onFastClosed(
          FastingRecord(
            date: '2026-07-28',
            startUtc: bjtUtc(27, 12),
            endUtc: bjtUtc(28, 4),
            actualSec: 16 * 3600,
            plannedSec: 16 * 3600,
            extendedMinutes: 0,
            result: CycleResult.completedOnTime,
            qualified: true,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await service.flush();

    final events = eventsNamed('badge_reach');
    expect(events, hasLength(1));
    expect(events.single.properties['milestone'], 7);
    expect(events.single.properties['streak_days'], 7);

    // 卸载页面：取消每秒 tick 的周期 Timer，避免收尾判定 Timer 未决。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
