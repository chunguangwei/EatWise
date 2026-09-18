/// 体重曲线解锁钩子（薄荷走查 P3：对标薄荷「记录 3 天体重，解锁曲线」引导）。
///
/// 体重记录数 < [kWeightCurveUnlockThreshold] 时，趋势图区域盖半透明遮罩 +
/// 「再记录 N 次体重，解锁完整曲线」；≥ 阈值正常展示曲线。纯函数/常量可测。
library;

/// 解锁完整体重曲线所需的最少记录条数（薄荷同款口径：3 条）。
const int kWeightCurveUnlockThreshold = 3;

/// 距解锁还差几条（已记录 ≥ 阈值返回 0，UI 据此决定盖不盖遮罩）。
int weightRecordsToUnlock(int recordedCount) {
  if (recordedCount < 0) return kWeightCurveUnlockThreshold;
  final remaining = kWeightCurveUnlockThreshold - recordedCount;
  return remaining > 0 ? remaining : 0;
}
