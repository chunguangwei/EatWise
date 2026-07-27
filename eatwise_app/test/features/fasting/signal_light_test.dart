import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/domain/signal_light.dart';
import 'package:flutter_test/flutter_test.dart';

/// 《规格-营养规则》§5.2 单测清单 U16–U22（信号灯阈值，D-05）。
/// 闭区间边界规则见 §3.1：判定用未取整原始值，禁止先取整再比较。
void main() {
  const config = NutritionRuleConfig.defaults;

  test('U16 热量边界（§3.1 闭区间）', () {
    expect(classify(59.99, NutrientType.kcal, config), SignalZone.red);
    expect(classify(60.0, NutrientType.kcal, config), SignalZone.yellow);
    expect(classify(84.99, NutrientType.kcal, config), SignalZone.yellow);
    expect(classify(85.0, NutrientType.kcal, config), SignalZone.green);
    expect(classify(110.0, NutrientType.kcal, config), SignalZone.green);
    expect(classify(110.01, NutrientType.kcal, config), SignalZone.yellow);
    expect(classify(130.0, NutrientType.kcal, config), SignalZone.yellow);
    expect(classify(130.01, NutrientType.kcal, config), SignalZone.red);
  });

  test('U17 蛋白质边界（含独有「过量标红」150，D-05）', () {
    expect(classify(69.99, NutrientType.protein, config), SignalZone.red);
    expect(classify(70.0, NutrientType.protein, config), SignalZone.yellow);
    expect(classify(90.0, NutrientType.protein, config), SignalZone.green);
    expect(classify(150.0, NutrientType.protein, config), SignalZone.green);
    expect(classify(150.01, NutrientType.protein, config), SignalZone.red);
    // 细分：过量标红方向为 redOver（映射 redHigh 模板）
    expect(
      classifyVerdict(150.01, NutrientType.protein, config).subZone,
      SignalSubZone.redOver,
    );
  });

  test('U18 碳水边界：65.0 黄 / 85.0 绿 / 115.0 绿 / 135.0 黄', () {
    expect(classify(64.99, NutrientType.carb, config), SignalZone.red);
    expect(classify(65.0, NutrientType.carb, config), SignalZone.yellow);
    expect(classify(85.0, NutrientType.carb, config), SignalZone.green);
    expect(classify(115.0, NutrientType.carb, config), SignalZone.green);
    expect(classify(135.0, NutrientType.carb, config), SignalZone.yellow);
    expect(classify(135.01, NutrientType.carb, config), SignalZone.red);
  });

  test('U19 脂肪边界：55.0 黄 / 80.0 绿 / 110.0 绿 / 130.0 黄', () {
    expect(classify(54.99, NutrientType.fat, config), SignalZone.red);
    expect(classify(55.0, NutrientType.fat, config), SignalZone.yellow);
    expect(classify(80.0, NutrientType.fat, config), SignalZone.green);
    expect(classify(110.0, NutrientType.fat, config), SignalZone.green);
    expect(classify(130.0, NutrientType.fat, config), SignalZone.yellow);
    expect(classify(130.01, NutrientType.fat, config), SignalZone.red);
  });

  test('U20 p 不预取整：84.6 必须判黄（不得因四舍五入变绿）', () {
    expect(classify(84.6, NutrientType.kcal, config), SignalZone.yellow);
  });

  test('U21 当日 0 条 FoodEntry → 不产出信号灯（§3.2）', () {
    const goal = NutritionGoal(
      bmr: null,
      tdee: null,
      targetKcal: 1800,
      proteinG: 113,
      carbG: 203,
      fatG: 60,
      usedFallback: true,
      configVersion: '1.0.0',
    );
    const intake = DailyIntake(
      entryCount: 0,
      kcal: 0,
      proteinG: 0,
      carbG: 0,
      fatG: 0,
    );
    final result = evaluateDailySignals(intake, goal, config);
    expect(result.hasData, isFalse);
    expect(result.verdicts, isEmpty);
    expect(result.adviceKeys, isEmpty);
  });

  test('U22 有记录但脂肪=0 → 红-低 + zero 文案 key（§3.2/§4.4）', () {
    const goal = NutritionGoal(
      bmr: null,
      tdee: null,
      targetKcal: 1800,
      proteinG: 113,
      carbG: 203,
      fatG: 60,
      usedFallback: true,
      configVersion: '1.0.0',
    );
    const intake = DailyIntake(
      entryCount: 1,
      kcal: 500,
      proteinG: 30,
      carbG: 60,
      fatG: 0, // 记了食物但脂肪为 0
    );
    final result = evaluateDailySignals(intake, goal, config);
    expect(result.hasData, isTrue);
    // p=0 落红区低侧
    expect(result.verdicts[NutrientType.fat]!.zone, SignalZone.red);
    expect(result.verdicts[NutrientType.fat]!.subZone, SignalSubZone.redLow);
    // 文案用「还没记到」语义
    expect(result.adviceKeys, contains('nutrition.signalCard.advice.fat.zero'));
  });
}
