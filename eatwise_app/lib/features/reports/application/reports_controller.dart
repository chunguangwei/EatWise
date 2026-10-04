import 'package:drift/drift.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/fasting_result_mapping.dart'
    show isRealFastResult;
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart'
    show fastingCycleStoreProvider;
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart'
    show nutritionGoalProvider;
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart'
    show dateOnly, localDateOf;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show onboardingStoreProvider;
import 'package:eatwise/features/reports/application/monthly_report.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/domain/weekly_summary.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart'
    show userMeProvider;
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
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
///
/// 2026-09-30 长期趋势：补 90 天 / 365 天两档——此前上限 30 天，
/// 用户坚持数月也看不到长期坚持度，只能逐月翻月报卡的文字摘要。
/// 长窗口配合 [TrendBucket] 聚合（90 天按周、365 天按月），避免逐日点糊成噪声。
enum ReportRange {
  d7(7, TrendBucket.day),
  d30(30, TrendBucket.day),
  d90(90, TrendBucket.week),
  d365(365, TrendBucket.month);

  const ReportRange(this.days, this.bucket);

  /// 窗口天数。
  final int days;

  /// 该窗口的聚合粒度。
  final TrendBucket bucket;

  /// 是否为长窗口（逐日格/逐日折线不再适用）。
  bool get isLongRange => bucket != TrendBucket.day;
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

  /// 全部断食记录（全生命周期统计用，不限窗口）。
  Future<List<FastingRecord>> fastingAll();

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

  /// 归属用户（与写入侧 currentUserIdProvider 同口径：登录取真实 userId，
  /// 未登录 anonymous）。
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

  @override
  Future<List<FastingRecord>> fastingAll() {
    return (_db.select(_db.fastingRecords)
          ..where((r) => r.userId.equals(userId))
          ..orderBy(<OrderingTerm Function(FastingRecords)>[
            (r) => OrderingTerm.asc(r.attributionDate),
          ]))
        .get();
  }
}

/// 数据源装配（生产：drift + prefs；测试：override 为内存实现）。
///
/// userId 与写入侧（streak_controller / record 仓储）同口径取
/// [currentUserIdProvider]，否则登录用户的数据全落在真实 userId 下、
/// 报告按 anonymous 读取会全空。
final Provider<ReportsDataSource> reportsDataSourceProvider =
    Provider<ReportsDataSource>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return DriftReportsDataSource(
        db,
        ref.watch(weightLogStoreProvider),
        userId: ref.watch(currentUserIdProvider),
      );
    });

/// fasting_records 表级变更流（不消费数据，仅作失效挂钩）：同步下行/回填纠偏/
/// 本地关闭周期等任何写入都让 watch 它的 FutureProvider 重取——报告页
/// FutureProvider 此前会话内只取一次，回填纠偏在页面打开后才落库时图表停留在
/// 旧值直到杀进程（2026-10-04 wcg 趋势 0 值「数据已修好图不变」走查）。
final StreamProvider<void> _fastingTableChangesProvider = StreamProvider<void>((
  ref,
) {
  try {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(db.fastingRecords)..limit(1)).watch().map((_) {});
  } on Object {
    // 测试未装配数据库（数据源走内存 fake）：无失效挂钩，fake 自管。
    return const Stream<void>.empty();
  }
});

/// daily_nutrition_caches 表级变更流（同上：同步下行重算/聚合修复后热量趋势
/// 与周月报自动重取，不再停留在会话首取值）。
final StreamProvider<void> _nutritionCacheTableChangesProvider =
    StreamProvider<void>((ref) {
      try {
        final db = ref.watch(appDatabaseProvider);
        return (db.select(
          db.dailyNutritionCaches,
        )..limit(1)).watch().map((_) {});
      } on Object {
        return const Stream<void>.empty();
      }
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
      ref.watch(_nutritionCacheTableChangesProvider);
      final window = ref.watch(reportWindowProvider);
      return ref
          .watch(reportsDataSourceProvider)
          .nutritionRange(window.from, window.to);
    });

