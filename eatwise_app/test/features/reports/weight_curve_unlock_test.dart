import 'package:eatwise/features/reports/domain/weight_curve_unlock.dart';
import 'package:flutter_test/flutter_test.dart';

/// 体重曲线解锁钩子纯函数（薄荷走查 P3）：<3 条盖遮罩，N = 3 − 已有条数。
void main() {
  group('weightRecordsToUnlock（阈值 3 条）', () {
    test('0 条 → 还差 3 条', () {
      expect(weightRecordsToUnlock(0), 3);
    });

    test('1 条 → 还差 2 条；2 条 → 还差 1 条', () {
      expect(weightRecordsToUnlock(1), 2);
      expect(weightRecordsToUnlock(2), 1);
    });

    test('≥3 条 → 0（正常显示曲线，不盖遮罩）', () {
      expect(weightRecordsToUnlock(kWeightCurveUnlockThreshold), 0);
      expect(weightRecordsToUnlock(10), 0);
    });

    test('负数防御 → 按 0 条处理', () {
      expect(weightRecordsToUnlock(-1), kWeightCurveUnlockThreshold);
    });
  });
}
