import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:flutter_test/flutter_test.dart';

/// M6 聚合纯函数单测：序列对齐（断点）、成长轨迹摘要、自然周周报统计。
void main() {
  final end = DateTime(2026, 7, 28); // 周二

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

  DailyIntake intakeOf(double ratio, {int entries = 2}) => DailyIntake(
    entryCount: entries,
    kcal: 2000 * ratio,
    proteinG: 100 * ratio,
    carbG: 200 * ratio,
    fatG: 60 * ratio,
  );

  group('alignDailySeries', () {
    test('按日期升序对齐，无数据日为 null（断点）', () {
      final series = alignDailySeries(
        end: end,
        days: 7,
        byDate: const {'2026-07-28': 1800, '2026-07-23': 1500},
      );
      expect(series.length, 7);
      // 7/22(起) 7/23 7/24 7/25 7/26 7/27 7/28(终)
      expect(series, <double?>[null, 1500, null, null, null, null, 1800]);
    });

    test('30 天档长度与端点正确', () {
      final series = alignDailySeries(
        end: end,
        days: 30,
        byDate: const {'2026-06-29': 1, '2026-07-28': 2},
      );
      expect(series.length, 30);
      expect(series.first, 1);
      expect(series.last, 2);
      expect(series.whereType<double>().length, 2);
    });
  });

  group('computeGrowthSummary', () {
    test('达标天数/记录天数/平均断食/体重 Δ 统计正确', () {
      final summary = computeGrowthSummary(
        end: end,
        days: 7,
        fastingHoursByDate: const {'2026-07-26': 16, '2026-07-27': 14},
        qualifiedDates: const {'2026-07-26', '2026-07-27', '2026-07-28'},
        entryCountByDate: const {'2026-07-27': 3, '2026-07-28': 1},
        weightByDate: const {'2026-07-23': 65.0, '2026-07-28': 64.2},
      );
      expect(summary.qualifiedDays, 3);
      expect(summary.recordedDays, 2);
      expect(summary.avgFastingHours, 15);
      expect(summary.weightDeltaKg, closeTo(-0.8, 1e-9));
      expect(summary.hasData, isTrue);
    });

    test('断食按归属日聚合：窗口外的归属日不计入（跨日不串）', () {
      final summary = computeGrowthSummary(
        end: end,
        days: 7,
        // 7/21 在 7 天窗口（7/22 起）之外，不应计入。
        fastingHoursByDate: const {'2026-07-21': 20, '2026-07-28': 16},
        qualifiedDates: const {'2026-07-21', '2026-07-28'},
        entryCountByDate: const {},
        weightByDate: const {},
      );
      expect(summary.qualifiedDays, 1);
      expect(summary.avgFastingHours, 16);
    });

    test('体重仅一次称重 → Δ 为 null；全无数据 → hasData=false', () {
      final oneWeigh = computeGrowthSummary(
        end: end,
        days: 7,
        fastingHoursByDate: const {},
        qualifiedDates: const {},
        entryCountByDate: const {},
        weightByDate: const {'2026-07-28': 64.0},
      );
      expect(oneWeigh.weightDeltaKg, isNull);
      expect(oneWeigh.hasData, isFalse); // 仅一次称重不算足迹

      final empty = computeGrowthSummary(
        end: end,
        days: 30,
        fastingHoursByDate: const {},
        qualifiedDates: const {},
        entryCountByDate: const {},
        weightByDate: const {},
      );
      expect(empty.hasData, isFalse);
      expect(empty.avgFastingHours, isNull);
    });
  });

  group('computeWeeklyReport', () {
    test('自然周（周一起算）统计：达标/条数/绿占比', () {
      // 本周 = 7/27(周一)～8/2(周日)，今天 7/28 → 只统计 7/27、7/28。
      final stats = computeWeeklyReport(
        now: end,
        intakeByDate: <String, DailyIntake>{
          '2026-07-27': intakeOf(1.0, entries: 3), // 全绿 ×4
          '2026-07-28': intakeOf(1.0), // 全绿 ×4
        },
        qualifiedDates: const {'2026-07-27'},
        goal: goal,
      );
      expect(stats.weekStart, DateTime(2026, 7, 27));
      expect(stats.weekEnd, end); // 本周未过完，不看未来
      expect(stats.qualifiedDays, 1);
      expect(stats.entryCount, 5);
      expect(stats.greenRatio, 1.0); // 8/8 全绿
      expect(stats.hasData, isTrue);
    });

    test('绿占比按判定项加权：全绿日 + 全红日 → 0.5', () {
      final stats = computeWeeklyReport(
        now: end,
        intakeByDate: <String, DailyIntake>{
          '2026-07-27': intakeOf(1.0), // 4 绿
          '2026-07-28': intakeOf(2.0), // 4 红（>130%）
        },
        qualifiedDates: const {},
        goal: goal,
      );
      expect(stats.greenRatio, 0.5);
    });

    test('周日回看整周；无记录日绿占比为 null', () {
      final sunday = DateTime(2026, 8, 2);
      final stats = computeWeeklyReport(
        now: sunday,
        intakeByDate: <String, DailyIntake>{
          '2026-07-27': intakeOf(1.0), // 上周一，属本周
          '2026-07-26': intakeOf(1.0), // 上周日，属上一周，不计入
        },
        qualifiedDates: const {'2026-07-26', '2026-08-01'},
        goal: goal,
      );
      expect(stats.weekStart, DateTime(2026, 7, 27));
      expect(stats.weekEnd, sunday);
      expect(stats.entryCount, 2); // 只算 7/27 的 2 条
      expect(stats.qualifiedDays, 1); // 只算 8/1
      expect(stats.greenRatio, 1.0);

      final noIntake = computeWeeklyReport(
        now: end,
        intakeByDate: const {},
        qualifiedDates: const {'2026-07-28'},
        goal: goal,
      );
      expect(noIntake.greenRatio, isNull);
      expect(noIntake.hasData, isTrue); // 有达标也算有数据
    });

    test('完全无数据 → hasData=false（空态引导）', () {
      final stats = computeWeeklyReport(
        now: end,
        intakeByDate: const {},
        qualifiedDates: const {},
        goal: goal,
      );
      expect(stats.hasData, isFalse);
      expect(stats.entryCount, 0);
      expect(stats.greenRatio, isNull);
    });
  });
}
