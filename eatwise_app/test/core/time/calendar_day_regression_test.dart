import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/record/data/daily_nutrition_cache_repair.dart';
import 'package:eatwise/features/reports/application/monthly_report.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:eatwise/features/reports/domain/weekly_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// CI also runs this file with TZ=America/New_York to exercise real local DST.
void main() {
  for (final now in [
    DateTime(2026, 3, 9, 0, 30),
    DateTime(2026, 11, 2, 23, 30),
  ]) {
    test(
      'recent cache repair includes exactly seven calendar dates at $now',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final first = localDateOf(DateTime(now.year, now.month, now.day - 6));
        final outside = localDateOf(DateTime(now.year, now.month, now.day - 7));
        final today = localDateOf(now);
        for (final date in [outside, first, today]) {
          await db
              .into(db.dailyNutritionCaches)
              .insert(
                DailyNutritionCachesCompanion(
                  userId: const Value('dst-user'),
                  date: Value(date),
                  kcal: const Value(100),
                  proteinG: const Value(0),
                  carbG: const Value(0),
                  fatG: const Value(0),
                  entryCount: const Value(1),
                  updatedAtUtc: Value(now.toUtc().toIso8601String()),
                ),
              );
        }
        final repair = DailyNutritionCacheRepair(db: db, clock: () => now);
        expect(await repair.repairRecent('dst-user'), 2);
        expect(
          (await db.foodEntryDao.getDailyNutrition('dst-user', first))!.kcal,
          0,
        );
        expect(
          (await db.foodEntryDao.getDailyNutrition('dst-user', today))!.kcal,
          0,
        );
        expect(
          (await db.foodEntryDao.getDailyNutrition('dst-user', outside))!.kcal,
          100,
        );
      },
    );
  }

  test('previous and next date remain local midnights across spring DST', () {
    final container = ProviderContainer(
      overrides: [
        nutritionNowProvider.overrideWithValue(DateTime(2026, 3, 9, 12)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(selectedDateProvider.notifier);
    controller.prevDay();
    expect(container.read(selectedDateProvider), DateTime(2026, 3, 8));
    controller.nextDay();
    expect(container.read(isTodaySelectedProvider), isTrue);
    expect(container.read(canGoNextDayProvider), isFalse);
  });

  for (final end in [DateTime(2026, 3, 9), DateTime(2026, 11, 2)]) {
    test(
      'daily and fasting series contain each calendar date through $end',
      () {
        final dates = List.generate(
          7,
          (i) => localDateOf(DateTime(end.year, end.month, end.day - 6 + i)),
        );
        final values = {
          for (var i = 0; i < dates.length; i++) dates[i]: i + 1.0,
        };
        expect(alignDailySeries(end: end, days: 7, byDate: values), [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ]);
        expect(
          alignFastingDayStates(
            end: end,
            days: 7,
            qualifiedByDate: {for (final d in dates) d: true},
          ),
          List.filled(7, FastingDayState.qualified),
        );
        final buckets = bucketDailySeries(
          end: end,
          days: 7,
          byDate: values,
          bucket: TrendBucket.week,
        );
        expect(buckets.single.totalDays, 7);
        expect(buckets.single.recordedDays, 7);
        expect(buckets.single.value, 4);
        final growth = computeGrowthSummary(
          end: end,
          days: 7,
          fastingHoursByDate: values,
          qualifiedDates: dates.toSet(),
          entryCountByDate: {for (final d in dates) d: 1},
          weightByDate: const {},
        );
        expect(growth.qualifiedDays, 7);
        expect(growth.recordedDays, 7);
      },
    );
  }

  test('last full week keeps spring Sunday and excludes preceding Sunday', () {
    final summary = computeWeeklySummary(
      now: DateTime(2026, 3, 9),
      kcalByDate: const {'2026-03-01': 900, '2026-03-08': 1800},
      qualifiedDates: const {'2026-03-08'},
      weightByDate: const {},
      targetKcal: 2000,
    );
    expect(summary.weekStart, DateTime(2026, 3, 2));
    expect(summary.weekEnd, DateTime(2026, 3, 8));
    expect(summary.qualifiedDays, 1);
    expect(summary.avgKcal, 1800);
  });

  test('November report counts final day once after fall DST', () {
    const goal = NutritionGoal(
      bmr: null,
      tdee: null,
      targetKcal: 2000,
      proteinG: 100,
      carbG: 200,
      fatG: 60,
      usedFallback: false,
      configVersion: 'test',
    );
    final report = computeMonthlyReport(
      month: DateTime(2026, 11),
      fastingHoursByDate: const {'2026-11-01': 16, '2026-11-30': 18},
      qualifiedDates: const {'2026-11-01', '2026-11-30'},
      intakeByDate: const {},
      weightByDate: const {'2026-11-01': 70, '2026-11-30': 69},
      goal: goal,
    );
    expect(report.qualifiedDays, 2);
    expect(report.avgFastedMinutes, 17 * 60);
    expect(report.weightChangeKg, -1);
  });
}
