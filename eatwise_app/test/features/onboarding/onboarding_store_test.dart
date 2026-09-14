import 'dart:convert';

import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
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
  });

  group('InMemoryOnboardingStore', () {
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