/// 窗口内断食记录（断食时长/达标天数来源）。
final FutureProvider<List<FastingRecord>> reportFastingProvider =
    FutureProvider<List<FastingRecord>>((ref) {
      ref.watch(_fastingTableChangesProvider);
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

/// 体重目标线（阶段 C 体重管理闭环）：本地档案 targetWeightKg 优先，
/// 未设置回落服务端档案（GET /users/me）；均无 → null（趋势图不画目标线）。
final Provider<double?> weightTargetProvider = Provider<double?>((ref) {
  try {
    final local = ref
        .watch(onboardingStoreProvider)
        .loadProfile()
        ?.targetWeightKg;
    if (local != null) return local;
    return ref.watch(userMeProvider).value?.targetWeightKg;
  } on Object {
    // 档案/网络未装配（测试/预览）时按未设置处理。
    return null;
  }
});

/// 体重记录总条数（P3 体重曲线解锁钩子：按全量记录判定，与趋势窗口无关）。
/// 依赖 [reportWeightProvider]：体重保存后该 Provider 失效，本计数随之重算。
final Provider<int> weightRecordCountProvider = Provider<int>((ref) {
  ref.watch(reportWeightProvider);
  try {
    return ref.watch(weightLogStoreProvider).recordCount();
  } on Object {
    // 存储未装配（测试/预览）时按 0 条处理（遮罩引导记录）。
    return 0;
  }
});

/// 归属日 → 断食时长（小时）。
///
/// 2026-09-30 两处修：
/// ① 排除 tombstone（deleted）——此前不筛，已删除记录仍进时长 map，
///    污染趋势折线与平均时长（与 [fastingDayStatesProvider] 口径不一致）；
/// ② 排除补签（makeup）——补签未实际断食，其计划时长不是用户成绩。
/// 注：用户确认真实完成但被 bug 吞掉的记录，修复口径是服务端数据转正
/// completed（追记四十五），不靠本层放行 makeup（/sync 下行 makeup 行
/// actualSec 恒为 0，放行也只会画 0）。
final Provider<Map<String, double>> fastingHoursByDateProvider =
    Provider<Map<String, double>>((ref) {
      final records = ref.watch(reportFastingProvider).valueOrNull;
      final map = <String, double>{
        for (final r in records ?? const <FastingRecord>[])
          if (!r.deleted && isRealFastResult(r.result))
            r.attributionDate: r.actualSec / 3600,
      };
      _debugTrackHoursMap(ref, map, records?.length ?? 0);
      return map;
    });

/// 临时诊断（2026-10-04 趋势 0 值三轮排障，定位后移除）：报告链路时长 map
/// 与源行数快照，每会话最多一次——核对 provider 层看到的行与磁盘是否一致。
bool _hoursProbeSent = false;

void _debugTrackHoursMap(Ref ref, Map<String, double> map, int recordCount) {
  if (_hoursProbeSent) return;
  _hoursProbeSent = true;
  try {
    ref
        .read(analyticsServiceProvider)
        .track(
          'debug_f_hours',
          properties: <String, Object?>{
            'uid': ref.read(currentUserIdProvider),
            'records': recordCount,
            'map': map.entries
                .map((e) => '${e.key}:${e.value.toStringAsFixed(1)}')
                .join('|'),
          },
        );
  } on Object {
    // 诊断失败静默。
  }
}

/// 断食趋势日状态序列（长度 = 窗口天数，末位 = 今天）：
/// 达标/未达标/无记录三态 + 进行中第四态（今天有进行中周期且无终态记录）。
///
/// tombstone（deleted）行不算记录——删除后该日回落「无记录」而非断签。
final Provider<List<FastingDayState>> fastingDayStatesProvider =
    Provider<List<FastingDayState>>((ref) {
      final range = ref.watch(reportRangeProvider);
      final end = dateOnly(ref.watch(reportsNowProvider));
      final records = ref.watch(reportFastingProvider).valueOrNull;
      final qualifiedByDate = <String, bool>{
        for (final r in records ?? const <FastingRecord>[])
          if (!r.deleted) r.attributionDate: r.qualified,
      };
      final todayKey = localDateOf(end);
      String? inProgressDate;
      try {
        if (ref.watch(fastingCycleStoreProvider).loadActiveCycle() != null &&
            !qualifiedByDate.containsKey(todayKey)) {
          inProgressDate = todayKey;
        }
      } on Object {
        // 周期存储未装配（测试/预览）：按无进行中周期处理。
      }
      return alignFastingDayStates(
        end: end,
        days: range.days,
        qualifiedByDate: qualifiedByDate,
        inProgressDate: inProgressDate,
      );
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
      if (r.qualified && !r.deleted) r.attributionDate,
  };
});

/// 全部断食记录（全生命周期统计源，不限窗口）。
final FutureProvider<List<FastingRecord>> allFastingRecordsProvider =
    FutureProvider<List<FastingRecord>>((ref) {
      // 依赖窗口 Provider 以便记录写入后一并失效重算。
      ref.watch(reportFastingProvider);
      return ref.watch(reportsDataSourceProvider).fastingAll();
    });

/// 断食全生命周期统计（累计时长/达标率/最长单次）。
final Provider<FastingLifetimeStats> fastingLifetimeProvider =
    Provider<FastingLifetimeStats>((ref) {
      final records =
          ref.watch(allFastingRecordsProvider).valueOrNull ??
          const <FastingRecord>[];
      final alive = records.where((r) => !r.deleted);
      return computeFastingLifetime(
        hoursByDate: <String, double>{
          for (final r in alive)
            if (isRealFastResult(r.result))
              r.attributionDate: r.actualSec / 3600,
        },
        qualifiedDates: <String>{
          for (final r in alive)
            if (r.qualified) r.attributionDate,
        },
        makeupDates: <String>{
          for (final r in alive)
            if (!isRealFastResult(r.result)) r.attributionDate,
        },
      );
    });

/// 当前维度的分桶趋势序列（7/30 天逐日，90 天按周，365 天按自然月）。
final Provider<List<TrendPoint>> trendPointsProvider =
    Provider<List<TrendPoint>>((ref) {
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
          ref.watch(reportWeightProvider).valueOrNull ??
              const <String, double>{},
      };
      return bucketDailySeries(
        end: end,
        days: range.days,
        byDate: byDate,
        bucket: range.bucket,
      );
    });

