/// 营养规则类型定义（《规格-营养规则-TDEE公式与信号灯阈值》，D-04/D-05）。
///
/// 整体状态〔待外部确认：营养专业侧书面背书〕，数值变更只走热配置。

/// 生理性别（仅用于 Mifflin-St Jeor 公式）。
library;

enum Sex { male, female }

/// 活动水平（§1.3 系数表）。
enum ActivityLevel { sedentary, light, moderate, high }

/// 用户目标（§1.4：lose 减脂 ×0.8；maintain 维持/作息/先试试看 ×1.0）。
enum NutritionGoalType { lose, maintain }

/// 营养素类型（信号灯判定维度）。
enum NutrientType { kcal, protein, carb, fat }

/// 信号灯落区（§3：绿=达标 / 黄=提醒 / 红=警示，三重编码语义全局固定）。
enum SignalZone { green, yellow, red }

/// 细分落区（建议模板 key 映射用，§4.2：热量/碳水/脂肪黄区拆低/高，
/// 蛋白质红区拆低/过量）。
enum SignalSubZone { green, yellowLow, yellowHigh, redLow, redHigh, redOver }

/// 信号灯判定结果（`classify` 输出）。
final class SignalVerdict {
  const SignalVerdict({required this.zone, required this.subZone});

  /// 三色落区。
  final SignalZone zone;

  /// 细分落区（方向），用于映射建议模板 key。
  final SignalSubZone subZone;

  @override
  bool operator ==(Object other) =>
      other is SignalVerdict && other.zone == zone && other.subZone == subZone;

  @override
  int get hashCode => Object.hash(zone, subZone);

  @override
  String toString() => 'SignalVerdict($zone/$subZone)';
}
