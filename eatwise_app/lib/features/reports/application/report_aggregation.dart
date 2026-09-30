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

/// 断食趋势日状态（三态诚实区分 + 进行中第四态）。
///
/// 无记录 ≠ 断签：丢失/未断食的天一律 [noRecord]，只有存在终态记录且
/// 未达标才是 [unqualified]（判定口径不动，直接消费 FastingRecord.qualified）。
enum FastingDayState {
  /// 有终态记录且达标。
  qualified,

  /// 有终态记录但未达标。
  unqualified,

  /// 今天有进行中断食周期且尚无终态记录。
  inProgress,

  /// 无任何记录（数据缺失或当天未断食，明确不是断签）。
  noRecord,
}

/// 把断食记录对齐成长度为 [days]、以 [end]（今天）为终点的日状态序列。
///
/// [qualifiedByDate] 归属日（yyyy-MM-dd）→ 是否达标（仅终态记录，tombstone
/// 与进行中周期不进 map）；[inProgressDate] 进行中周期覆盖的日期（仅当该日
/// 无终态记录时生效，通常 = 今天）。
List<FastingDayState> alignFastingDayStates({
  required DateTime end,
  required int days,
  required Map<String, bool> qualifiedByDate,
  String? inProgressDate,
}) {
  final last = dateOnly(end);
  return List<FastingDayState>.generate(days, (i) {
    final key = localDateOf(last.subtract(Duration(days: days - 1 - i)));
    final qualified = qualifiedByDate[key];
    if (qualified != null) {
      return qualified
          ? FastingDayState.qualified
          : FastingDayState.unqualified;
    }
    if (key == inProgressDate) return FastingDayState.inProgress;
    return FastingDayState.noRecord;
  });
}

/// 趋势聚合粒度（2026-09-30 长期趋势）。
///
/// 长窗口逐日画点会把折线糊成噪声（365 个点挤在 300px 宽度里），
/// 因此 90 天按周聚合、365 天按自然月聚合；7/30 天保持逐日。
enum TrendBucket {
  /// 逐日（7/30 天窗口）。
  day,

  /// 按 7 日块聚合（90 天窗口；从窗口终点向前切块，末块必含今天）。
  week,

  /// 按自然月聚合（365 天窗口；首月可能不完整）。
  month,
}

/// 聚合后的一个趋势桶。
final class TrendPoint {
  const TrendPoint({
    required this.start,
    required this.end,
    required this.value,
    required this.recordedDays,
    required this.totalDays,
  });

  /// 桶起始日（含）。
  final DateTime start;

  /// 桶结束日（含）。
  final DateTime end;

  /// 桶内均值（仅对有数据的天求平均；全桶无数据为 null → 折线断点）。
  ///
  /// 用均值而非求和：均值在「桶天数不等」（首月不完整、末块不满 7 天）时
  /// 仍可横向比较，求和会让不完整桶凭空显得低。
  final double? value;

  /// 桶内有数据的天数。
  final int recordedDays;

  /// 桶覆盖的总天数。
  final int totalDays;
}