/// 窗口内断食「达标率」分桶序列（长窗口的坚持度视图，值域 0..1）。
///
/// 短窗口用三态格逐日直读；长窗口（90/365 天）格子会多到不可读，
/// 改用「每桶达标天数 ÷ 桶内天数」的比率序列。
final Provider<List<TrendPoint>> fastingQualifiedRatePointsProvider =
    Provider<List<TrendPoint>>((ref) {
      final range = ref.watch(reportRangeProvider);
      final end = dateOnly(ref.watch(reportsNowProvider));
      final qualified = ref.watch(qualifiedDatesProvider);
      return bucketDailySeries(
            end: end,
            days: range.days,
            // 达标日记 1、其余日缺席；桶内均值即达标率（桶天数为分母需补 0）。
            byDate: <String, double>{for (final d in qualified) d: 1},
            bucket: range.bucket,
          )
          .map((p) {
            return TrendPoint(
              start: p.start,
              end: p.end,
              // recordedDays = 达标天数；除以桶总天数得达标率（无达标日为 0 而非 null，
              // 长窗口的「这周一天没达标」是有意义的信息，不能画成断点）。
              value: p.totalDays == 0 ? null : p.recordedDays / p.totalDays,
              recordedDays: p.recordedDays,
              totalDays: p.totalDays,
            );
          })
          .toList(growable: false);
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
      ref.watch(_fastingTableChangesProvider);
      ref.watch(_nutritionCacheTableChangesProvider);
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
            if (r.qualified && !r.deleted) r.attributionDate,
        },
        goal: ref.watch(nutritionGoalProvider),
      );
    });

