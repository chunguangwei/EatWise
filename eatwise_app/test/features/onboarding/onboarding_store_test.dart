import 'dart:convert';

import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OnboardingStore 持久化单测（M1：进度本地保存可续答 / 方案与营养目标写入）。
void main() {
  group('SharedPreferencesOnboardingStore', () {
    test('完成标志位读写', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
      );
      expect(store.isOnboardingCompleted, isFalse);
      store.markOnboardingCompleted();
      expect(store.isOnboardingCompleted, isTrue);
    });

    test('问卷进度保存/读取/清除（续答）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
      );
      expect(store.loadQuizProgress(), isNull);

      store.saveQuizProgress(
        const QuizProgress(
          answers: <String, String>{'q1': 'loseWeight', 'q2': 'regular'},
          currentStep: 2,
        ),
      );
      final progress = store.loadQuizProgress();
      expect(progress!.currentStep, 2);
      expect(progress.answers, <String, String>{
        'q1': 'loseWeight',
        'q2': 'regular',
      });

      store.clearQuizProgress();
      expect(store.loadQuizProgress(), isNull);
    });

    test('方案快照与营养目标往返', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
      );
      store.saveActivePlan(
        const ActivePlanSnapshot(
          plan: FastingPlan(
            id: '14:10',
            eatStartMinutes: 600,
            eatEndMinutes: 1200,
          ),
          initialState: 'fasting',
          targetUtc: 1780000000,
          attributionDate: '2026-07-29',
          startedAtUtc: 1779900000,
        ),
      );
      final plan = store.loadActivePlan()!;
      expect(plan.plan.id, '14:10');
      expect(plan.plan.eatStartMinutes, 600);
      expect(plan.initialState, 'fasting');
      expect(plan.targetUtc, 1780000000);
      expect(plan.attributionDate, '2026-07-29');

      store.saveNutritionGoal(
        const NutritionGoalSnapshot(
          targetKcal: 2000,
          proteinG: 125,
          carbG: 225,
          fatG: 67,
          usedFallback: true,
          configVersion: '1.0.0',
        ),
      );
      final goal = store.loadNutritionGoal()!;
      expect(goal.targetKcal, 2000);
      expect(goal.usedFallback, isTrue);
    });

    test('档案采集往返（阶段 A）；空档案按未采集处理', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
      );
      expect(store.loadProfile(), isNull);

      const profile = OnboardingProfile(
        sex: ProfileSex.female,
        birthYear: 1998,
        heightCm: 162,
        weightKg: 55,
        activityLevel: ActivityLevel.sedentary,
      );
      store.saveProfile(profile);
      expect(store.loadProfile(), profile);

      // 空档案（全留空/跳过）→ 清除键位，按未采集走兜底。
      store.saveProfile(OnboardingProfile.empty);
      expect(store.loadProfile(), isNull);
    });

    test('本地数据损坏按无进度处理（防御）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding.quizProgress': '{broken json',
        'onboarding.activePlan': jsonEncode(<String, dynamic>{'bad': 1}),
      });
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
      );
      expect(store.loadQuizProgress(), isNull);
      expect(store.loadActivePlan(), isNull);
    });

    test('待生效方案（PendingPlan，D-06/T12）保存/读取/清除', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
      );
      expect(store.loadPendingPlan(), isNull);

      store.savePendingPlan(
        const PendingPlan(
          plan: FastingPlan.plan14x10,
          effectiveDate: LocalDate(2026, 7, 29),
          effectiveUtc: 1780000000,
        ),
      );
      final pending = store.loadPendingPlan()!;
      expect(pending.plan, FastingPlan.plan14x10);
      expect(pending.effectiveDate, const LocalDate(2026, 7, 29));
      expect(pending.effectiveUtc, 1780000000);

      store.clearPendingPlan();
      expect(store.loadPendingPlan(), isNull);
    });

    test('减重目标锚点：首设落锚 / 值不变保留 / 变更重置 / 清空与清档案移除', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      var fakeNow = 1000000;
      final store = SharedPreferencesOnboardingStore(
        await SharedPreferences.getInstance(),
        nowUtc: () => fakeNow,
      );
      expect(store.loadTargetWeightSetAtUtc(), isNull);

      // 首设目标 → 落锚。
      store.saveProfile(
        const OnboardingProfile(weightKg: 80, targetWeightKg: 70),
      );
      expect(store.loadTargetWeightSetAtUtc(), 1000000);

      // 无关字段变更、目标值不变 → 锚点保留。
      fakeNow = 2000000;
      store.saveProfile(
        const OnboardingProfile(
          weightKg: 80,
          heightCm: 175,
          targetWeightKg: 70,
        ),
      );
      expect(store.loadTargetWeightSetAtUtc(), 1000000);

      // 目标值变更 → 重置为保存时刻。
      store.saveProfile(
        const OnboardingProfile(
          weightKg: 80,
          heightCm: 175,
          targetWeightKg: 65,
        ),
      );
      expect(store.loadTargetWeightSetAtUtc(), 2000000);

      // 目标清空 → 锚点移除。
      fakeNow = 3000000;
      store.saveProfile(const OnboardingProfile(weightKg: 80, heightCm: 175));
      expect(store.loadTargetWeightSetAtUtc(), isNull);

      // 重新设定 → 重新落锚；档案整体清空 → 锚点一并移除。
      store.saveProfile(
        const OnboardingProfile(weightKg: 80, targetWeightKg: 70),
      );
      expect(store.loadTargetWeightSetAtUtc(), 3000000);
      store.saveProfile(const OnboardingProfile());
      expect(store.loadTargetWeightSetAtUtc(), isNull);
    });
  });

  group('InMemoryOnboardingStore', () {
    test('减重目标锚点语义与 SharedPreferences 实现一致', () {
      var fakeNow = 1000000;
      final store = InMemoryOnboardingStore(nowUtc: () => fakeNow);
      store.saveProfile(
        const OnboardingProfile(weightKg: 80, targetWeightKg: 70),
      );
      expect(store.loadTargetWeightSetAtUtc(), 1000000);
      fakeNow = 2000000;
      store.saveProfile(
        const OnboardingProfile(weightKg: 80, targetWeightKg: 70),
      );
      expect(store.loadTargetWeightSetAtUtc(), 1000000); // 值不变保留
      store.saveProfile(
        const OnboardingProfile(weightKg: 80, targetWeightKg: 65),
      );
      expect(store.loadTargetWeightSetAtUtc(), 2000000); // 变更重置
      store.saveProfile(const OnboardingProfile());
      expect(store.loadTargetWeightSetAtUtc(), isNull); // 清档案移除
    });

    test('读写往返', () {
      final store = InMemoryOnboardingStore();
      expect(store.isOnboardingCompleted, isFalse);
      store.markOnboardingCompleted();
      expect(store.isOnboardingCompleted, isTrue);
      store.saveQuizProgress(
        const QuizProgress(
          answers: <String, String>{'q1': 'justTrying'},
          currentStep: 1,
        ),
      );
      expect(store.loadQuizProgress()!.currentStep, 1);
      store.clearQuizProgress();
      expect(store.loadQuizProgress(), isNull);
    });
  });
}
