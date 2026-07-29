import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart'
    show dateOnly, localDateOf;

/// M6 数据趋势与深度报告：纯函数聚合层（无依赖注入，直接可单测）。
///
/// 数据口径：
/// - 热量：DailyNutritionCaches（本地预估，entryCount>0 才计为记录日）；
/// - 断食时长：FastingRecords 按归属日（D-07 冻结口径，跨自然日结算不串日）；
/// - 体重：轻量体重日志（record 模块录入入口〔遗留〕，本模块定义存储端口）。

/// 把 `byDate`（yyyy-MM-dd → 数值）对齐成长度为 [days]、以 [end] 为终点的
/// 日序列；无数据日为 null（趋势图断点，不连线）。
List<double?> alignDailySeries({
  required DateTime end,
  required int days,
  required Map<String, double> byDate,
}) {
  final last = dateOnly(end);
  return List<double?>.generate(days, (i) {
    final date = localDateOf(last.subtract(Duration(days: days - 1 - i)));
    return byDate[date];
  });
}

/// 7/30 天成长轨迹摘要（信息图 ⑦）。
final class GrowthSummary {
  const GrowthSummary({
    required this.days,
    required this.qualifiedDays,
    required this.recordedDays,
    required this.avgFastingHours,
    required this.weightDeltaKg,
  });

  /// 窗口天数（7 或 30）。
  final int days;

  /// 断食达标天数（D-08 口径）。
  final int qualifiedDays;

  /// 有饮食记录的天数。
  final int recordedDays;

  /// 平均断食时长（小时；窗口内无断食记录为 null）。
  final double? avgFastingHours;

  /// 体重变化 Δ = 窗口内最后一次称重 − 第一次称重（kg；不足两次为 null）。
  final double? weightDeltaKg;

  /// 是否有任一维度数据（全无 → 整卡走空态引导）。
  bool get hasData =>
      qualifiedDays > 0 ||
      recordedDays > 0 ||
      avgFastingHours != null ||
      weightDeltaKg != null;
}

/// 计算成长轨迹摘要。
///
/// [fastingHoursByDate] 归属日 → 实际断食小时；[qualifiedDates] 达标归属日；
/// [entryCountByDate] 归属日 → 饮食记录条数；[weightByDate] 归属日 → 体重 kg。
GrowthSummary computeGrowthSummary({
  required DateTime end,
  required int days,
  required Map<String, double> fastingHoursByDate,
  required Set<String> qualifiedDates,
  required Map<String, int> entryCountByDate,
  required Map<String, double> weightByDate,
}) {
  final last = dateOnly(end);
  final first = last.subtract(Duration(days: days - 1));

  var qualified = 0;
  var recorded = 0;
  var fastingSum = 0.0;
  var fastingCount = 0;
  DateTime? firstWeighDay;
  DateTime? lastWeighDay;

  for (var i = 0; i < days; i++) {
    final day = first.add(Duration(days: i));
    final key = localDateOf(day);
    if (qualifiedDates.contains(key)) qualified++;
    if ((entryCountByDate[key] ?? 0) > 0) recorded++;
    final hours = fastingHoursByDate[key];
    if (hours != null) {
      fastingSum += hours;
      fastingCount++;
    }
    if (weightByDate.containsKey(key)) {
      firstWeighDay ??= day;
      lastWeighDay = day;
    }
  }

  double? delta;
  if (firstWeighDay != null &&
      lastWeighDay != null &&
      !firstWeighDay.isAtSameMomentAs(lastWeighDay)) {
    delta =
        weightByDate[localDateOf(lastWeighDay)]! -
        weightByDate[localDateOf(firstWeighDay)]!;
  }

  return GrowthSummary(
    days: days,
    qualifiedDays: qualified,
    recordedDays: recorded,
    avgFastingHours: fastingCount == 0 ? null : fastingSum / fastingCount,
    weightDeltaKg: delta,
  );
}

/// 自然周（周一为起点）报告统计〔PRD M6 周期报告·假设〕。
final class WeeklyReportStats {
  const WeeklyReportStats({
    required this.weekStart,
    required this.weekEnd,
    required this.qualifiedDays,
    required this.entryCount,
    required this.greenRatio,
  });

  /// 本周一（本地日期）。
  final DateTime weekStart;

  /// 统计截止日（周日或今天，取较早者——本周未过完不做未来统计）。
  final DateTime weekEnd;

  /// 本周断食达标天数。
  final int qualifiedDays;

  /// 本周饮食记录总条数。
  final int entryCount;

  /// 信号灯绿灯占比（所有记录日四项判定中绿区占比；无记录日为 null）。
  final double? greenRatio;

  /// 是否有数据（无 → 周报卡走空态引导）。
  bool get hasData => qualifiedDays > 0 || entryCount > 0;
}

/// 计算自然周（周一～周日）报告统计。
///
/// 绿占比：对每个有记录的归属日跑 `evaluateDailySignals`（D-05 阈值），
/// 汇总四项判定中绿区数量 / 总判定数。
WeeklyReportStats computeWeeklyReport({
  required DateTime now,
  required Map<String, DailyIntake> intakeByDate,
  required Set<String> qualifiedDates,
  required NutritionGoal goal,
  NutritionRuleConfig config = NutritionRuleConfig.defaults,
}) {
  final today = dateOnly(now);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final sunday = weekStart.add(const Duration(days: 6));
  final weekEnd = sunday.isAfter(today) ? today : sunday;

  var qualified = 0;
  var entries = 0;
  var green = 0;
  var judged = 0;

  for (
    var day = weekStart;
    !day.isAfter(weekEnd);
    day = day.add(const Duration(days: 1))
  ) {
    final key = localDateOf(day);
    if (qualifiedDates.contains(key)) qualified++;
    final intake = intakeByDate[key];
    if (intake == null || intake.entryCount == 0) continue;
    entries += intake.entryCount;
    final signal = evaluateDailySignals(intake, goal, config);
    for (final verdict in signal.verdicts.values) {
      judged++;
      if (verdict.zone == SignalZone.green) green++;
    }
  }

  return WeeklyReportStats(
    weekStart: weekStart,
    weekEnd: weekEnd,
    qualifiedDays: qualified,
    entryCount: entries,
    greenRatio: judged == 0 ? null : green / judged,
  );
}