/// 上周小结（P1：上一个完整自然周；断食环比需多取前周，独立于趋势窗口）。
final FutureProvider<WeeklySummary> weeklySummaryProvider =
    FutureProvider<WeeklySummary>((ref) async {
      ref.watch(_fastingTableChangesProvider);
      ref.watch(_nutritionCacheTableChangesProvider);
      final now = dateOnly(ref.watch(reportsNowProvider));
      final thisMonday = now.subtract(Duration(days: now.weekday - 1));
      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      final lastSunday = thisMonday.subtract(const Duration(days: 1));
      final prevMonday = lastMonday.subtract(const Duration(days: 7));
      final source = ref.watch(reportsDataSourceProvider);
      final caches = await source.nutritionRange(
        localDateOf(lastMonday),
        localDateOf(lastSunday),
      );
      final fasts = await source.fastingRange(
        localDateOf(prevMonday),
        localDateOf(lastSunday),
      );
      final weights = await source.weightRange(
        localDateOf(lastMonday),
        localDateOf(lastSunday),
      );
      return computeWeeklySummary(
        now: now,
        kcalByDate: <String, double>{
          for (final c in caches)
            if (c.entryCount > 0) c.date: c.kcal,
        },
        qualifiedDates: <String>{
          for (final r in fasts)
            if (r.qualified && !r.deleted) r.attributionDate,
        },
        weightByDate: weights,
        targetKcal: ref.watch(nutritionGoalProvider).targetKcal,
      );
    });

/// 月报选中月份（每月 1 日；不可切换到未来月）。
final NotifierProvider<MonthlyReportMonthController, DateTime>
monthlyReportMonthProvider =
    NotifierProvider<MonthlyReportMonthController, DateTime>(
      MonthlyReportMonthController.new,
    );

/// 月报月份控制器（默认当月；下一月在未来时停在当月）。
class MonthlyReportMonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = ref.watch(reportsNowProvider);
    return DateTime(now.year, now.month, 1);
  }

  /// 上一月。
  void previous() => state = DateTime(state.year, state.month - 1, 1);

  /// 下一月（未来月不可达，多次调用安全）。
  void next() {
    final now = dateOnly(ref.read(reportsNowProvider));
    final current = DateTime(now.year, now.month, 1);
    final candidate = DateTime(state.year, state.month + 1, 1);
    if (!candidate.isAfter(current)) state = candidate;
  }
}

/// 月报（选中自然月，本地生成，独立于趋势窗口单独取数）。
///
/// 当月范围终点取今天（未过完的月份不做未来统计）。
final FutureProvider<MonthlyReport> monthlyReportProvider =
    FutureProvider<MonthlyReport>((ref) async {
      ref.watch(_fastingTableChangesProvider);
      ref.watch(_nutritionCacheTableChangesProvider);
      final monthStart = ref.watch(monthlyReportMonthProvider);
      final now = dateOnly(ref.watch(reportsNowProvider));
      final from = localDateOf(monthStart);
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
      final to = localDateOf(monthEnd.isBefore(now) ? monthEnd : now);
      final source = ref.watch(reportsDataSourceProvider);
      final caches = await source.nutritionRange(from, to);
      final fasts = await source.fastingRange(from, to);
      final weights = await source.weightRange(from, to);
      return computeMonthlyReport(
        month: monthStart,
        // 2026-10-04 全量口径审计修订：时长 map 排除 tombstone 与补签
        // （此前不过滤——补签行 actualSec 恒 0，把月报平均时长拉低，
        // 与「补签计达标不计时长」口径矛盾）。
        fastingHoursByDate: <String, double>{
          for (final r in fasts)
            if (!r.deleted && isRealFastResult(r.result))
              r.attributionDate: r.actualSec / 3600,
        },
        qualifiedDates: <String>{
          for (final r in fasts)
            if (r.qualified && !r.deleted) r.attributionDate,
        },
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
        weightByDate: weights,
        goal: ref.watch(nutritionGoalProvider),
      );
    });
