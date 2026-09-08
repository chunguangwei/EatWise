import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/reports/application/monthly_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// M6 月报（轻量版）聚合纯函数单测：达标天数、平均断食时长、月均营养、
/// 体重变化、空数据、跨月边界。
void main() {
  // 2026-08：8/1 周六 ～ 8/31 周一，共 31 天。
  final aug = DateTime(2026, 8, 15);

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

  MonthlyReport compute({
    DateTime? month,
    Map<String, double> fasting = const {},
    Set<String> qualified = const {},
    Map<String, DailyIntake> intake = const {},
    Map<String, double> weight = const {},
  }) => computeMonthlyReport(
    month: month ?? aug,
    fastingHoursByDate: fasting,
    qualifiedDates: qualified,
    intakeByDate: intake,
    weightByDate: weight,
    goal: goal,
  );

  DailyIntake intakeOf(double ratio, {int entries = 2}) => DailyIntake(
    entryCount: entries,
    kcal: 2000 * ratio,
    proteinG: 100 * ratio,
    carbG: 200 * ratio,
    fatG: 60 * ratio,
  );

  group('computeMonthlyReport · 断食统计', () {
    test('达标天数只计月内归属日（D-08 口径）', () {
      final report = compute(
        fasting: const {'2026-08-03': 16, '2026-08-10': 14},
        qualified: const {'2026-08-03', '2026-08-10', '2026-07-31'},
      );
      expect(report.qualifiedDays, 2);
      expect(report.daysWithRecords, 2);
    });

    test('平均断食时长按断食记录日平均，换算分钟', () {
      final report = compute(
        fasting: const {'2026-08-03': 16, '2026-08-05': 15.5},
      );
      expect(report.avgFastedMinutes, closeTo(15.75 * 60, 1e-9));
      expect(report.year, 2026);
      expect(report.month, 8);
    });

    test('月内无断食记录 → avgFastedMinutes 为 null', () {
      expect(compute().avgFastedMinutes, isNull);
    });
  });

  group('computeMonthlyReport · 营养汇总', () {
    test('月均按有饮食记录日平均（不是按整月天数）', () {
      final report = compute(
        intake: {'2026-08-01': intakeOf(1.0), '2026-08-02': intakeOf(0.5)},
      );
      expect(report.avgKcal, 1500);
      expect(report.avgProteinG, 75);
      expect(report.avgCarbsG, 150);
      expect(report.avgFatG, 45);
      expect(report.targetKcal, 2000);
    });

    test('entryCount=0 的摄入不计为记录日', () {
      final report = compute(
        intake: {
          '2026-08-01': intakeOf(1.0),
          '2026-08-02': intakeOf(1.0, entries: 0),
        },
      );
      expect(report.avgKcal, 2000);
      expect(report.daysWithRecords, 1);
    });

    test('无饮食记录 → 月均营养为 null', () {
      final report = compute();
      expect(report.avgKcal, isNull);
      expect(report.avgProteinG, isNull);
      expect(report.avgCarbsG, isNull);
      expect(report.avgFatG, isNull);
    });
  });

  group('computeMonthlyReport · 体重变化', () {
    test('月初 vs 月末：最后一次称重 − 第一次称重', () {
      final report = compute(
        weight: const {'2026-08-01': 65.0, '2026-08-31': 64.2},
      );
      expect(report.weightChangeKg, closeTo(-0.8, 1e-9));
    });

    test('月内多次称重取首尾，与中间波动无关', () {
      final report = compute(
        weight: const {
          '2026-08-02': 66.0,
          '2026-08-15': 64.0,
          '2026-08-20': 65.0,
        },
      );
      expect(report.weightChangeKg, closeTo(-1.0, 1e-9));
    });

    test('不足两次称重 → weightChangeKg 为 null', () {
      expect(
        compute(weight: const {'2026-08-10': 65.0}).weightChangeKg,
        isNull,
      );
    });
  });

  group('computeMonthlyReport · 跨月边界', () {
    test('相邻月份归属日互不串月（7/31 与 9/1 不计入 8 月）', () {
      final report = compute(
        fasting: const {'2026-07-31': 20, '2026-08-01': 16, '2026-09-01': 18},
        qualified: const {'2026-07-31', '2026-08-01', '2026-09-01'},
        intake: {'2026-07-31': intakeOf(1), '2026-08-31': intakeOf(1)},
        weight: const {'2026-07-31': 66.0, '2026-09-01': 63.0},
      );
      expect(report.qualifiedDays, 1);
      expect(report.avgFastedMinutes, 16 * 60);
      expect(report.avgKcal, 2000);
      // 8 月内只有一次称重 → 无体重变化。
      expect(report.weightChangeKg, isNull);
      expect(report.daysWithRecords, 2);
    });

    test('2 月平年 28 天整月遍历（月末 2/28 计入）', () {
      final report = compute(
        month: DateTime(2026, 2, 10),
        fasting: const {'2026-02-28': 14},
        qualified: const {'2026-02-28'},
      );
      expect(report.qualifiedDays, 1);
      expect(report.avgFastedMinutes, 14 * 60);
    });
  });

  group('computeMonthlyReport · 空数据', () {
    test('全空 → hasData=false，各项为 null/0', () {
      final report = compute();
      expect(report.hasData, isFalse);
      expect(report.qualifiedDays, 0);
      expect(report.daysWithRecords, 0);
      expect(report.avgFastedMinutes, isNull);
      expect(report.avgKcal, isNull);
      expect(report.weightChangeKg, isNull);
    });

    test('仅体重一条记录也算有数据（引导语可见）', () {
      expect(compute(weight: const {'2026-08-05': 65.0}).hasData, isTrue);
    });

    test('饮食与断食同日 → daysWithRecords 只计一次', () {
      final report = compute(
        fasting: const {'2026-08-05': 16},
        intake: {'2026-08-05': intakeOf(1)},
      );
      expect(report.daysWithRecords, 1);
    });
  });
}
