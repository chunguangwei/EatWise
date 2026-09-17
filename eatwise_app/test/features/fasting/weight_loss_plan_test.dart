import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/domain/weight_loss_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阶段 B 减重速率→热量缺口（《规格-营养规则》缺口法章节，叠加 D-04）：
/// 7700 kcal/kg、周速率 [0.1, 1.0] 安全夹取、温和节奏 0.5、下限保护、
/// 不生效场景回落固定折算。
void main() {
  const today = LocalDate(2026, 9, 17);
  const config = NutritionRuleConfig.defaults;

  group('computeWeightLossPlan', () {
    test('正常缺口：70→65 kg / 70 天 → 0.5 kg/周，日缺口 550 kcal', () {
      final plan = computeWeightLossPlan(
        currentWeightKg: 70,
        targetWeightKg: 65,
        targetDate: today.addDays(70),
        today: today,
        tdee: 2000,
        minKcal: 1200,
      )!;
      expect(plan.weeklyRateKg, closeTo(0.5, 1e-9));
      expect(plan.dailyDeficitKcal, closeTo(550, 1e-9)); // 0.5 × 7700 ÷ 7
      expect(plan.targetKcal, closeTo(1450, 1e-9));
      expect(plan.clamped, isFalse);
      expect(plan.reachDate, today.addDays(70));
    });

    test('超安全上限 clamp：60→50 kg / 28 天 → 1.0 kg/周 + clamped + 达成日后移', () {
      final plan = computeWeightLossPlan(
        currentWeightKg: 60,
        targetWeightKg: 50,
        targetDate: today.addDays(28),
        today: today,
        tdee: 2200,
        minKcal: 1500,
      )!;
      expect(plan.weeklyRateKg, 1.0);
      expect(plan.dailyDeficitKcal, closeTo(1100, 1e-9));
      // 2200 − 1100 = 1100 < 1500 → 下限保护（不破既有下限常量）
      expect(plan.targetKcal, 1500);
      expect(plan.clamped, isTrue);
      expect(plan.reachDate, today.addDays(70)); // 10kg ÷ 1kg/周
    });

    test('速率恰好 1.0 kg/周不标 clamped（边界）', () {
      final plan = computeWeightLossPlan(
        currentWeightKg: 60,
        targetWeightKg: 55,
        targetDate: today.addDays(35),
        today: today,
        tdee: 2500,
        minKcal: 1500,
      )!;
      expect(plan.weeklyRateKg, 1.0);
      expect(plan.clamped, isFalse);
      // 2500 − 1100 = 1400 < 1500 → 下限保护
      expect(plan.targetKcal, 1500);
    });

    test('速率下限：极缓目标夹取到 0.1 kg/周', () {
      final plan = computeWeightLossPlan(
        currentWeightKg: 60,
        targetWeightKg: 59,
        targetDate: today.addDays(365),
        today: today,
        tdee: 2000,
        minKcal: 1200,
      )!;
      expect(plan.weeklyRateKg, 0.1);
      expect(plan.clamped, isFalse);
      expect(plan.reachDate, today.addDays(70)); // 1kg ÷ 0.1kg/周
    });

    test('温和节奏（进食障碍筛查「是」）：上限 0.5 kg/周', () {
      final plan = computeWeightLossPlan(
        currentWeightKg: 70,
        targetWeightKg: 60,
        targetDate: today.addDays(56), // 原始速率 1.25 kg/周
        today: today,
        tdee: 2500,
        minKcal: 1500,
        gentle: true,
      )!;
      expect(plan.weeklyRateKg, 0.5);
      expect(plan.dailyDeficitKcal, closeTo(550, 1e-9));
      expect(plan.clamped, isTrue);
      expect(plan.reachDate, today.addDays(140)); // 10kg ÷ 0.5kg/周
    });

    test('不生效场景返回 null：无目标 / 目标≥当前 / 目标日期非未来', () {
      expect(
        computeWeightLossPlan(
          currentWeightKg: 60,
          targetWeightKg: null,
          targetDate: today.addDays(30),
          today: today,
          tdee: 2000,
          minKcal: 1200,
        ),
        isNull,
      );
      expect(
        computeWeightLossPlan(
          currentWeightKg: 60,
          targetWeightKg: 55,
          targetDate: null,
          today: today,
          tdee: 2000,
          minKcal: 1200,
        ),
        isNull,
      );
      for (final target in <double>[60, 70]) {
        expect(
          computeWeightLossPlan(
            currentWeightKg: 60,
            targetWeightKg: target,
            targetDate: today.addDays(30),
            today: today,
            tdee: 2000,
            minKcal: 1200,
          ),
          isNull,
          reason: '目标≥当前按维持（$target kg）',
        );
      }
      for (final date in <LocalDate>[today, const LocalDate(2026, 9, 16)]) {
        expect(
          computeWeightLossPlan(
            currentWeightKg: 60,
            targetWeightKg: 55,
            targetDate: date,
            today: today,
            tdee: 2000,
            minKcal: 1200,
          ),
          isNull,
          reason: '目标日期非未来（$date）',
        );
      }
    });
  });

  group('daysBetweenLocalDate', () {
    test('跨月/跨年天数', () {
      expect(daysBetweenLocalDate(const LocalDate(2026, 9, 17), today), 0);
      expect(daysBetweenLocalDate(today, const LocalDate(2026, 10, 17)), 30);
      expect(daysBetweenLocalDate(today, const LocalDate(2027, 9, 17)), 365);
    });
  });

  group('computeNutritionGoal 叠加缺口法', () {
    /// 规格 §2.2 示例 A 基线：28 岁女，55 kg / 162 cm，久坐，减脂。
    /// BMR 1261.5 × 1.2 = TDEE 1513.8。
    const base = UserProfileInput(
      sex: Sex.female,
      age: 28,
      heightCm: 162,
      weightKg: 55,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
      today: today,
    );

    test('无减重目标 → 维持 TDEE×0.8（1210），weightLoss 为 null', () {
      final goal = computeNutritionGoal(base, config);
      expect(goal.targetKcal, 1210);
      expect(goal.weightLoss, isNull);
    });

    test('有目标体重+日期 → 缺口法覆盖 ×0.8 并带出计划信息', () {
      // 55→53 kg / 70 天：0.2 kg/周 → 缺口 220 → 1513.8−220=1293.8 → 1290
      final goal = computeNutritionGoal(
        UserProfileInput(
          sex: base.sex,
          age: base.age,
          heightCm: base.heightCm,
          weightKg: base.weightKg,
          activityLevel: base.activityLevel,
          goal: base.goal,
          today: today,
          targetWeightKg: 53,
          targetDate: today.addDays(70),
        ),
        config,
      );
      expect(goal.targetKcal, 1290);
      expect(goal.weightLoss, isNotNull);
      expect(goal.weightLoss!.weeklyRateKg, closeTo(0.2, 1e-9));
      expect(goal.weightLoss!.clamped, isFalse);
      expect(goal.weightLoss!.reachDate, today.addDays(70));
    });

    test('缺口法不破下限：缺口压到地板以下 → 1200 且仍带计划信息', () {
      // 55→50 kg / 35 天：1.0 kg/周 → 缺口 1100 → 1513.8−1100=413.8 → 1200
      final goal = computeNutritionGoal(
        UserProfileInput(
          sex: base.sex,
          age: base.age,
          heightCm: base.heightCm,
          weightKg: base.weightKg,
          activityLevel: base.activityLevel,
          goal: base.goal,
          today: today,
          targetWeightKg: 50,
          targetDate: today.addDays(35),
        ),
        config,
      );
      expect(goal.targetKcal, 1200);
      expect(goal.weightLoss!.weeklyRateKg, 1.0);
      expect(goal.weightLoss!.clamped, isFalse);
    });

    test('温和化路径：gentleWeightLoss → 周速率 ≤0.5 kg', () {
      final goal = computeNutritionGoal(
        UserProfileInput(
          sex: base.sex,
          age: base.age,
          heightCm: base.heightCm,
          weightKg: base.weightKg,
          activityLevel: base.activityLevel,
          goal: base.goal,
          today: today,
          targetWeightKg: 50,
          targetDate: today.addDays(35), // 原始 1.0 → 温和 0.5
          gentleWeightLoss: true,
        ),
        config,
      );
      expect(goal.weightLoss!.weeklyRateKg, 0.5);
      expect(goal.weightLoss!.clamped, isTrue);
      // 1513.8 − 550 = 963.8 → 下限 1200
      expect(goal.targetKcal, 1200);
    });

    test('维持目标不启用缺口法（仅 lose 生效）', () {
      final goal = computeNutritionGoal(
        UserProfileInput(
          sex: base.sex,
          age: base.age,
          heightCm: base.heightCm,
          weightKg: base.weightKg,
          activityLevel: base.activityLevel,
          goal: NutritionGoalType.maintain,
          today: today,
          targetWeightKg: 50,
          targetDate: today.addDays(35),
        ),
        config,
      );
      expect(goal.targetKcal, 1510); // TDEE 取整
      expect(goal.weightLoss, isNull);
    });
  });
}
