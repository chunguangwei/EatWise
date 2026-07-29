import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart'
    show nutritionGoalProvider;
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart'
    show dateOnly, localDateOf;
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M6 趋势与报告页（/data/reports）application 层：
/// 维度（体重/热量/断食时长）× 时间范围（7/30 天）切换 + 成长轨迹 + 周报。
///
/// 数据源：DailyNutritionCaches（热量/记录天数）、FastingRecords（断食时长与
/// 达标，按 D-07 归属日聚合）、[WeightLogStore]（体重轻量日志）。

/// 报告页时钟（测试可拨动；范围终点 = 今天，不看未来）。
final Provider<DateTime> reportsNowProvider = Provider<DateTime>((ref) {
  return DateTime.now();
});

/// 趋势时间范围。
enum ReportRange {
  d7(7),
  d30(30);

  const ReportRange(this.days);

  /// 窗口天数。
  final int days;
}

/// 趋势维度。
enum ReportDimension { weight, kcal, fasting }

/// 时间范围切换。
final NotifierProvider<ReportRangeController, ReportRange> reportRangeProvider =
    NotifierProvider<ReportRangeController, ReportRange>(
      ReportRangeController.new,
    );

/// 时间范围控制器（默认 7 天）。
class ReportRangeController extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.d7;

  /// 切换范围。
  void select(ReportRange range) => state = range;
}

/// 维度切换。
final NotifierProvider<ReportDimensionController, ReportDimension>
reportDimensionProvider =
    NotifierProvider<ReportDimensionController, ReportDimension>(
      ReportDimensionController.new,
    );

/// 维度控制器（默认热量——记录入口最高频，最容易先有数据）。
class ReportDimensionController extends Notifier<ReportDimension> {
  @override
  ReportDimension build() => ReportDimension.kcal;

  /// 切换维度。
  void select(ReportDimension dimension) => state = dimension;
}

/// 报告页数据读取端口（测试可换内存实现）。
abstract interface class ReportsDataSource {
  /// 日期区间聚合缓存（含端点，yyyy-MM-dd）。
  Future<List<DailyNutritionCache>> nutritionRange(String from, String to);

  /// 日期区间断食记录（含端点，按归属日）。
  Future<List<FastingRecord>> fastingRange(String from, String to);

  /// 日期区间体重日志（含端点，yyyy-MM-dd → kg）。
  Future<Map<String, double>> weightRange(String from, String to);
}

/// drift + 体重日志实现。
final class DriftReportsDataSource implements ReportsDataSource {
  const DriftReportsDataSource(
    this._db,
    this._weightLog, {
    required this.userId,
  });

  final AppDatabase _db;
  final WeightLogStore _weightLog;

  /// 归属用户（与 record 仓储缺省口径一致：anonymous）。
  final String userId;

  @override
  Future<List<DailyNutritionCache>> nutritionRange(String from, String to) {
    return (_db.select(_db.dailyNutritionCaches)
          ..where(
            (c) =>
                c.userId.equals(userId) &
                c.date.isBiggerOrEqualValue(from) &
                c.date.isSmallerOrEqualValue(to),
          )
          ..orderBy(<OrderingTerm Function(DailyNutritionCaches)>[
            (c) => OrderingTerm.asc(c.date),
          ]))
        .get();
  }

  @override
  Future<List<FastingRecord>> fastingRange(String from, String to) {
    return (_db.select(_db.fastingRecords)
          ..where(
            (r) =>
                r.userId.equals(userId) &
                r.attributionDate.isBiggerOrEqualValue(from) &
                r.attributionDate.isSmallerOrEqualValue(to),
          )
          ..orderBy(<OrderingTerm Function(FastingRecords)>[
            (r) => OrderingTerm.asc(r.attributionDate),
          ]))
        .get();
  }

  @override
  Future<Map<String, double>> weightRange(String from, String to) async {
    return _weightLog.loadRange(from, to);
  }
}

/// 数据源装配（生产：drift + prefs；测试：override 为内存实现）。
final Provider<ReportsDataSource> reportsDataSourceProvider =
    Provider<ReportsDataSource>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return DriftReportsDataSource(
        db,
        ref.watch(weightLogStoreProvider),
        userId: 'anonymous',
      );
    });

/// 当前窗口（终点 = 今天）的起止日期键（yyyy-MM-dd，含端点）。
final Provider<({String from, String to})> reportWindowProvider =
    Provider<({String from, String to})>((ref) {
      final range = ref.watch(reportRangeProvider);
      final end = dateOnly(ref.watch(reportsNowProvider));
      final start = end.subtract(Duration(days: range.days - 1));
      return (from: localDateOf(start), to: localDateOf(end));
    });

