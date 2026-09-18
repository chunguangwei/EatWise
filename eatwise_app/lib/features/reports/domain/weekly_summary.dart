import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart'
    show dateOnly, localDateOf;

/// 「上周小结」纯函数层（薄荷走查 P1，对标薄荷「上周状态分」形态）：
/// 本地数据统计 → 模板化 2–3 句总结。**不调用任何模型**、不给医疗建议，
/// 仅做事实陈述；展示层固定追加「仅供健康生活方式参考」。
///
/// 数据口径与 M6 报告一致：热量/记录天数来自 DailyNutritionCaches
///（entryCount>0 才计为记录日），断食达标按归属日（D-07/D-08），
/// 体重来自轻量体重日志。上周 = 上一个完整自然周（周一～周日）。

/// 上周小结统计。
final class WeeklySummary {
  const WeeklySummary({
    required this.weekStart,
    required this.weekEnd,
    required this.qualifiedDays,
    required this.prevQualifiedDays,
    required this.recordedDays,
    required this.avgKcal,
    required this.targetKcal,
    required this.weightDeltaKg,
  });

  /// 上周一（本地日期）。
  final DateTime weekStart;

  /// 上周日（本地日期）。
  final DateTime weekEnd;

  /// 上周断食达标天数（D-08 口径）。
  final int qualifiedDays;

  /// 前周断食达标天数（用于环比句式；前周无达标时不做环比）。
  final int prevQualifiedDays;

  /// 上周有饮食记录的天数。
  final int recordedDays;

  /// 上周记录日平均每日摄入（kcal；无记录日为 null）。
  final double? avgKcal;

  /// 目标热量（kcal，来自 NutritionGoal）。
  final int targetKcal;

  /// 上周体重变化 Δ = 最后一次称重 − 第一次称重（kg；不足两次为 null）。
  final double? weightDeltaKg;

  /// 是否有数据（上周 0 记录 → 走「先记录几天」引导文案）。
  bool get hasData => recordedDays > 0 || qualifiedDays > 0;
}

/// 计算上周小结。
///
/// [now] 当前时间（只取本地日期）；[kcalByDate] 归属日 → 当日摄入 kcal
///（仅记录日）；[qualifiedDates] 达标归属日集合（需覆盖前周～上周，
/// 供环比取数）；[weightByDate] 归属日 → 体重 kg（上周范围）；
/// [targetKcal] 目标热量。
WeeklySummary computeWeeklySummary({
  required DateTime now,
  required Map<String, double> kcalByDate,
  required Set<String> qualifiedDates,
  required Map<String, double> weightByDate,
  required int targetKcal,
}) {
  final today = dateOnly(now);
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final weekStart = thisMonday.subtract(const Duration(days: 7));
  final weekEnd = thisMonday.subtract(const Duration(days: 1));
  final prevStart = weekStart.subtract(const Duration(days: 7));

  var qualified = 0;
  var prevQualified = 0;
  var recorded = 0;
  var kcalSum = 0.0;
  DateTime? firstWeighDay;
  DateTime? lastWeighDay;

  for (var i = 0; i < 7; i++) {
    final day = weekStart.add(Duration(days: i));
    final key = localDateOf(day);
    if (qualifiedDates.contains(key)) qualified++;
    if (qualifiedDates.contains(
      localDateOf(prevStart.add(Duration(days: i))),
    )) {
      prevQualified++;
    }
    final kcal = kcalByDate[key];
    if (kcal != null) {
      recorded++;
      kcalSum += kcal;
    }
    if (weightByDate.containsKey(key)) {
      firstWeighDay ??= day;
      lastWeighDay = day;
    }
  }

  double? weightDelta;
  if (firstWeighDay != null &&
      lastWeighDay != null &&
      !firstWeighDay.isAtSameMomentAs(lastWeighDay)) {
    weightDelta =
        weightByDate[localDateOf(lastWeighDay)]! -
        weightByDate[localDateOf(firstWeighDay)]!;
  }

  return WeeklySummary(
    weekStart: weekStart,
    weekEnd: weekEnd,
    qualifiedDays: qualified,
    prevQualifiedDays: prevQualified,
    recordedDays: recorded,
    avgKcal: recorded == 0 ? null : kcalSum / recorded,
    targetKcal: targetKcal,
    weightDeltaKg: weightDelta,
  );
}

/// 模板句类型（展示层按类型 + 统计值取 i18n 文案；保证句型集合可穷举测试）。
enum WeeklySummarySentence {
  /// 上周断食达标 N 天（前周无达标，不环比）。
  fastingPlain,

  /// …，比前周多 N 天。
  fastingMore,

  /// …，比前周少 N 天。
  fastingLess,

  /// …，与前周持平。
  fastingSame,

  /// 平均每日摄入 X 千卡，在目标范围内。
  intakeWithin,

  /// …，比目标高 P%。
  intakeAbove,

  /// …，比目标低 P%。
  intakeBelow,

  /// 体重上升 X 公斤。
  weightUp,

  /// 体重下降 X 公斤。
  weightDown,

  /// 体重基本持平。
  weightSame,
}

/// 平均摄入在目标 ±10% 以内视为「在目标范围内」（模板阈值，待营养背书）。
const double weeklySummaryIntakeTolerance = 0.10;

/// 体重变化绝对值小于 0.1 kg 视为「基本持平」（展示精度即 0.1 kg）。
const double weeklySummaryWeightEpsilon = 0.1;

/// 按统计值挑选 1–3 句模板句（顺序：断食 → 摄入 → 体重）。
///
/// 调用方保证 [summary].hasData 为 true（无数据走引导文案，不进模板）。
List<WeeklySummarySentence> weeklySummarySentences(WeeklySummary summary) {
  final sentences = <WeeklySummarySentence>[];

  // 断食句必有（hasData 也可能是纯饮食记录，此时达标 0 天照实陈述）。
  final delta = summary.qualifiedDays - summary.prevQualifiedDays;
  if (summary.prevQualifiedDays == 0) {
    sentences.add(WeeklySummarySentence.fastingPlain);
  } else if (delta > 0) {
    sentences.add(WeeklySummarySentence.fastingMore);
  } else if (delta < 0) {
    sentences.add(WeeklySummarySentence.fastingLess);
  } else {
    sentences.add(WeeklySummarySentence.fastingSame);
  }

  final avgKcal = summary.avgKcal;
  if (avgKcal != null) {
    final deviation = (avgKcal - summary.targetKcal) / summary.targetKcal;
    if (deviation.abs() <= weeklySummaryIntakeTolerance) {
      sentences.add(WeeklySummarySentence.intakeWithin);
    } else if (deviation > 0) {
      sentences.add(WeeklySummarySentence.intakeAbove);
    } else {
      sentences.add(WeeklySummarySentence.intakeBelow);
    }
  }

  final weightDelta = summary.weightDeltaKg;
  if (weightDelta != null) {
    if (weightDelta.abs() < weeklySummaryWeightEpsilon) {
      sentences.add(WeeklySummarySentence.weightSame);
    } else if (weightDelta > 0) {
      sentences.add(WeeklySummarySentence.weightUp);
    } else {
      sentences.add(WeeklySummarySentence.weightDown);
    }
  }

  return sentences;
}

/// 平均摄入偏离目标的百分比（四舍五入取整；intakeAbove/intakeBelow 句用）。
int weeklySummaryIntakeDeviationPercent(WeeklySummary summary) {
  final avgKcal = summary.avgKcal;
  if (avgKcal == null) return 0;
  return ((avgKcal - summary.targetKcal).abs() / summary.targetKcal * 100)
      .round();
}
