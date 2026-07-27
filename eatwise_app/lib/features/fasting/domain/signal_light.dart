import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';

/// 红黄绿信号灯判定纯函数（《规格-营养规则》§3，D-05）。
///
/// 判定量 p = 当日累计摄入 ÷ 当日目标 × 100，**未取整原始值**参与比较，
/// 禁止先取整再比较（避免 84.6 → 85 误判为绿，§3.1 / U20）。

/// 信号灯判定（§1.7 接口）：返回三色落区。
SignalZone classify(
  double p,
  NutrientType nutrient,
  NutritionRuleConfig config,
) {
  return classifyVerdict(p, nutrient, config).zone;
}

/// 信号灯判定（含细分方向，供建议模板 key 映射）。
///
/// 闭区间边界规则（§3.1）：
/// - 绿区两端闭端点（如热量 p=85.0、p=110.0 均为绿）；
/// - 绿→黄上边界开、黄→红上边界闭（p=130.0 为黄，p>130 才为红）；
/// - 低侧对称（p<60 红、p=60.0 黄、p=85.0 绿）；
/// - 蛋白质独有「过量标红」（p=150.0 绿，p>150 红）。
SignalVerdict classifyVerdict(
  double p,
  NutrientType nutrient,
  NutritionRuleConfig config,
) {
  final t = config.thresholds[nutrient]!;
  // 过量标红（仅蛋白质，redLowOver 不含）
  final over = t.redLowOver;
  if (over != null && p > over) {
    return const SignalVerdict(
      zone: SignalZone.red,
      subZone: SignalSubZone.redOver,
    );
  }
  // 低侧红
  if (p < t.yellowLow) {
    return const SignalVerdict(
      zone: SignalZone.red,
      subZone: SignalSubZone.redLow,
    );
  }
  // 高侧红（redHigh 不含）
  if (p > t.redHigh) {
    return const SignalVerdict(
      zone: SignalZone.red,
      subZone: SignalSubZone.redHigh,
    );
  }
  // 绿区（双闭）
  if (p >= t.greenLow && p <= t.greenHigh) {
    return const SignalVerdict(
      zone: SignalZone.green,
      subZone: SignalSubZone.green,
    );
  }
  // 黄区（细分低/高；蛋白质无黄-高区，由上界判定自然跳过）
  if (p < t.greenLow) {
    return const SignalVerdict(
      zone: SignalZone.yellow,
      subZone: SignalSubZone.yellowLow,
    );
  }
  return const SignalVerdict(
    zone: SignalZone.yellow,
    subZone: SignalSubZone.yellowHigh,
  );
}
