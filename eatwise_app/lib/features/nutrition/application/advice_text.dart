import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';

/// 建议模板文案解析（《规格-营养规则》§4，D-05）：
/// 营养素 × 落区 × 餐段 → 模板库文案（中英双语，slang 类型化访问）。
///
/// 与 `adviceKeyFor`（key 映射，埋点/调试用）一一对应；零摄入营养素走
/// zero 专用文案（§4.4，无 `{meal_action}` 插值）。

/// 餐段模板文案（§4.3 `{meal_action}` 片段）。
String mealActionTextFor(Translations t, MealSegment segment) {
  final meal = t.nutrition.signalCard.advice.meal;
  return switch (segment) {
    MealSegment.breakfast => meal.breakfast,
    MealSegment.lunch => meal.lunch,
    MealSegment.dinner => meal.dinner,
    MealSegment.snack => meal.snack,
  };
}

/// 一句话建议文案（营养素 × 细分落区；zeroIntake 优先走 zero 文案）。
String adviceTextFor(
  Translations t, {
  required NutrientType nutrient,
  required SignalSubZone subZone,
  required bool zeroIntake,
  required String mealAction,
}) {
  final advice = t.nutrition.signalCard.advice;
  return switch (nutrient) {
    NutrientType.kcal => _kcal(advice, subZone, zeroIntake, mealAction),
    NutrientType.protein => _protein(advice, subZone, zeroIntake, mealAction),
    NutrientType.carb => _carb(advice, subZone, zeroIntake, mealAction),
    NutrientType.fat => _fat(advice, subZone, zeroIntake, mealAction),
  };
}

String _kcal(
  Translations$nutrition$signalCard$advice$zh_CN a,
  SignalSubZone z,
  bool zero,
  String meal,
) {
  if (zero) return a.kcal.zero;
  return switch (z) {
    SignalSubZone.green => a.kcal.green,
    SignalSubZone.yellowLow => a.kcal.yellowLow(meal_action: meal),
    SignalSubZone.yellowHigh => a.kcal.yellowHigh(meal_action: meal),
    SignalSubZone.redLow => a.kcal.redLow(meal_action: meal),
    SignalSubZone.redHigh ||
    SignalSubZone.redOver => a.kcal.redHigh(meal_action: meal),
  };
}

String _protein(
  Translations$nutrition$signalCard$advice$zh_CN a,
  SignalSubZone z,
  bool zero,
  String meal,
) {
  if (zero) return a.protein.zero;
  return switch (z) {
    SignalSubZone.green => a.protein.green,
    SignalSubZone.yellowLow => a.protein.yellowLow(meal_action: meal),
    // 蛋白质无黄-高区（D-05）；防御映射到 green 文案，不可达。
    SignalSubZone.yellowHigh => a.protein.green,
    SignalSubZone.redLow => a.protein.redLow(meal_action: meal),
    SignalSubZone.redHigh ||
    SignalSubZone.redOver => a.protein.redHigh(meal_action: meal),
  };
}

String _carb(
  Translations$nutrition$signalCard$advice$zh_CN a,
  SignalSubZone z,
  bool zero,
  String meal,
) {
  if (zero) return a.carb.zero;
  return switch (z) {
    SignalSubZone.green => a.carb.green,
    SignalSubZone.yellowLow => a.carb.yellowLow(meal_action: meal),
    SignalSubZone.yellowHigh => a.carb.yellowHigh(meal_action: meal),
    SignalSubZone.redLow => a.carb.redLow(meal_action: meal),
    SignalSubZone.redHigh ||
    SignalSubZone.redOver => a.carb.redHigh(meal_action: meal),
  };
}

String _fat(
  Translations$nutrition$signalCard$advice$zh_CN a,
  SignalSubZone z,
  bool zero,
  String meal,
) {
  if (zero) return a.fat.zero;
  return switch (z) {
    SignalSubZone.green => a.fat.green,
    SignalSubZone.yellowLow => a.fat.yellowLow(meal_action: meal),
    SignalSubZone.yellowHigh => a.fat.yellowHigh(meal_action: meal),
    SignalSubZone.redLow => a.fat.redLow(meal_action: meal),
    SignalSubZone.redHigh ||
    SignalSubZone.redOver => a.fat.redHigh(meal_action: meal),
  };
}
