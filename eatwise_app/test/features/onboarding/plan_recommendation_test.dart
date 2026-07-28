import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

/// D-03 推荐规则表全组合单测（M1）。
void main() {
  group('recommendPlan — D-03 规则表', () {
    test('零基础 → 主 14:10（10:00–20:00），备选 16:8', () {
      final rec = recommendPlan(
        const OnboardingAnswers(
          goal: GoalAnswer.loseWeight,
          schedule: ScheduleAnswer.regular,
          experience: ExperienceAnswer.beginner,
        ),
      );
      expect(rec.primary, PlanOption.p14x10);
      expect(rec.primary.eatStartMinutes, 10 * 60);
      expect(rec.primary.eatEndMinutes, 20 * 60);
      expect(rec.alternatives, <PlanOption>[PlanOption.p16x8]);
      expect(rec.reason, RecommendationReason.beginner);
      expect(rec.usedFallback, isFalse);
      expect(rec.flexibleWindowHint, isFalse);
    });

    test('试过没坚持 → 主 16:8（12:00–20:00），备选 14:10', () {
      final rec = recommendPlan(
        const OnboardingAnswers(
          goal: GoalAnswer.justTrying,
          schedule: ScheduleAnswer.regular,
          experience: ExperienceAnswer.triedButStopped,
        ),
      );
      expect(rec.primary, PlanOption.p16x8);
      expect(rec.primary.eatStartMinutes, 12 * 60);
      expect(rec.primary.eatEndMinutes, 20 * 60);
      expect(rec.alternatives, <PlanOption>[PlanOption.p14x10]);
      expect(rec.reason, RecommendationReason.triedButStopped);
    });

    test('有经验（非体检目标）→ 主 16:8，备选 18:6', () {
      for (final goal in <GoalAnswer>[
        GoalAnswer.loseWeight,
        GoalAnswer.adjustSchedule,
        GoalAnswer.justTrying,
      ]) {
        final rec = recommendPlan(
          OnboardingAnswers(
            goal: goal,
            schedule: ScheduleAnswer.regular,
            experience: ExperienceAnswer.experienced,
          ),
        );
        expect(rec.primary, PlanOption.p16x8, reason: 'goal=$goal');
        expect(rec.alternatives, <PlanOption>[PlanOption.p18x6]);
        expect(rec.reason, RecommendationReason.experienced);
      }
    });

    test('改善体检指标 + 有经验 → 主升级 18:6，备选 5:2（仅说明）', () {
      final rec = recommendPlan(
        const OnboardingAnswers(
          goal: GoalAnswer.improveHealth,
          schedule: ScheduleAnswer.regular,
          experience: ExperienceAnswer.experienced,
        ),
      );
      expect(rec.primary, PlanOption.p18x6);
      expect(rec.primary.eatStartMinutes, 12 * 60);
      expect(rec.primary.eatEndMinutes, 18 * 60);
      expect(rec.alternatives, <PlanOption>[PlanOption.p5x2]);
      expect(rec.alternatives.single.isInfoOnly, isTrue);
      expect(rec.alternatives.single.toFastingPlan(), isNull);
      expect(rec.reason, RecommendationReason.healthUpgrade);
    });

    test('改善体检指标 + 零基础 → 不升级，仍 14:10', () {
      final rec = recommendPlan(
        const OnboardingAnswers(
          goal: GoalAnswer.improveHealth,
          schedule: ScheduleAnswer.regular,
          experience: ExperienceAnswer.beginner,
        ),
      );
      expect(rec.primary, PlanOption.p14x10);
      expect(rec.reason, RecommendationReason.beginner);
    });

    test('Q2=轮班/不规律 → 窗口可自由调整提示，不设特殊方案', () {
      for (final schedule in <ScheduleAnswer>[
        ScheduleAnswer.shiftWork,
        ScheduleAnswer.flexible,
      ]) {
        final rec = recommendPlan(
          OnboardingAnswers(
            goal: GoalAnswer.loseWeight,
            schedule: schedule,
            experience: ExperienceAnswer.beginner,
          ),
        );
        expect(rec.flexibleWindowHint, isTrue, reason: 'schedule=$schedule');
        expect(rec.primary, PlanOption.p14x10); // 方案不变
      }
    });

    test('跳过问卷（空答案）→ 默认 16:8（12:00–20:00）兜底', () {
      final rec = recommendPlan(OnboardingAnswers.empty);
      expect(rec.primary, PlanOption.p16x8);
      expect(rec.primary.eatStartMinutes, 12 * 60);
      expect(rec.primary.eatEndMinutes, 20 * 60);
      expect(rec.alternatives, isNotEmpty);
      expect(rec.reason, RecommendationReason.fallback);
      expect(rec.usedFallback, isTrue);
    });

    test('部分作答（未答完）→ 同样走兜底', () {
      final rec = recommendPlan(
        const OnboardingAnswers(
          goal: GoalAnswer.loseWeight,
          experience: ExperienceAnswer.experienced,
        ),
      );
      expect(rec.usedFallback, isTrue);
      expect(rec.primary, PlanOption.p16x8);
    });
  });

  group('PlanOption / PlanRecommendation', () {
    test('toFastingPlan 转换为 M2 引擎方案', () {
      final plan = PlanOption.p18x6.toFastingPlan();
      expect(
        plan,
        const FastingPlan(
          id: '18:6',
          eatStartMinutes: 720,
          eatEndMinutes: 1080,
        ),
      );
      expect(plan!.fastWindowMinutes, 18 * 60);
      expect(plan.eatWindowMinutes, 6 * 60);
    });

    test('promote：备选升主，原主降为备选；5:2 不可升', () {
      final rec = recommendPlan(
        const OnboardingAnswers(
          goal: GoalAnswer.loseWeight,
          schedule: ScheduleAnswer.regular,
          experience: ExperienceAnswer.beginner,
        ),
      );
      final promoted = rec.promote(PlanOption.p16x8);
      expect(promoted.primary, PlanOption.p16x8);
      expect(promoted.alternatives, <PlanOption>[PlanOption.p14x10]);

      final noOp = rec.promote(PlanOption.p5x2);
      expect(noOp.primary, PlanOption.p14x10);
    });
  });
}
