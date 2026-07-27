import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// 《规格-营养规则》§5.2 单测清单 U1–U15（TDEE 计算，D-04）。
void main() {
  const config = NutritionRuleConfig.defaults;

  /// 规格 §2.2 示例 A：28 岁女，55 kg / 162 cm，久坐，减脂。
  const inputA = UserProfileInput(
    sex: Sex.female,
    age: 28,
    heightCm: 162,
    weightKg: 55,
    activityLevel: ActivityLevel.sedentary,
    goal: NutritionGoalType.lose,
  );

  /// 规格 §2.3 示例 B：24 岁男，75 kg / 176 cm，轻度，维持。
  const inputB = UserProfileInput(
    sex: Sex.male,
    age: 24,
    heightCm: 176,
    weightKg: 75,
    activityLevel: ActivityLevel.light,
    goal: NutritionGoalType.maintain,
  );

  test('U1 示例 A：BMR = 1261.5', () {
    expect(computeNutritionGoal(inputA, config).bmr, 1261.5);
  });

  test('U2 示例 B：BMR = 1735', () {
    expect(computeNutritionGoal(inputB, config).bmr, 1735);
  });

  test('U3 男女公式常数项（+5 / −161）不串用', () {
    const male = UserProfileInput(
      sex: Sex.male,
      age: 30,
      heightCm: 170,
      weightKg: 60,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.maintain,
    );
    const female = UserProfileInput(
      sex: Sex.female,
      age: 30,
      heightCm: 170,
      weightKg: 60,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.maintain,
    );
    final bmrM = computeNutritionGoal(male, config).bmr!;
    final bmrF = computeNutritionGoal(female, config).bmr!;
    expect(bmrM, isNot(bmrF));
    expect(bmrM - bmrF, 166); // +5 − (−161)
  });

  test('U4 四个活动系数 1.2/1.375/1.55/1.725 逐一映射（§1.3）', () {
    const base = UserProfileInput(
      sex: Sex.male,
      age: 24,
      heightCm: 176,
      weightKg: 75,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.maintain,
    );
    const expected = <ActivityLevel, double>{
      ActivityLevel.sedentary: 1.2,
      ActivityLevel.light: 1.375,
      ActivityLevel.moderate: 1.55,
      ActivityLevel.high: 1.725,
    };
    for (final entry in expected.entries) {
      final input = UserProfileInput(
        sex: base.sex,
        age: base.age,
        heightCm: base.heightCm,
        weightKg: base.weightKg,
        activityLevel: entry.key,
        goal: base.goal,
      );
      final goal = computeNutritionGoal(input, config);
      expect(goal.tdee, closeTo(1735 * entry.value, 1e-9));
    }
  });

  test('U5 activityLevel 缺失 → 走兜底，usedFallback=true', () {
    const input = UserProfileInput(
      sex: Sex.female,
      age: 28,
      heightCm: 162,
      weightKg: 55,
      goal: NutritionGoalType.lose,
    );
    final goal = computeNutritionGoal(input, config);
    expect(goal.usedFallback, isTrue);
    expect(goal.bmr, isNull); // 兜底时不计算/不展示 BMR/TDEE（§1.6）
    expect(goal.tdee, isNull);
  });

  test('U6 减脂 ×0.8（示例 A）：1211.04 → 1210', () {
    final goal = computeNutritionGoal(inputA, config);
    expect(goal.tdee, closeTo(1513.8, 1e-9));
    expect(goal.targetKcal, 1210);
  });

  test('U7 减脂触发女下限 1200（160cm/50kg 久坐，§2.2 边界验证）', () {
    const input = UserProfileInput(
      sex: Sex.female,
      age: 28,
      heightCm: 160,
      weightKg: 50,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    final goal = computeNutritionGoal(input, config);
    // BMR = 10×50 + 6.25×160 − 5×28 − 161 = 1199（规格 §2.2 注记 1151.5
    // 系原文算术笔误，不影响结论）→ TDEE 1438.8 → ×0.8 = 1151.04 < 1200
    // → 触发下限保护
    expect(goal.bmr, 1199);
    expect(goal.tdee, closeTo(1438.8, 1e-9));
    expect(goal.targetKcal, 1200);
  });

  test('U8 减脂触发男下限 1500（低体重构造用例）', () {
    const input = UserProfileInput(
      sex: Sex.male,
      age: 40,
      heightCm: 160,
      weightKg: 50,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    final goal = computeNutritionGoal(input, config);
    // BMR = 500+1000−200+5 = 1305 → TDEE 1566 → ×0.8 = 1252.8 < 1500
    expect(goal.bmr, 1305);
    expect(goal.targetKcal, 1500);
  });

  test('U9 维持 ×1.0（示例 B）：2390', () {
    final goal = computeNutritionGoal(inputB, config);
    expect(goal.tdee, closeTo(2385.625, 1e-9));
    expect(goal.targetKcal, 2390);
  });

  test('U10 目标热量四舍五入到 10 kcal 的边界（§1.4）', () {
    expect(roundKcalToStep(1214.9, 10), 1210); // x4.9 → x0
    expect(roundKcalToStep(1215.0, 10), 1220); // x5.0 → 入（四舍五入）
    expect(roundKcalToStep(1211.04, 10), 1210); // 示例 A
    expect(roundKcalToStep(2385.625, 10), 2390); // 示例 B
  });

  test('U11 示例 A 三营养素：76/136/40 g（§2.2）', () {
    final goal = computeNutritionGoal(inputA, config);
    expect(goal.proteinG, 76);
    expect(goal.carbG, 136);
    expect(goal.fatG, 40);
  });

  test('U12 示例 B 三营养素：149/269/80 g（§2.3）', () {
    final goal = computeNutritionGoal(inputB, config);
    expect(goal.proteinG, 149);
    expect(goal.carbG, 269);
    expect(goal.fatG, 80);
  });

  test('U13 缺身高 → 女 1800 / 男 2200；缺性别 → 2000（§1.6）', () {
    const noHeightF = UserProfileInput(
      sex: Sex.female,
      age: 28,
      weightKg: 55,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    const noHeightM = UserProfileInput(
      sex: Sex.male,
      age: 28,
      weightKg: 55,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    const noSex = UserProfileInput(
      age: 28,
      heightCm: 162,
      weightKg: 55,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    expect(computeNutritionGoal(noHeightF, config).targetKcal, 1800);
    expect(computeNutritionGoal(noHeightM, config).targetKcal, 2200);
    expect(computeNutritionGoal(noSex, config).targetKcal, 2000);
    expect(computeNutritionGoal(noHeightF, config).usedFallback, isTrue);
  });

  test('U14 越域输入（age=5、height=400）按缺失处理（§1.1〔假设〕取值域）', () {
    const badAge = UserProfileInput(
      sex: Sex.female,
      age: 5,
      heightCm: 162,
      weightKg: 55,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    const badHeight = UserProfileInput(
      sex: Sex.female,
      age: 28,
      heightCm: 400,
      weightKg: 55,
      activityLevel: ActivityLevel.sedentary,
      goal: NutritionGoalType.lose,
    );
    expect(computeNutritionGoal(badAge, config).usedFallback, isTrue);
    expect(computeNutritionGoal(badHeight, config).usedFallback, isTrue);
  });

  test('U15 兜底按同配比折算克数：1800→P113/C203/F60；2200→P138/C248/F73', () {
    const noHeightF = UserProfileInput(sex: Sex.female);
    const noHeightM = UserProfileInput(sex: Sex.male);
    final f = computeNutritionGoal(noHeightF, config);
    expect((f.proteinG, f.carbG, f.fatG), (113, 203, 60));
    final m = computeNutritionGoal(noHeightM, config);
    expect((m.proteinG, m.carbG, m.fatG), (138, 248, 73));
  });
}
