import 'package:eatwise/features/reports/domain/weekly_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「上周小结」纯函数测试（薄荷走查 P1：本地数据统计 + 模板句挑选，
/// 不调用任何模型）。
void main() {
  // 固定时钟：2026-09-18（周五）→ 上周 = 9/7（周一）～9/13（周日），
  // 前周 = 8/31～9/6。
  final now = DateTime(2026, 9, 18, 14);

  WeeklySummary compute({
    Map<String, double> kcalByDate = const <String, double>{},
    Set<String> qualifiedDates = const <String>{},
    Map<String, double> weightByDate = const <String, double>{},
    int targetKcal = 2000,
  }) {
    return computeWeeklySummary(
      now: now,
      kcalByDate: kcalByDate,
      qualifiedDates: qualifiedDates,
      weightByDate: weightByDate,
      targetKcal: targetKcal,
    );
  }

  group('computeWeeklySummary', () {
    test('上周窗口：周一～周日（不含本周与前周数据）', () {
      final s = compute(
        kcalByDate: <String, double>{
          '2026-09-07': 1800, // 上周一
          '2026-09-13': 1600, // 上周日
          '2026-09-14': 1500, // 本周一（不计）
          '2026-08-31': 1500, // 前周（不计摄入）
        },
        qualifiedDates: <String>{
          '2026-09-07',
          '2026-09-09',
          '2026-09-13',
          '2026-09-14', // 本周（不计）
          '2026-09-01', // 前周（只进环比）
          '2026-09-03', // 前周
        },
      );
      expect(s.weekStart, DateTime(2026, 9, 7));
      expect(s.weekEnd, DateTime(2026, 9, 13));
      expect(s.qualifiedDays, 3);
      expect(s.prevQualifiedDays, 2);
      expect(s.recordedDays, 2);
      expect(s.avgKcal, closeTo(1700, 1e-9));
      expect(s.hasData, isTrue);
    });

    test('0 记录：hasData=false → 走引导文案', () {
      final s = compute();
      expect(s.hasData, isFalse);
      expect(s.recordedDays, 0);
      expect(s.qualifiedDays, 0);
      expect(s.avgKcal, isNull);
      expect(s.weightDeltaKg, isNull);
    });

    test('只有断食达标也算有数据', () {
      final s = compute(qualifiedDates: <String>{'2026-09-08'});
      expect(s.hasData, isTrue);
      expect(s.qualifiedDays, 1);
    });

    test('体重变化：末次 − 首次；不足两次为 null', () {
      final up = compute(
        kcalByDate: <String, double>{'2026-09-08': 1800},
        weightByDate: <String, double>{'2026-09-08': 65.0, '2026-09-09': 66.0},
      );
      expect(up.weightDeltaKg, closeTo(1.0, 1e-9));
      final down = compute(
        kcalByDate: <String, double>{'2026-09-08': 1800},
        weightByDate: <String, double>{'2026-09-08': 65.0, '2026-09-12': 64.4},
      );
      expect(down.weightDeltaKg, closeTo(-0.6, 1e-9));
      // 只有 1 条 → null。
      final single = compute(
        kcalByDate: <String, double>{'2026-09-08': 1800},
        weightByDate: <String, double>{'2026-09-08': 65.0},
      );
      expect(single.weightDeltaKg, isNull);
    });
  });

  group('weeklySummarySentences 模板句挑选', () {
    test('环比：前周无达标 → 平铺句（不环比）', () {
      final s = compute(
        kcalByDate: <String, double>{'2026-09-08': 2000},
        qualifiedDates: <String>{'2026-09-08', '2026-09-09'},
      );
      final sentences = weeklySummarySentences(s);
      expect(sentences.first, WeeklySummarySentence.fastingPlain);
    });

    test('环比：比前周多 / 少 / 持平', () {
      final more = compute(
        kcalByDate: <String, double>{'2026-09-08': 2000},
        qualifiedDates: <String>{
          '2026-09-07', '2026-09-08', '2026-09-09', // 上周 3 天
          '2026-09-01', // 前周 1 天
        },
      );
      expect(
        weeklySummarySentences(more).first,
        WeeklySummarySentence.fastingMore,
      );
      final less = compute(
        kcalByDate: <String, double>{'2026-09-08': 2000},
        qualifiedDates: <String>{
          '2026-09-07', // 上周 1 天
          '2026-09-01', '2026-09-02', '2026-09-03', // 前周 3 天
        },
      );
      expect(
        weeklySummarySentences(less).first,
        WeeklySummarySentence.fastingLess,
      );
      final same = compute(
        kcalByDate: <String, double>{'2026-09-08': 2000},
        qualifiedDates: <String>{'2026-09-07', '2026-09-01'},
      );
      expect(
        weeklySummarySentences(same).first,
        WeeklySummarySentence.fastingSame,
      );
    });

    test('摄入句：±10% 内为目标范围，之外分高/低', () {
      WeeklySummary intake(double kcal) => compute(
        kcalByDate: <String, double>{'2026-09-08': kcal},
        targetKcal: 2000,
      );
      expect(
        weeklySummarySentences(intake(2000)),
        contains(WeeklySummarySentence.intakeWithin),
      );
      expect(
        weeklySummarySentences(intake(2200)), // 恰好 +10% → 范围内
        contains(WeeklySummarySentence.intakeWithin),
      );
      expect(
        weeklySummarySentences(intake(2300)),
        contains(WeeklySummarySentence.intakeAbove),
      );
      expect(
        weeklySummarySentences(intake(1700)),
        contains(WeeklySummarySentence.intakeBelow),
      );
      // 无饮食记录 → 无摄入句。
      final noIntake = compute(qualifiedDates: <String>{'2026-09-08'});
      expect(
        weeklySummarySentences(
          noIntake,
        ).where((s) => s.name.startsWith('intake')),
        isEmpty,
      );
    });

    test('体重句：升 / 降 / 持平（|Δ|<0.1）；无记录无体重句', () {
      WeeklySummary weight(double delta) => compute(
        kcalByDate: <String, double>{'2026-09-08': 2000},
        weightByDate: <String, double>{
          '2026-09-08': 65.0,
          '2026-09-12': 65.0 + delta,
        },
      );
      expect(
        weeklySummarySentences(weight(0.5)),
        contains(WeeklySummarySentence.weightUp),
      );
      expect(
        weeklySummarySentences(weight(-0.6)),
        contains(WeeklySummarySentence.weightDown),
      );
      expect(
        weeklySummarySentences(weight(0.05)),
        contains(WeeklySummarySentence.weightSame),
      );
      final noWeight = compute(
        kcalByDate: <String, double>{'2026-09-08': 2000},
      );
      expect(
        weeklySummarySentences(
          noWeight,
        ).where((s) => s.name.startsWith('weight')),
        isEmpty,
      );
    });

    test('完整形态：断食 + 摄入 + 体重共 3 句，顺序固定', () {
      final s = compute(
        kcalByDate: <String, double>{'2026-09-08': 1900},
        qualifiedDates: <String>{
          '2026-09-07',
          '2026-09-08',
          '2026-09-09',
          '2026-09-10',
          '2026-09-11',
          '2026-09-01',
          '2026-09-02',
          '2026-09-03',
        },
        weightByDate: <String, double>{'2026-09-08': 65.0, '2026-09-12': 64.4},
        targetKcal: 2000,
      );
      expect(weeklySummarySentences(s), <WeeklySummarySentence>[
        WeeklySummarySentence.fastingMore,
        WeeklySummarySentence.intakeWithin,
        WeeklySummarySentence.weightDown,
      ]);
    });
  });

  test('摄入偏离百分比（取绝对值取整）', () {
    final above = compute(
      kcalByDate: <String, double>{'2026-09-08': 2600},
      targetKcal: 2000,
    );
    expect(weeklySummaryIntakeDeviationPercent(above), 30);
    final below = compute(
      kcalByDate: <String, double>{'2026-09-08': 1500},
      targetKcal: 2000,
    );
    expect(weeklySummaryIntakeDeviationPercent(below), 25);
  });
}
