import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart'
    show nutritionGoalProvider;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 7, 28, 14); // 周二

const _goal = NutritionGoal(
  bmr: null,
  tdee: null,
  targetKcal: 2000,
  proteinG: 100,
  carbG: 200,
  fatG: 60,
  usedFallback: false,
  configVersion: 'test',
);

DailyNutritionCache _cache(String date, double kcal, {int entries = 2}) =>
    DailyNutritionCache(
      userId: 'anonymous',
      date: date,
      entryCount: entries,
      kcal: kcal,
      proteinG: 100,
      carbG: 200,
      fatG: 60,
      isLocalEstimate: true,
      updatedAtUtc: '2026-07-28T00:00:00.000Z',
    );

FastingRecord _fast(String date, int actualSec, {bool qualified = true}) =>
    FastingRecord(
      localId: 'anonymous-$date',
      userId: 'anonymous',
      attributionDate: date,
      startUtc: 0,
      endUtc: actualSec,
      actualSec: actualSec,
      plannedSec: actualSec,
      extendedMinutes: 0,
      result: 'completed',
      qualified: qualified,
      clientRequestId: 'req-$date',
      syncStatus: SyncStatus.synced,
      createdAtUtc: '2026-07-28T00:00:00.000Z',
    );

/// 内存数据源：固定数据集（7/26～7/28 有数据，其余空）。
final class _FakeSource implements ReportsDataSource {
  @override
  Future<List<DailyNutritionCache>> nutritionRange(
    String from,
    String to,
  ) async =>
      <DailyNutritionCache>[
            _cache('2026-07-26', 2000, entries: 3),
            _cache('2026-07-28', 1600),
          ]
          .where(
            (c) => c.date.compareTo(from) >= 0 && c.date.compareTo(to) <= 0,
          )
          .toList();

  @override
  Future<List<FastingRecord>> fastingRange(String from, String to) async =>
      <FastingRecord>[
            _fast('2026-07-26', 16 * 3600),
            _fast('2026-07-27', 14 * 3600, qualified: false),
          ]
          .where(
            (r) =>
                r.attributionDate.compareTo(from) >= 0 &&
                r.attributionDate.compareTo(to) <= 0,
          )
          .toList();

  @override
  Future<Map<String, double>> weightRange(String from, String to) async =>
      <String, double>{'2026-07-26': 65.0, '2026-07-28': 64.4};
}

