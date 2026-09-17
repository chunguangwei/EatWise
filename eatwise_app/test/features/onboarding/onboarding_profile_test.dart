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

/// 阶段 A：onboarding 档案采集页 —— 精准营养目标接线 / 留空兜底 /
/// 取值域校验 / 登录态云端同步（假 ProfileSyncService 断言）。
void main() {
  // 固定时钟：2026-07-28 15:00（Asia/Shanghai）= 07:00 UTC → currentYear=2026。
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

  /// 档案页为 ListView：保存按钮/活动选项可能在默认视口外，先滚动到可见。
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

  /// 答完 3 题进入档案页。
  Future<void> reachProfilePage(WidgetTester tester) async {
    for (final option in <String>['loseWeight', 'regular', 'beginner']) {
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

  Future<void> startAndLandHome(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.recommendation.start')),
    );
    await pumpFrames(tester);
    expect(find.text('断食计时'), findsOneWidget);
  }

  testWidgets('填齐档案 → 保存 → 一键启动：营养目标全参精准计算（非兜底），'
      '并回写服务端 onboardingStatus=completed + 档案字段', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    await reachProfilePage(tester);

    // 女 / 1998（2026 年 28 岁）/ 162cm / 55kg / 久坐 —— 规格 §2.2 示例 A。
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
      '55',
    );
    await pumpFrames(tester);
    await tapVisible(
      tester,
      const ValueKey<String>('profile.activity.sedentary'),
    );
    await tapVisible(tester, const ValueKey<String>('onboarding.profile.save'));

    // 保存后落到推荐页；档案已持久化。
    expect(find.text('为你推荐的方案'), findsOneWidget);
    final profile = store.loadProfile()!;
    expect(profile.sex, ProfileSex.female);
    expect(profile.birthYear, 1998);
    expect(profile.heightCm, 162);
    expect(profile.weightKg, 55);
    expect(profile.activityLevel?.name, 'sedentary');

    await startAndLandHome(tester);

    // 精准计算：BMR 1261.5 × 1.2 × 0.8 = 1211.04 → 取整 1210（§2.2 示例 A）。
    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isFalse);
    expect(goal.targetKcal, 1210);
    expect(goal.proteinG, 76);
    expect(goal.carbG, 136);
    expect(goal.fatG, 40);
    // 非兜底 → 不出现「补全资料」提示。
    expect(find.textContaining('kcal 估算'), findsNothing);

    // 登录态同步：completed + 档案字段映射（female/fat_loss/sedentary）。
    expect(sync.completedCalls, hasLength(1));
    expect(sync.completedCalls.single.goal, GoalAnswer.loseWeight);
    expect(sync.completedCalls.single.profile, profile);
    expect(sync.skippedCalls, 0);
  });

  testWidgets('单项留空（只填身高）→ 允许保存，营养目标仍走兜底并提示补全', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    await reachProfilePage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.heightCm')),
      '168',
    );
    await pumpFrames(tester);
    await tapVisible(tester, const ValueKey<String>('onboarding.profile.save'));
    expect(find.text('为你推荐的方案'), findsOneWidget);

    await startAndLandHome(tester);

    final goal = store.loadNutritionGoal()!;
    expect(goal.usedFallback, isTrue);
    expect(goal.targetKcal, 2000); // 性别未知兜底 2000（§1.6）
    // 兜底提示仍在（补全资料引导）。
    expect(find.textContaining('2000 kcal'), findsOneWidget);
    expect(sync.completedCalls.single.profile!.heightCm, 168);
    expect(sync.completedCalls.single.profile!.sex, isNull);
  });

  testWidgets('出生年越域（1800）→ 即时错误文案且保存按钮禁用', (tester) async {
    await pumpApp(tester);
    await reachProfilePage(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      '1800',
    );
    await pumpFrames(tester);

    expect(find.text('请输入 1920–2026 之间的年份'), findsOneWidget);
    // ListView 懒构建：按钮在视口外时不在树中，先滚动到可见再断言。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('onboarding.profile.save')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('onboarding.profile.save')),
    );
    expect(button.onPressed, isNull);

    // 改回合法值 → 错误消失、按钮恢复。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile.birthYear')),
      '1998',
    );
    await pumpFrames(tester);
    expect(find.text('请输入 1920–2026 之间的年份'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('onboarding.profile.save')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('onboarding.profile.save')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('问卷跳过 → 回写服务端 onboardingStatus=skipped', (tester) async {
    final (:store, :sync) = await pumpApp(tester);
    expect(store, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding.quiz.skip')),
    );
    await pumpFrames(tester);

    expect(sync.skippedCalls, 1);
    expect(sync.completedCalls, isEmpty);
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