/// 把 `byDate` 按 [bucket] 粒度聚合成趋势点序列（末桶含 [end]）。
///
/// [days] 为窗口总天数；返回序列按时间升序。
List<TrendPoint> bucketDailySeries({
  required DateTime end,
  required int days,
  required Map<String, double> byDate,
  required TrendBucket bucket,
}) {
  final last = dateOnly(end);
  final first = last.subtract(Duration(days: days - 1));

  // 计算桶边界（升序的 [start, end] 闭区间列表）。
  final ranges = <({DateTime start, DateTime end})>[];
  switch (bucket) {
    case TrendBucket.day:
      for (var i = 0; i < days; i++) {
        final d = first.add(Duration(days: i));
        ranges.add((start: d, end: d));
      }
    case TrendBucket.week:
      // 从终点向前切 7 日块，保证末块结束于今天；首块可能不满 7 天。
      var blockEnd = last;
      while (!blockEnd.isBefore(first)) {
        final blockStart = blockEnd.subtract(const Duration(days: 6));
        ranges.add((
          start: blockStart.isBefore(first) ? first : blockStart,
          end: blockEnd,
        ));
        blockEnd = blockStart.subtract(const Duration(days: 1));
      }
      ranges.sort((a, b) => a.start.compareTo(b.start));
    case TrendBucket.month:
      var cursor = DateTime(first.year, first.month, 1);
      while (!cursor.isAfter(last)) {
        final monthEnd = DateTime(cursor.year, cursor.month + 1, 0);
        ranges.add((
          start: cursor.isBefore(first) ? first : cursor,
          end: monthEnd.isAfter(last) ? last : monthEnd,
        ));
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
  }

  return <TrendPoint>[
    for (final r in ranges) _aggregateRange(r.start, r.end, byDate),
  ];
}

TrendPoint _aggregateRange(
  DateTime start,
  DateTime end,
  Map<String, double> byDate,
) {
  var sum = 0.0;
  var count = 0;
  var total = 0;
  for (
    var day = start;
    !day.isAfter(end);
    day = day.add(const Duration(days: 1))
  ) {
    total++;
    final v = byDate[localDateOf(day)];
    if (v != null) {
      sum += v;
      count++;
    }
  }
  return TrendPoint(
    start: start,
    end: end,
    value: count == 0 ? null : sum / count,
    recordedDays: count,
    totalDays: total,
  );
}

/// 断食全生命周期统计（2026-09-30：补齐「长期数据」的总量视角）。
///
/// 趋势图回答「最近怎么样」，本统计回答「一共坚持了多少」——此前二者皆无，
/// 用户记了几个月断食也看不到任何累计成果。
final class FastingLifetimeStats {
  const FastingLifetimeStats({
    required this.totalRecords,
    required this.qualifiedDays,
    required this.totalHours,
    required this.longestSingleHours,
    required this.avgHours,
    required this.avgQualifiedHours,
    required this.firstRecordDate,
  });

  /// 终态记录总条数（不含 tombstone / 进行中）。
  final int totalRecords;

  /// 累计达标天数（D-08 口径）。
  final int qualifiedDays;

  /// 累计断食总时长（小时，含未达标记录的实际时长）。
  final double totalHours;

  /// 最长单次断食时长（小时；无记录为 null）。
  final double? longestSingleHours;

  /// 平均单次断食时长（小时，含未达标；无记录为 null）。
  final double? avgHours;

  /// 仅达标记录的平均时长（小时；无达标记录为 null）。
  ///
  /// 与 [avgHours] 并列给出：提前破窗的短时长会把 [avgHours] 拉低，
  /// 二者分开才不会让用户误读「我的断食能力在下降」。
  final double? avgQualifiedHours;

  /// 首条记录归属日（yyyy-MM-dd；无记录为 null）。
  final String? firstRecordDate;

  /// 历史达标率（0..1；无记录为 null）。
  double? get qualifiedRate =>
      totalRecords == 0 ? null : qualifiedDays / totalRecords;

  /// 是否有任何记录。
  bool get hasData => totalRecords > 0;
}

/// 计算断食全生命周期统计。
///
/// [hoursByDate] 归属日 → 实际断食小时（**仅真实断食**，调用方已剔除
/// tombstone、进行中与补签）；[qualifiedDates] 达标归属日集合；
/// [makeupDates] 补签归属日集合（计入记录数与达标数，不进任何时长口径）。
FastingLifetimeStats computeFastingLifetime({
  required Map<String, double> hoursByDate,
  required Set<String> qualifiedDates,
  Set<String> makeupDates = const <String>{},
}) {
  var total = 0.0;
  var longest = 0.0;
  var qualifiedSum = 0.0;
  var qualifiedCount = 0;
  String? firstDate;
  for (final entry in hoursByDate.entries) {
    total += entry.value;
    if (entry.value > longest) longest = entry.value;
    if (qualifiedDates.contains(entry.key)) {
      qualifiedSum += entry.value;
      qualifiedCount++;
    }
    if (firstDate == null || entry.key.compareTo(firstDate) < 0) {
      firstDate = entry.key;
    }
  }
  // 补签日：计入记录数与达标数，不进任何时长累计。与真实断食日取差集，
  // 避免同日既有真实记录又被补签时重复计数（否则达标率可能 >1）。
  final makeupOnly = makeupDates.difference(hoursByDate.keys.toSet());
  for (final d in makeupOnly) {
    if (firstDate == null || d.compareTo(firstDate) < 0) firstDate = d;
  }
  final realCount = hoursByDate.length;
  final totalRecords = realCount + makeupOnly.length;
  if (totalRecords == 0) {
    return const FastingLifetimeStats(
      totalRecords: 0,
      qualifiedDays: 0,
      totalHours: 0,
      longestSingleHours: null,
      avgHours: null,
      avgQualifiedHours: null,
      firstRecordDate: null,
    );
  }
  return FastingLifetimeStats(
    totalRecords: totalRecords,
    qualifiedDays: qualifiedCount + makeupOnly.length,
    totalHours: total,
    longestSingleHours: realCount == 0 ? null : longest,
    avgHours: realCount == 0 ? null : total / realCount,
    avgQualifiedHours: qualifiedCount == 0
        ? null
        : qualifiedSum / qualifiedCount,
    firstRecordDate: firstDate,
  );
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
