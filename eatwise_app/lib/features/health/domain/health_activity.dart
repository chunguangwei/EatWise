/// 阶段 D：HealthKit / Health Connect 运动数据接入（D-19 翻案）领域层。
///
/// 边界（与合规方案一致）：系统健康数据只在本机读取、本机展示，
/// 不上传服务端、不落盘持久化（同意记录除外）。
library;

/// 今日活动摘要（系统健康数据源；字段可空 = 该类型无数据或未授权该项）。
final class HealthTodaySummary {
  const HealthTodaySummary({
    this.steps,
    this.activeEnergyKcal,
    this.latestWeightKg,
  });

  /// 今日累计步数。
  final int? steps;

  /// 今日活动能量消耗（kcal，不含静息代谢）。
  final double? activeEnergyKcal;

  /// 最近一次体重记录（kg；仅展示 + 一键填入体重记录，不自动入账）。
  final double? latestWeightKg;

  bool get isEmpty =>
      steps == null && activeEnergyKcal == null && latestWeightKg == null;

  /// 展示用活动消耗（kcal）：系统活动能量优先，缺失时按步数粗估兜底。
  double? get displayBurnKcal {
    final energy = activeEnergyKcal;
    if (energy != null) return energy;
    final s = steps;
    if (s == null) return null;
    return estimateKcalFromSteps(s);
  }
}

/// 步数 → 活动消耗粗估（kcal，备用换算：系统未提供活动能量时兜底）。
///
/// 〔假设：步行约 0.53 kcal/kg/km × 平均步幅 0.75 m ≈ 0.0004 kcal/kg/步，
/// 待营养背书〕默认体重取 60 kg 中性值，结果仅供展示参考，不参与入账。
double estimateKcalFromSteps(int steps, {double weightKg = 60}) {
  if (steps <= 0) return 0;
  return steps * 0.0004 * weightKg;
}

/// 摄入 − 消耗结余（kcal；正 = 盈余，负 = 缺口）。
double energyBalanceKcal({
  required double intakeKcal,
  required double burnKcal,
}) {
  return intakeKcal - burnKcal;
}
