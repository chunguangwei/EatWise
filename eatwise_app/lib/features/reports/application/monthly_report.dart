import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart'
    show dateOnly, localDateOf;

/// M6 月报卡片（轻量版，2026-09-07 拍板范围）：自然月统计纯函数，
/// 无 I/O、无时钟依赖，直接可单测。数据源口径与周报（report_aggregation）
/// 一致：热量/记录天数来自 DailyNutritionCaches（entryCount>0 才计为记录日），
/// 断食时长/达标按归属日（D-07 冻结、D-08 达标口径），体重来自轻量体重日志。

/// 自然月报告统计。
final class MonthlyReport {
  const MonthlyReport({
    required this.year,
    required this.month,
    required this.qualifiedDays,
    required this.avgFastedMinutes,
    required this.avgKcal,
    required this.avgProteinG,
    required this.avgCarbsG,
    required this.avgFatG,
    required this.targetKcal,
    required this.weightChangeKg,
    required this.daysWithRecords,
    required this.weighDays,
  });

  /// 报告所属年。
  final int year;

  /// 报告所属月（1–12）。
  final int month;

  /// 断食打卡达标天数（D-08 口径）。
  final int qualifiedDays;

  /// 平均断食时长（分钟；月内无断食记录为 null）。
  final double? avgFastedMinutes;

  /// 有饮食记录日均热量（kcal；无饮食记录日为 null）。
  final double? avgKcal;

  /// 有饮食记录日均蛋白质（g；无饮食记录日为 null）。
  final double? avgProteinG;

  /// 有饮食记录日均碳水（g；无饮食记录日为 null）。
  final double? avgCarbsG;

  /// 有饮食记录日均脂肪（g；无饮食记录日为 null）。
  final double? avgFatG;

  /// 目标热量（kcal，来自 [NutritionGoal]）。
  final int targetKcal;

  /// 体重变化 Δ = 月内最后一次称重 − 第一次称重（kg；不足两次为 null）。
  final double? weightChangeKg;

  /// 有任一记记录的天数（饮食记录或断食记录）。
  final int daysWithRecords;

  /// 月内有体重记录的天数。
  final int weighDays;

  /// 是否有任一维度数据（全无 → 月报卡走空态引导）。
  bool get hasData =>
      qualifiedDays > 0 ||
      daysWithRecords > 0 ||
      weighDays > 0 ||
      avgFastedMinutes != null ||
      weightChangeKg != null;
}

/// 计算自然月报告统计。
///
/// [month] 任取该月内一天（仅年月参与计算）；[fastingHoursByDate] 归属日 →
/// 实际断食小时；[qualifiedDates] 达标归属日；[intakeByDate] 归属日 → 当日
/// 摄入（entryCount>0 才计为记录日）；[weightByDate] 归属日 → 体重 kg。
MonthlyReport computeMonthlyReport({
  required DateTime month,
  required Map<String, double> fastingHoursByDate,
  required Set<String> qualifiedDates,
  required Map<String, DailyIntake> intakeByDate,
  required Map<String, double> weightByDate,
  required NutritionGoal goal,
}) {
  final first = DateTime(month.year, month.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

  var qualified = 0;
  var fastingSum = 0.0;
  var fastingCount = 0;
  var kcalSum = 0.0;
  var proteinSum = 0.0;
  var carbsSum = 0.0;
  var fatSum = 0.0;
  var nutritionDays = 0;
  var daysWithRecords = 0;
  var weighDays = 0;
  DateTime? firstWeighDay;
  DateTime? lastWeighDay;

  for (var i = 0; i < daysInMonth; i++) {
    final day = first.add(Duration(days: i));
    final key = localDateOf(day);
    if (qualifiedDates.contains(key)) qualified++;
    final hours = fastingHoursByDate[key];
    if (hours != null) {
      fastingSum += hours;
      fastingCount++;
    }
    final intake = intakeByDate[key];
    if (intake != null && intake.entryCount > 0) {
      nutritionDays++;
      kcalSum += intake.kcal;
      proteinSum += intake.proteinG;
      carbsSum += intake.carbG;
      fatSum += intake.fatG;
    }
    // 记录日：饮食记录与断食记录取并集，同一日只计一次。
    if (hours != null || (intake != null && intake.entryCount > 0)) {
      daysWithRecords++;
    }
    if (weightByDate.containsKey(key)) {
      weighDays++;
      firstWeighDay ??= day;
      lastWeighDay = day;
    }
  }

  double? weightDelta;
  if (firstWeighDay != null &&
      lastWeighDay != null &&
      !dateOnly(firstWeighDay).isAtSameMomentAs(dateOnly(lastWeighDay))) {
    weightDelta =
        weightByDate[localDateOf(lastWeighDay)]! -
        weightByDate[localDateOf(firstWeighDay)]!;
  }

  return MonthlyReport(
    year: month.year,
    month: month.month,
    qualifiedDays: qualified,
    avgFastedMinutes: fastingCount == 0 ? null : fastingSum / fastingCount * 60,
    avgKcal: nutritionDays == 0 ? null : kcalSum / nutritionDays,
    avgProteinG: nutritionDays == 0 ? null : proteinSum / nutritionDays,
    avgCarbsG: nutritionDays == 0 ? null : carbsSum / nutritionDays,
    avgFatG: nutritionDays == 0 ? null : fatSum / nutritionDays,
    targetKcal: goal.targetKcal,
    weightChangeKg: weightDelta,
    daysWithRecords: daysWithRecords,
    weighDays: weighDays,
  );
}
