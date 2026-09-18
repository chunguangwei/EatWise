import 'dart:convert';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:visibility_detector/visibility_detector.dart';

import '../fasting/presentation/fasting_presentation_test_helper.dart';
import '../fasting/tz_test_helper.dart';

/// M1 新手引导全流程 widget 测试：
/// 问卷全路径 / 跳过兜底 / 续答 / 一键启动跳转 / 双语切换。
void main() {
  // 固定时钟：2026-07-28 15:00（Asia/Shanghai）= 07:00 UTC。
  final fixedNowUtc =
      DateTime.utc(2026, 7, 28, 7).millisecondsSinceEpoch ~/ 1000;
  late tz.Location shanghai;

  setUpAll(() async {
    await initTestTimeZones();
    shanghai = tz.getLocation('Asia/Shanghai');
  });

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.zhCn);
    // 组件级曝光埋点（ExposureTracker）：即时分发可视回调，避免插件默认
    // 500ms 聚合 Timer 在卸载时未决。
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  /// 以 [completed] 门禁状态启动 App；返回门禁与存储便于断言。
  Future<({OnboardingGate gate, OnboardingStore store})> pumpApp(
    WidgetTester tester, {
    required bool completed,
    Map<String, Object> initialPrefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesOnboardingStore(prefs);
    final gate = OnboardingGate(completed: completed);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            onboardingGateProvider.overrideWithValue(gate),
            deviceLocationProvider.overrideWithValue(shanghai),
            nowUtcProvider.overrideWithValue(fixedNowUtc),
            // 计时主控固定时钟（换方案测试断言 pendingPlan 不被即时转正）；
            // 通知服务替身（build 回前台对账补排走插件会抛 MissingPlugin）。
            fastingClockProvider.overrideWithValue(() => fixedNowUtc),
            localNotificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
          ],
          child: EatWiseApp(gate: gate),
        ),
      ),
    );
    // 注：不用 pumpAndSettle——go_router/slang 存在持续帧调度，settle 不收敛。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return (gate: gate, store: store);
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> answerAndNext(WidgetTester tester, String optionName) async {
    await tester.tap(
      find.byKey(ValueKey<String>('onboarding.quiz.option.$optionName')),
    );
    await pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.next')),
    );
    await pumpFrames(tester);
  }

  /// 阶段 A：3 题后先进档案采集页；本组用例不采集，直接整页跳过
  /// （维持兜底行为；Q1=减脂时跳过档案会先落减重目标页，由用例自行再跳过）。
  Future<void> skipProfile(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.profile.skip')),
    );
    await pumpFrames(tester);
  }

  testWidgets('首进重定向到问卷；完成 3 题 → 推荐 → 一键启动 → 首页', (tester) async {
    final (:gate, :store) = await pumpApp(tester, completed: false);

    // 首进重定向 /onboarding，展示 Q1
    expect(find.text('你的小目标是？'), findsOneWidget);
    expect(find.text('第 1 题，共 3 题'), findsOneWidget);

    await answerAndNext(tester, 'loseWeight');
    expect(find.text('你现在的作息是？'), findsOneWidget);

    await answerAndNext(tester, 'regular');
    expect(find.text('之前试过轻断食吗？'), findsOneWidget);

    await answerAndNext(tester, 'beginner');

    // 阶段 A：3 题后先进档案采集页，跳过 → 目标页（Q1=减脂必经，
    // 目标页再跳过）→ 推荐页（兜底行为不变）
    expect(find.text('了解你的身体，目标更精准'), findsOneWidget);
    await skipProfile(tester);
    expect(find.text('定个减重小目标'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.goal.skip')),
    );
    await pumpFrames(tester);

    // 推荐页：主方案卡（14:10）+ 备选卡（16:8）+ 推荐理由
    expect(find.text('为你推荐的方案'), findsOneWidget);
    expect(find.text('主推荐'), findsOneWidget);
    expect(find.text('14:10 温和入门'), findsOneWidget);
    expect(find.text('进食窗口 10:00–20:00'), findsOneWidget);
    expect(find.text('零基础起步，14:10 最温和，先让身体慢慢习惯节奏。'), findsOneWidget);
    expect(find.text('16:8 经典节奏'), findsOneWidget);

    // 一键启动 → 写入方案 + 营养目标兜底 + 跳转首页占位
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);

    expect(gate.completed, isTrue);
    expect(store.isOnboardingCompleted, isTrue);
    expect(find.text('断食计时'), findsOneWidget); // 首页占位（M0 演示页）
    // 兜底提示（D-04：缺基础信息 → 2000 kcal 兜底并提示补全）
    expect(find.textContaining('2000 kcal'), findsOneWidget);

    final plan = store.loadActivePlan()!;
    expect(plan.plan.id, '14:10');
    expect(plan.plan.eatStartMinutes, 600);
    expect(plan.startedAtUtc, fixedNowUtc);
    expect(plan.initialState, isNotEmpty);
    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isTrue);
    expect(goal.targetKcal, 2000);
    // 完成后续答进度已清除
    expect(store.loadQuizProgress(), isNull);
  });

  testWidgets('跳过问卷 → 默认 16:8 兜底，不阻断进首页', (tester) async {
    final (:gate, :store) = await pumpApp(tester, completed: false);

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.skip')),
    );
    await pumpFrames(tester);

    // 兜底推荐：16:8 主卡 + 兜底理由
    expect(find.text('16:8 经典节奏'), findsOneWidget);
    expect(find.text('进食窗口 12:00–20:00'), findsOneWidget);
    expect(find.text('先按人气最高的 16:8 开始，随时可以在「我的」里调整。'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);

    expect(gate.completed, isTrue);
    expect(store.loadActivePlan()!.plan.id, '16:8');
    expect(find.text('断食计时'), findsOneWidget);
  });

  testWidgets('问卷中途退出 → 进度本地保存，下次进入续答', (tester) async {
    final (:gate, :store) = await pumpApp(
      tester,
      completed: false,
      initialPrefs: <String, Object>{
        'onboarding.quizProgress': jsonEncode(<String, dynamic>{
          'answers': <String, String>{'q1': 'loseWeight'},
          'currentStep': 1,
        }),
      },
    );
    expect(gate.completed, isFalse);

    // 直接从 Q2 续答
    expect(find.text('你现在的作息是？'), findsOneWidget);
    expect(find.text('第 2 题，共 3 题'), findsOneWidget);

    // 上一题的答案仍在（返回 Q1 可见已选）
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.back')),
    );
    await pumpFrames(tester);
    expect(find.text('你的小目标是？'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(store.loadQuizProgress()!.answers['q1'], 'loseWeight');
  });

  testWidgets('备选卡可升为主推荐；5:2 仅说明不可选', (tester) async {
    await pumpApp(tester, completed: false);

    // 改善体检指标 + 有经验 → 18:6 主推荐，5:2 备选（D-03 附加规则）
    await answerAndNext(tester, 'improveHealth');
    await answerAndNext(tester, 'regular');
    await answerAndNext(tester, 'experienced');
    await skipProfile(tester);

    expect(find.text('18:6 进阶挑战'), findsOneWidget);
    expect(find.text('想改善体检指标又有经验，18:6 更适合你，记得循序渐进哦。'), findsOneWidget);
    expect(find.text('5:2 轻断食'), findsOneWidget);
    expect(find.text('后续版本提供'), findsOneWidget);
    // 5:2 无「选这个」按钮
    expect(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.select.5:2'),
      ),
      findsNothing,
    );
  });

  testWidgets('备选方案一键升级为主推荐', (tester) async {
    await pumpApp(tester, completed: false);
    await answerAndNext(tester, 'justTrying');
    await answerAndNext(tester, 'shiftWork'); // 轮班 → 窗口可自由调整提示
    await answerAndNext(tester, 'beginner');
    await skipProfile(tester);

    expect(find.text('14:10 温和入门'), findsOneWidget);
    expect(find.text('你的作息不太固定，进食窗口可以随时自由调整，跟着生活节奏走就好。'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.select.16:8'),
      ),
    );
    await pumpFrames(tester);

    // 主卡换成 16:8，备选换成 14:10
    expect(find.text('16:8 经典节奏'), findsOneWidget);
    expect(find.text('14:10 温和入门'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.select.14:10'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('原理科普卡占位页含「非医疗建议」免责文案', (tester) async {
    await pumpApp(tester, completed: false);
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.skip')),
    );
    await pumpFrames(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.science')),
    );
    await pumpFrames(tester);

    expect(find.text('断食原理小科普'), findsOneWidget);
    expect(find.textContaining('非医疗建议'), findsOneWidget);
  });

  testWidgets('双语切换：中英文案即时生效（D-15）', (tester) async {
    await pumpApp(tester, completed: false);
    expect(find.text('你的小目标是？'), findsOneWidget);

    LocaleSettings.setLocaleSync(AppLocale.en);
    await pumpFrames(tester);
    expect(find.text("What's your goal?"), findsOneWidget);
    expect(find.text('Question 1 of 3'), findsOneWidget);

    // 英文路径走跳过 → 英文兜底推荐
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.skip')),
    );
    await pumpFrames(tester);
    expect(find.text('16:8 Classic Rhythm'), findsOneWidget);
    expect(find.text('Eating window 12:00–20:00'), findsOneWidget);
    expect(
      find.text(
        "Let's start with the crowd favorite 16:8 — you can adjust it anytime in Profile.",
      ),
      findsOneWidget,
    );

    // 切回中文
    LocaleSettings.setLocaleSync(AppLocale.zhCn);
    await pumpFrames(tester);
    expect(find.text('16:8 经典节奏'), findsOneWidget);
  });

  testWidgets('已完成引导 → 直达首页，不再进问卷', (tester) async {
    await pumpApp(tester, completed: true);
    expect(find.text('断食计时'), findsOneWidget);
    expect(find.text('你的小目标是？'), findsNothing);
  });

  testWidgets('换方案（D-06/T12）：一键启动先弹「次日 0:00 生效」确认；'
      '取消不登记，确认后登记 pendingPlan 且当日方案不动', (tester) async {
    // 预置生效方案 14:10；兜底推荐 16:8 与之不同 → 构成换方案。
    final (:gate, :store) = await pumpApp(
      tester,
      completed: false,
      initialPrefs: <String, Object>{
        'onboarding.activePlan': jsonEncode(<String, dynamic>{
          'planId': '14:10',
          'eatStartMinutes': 600,
          'eatEndMinutes': 1200,
          'initialState': 'fasting',
          'targetUtc': null,
          'attributionDate': null,
          'startedAtUtc': fixedNowUtc - 86400,
        }),
      },
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.skip')),
    );
    await pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);

    // T12 确认弹窗：明示次日 0:00 生效（fixedNow = 07-28 → 生效日 07-29）
    expect(find.text('更换断食方案'), findsOneWidget);
    expect(find.text('新方案将于 2026-07-29 00:00 生效，今天仍按当前方案计时。'), findsOneWidget);
    expect(store.loadPendingPlan(), isNull); // 确认前不写入

    // 取消：不登记，停留推荐页
    await tester.tap(find.text('取消'));
    await pumpFrames(tester);
    expect(store.loadPendingPlan(), isNull);
    expect(find.text('为你推荐的方案'), findsOneWidget);

    // 再次启动并确认：登记 pendingPlan，当日方案不动
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    await tester.tap(find.text('确定'));
    await pumpFrames(tester);

    expect(gate.completed, isTrue);
    expect(store.loadActivePlan()!.plan.id, '14:10'); // 当日方案不动
    final pending = store.loadPendingPlan()!;
    expect(pending.plan.id, '16:8');
    expect(pending.effectiveDate.toIsoString(), '2026-07-29');
  });

  testWidgets('D-06 换方案入口闭环（R3 回归）：已完成引导用户从设置页'
      '「断食方案」直达推荐页，弹窗确认后登记 pendingPlan', (tester) async {
    // 已完成引导 + 生效方案 14:10：/onboarding 前缀会被 redirect 弹回首页，
    // 入口走 /settings/fasting-plan。
    final (:gate, :store) = await pumpApp(
      tester,
      completed: true,
      initialPrefs: <String, Object>{
        'onboarding.activePlan': jsonEncode(<String, dynamic>{
          'planId': '14:10',
          'eatStartMinutes': 600,
          'eatEndMinutes': 1200,
          'initialState': 'fasting',
          'targetUtc': null,
          'attributionDate': null,
          'startedAtUtc': fixedNowUtc - 86400,
        }),
      },
    );
    expect(find.text('断食计时'), findsOneWidget);

    // 我的 Tab → 设置页「断食方案」入口（偏好组，视口外先滚动）。
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      find.text('断食方案'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(find.text('断食方案'));
    await pumpFrames(tester);

    // 直达推荐页（未被 redirect 弹回）；兜底推荐 16:8 ≠ 生效 14:10 → 换方案。
    expect(find.text('为你推荐的方案'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    // T12 确认弹窗：次日 0:00 生效（fixedNow = 07-28 → 生效日 07-29）。
    expect(find.text('更换断食方案'), findsOneWidget);
    expect(find.text('新方案将于 2026-07-29 00:00 生效，今天仍按当前方案计时。'), findsOneWidget);
    expect(store.loadPendingPlan(), isNull); // 确认前不写入

    await tester.tap(find.text('确定'));
    await pumpFrames(tester);

    expect(gate.completed, isTrue);
    expect(store.loadActivePlan()!.plan.id, '14:10'); // 当日方案不动
    final pending = store.loadPendingPlan()!;
    expect(pending.plan.id, '16:8');
    expect(pending.effectiveDate.toIsoString(), '2026-07-29');
    expect(find.text('断食计时'), findsOneWidget); // 确认后回首页
  });
}
