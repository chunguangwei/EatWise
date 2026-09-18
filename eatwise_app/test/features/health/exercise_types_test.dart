import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手动记运动领域纯函数测试：MET 系数表 / kcal 估算 / 系统+手动合并口径。
void main() {
  group('MET 系数表', () {
    test('12 种常见运动齐备，MET 均为正', () {
      expect(exerciseTypes, hasLength(12));
      expect(exerciseTypes.map((e) => e.key), <String>[
        'walk',
        'jog',
        'run',
        'cycling',
        'swimming',
        'jumpRope',
        'yoga',
        'strength',
        'elliptical',
        'hiking',
        'badminton',
        'hiit',
      ]);
      for (final type in exerciseTypes) {
        expect(type.met, greaterThan(0), reason: type.key);
      }
    });

    test('exerciseTypeByKey：命中返回类型，未知键返回 null（向前兼容）', () {
      expect(exerciseTypeByKey('jog')?.met, 7.0);
      expect(exerciseTypeByKey('hiit')?.key, 'hiit');
      expect(exerciseTypeByKey('future-type'), isNull);
    });
  });

  group('estimateExerciseKcal（MET × 体重 × 时长小时）', () {
    test('慢跑 60kg 30 分钟 = 7.0 × 60 × 0.5 = 210 kcal', () {
      expect(
        estimateExerciseKcal(met: 7.0, weightKg: 60, minutes: 30),
        moreOrLessEquals(210, epsilon: 1e-9),
      );
    });

    test('体重缺省用 60kg 兜底：走路 60 分钟 = 3.5 × 60 × 1 = 210 kcal', () {
      expect(
        estimateExerciseKcal(
          met: 3.5,
          weightKg: defaultExerciseWeightKg,
          minutes: 60,
        ),
        moreOrLessEquals(210, epsilon: 1e-9),
      );
    });

    test('非法输入（met/体重/时长 ≤ 0）返回 0', () {
      expect(estimateExerciseKcal(met: 0, weightKg: 60, minutes: 30), 0);
      expect(estimateExerciseKcal(met: 7, weightKg: 0, minutes: 30), 0);
      expect(estimateExerciseKcal(met: 7, weightKg: 60, minutes: 0), 0);
      expect(estimateExerciseKcal(met: 7, weightKg: 60, minutes: -5), 0);
    });
  });

  group('mergeBurnKcal（系统活动能量 + 手动运动合计）', () {
    test('系统 + 手动叠加', () {
      expect(mergeBurnKcal(systemKcal: 250, manualKcal: 180), 430);
    });

    test('仅手动（unsupported 设备）/ 仅系统', () {
      expect(mergeBurnKcal(manualKcal: 180), 180);
      expect(mergeBurnKcal(systemKcal: 250), 250);
    });

    test('两者皆无或皆为 0 → null（UI 走「—」/不出卡）', () {
      expect(mergeBurnKcal(), isNull);
      expect(mergeBurnKcal(systemKcal: 0, manualKcal: 0), isNull);
      expect(mergeBurnKcal(systemKcal: null, manualKcal: null), isNull);
    });
  });
}