/// 窗口内聚合缓存（热量/记录天数来源）。
final FutureProvider<List<DailyNutritionCache>> reportNutritionProvider =
    FutureProvider<List<DailyNutritionCache>>((ref) {
      final window = ref.watch(reportWindowProvider);
      return ref
          .watch(reportsDataSourceProvider)
          .nutritionRange(window.from, window.to);
    });

/// 窗口内断食记录（断食时长/达标天数来源）。
final FutureProvider<List<FastingRecord>> reportFastingProvider =
    FutureProvider<List<FastingRecord>>((ref) {
      final window = ref.watch(reportWindowProvider);
      return ref
          .watch(reportsDataSourceProvider)
          .fastingRange(window.from, window.to);
    });

/// 窗口内体重日志。
final FutureProvider<Map<String, double>> reportWeightProvider =
    FutureProvider<Map<String, double>>((ref) {
      final window = ref.watch(reportWindowProvider);
      return ref
          .watch(reportsDataSourceProvider)
          .weightRange(window.from, window.to);
    });

/// 归属日 → 断食时长（小时）。
final Provider<Map<String, double>> fastingHoursByDateProvider =
    Provider<Map<String, double>>((ref) {
      final records = ref.watch(reportFastingProvider).valueOrNull;
      return <String, double>{
        for (final r in records ?? const <FastingRecord>[])
          r.attributionDate: r.actualSec / 3600,
      };
    });

/// 归属日 → 饮食记录条数。
final Provider<Map<String, int>> entryCountByDateProvider =
    Provider<Map<String, int>>((ref) {
      final caches = ref.watch(reportNutritionProvider).valueOrNull;
      return <String, int>{
        for (final c in caches ?? const <DailyNutritionCache>[])
          if (c.entryCount > 0) c.date: c.entryCount,
      };
    });

/// 达标归属日集合。
final Provider<Set<String>> qualifiedDatesProvider = Provider<Set<String>>((
  ref,
) {
  final records = ref.watch(reportFastingProvider).valueOrNull;
  return <String>{
    for (final r in records ?? const <FastingRecord>[])
      if (r.qualified) r.attributionDate,
  };
});

/// 当前维度趋势序列（长度 = 窗口天数，无数据日为 null → 折线断点）。
final Provider<List<double?>> trendSeriesProvider = Provider<List<double?>>((
  ref,
) {
  final range = ref.watch(reportRangeProvider);
  final end = dateOnly(ref.watch(reportsNowProvider));
  final byDate = switch (ref.watch(reportDimensionProvider)) {
    ReportDimension.kcal => <String, double>{
      for (final c
          in ref.watch(reportNutritionProvider).valueOrNull ??
              const <DailyNutritionCache>[])
        if (c.entryCount > 0) c.date: c.kcal,
    },
    ReportDimension.fasting => ref.watch(fastingHoursByDateProvider),
    ReportDimension.weight =>
      ref.watch(reportWeightProvider).valueOrNull ?? const <String, double>{},
  };
  return alignDailySeries(end: end, days: range.days, byDate: byDate);
});

/// 7/30 天成长轨迹摘要。
final Provider<GrowthSummary> growthSummaryProvider = Provider<GrowthSummary>((
  ref,
) {
  final range = ref.watch(reportRangeProvider);
  final end = dateOnly(ref.watch(reportsNowProvider));
  return computeGrowthSummary(
    end: end,
    days: range.days,
    fastingHoursByDate: ref.watch(fastingHoursByDateProvider),
    qualifiedDates: ref.watch(qualifiedDatesProvider),
    entryCountByDate: ref.watch(entryCountByDateProvider),
    weightByDate:
        ref.watch(reportWeightProvider).valueOrNull ?? const <String, double>{},
  );
});

/// 本周报告（自然周，独立于趋势窗口单独取数）。
final FutureProvider<WeeklyReportStats> weeklyReportProvider =
    FutureProvider<WeeklyReportStats>((ref) async {
      final now = dateOnly(ref.watch(reportsNowProvider));
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final from = localDateOf(weekStart);
      final to = localDateOf(now);
      final source = ref.watch(reportsDataSourceProvider);
      final caches = await source.nutritionRange(from, to);
      final fasts = await source.fastingRange(from, to);
      return computeWeeklyReport(
        now: now,
        intakeByDate: <String, DailyIntake>{
          for (final c in caches)
            if (c.entryCount > 0)
              c.date: DailyIntake(
                entryCount: c.entryCount,
                kcal: c.kcal,
                proteinG: c.proteinG,
                carbG: c.carbG,
                fatG: c.fatG,
              ),
        },
        qualifiedDates: <String>{
          for (final r in fasts)
            if (r.qualified) r.attributionDate,
        },
        goal: ref.watch(nutritionGoalProvider),
      );
    });
