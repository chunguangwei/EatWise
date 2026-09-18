/// 运动目标（薄荷走查 P2：消耗目标环 + 步数目标）领域层。
///
/// 纯展示口径：目标只用于数据页「今日消耗」卡的进度呈现，
/// 不参与营养目标/信号灯判定，也不上传服务端（本地偏好）。
library;

/// 每日运动目标（消耗 + 步数；默认值对标薄荷步数页 5000 步）。
final class ExerciseGoals {
  const ExerciseGoals({
    this.burnGoalKcal = defaultBurnGoalKcal,
    this.stepsGoal = defaultStepsGoal,
  });

  /// 每日活动消耗目标（kcal，默认 200〔假设：轻量活动基线，待营养背书〕）。
  final double burnGoalKcal;

  /// 每日步数目标（步，默认 5000，对标薄荷步数页）。
  final int stepsGoal;

  static const double defaultBurnGoalKcal = 200;
  static const int defaultStepsGoal = 5000;

  /// 可设区间（防误输〔假设〕）：消耗 50–5000 kcal，步数 500–100000 步。
  static const double minBurnGoalKcal = 50;
  static const double maxBurnGoalKcal = 5000;
  static const int minStepsGoal = 500;
  static const int maxStepsGoal = 100000;

  ExerciseGoals copyWith({double? burnGoalKcal, int? stepsGoal}) {
    return ExerciseGoals(
      burnGoalKcal: burnGoalKcal ?? this.burnGoalKcal,
      stepsGoal: stepsGoal ?? this.stepsGoal,
    );
  }

  static bool isValidBurnGoal(double kcal) =>
      kcal >= minBurnGoalKcal && kcal <= maxBurnGoalKcal;

  static bool isValidStepsGoal(int steps) =>
      steps >= minStepsGoal && steps <= maxStepsGoal;
}

/// 目标进度 0..1（环弧长用；超目标只封顶弧长，文案仍展示真实 X/目标 Y）。
double exerciseGoalProgress({required double value, required double goal}) {
  if (goal <= 0) return 0;
  if (value <= 0) return 0;
  return (value / goal).clamp(0.0, 1.0);
}
