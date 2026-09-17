import 'package:eatwise/features/fasting/domain/fasting_types.dart';

/// 减重速率→热量缺口纯函数（阶段 B，《规格-营养规则》缺口法章节，叠加 D-04）。
///
/// 纯函数：无 I/O、无时钟依赖（today 由调用方注入）、无副作用。
/// 与服务端 `nutrition.rules.ts` 的 `computeWeightLossPlan` 同口径。
/// 整体状态〔待外部确认：营养专业侧书面背书〕。

/// 1 kg 体脂 ≈ 7700 kcal。
const double kKcalPerKgBodyWeight = 7700;

/// 周减重速率安全上限（kg/周）。
const double kWeeklyRateMaxKg = 1.0;

/// 周减重速率下限（kg/周）：低于此按 0.1 计（避免无意义的小缺口）。
const double kWeeklyRateMinKg = 0.1;

/// 进食障碍筛查「是」的温和节奏上限（kg/周）。
const double kGentleWeeklyRateMaxKg = 0.5;

/// 缺口法计算结果。
final class WeightLossPlan {
  const WeightLossPlan({
    required this.weeklyRateKg,
    required this.dailyDeficitKcal,
    required this.targetKcal,
    required this.clamped,
    required this.reachDate,
  });

  /// 周减重速率（kg/周，夹取到 [kWeeklyRateMinKg, 上限]）。
  final double weeklyRateKg;

  /// 日热量缺口（kcal）= weeklyRateKg × 7700 ÷ 7。
  final double dailyDeficitKcal;

  /// 缺口法每日热量目标（kcal，含下限保护，未取整——取整由调用方统一做）。
  final double targetKcal;

  /// 原始速率超安全上限被夹取（UI 提示「已按安全上限调整」）。
  final bool clamped;

  /// 预计达成日期（按夹取后速率折算；被夹取时晚于目标日期）。
  final LocalDate reachDate;

  @override
  String toString() =>
      'WeightLossPlan(${weeklyRateKg}kg/周, 缺口$dailyDeficitKcal, '
      'target=$targetKcal, clamped=$clamped, reach=$reachDate)';
}

/// 两个本地日之间的天数（to − from；经 UTC 日期算术，与时区无关）。
int daysBetweenLocalDate(LocalDate from, LocalDate to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// 减重目标 → 每周速率 / 日缺口 / 目标热量。
///
/// 生效条件（任一不满足返回 null，调用方回落 D-04 固定 ×0.8）：
/// - [targetWeightKg] / [targetDate] 齐备；
/// - 目标体重 < 当前体重（增重/维持不走缺口法）；
/// - 目标日期为 [today] 之后的未来日期。
///
/// 规则：weeklyRate = 体重差 ÷ 周数，夹取到 [kWeeklyRateMinKg]–
/// （[gentle] 时 [kGentleWeeklyRateMaxKg]，否则 [kWeeklyRateMaxKg]）；
/// targetKcal = tdee − dailyDeficit，且不破 [minKcal] 下限保护
/// （复用 D-04 既有下限常量，由调用方按性别传入）。
WeightLossPlan? computeWeightLossPlan({
  required double currentWeightKg,
  required double? targetWeightKg,
  required LocalDate? targetDate,
  required LocalDate today,
  required double tdee,
  required double minKcal,
  bool gentle = false,
}) {
  if (targetWeightKg == null || targetDate == null) return null;
  if (targetWeightKg >= currentWeightKg) return null;
  final daysToTarget = daysBetweenLocalDate(today, targetDate);
  if (daysToTarget <= 0) return null;

  final deltaKg = currentWeightKg - targetWeightKg;
  final rawRate = deltaKg / (daysToTarget / 7);
  final maxRate = gentle ? kGentleWeeklyRateMaxKg : kWeeklyRateMaxKg;
  final clamped = rawRate > maxRate;
  final weeklyRateKg = rawRate.clamp(kWeeklyRateMinKg, maxRate);
  final dailyDeficitKcal = weeklyRateKg * kKcalPerKgBodyWeight / 7;
  final targetKcal = (tdee - dailyDeficitKcal) < minKcal
      ? minKcal
      : tdee - dailyDeficitKcal;
  final daysToReach = (deltaKg / weeklyRateKg * 7).ceil();
  return WeightLossPlan(
    weeklyRateKg: weeklyRateKg,
    dailyDeficitKcal: dailyDeficitKcal,
    targetKcal: targetKcal,
    clamped: clamped,
    reachDate: today.addDays(daysToReach),
  );
}
