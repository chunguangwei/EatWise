import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/domain/signal_light.dart';

/// 食物级红绿灯评价纯函数（阶段 E 食物详情页徽标，薄荷对标合并设计：
/// 红灯尽量别吃 / 黄灯适量少吃 / 绿灯放心吃；红色语义只表警告，§3.3）。
///
/// 判定口径：p = 食物每 100g 营养值 ÷ 当日目标 × 100，逐营养素复用
/// D-05 阈值纯函数 [classifyVerdict]（不新增任何阈值数值，阈值调整仍只
/// 走服务端热配置）。
///
/// 聚合只取**高侧**落区：对单个食物而言，「占日预算比例偏低」不构成
/// 警告（红色只表警告），故 redLow / yellowLow 不参与徽标判定；
/// redHigh / redOver → 红，yellowHigh → 黄，其余 → 绿。
///
/// 〔已知局限〕D-05 阈值面向「当日完成率」标定，对每 100g 食物值的区分度
/// 弱——绝大多数食物的四个 p 都远低于高侧边界，徽标恒绿；薄荷式按
/// 热量密度的食物分级需新增阈值规格并过营养背书，列为阶段 E 遗留，
/// 此处不擅自新增数值。
SignalVerdict evaluateFoodSignal({
  required double kcalPer100g,
  required double proteinPer100g,
  required double carbPer100g,
  required double fatPer100g,
  required NutritionGoal goal,
  required NutritionRuleConfig config,
}) {
  double percentOf(double value, int target) =>
      target > 0 ? value / target * 100 : 0;
  final inputs = <NutrientType, double>{
    NutrientType.kcal: percentOf(kcalPer100g, goal.targetKcal),
    NutrientType.protein: percentOf(proteinPer100g, goal.proteinG),
    NutrientType.carb: percentOf(carbPer100g, goal.carbG),
    NutrientType.fat: percentOf(fatPer100g, goal.fatG),
  };
  var hasHighYellow = false;
  for (final entry in inputs.entries) {
    final verdict = classifyVerdict(entry.value, entry.key, config);
    switch (verdict.subZone) {
      case SignalSubZone.redHigh || SignalSubZone.redOver:
        return const SignalVerdict(
          zone: SignalZone.red,
          subZone: SignalSubZone.redHigh,
        );
      case SignalSubZone.yellowHigh:
        hasHighYellow = true;
      case SignalSubZone.green ||
          SignalSubZone.yellowLow ||
          SignalSubZone.redLow:
        break;
    }
  }
  if (hasHighYellow) {
    return const SignalVerdict(
      zone: SignalZone.yellow,
      subZone: SignalSubZone.yellowHigh,
    );
  }
  return const SignalVerdict(
    zone: SignalZone.green,
    subZone: SignalSubZone.green,
  );
}
