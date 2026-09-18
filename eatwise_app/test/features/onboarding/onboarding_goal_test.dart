import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:visibility_detector/visibility_detector.dart';

import '../fasting/presentation/fasting_presentation_test_helper.dart';
import '../fasting/tz_test_helper.dart';

/// 阶段 B：onboarding 减重目标页 + 进食障碍筛查 —— Q1=减脂必经（保存或
/// 跳过档案页、有无当前体重都进入）/ 缺口法预览与落盘 / 安全夹取提示 /
/// 筛查「是」温和化 + 强化免责提示。
void main() {
  // 固定时钟：2026-07-28 15:00（Asia/Shanghai）= 07:00 UTC → 本地日 2026-07-28。
  final fixedNowUtc =
      DateTime.utc(2026, 7, 28, 7).millisecondsSinceEpoch ~/ 1000;
  late tz.Location shanghai;

  setUpAll(() async {
    await initTestTimeZones();
    shanghai = tz.getLocation('Asia/Shanghai');
  });

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.zhCn);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Future<({OnboardingStore store, _RecordingProfileSync sync})> pumpApp(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesOnboardingStore(prefs);
    final gate = OnboardingGate(completed: false);
    final sync = _RecordingProfileSync();
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            onboardingGateProvider.overrideWithValue(gate),
            deviceLocationProvider.overrideWithValue(shanghai),
            nowUtcProvider.overrideWithValue(fixedNowUtc),
            fastingClockProvider.overrideWithValue(() => fixedNowUtc),
            localNotificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            profileSyncServiceProvider.overrideWithValue(sync),
          ],
          child: EatWiseApp(gate: gate),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return (store: store, sync: sync);
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapVisible(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(find.byKey(key));
    await pumpFrames(tester);
  }

  /// 答完 3 题（Q1 可配）进入档案页。
  Future<void> reachProfilePage(
    WidgetTester tester, {
    String q1 = 'loseWeight',
  }) async {
    for (final option in <String>[q1, 'regular', 'beginner']) {
      await tester.tap(
        find.byKey(ValueKey<String>('onboarding.quiz.option.$option')),
      );
      await pumpFrames(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding.quiz.next')),
      );
      await pumpFrames(tester);
    }
    expect(find.text('了解你的身体，目标更精准'), findsOneWidget);
  }

  /// 档案页：女 / 1998 / 162cm / 70kg / 久坐，保存落到下一页。
  Future<void> fillProfileAndSave(
    WidgetTester tester, {
    bool screeningYes = false,
  }) async {
    if (screeningYes) {
      await tester.tap(find.text('是'));
      await pumpFrames(tester);
    }
    await tester.tap(find.text('女'));
    await pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      '1998',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '162',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.weightKg')),
      '70',
    );
    await pumpFrames(tester);
    await tapVisible(
      tester,
      const ValueKey<String>('profile.activity.sedentary'),
    );
    await tapVisible(tester, const ValueKey<String>('onboarding.profile.save'));
  }

  testWidgets('减脂 + 填了体重 → 目标页出现；填目标后推荐页展示周速率/达成日/热量目标，'
      '超上限标安全夹取提示，一键启动落盘缺口法结果', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    await reachProfilePage(tester);
    await fillProfileAndSave(tester);

    // 目标页出现（Q1=减脂必经）。
    expect(find.text('定个减重小目标'), findsOneWidget);

    // 70→60 kg / 4 周：原始 2.5 kg/周 → 夹取 1.0（clamped）。
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '60',
    );
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('goal.quickWeeks.4')));
    await pumpFrames(tester);
    expect(find.text('2026年8月25日'), findsOneWidget); // 日期预览
    await tapVisible(tester, const ValueKey<String>('onboarding.goal.save'));

    // 推荐页：缺口法预览卡（BMR 1411.5 × 1.2 = 1693.8 − 1100 → 下限 1200）。
    expect(find.text('为你推荐的方案'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.weightLoss'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('预计每周减 1 kg'), findsOneWidget);
    expect(find.textContaining('2026年10月6日'), findsOneWidget); // 夹取后 70 天
    expect(find.textContaining('每日热量目标约 1200 kcal'), findsOneWidget);
    expect(find.textContaining('已按安全上限调整为每周最多减 1 kg'), findsOneWidget);
    // 未答筛查题 → 无强化免责提示。
    expect(
      find.byKey(const ValueKey<String>('onboarding.recommendation.edNotice')),
      findsNothing,
    );

    // 一键启动：营养目标快照带缺口法字段，目标体重/日期同步服务端。
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    expect(find.text('断食计时'), findsOneWidget);
    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isFalse);
    expect(goal.targetKcal, 1200);
    expect(goal.weeklyRateKg, 1.0);
    expect(goal.weightLossClamped, isTrue);
    expect(goal.reachDate, '2026-10-06');
    final synced = sync.completedCalls.single.profile!;
    expect(synced.targetWeightKg, 60);
    expect(synced.targetDate?.toIsoString(), '2026-08-25');
  });

  testWidgets('筛查选「是」→ 温和化（≤0.5 kg/周）+ 推荐页强化免责提示，不阻止使用', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    await reachProfilePage(tester);
    await fillProfileAndSave(tester, screeningYes: true);

    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '60',
    );
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('goal.quickWeeks.4')));
    await pumpFrames(tester);
    await tapVisible(tester, const ValueKey<String>('onboarding.goal.save'));

    // 温和节奏提示 + 强化免责提示。
    expect(find.textContaining('预计每周减 0.5 kg'), findsOneWidget);
    expect(find.textContaining('每周最多减 0.5 kg'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('onboarding.recommendation.edNotice')),
      findsOneWidget,
    );
    expect(find.textContaining('建议同步咨询专业医生'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    expect(find.text('断食计时'), findsOneWidget);
    final goal = store.loadNutritionGoal()!;
    expect(goal.weeklyRateKg, 0.5);
    expect(goal.weightLossClamped, isTrue);
    // 1693.8 − 550 = 1143.8 → 下限 1200
    expect(goal.targetKcal, 1200);

    // 筛查作答仅存本地：同步档案含作答（本地），PATCH 字段由
    // serverProfilePatch 负责剔除（此处断言档案记录即可）。
    expect(
      sync.completedCalls.single.profile!.eatingDisorderScreening,
      EatingDisorderScreening.yes,
    );
    expect(
      store.loadProfile()!.eatingDisorderScreening,
      EatingDisorderScreening.yes,
    );
  });

  testWidgets('非减脂目标（改善健康）→ 档案页保存直达推荐页，不出现目标页', (tester) async {
    await pumpApp(tester);
    await reachProfilePage(tester, q1: 'improveHealth');
    await fillProfileAndSave(tester);
    expect(find.text('定个减重小目标'), findsNothing);
    expect(find.text('为你推荐的方案'), findsOneWidget);
    // 无缺口法预览卡。
    expect(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.weightLoss'),
      ),
      findsNothing,
    );
  });

  testWidgets('目标页可整页跳过 → 维持 TDEE×0.8 固定折算，无缺口法字段', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    await reachProfilePage(tester);
    await fillProfileAndSave(tester);
    expect(find.text('定个减重小目标'), findsOneWidget);

    await tapVisible(tester, const ValueKey<String>('onboarding.goal.skip'));
    expect(find.text('为你推荐的方案'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.weightLoss'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    // 1693.8 × 0.8 = 1355.04 → 1355 → 取整 1350？步进 10：1355.04/10=135.504→136→1360
    final goal = store.loadNutritionGoal()!;
    expect(goal.weeklyRateKg, isNull);
    expect(goal.weightLossClamped, isFalse);
    expect(goal.targetKcal, 1360);
    expect(sync.completedCalls.single.profile!.targetWeightKg, isNull);
  });

  testWidgets('档案页整页跳过 + Q1=减脂 → 同样进目标页（可再跳过到推荐页）', (tester) async {
    await pumpApp(tester);
    await reachProfilePage(tester);

    // 产品决策：跳过档案的减脂用户也要经过减重目标页。
    await tapVisible(tester, const ValueKey<String>('onboarding.profile.skip'));
    expect(find.text('定个减重小目标'), findsOneWidget);

    // 目标页本身可跳过，不想填的用户仍有退路。
    await tapVisible(tester, const ValueKey<String>('onboarding.goal.skip'));
    expect(find.text('为你推荐的方案'), findsOneWidget);
  });

  testWidgets('档案页整页跳过 + Q1=非减脂 → 直达推荐页，不出现目标页', (tester) async {
    await pumpApp(tester);
    await reachProfilePage(tester, q1: 'improveHealth');

    await tapVisible(tester, const ValueKey<String>('onboarding.profile.skip'));
    expect(find.text('定个减重小目标'), findsNothing);
    expect(find.text('为你推荐的方案'), findsOneWidget);
  });

  testWidgets('保存但未填体重 + Q1=减脂 → 目标页正常渲染，目标可保存落盘；'
      '推荐页因缺当前体重不出现缺口法预览', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    await reachProfilePage(tester);

    // 单项可留空（D-18）：全部留空直接保存，减脂用户仍进目标页。
    await tapVisible(tester, const ValueKey<String>('onboarding.profile.save'));
    expect(find.text('定个减重小目标'), findsOneWidget);

    // 缺当前体重不影响目标收集：目标体重 + 目标日期照常保存。
    await tester.enterText(
      find.byKey(const ValueKey<String>('goal.targetWeight')),
      '60',
    );
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('goal.quickWeeks.4')));
    await pumpFrames(tester);
    expect(find.text('2026年8月25日'), findsOneWidget); // 日期预览
    await tapVisible(tester, const ValueKey<String>('onboarding.goal.save'));

    expect(find.text('为你推荐的方案'), findsOneWidget);
    final profile = store.loadProfile()!;
    expect(profile.weightKg, isNull);
    expect(profile.targetWeightKg, 60);
    expect(profile.targetDate?.toIsoString(), '2026-08-25');
    // 缺当前体重 → 缺口法不生效，无减重预览卡（回落固定折算/兜底）。
    expect(
      find.byKey(
        const ValueKey<String>('onboarding.recommendation.weightLoss'),
      ),
      findsNothing,
    );

    // 一键启动仍可用：兜底营养目标，无缺口法字段。
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    expect(find.text('断食计时'), findsOneWidget);
    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isTrue);
    expect(goal.weeklyRateKg, isNull);
    expect(sync.completedCalls.single.profile!.targetWeightKg, 60);
  });
}

/// 记录型假同步服务（不触网）。
final class _RecordingProfileSync implements ProfileSyncService {
  final List<({OnboardingProfile? profile, GoalAnswer? goal})> completedCalls =
      <({OnboardingProfile? profile, GoalAnswer? goal})>[];
  int skippedCalls = 0;

  @override
  void syncOnboardingCompleted({
    required OnboardingProfile? profile,
    required GoalAnswer? goal,
  }) {
    completedCalls.add((profile: profile, goal: goal));
  }

  @override
  void syncOnboardingSkipped() {
    skippedCalls += 1;
  }
}
