import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/record/domain/food_signal.dart';
import 'package:flutter_test/flutter_test.dart';

/// 食物级红绿灯纯函数测试（阶段 E：复用 D-05 阈值 classifyVerdict，
/// 聚合只取高侧落区——低侧对单个食物不构成警告）。
void main() {
  // 兜底口径目标：2000 kcal（D-04 §1.6 未知兜底），P125/C225/F67 g。
  const goal = NutritionGoal(
    bmr: null,
    tdee: null,
    targetKcal: 2000,
    proteinG: 125,
    carbG: 225,
    fatG: 67,
    usedFallback: true,
    configVersion: '1.0.0',
  );
  const config = NutritionRuleConfig.defaults;

  SignalVerdict evaluate({
    double kcal = 0,
    double protein = 0,
    double carb = 0,
    double fat = 0,
  }) {
    return evaluateFoodSignal(
      kcalPer100g: kcal,
      proteinPer100g: protein,
      carbPer100g: carb,
      fatPer100g: fat,
      goal: goal,
      config: config,
    );
  }

  test('普通食物（白米饭 116kcal）：各 p 远低于高侧边界 → 绿', () {
    final v = evaluate(kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3);
    expect(v.zone, SignalZone.green);
  });

  test('低侧落区不产生警告：零热量食物 → 绿（红色只表警告）', () {
    // 所有 p = 0 → classify 均为 redLow，但食物徽标不得因此标红。
    final v = evaluate();
    expect(v.zone, SignalZone.green);
  });

  test('单一营养素高侧黄：脂肪 p ∈ (110,130] → 黄', () {
    // 脂肪目标 67g，80g/100g → p = 119.4 → yellowHigh。
    final v = evaluate(fat: 80);
    expect(v.zone, SignalZone.yellow);
    expect(v.subZone, SignalSubZone.yellowHigh);
  });

  test('单一营养素高侧红：脂肪 p > 130 → 红', () {
    // 脂肪目标 67g，99g/100g（猪油级）→ p = 147.8 → redHigh。
    final v = evaluate(fat: 99);
    expect(v.zone, SignalZone.red);
  });

  test('热量高侧红：kcal p > 130 → 红', () {
    // 目标 2000，2700 kcal/100g → p = 135 → redHigh。
    final v = evaluate(kcal: 2700);
    expect(v.zone, SignalZone.red);
  });

  test('蛋白质过量标红沿用 redOver（p > 150 → 红）', () {
    // 蛋白目标 125g，190g/100g → p = 152 → redOver。
    final v = evaluate(protein: 190);
    expect(v.zone, SignalZone.red);
  });

  test('边界：p 恰为 redHigh（130.0）仍是黄（开区间规则与 D-05 一致）', () {
    // 脂肪目标 67g：87.1g → p = 130.0 恰好 → yellowHigh（p>130 才红）。
    final v = evaluate(fat: 87.1);
    expect(v.zone, SignalZone.yellow);
  });

  test('任一营养素高侧红即红（多营养素取最重）', () {
    // 热量绿区、脂肪红区 → 红。
    final v = evaluate(kcal: 1900, fat: 99);
    expect(v.zone, SignalZone.red);
  });

  test('目标为 0 的防御：不除零，按 p=0 处理（不产生警告）', () {
    const zeroGoal = NutritionGoal(
      bmr: null,
      tdee: null,
      targetKcal: 0,
      proteinG: 0,
      carbG: 0,
      fatG: 0,
      usedFallback: true,
      configVersion: '1.0.0',
    );
    final v = evaluateFoodSignal(
      kcalPer100g: 900,
      proteinPer100g: 99,
      carbPer100g: 99,
      fatPer100g: 99,
      goal: zeroGoal,
      config: config,
    );
    expect(v.zone, SignalZone.green);
  });
}
