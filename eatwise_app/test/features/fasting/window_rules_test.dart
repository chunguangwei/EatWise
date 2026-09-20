import 'package:eatwise/features/fasting/domain/window_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planTypeForEatingHours', () {
    test('进食时长派生 planType（服务端契约）', () {
      expect(planTypeForEatingHours(10), '14:10');
      expect(planTypeForEatingHours(8), '16:8');
      expect(planTypeForEatingHours(6), '18:6');
    });

    test('非 6/8/10 抛 ArgumentError', () {
      expect(() => planTypeForEatingHours(12), throwsArgumentError);
      expect(() => planTypeForEatingHours(0), throwsArgumentError);
    });
  });

  group('formatClock / formatWindow', () {
    test('墙钟分钟 → HH:mm 补零', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(540), '09:00');
      expect(formatClock(1439), '23:59');
    });

    test('窗口标签；跨午夜 end < start 原样展示', () {
      expect(formatWindow(540, 1140), '09:00–19:00');
      expect(formatWindow(23 * 60, 540), '23:00–09:00');
    });
  });

  group('sameWindow', () {
    test('只比起止分钟，跨午夜与同日不等价', () {
      expect(sameWindow(540, 1140, 540, 1140), isTrue);
      expect(sameWindow(540, 1140, 540, 1139), isFalse);
      // 同日窗口 (0,540) 与跨午夜窗口 (0,540)→(0,540) 起止相同即等价；
      // 起点不同必不等价。
      expect(sameWindow(0, 540, 60, 540), isFalse);
    });
  });

  group('buildWindow', () {
    test('常规窗口：09:00 + 10h → 19:00，planId 14:10@09:00', () {
      final w = buildWindow(eatingHours: 10, startMinutes: 540);
      expect(w.startMinutes, 540);
      expect(w.endMinutes, 1140);
      expect(w.planType, '14:10');
      expect(w.planId, '14:10@09:00');
      expect(w.fastingHours, 14);
      final plan = w.toFastingPlan();
      expect(plan.id, '14:10@09:00');
      expect(plan.eatStartMinutes, 540);
      expect(plan.eatEndMinutes, 1140);
      expect(plan.eatWindowMinutes, 600);
    });

    test('跨午夜：23:00 + 10h → 09:00（end 落次日）', () {
      final w = buildWindow(eatingHours: 10, startMinutes: 23 * 60);
      expect(w.endMinutes, 540);
      expect(w.planId, '14:10@23:00');
      expect(w.toFastingPlan().eatWindowMinutes, 600);
    });

    test('6h 窗口从 12:00 → 18:00，planId 18:6@12:00', () {
      final w = buildWindow(eatingHours: 6, startMinutes: 720);
      expect(w.endMinutes, 1080);
      expect(w.planId, '18:6@12:00');
      expect(w.fastingHours, 18);
    });

    test('startMinutes 越界抛 ArgumentError', () {
      expect(
        () => buildWindow(eatingHours: 8, startMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => buildWindow(eatingHours: 8, startMinutes: 1440),
        throwsArgumentError,
      );
    });

    test('eatingHours 非法抛 ArgumentError', () {
      expect(
        () => buildWindow(eatingHours: 7, startMinutes: 0),
        throwsArgumentError,
      );
    });

    test('窗口时长恒等于 eatingHours×60（FastingPlan.eatWindowMinutes 口径）', () {
      for (final hours in <int>[6, 8, 10]) {
        for (final start in <int>[0, 540, 1380, 1439]) {
          final w = buildWindow(eatingHours: hours, startMinutes: start);
          expect(
            w.toFastingPlan().eatWindowMinutes,
            hours * 60,
            reason: 'hours=$hours start=$start',
          );
        }
      }
    });
  });
}