/// M6 reports controller 单测：范围切换、维度切换、无数据日断点、
/// 周报 provider 统计（内存数据源，不依赖 drift）。
void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        reportsNowProvider.overrideWithValue(_now),
        reportsDataSourceProvider.overrideWithValue(_FakeSource()),
        nutritionGoalProvider.overrideWithValue(_goal),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('维度切换：热量/断食/体重序列与断点', () async {
    final container = makeContainer();
    // 等 FutureProvider 就绪。
    await container.read(reportNutritionProvider.future);
    await container.read(reportFastingProvider.future);
    await container.read(reportWeightProvider.future);

    // 默认热量：7/22～7/28，7/26 与 7/28 有值，其余 null 断点。
    container
        .read(reportDimensionProvider.notifier)
        .select(ReportDimension.kcal);
    expect(container.read(trendSeriesProvider), <double?>[
      null,
      null,
      null,
      null,
      2000,
      null,
      1600,
    ]);

    container
        .read(reportDimensionProvider.notifier)
        .select(ReportDimension.fasting);
    expect(container.read(trendSeriesProvider), <double?>[
      null,
      null,
      null,
      null,
      16,
      14,
      null,
    ]);

    container
        .read(reportDimensionProvider.notifier)
        .select(ReportDimension.weight);
    expect(container.read(trendSeriesProvider), <double?>[
      null,
      null,
      null,
      null,
      65.0,
      null,
      64.4,
    ]);
  });

  test('范围切换 7 → 30：序列长度变化且数据对齐窗口', () async {
    final container = makeContainer();
    await container.read(reportNutritionProvider.future);
    expect(container.read(trendSeriesProvider).length, 7);

    container.read(reportRangeProvider.notifier).select(ReportRange.d30);
    // 范围变化触发重新取数。
    await container.read(reportNutritionProvider.future);
    final series = container.read(trendSeriesProvider);
    expect(series.length, 30);
    // 7/26 为倒数第 3 天（index 27），7/28 为最后一天。
    expect(series[27], 2000);
    expect(series[29], 1600);
    expect(series.whereType<double>().length, 2);
  });

  test('成长轨迹 provider：达标/记录/平均断食/体重 Δ', () async {
    final container = makeContainer();
    await container.read(reportNutritionProvider.future);
    await container.read(reportFastingProvider.future);
    await container.read(reportWeightProvider.future);

    final summary = container.read(growthSummaryProvider);
    expect(summary.days, 7);
    expect(summary.qualifiedDays, 1); // 7/26 达标，7/27 未达标
    expect(summary.recordedDays, 2);
    expect(summary.avgFastingHours, 15);
    expect(summary.weightDeltaKg, closeTo(-0.6, 1e-9));
    expect(summary.hasData, isTrue);
  });

  test('周报 provider：自然周统计（达标/条数/绿占比）', () async {
    final container = makeContainer();
    final stats = await container.read(weeklyReportProvider.future);
    expect(stats.weekStart, DateTime(2026, 7, 27));
    expect(stats.weekEnd, DateTime(2026, 7, 28));
    expect(stats.qualifiedDays, 0); // 窗口内无达标（7/26 在周一前）
    expect(stats.entryCount, 2); // 7/28 的 2 条
    // 7/28：1600/2000=80% 黄；其余 100% 绿 → 3/4 绿。
    expect(stats.greenRatio, 0.75);
    expect(stats.hasData, isTrue);
  });

  group('数据源 userId 口径（drift 实现）', () {
    late AppDatabase db;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.memory();
      addTearDown(db.close);
    });

    Future<void> seedCache(String userId, String date) {
      return db
          .into(db.dailyNutritionCaches)
          .insert(
            DailyNutritionCachesCompanion(
              userId: Value(userId),
              date: Value(date),
              entryCount: const Value(2),
              kcal: const Value(1800),
              proteinG: const Value(100),
              carbG: const Value(200),
              fatG: const Value(60),
              updatedAtUtc: Value(_now.toUtc().toIso8601String()),
            ),
          );
    }

    Future<void> seedFast(String userId, String date) {
      return db
          .into(db.fastingRecords)
          .insert(
            FastingRecordsCompanion(
              localId: Value('$userId-$date'),
              userId: Value(userId),
              attributionDate: Value(date),
              startUtc: const Value(0),
              endUtc: const Value(16 * 3600),
              actualSec: const Value(16 * 3600),
              plannedSec: const Value(16 * 3600),
              extendedMinutes: const Value(0),
              result: const Value('completed'),
              qualified: const Value(true),
              clientRequestId: Value('req-$userId-$date'),
              syncStatus: const Value(SyncStatus.synced),
              createdAtUtc: Value(_now.toUtc().toIso8601String()),
            ),
          );
    }

    ProviderContainer driftContainer({required String userId}) {
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          reportsNowProvider.overrideWithValue(_now),
          currentUserIdProvider.overrideWithValue(userId),
          nutritionGoalProvider.overrideWithValue(_goal),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('登录用户按 currentUserIdProvider 取数（不再硬编码 anonymous 全空）', () async {
      await seedCache('u-1', '2026-07-28');
      await seedCache('anonymous', '2026-07-28');
      await seedFast('u-1', '2026-07-27');
      await seedFast('anonymous', '2026-07-27');

      final container = driftContainer(userId: 'u-1');
      final caches = await container.read(reportNutritionProvider.future);
      final fasts = await container.read(reportFastingProvider.future);
      expect(caches.map((c) => c.userId).toList(), <String>['u-1']);
      expect(fasts.map((r) => r.userId).toList(), <String>['u-1']);
      // 登录用户的断食趋势不再全空。
      expect(container.read(fastingHoursByDateProvider), <String, double>{
        '2026-07-27': 16,
      });
    });

    test('未登录回落 anonymous（与写入侧缺省口径一致）', () async {
      await seedCache('u-1', '2026-07-28');
      await seedFast('anonymous', '2026-07-27');

      final container = driftContainer(userId: 'anonymous');
      final caches = await container.read(reportNutritionProvider.future);
      final fasts = await container.read(reportFastingProvider.future);
      expect(caches, isEmpty);
      expect(fasts.map((r) => r.userId).toList(), <String>['anonymous']);
    });
  });
}
