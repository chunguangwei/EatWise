import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手动记运动领域纯函数测试：MET 系数表 / kcal 估算 / 系统+手动合并口径。
void main() {
  group('MET 系数表', () {
    test('17 种常见运动齐备（含篮球/足球/乒乓球/网球/健身操补齐项），MET 均为正', () {
      expect(exerciseTypes, hasLength(17));
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
        'basketball',
        'soccer',
        'tableTennis',
        'tennis',
        'dance',
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

  group('estimateKcalFromStepsWalk（步数 → 步行消耗，〔待营养背书〕）', () {
    test(
      '1466 步 60kg：距离 1466 × 0.75m = 1.0995km → 60 × 1.0995 × 1.036 ≈ 68.3',
      () {
        expect(
          estimateKcalFromStepsWalk(steps: 1466, weightKg: 60),
          moreOrLessEquals(60 * 1.0995 * 1.036, epsilon: 1e-9),
        );
      },
    );

    test('带截图距离时优先用距离（60kg × 1.10km × 1.036 = 68.376）', () {
      expect(
        estimateKcalFromStepsWalk(steps: 1466, weightKg: 60, distanceKm: 1.10),
        moreOrLessEquals(68.376, epsilon: 1e-9),
      );
    });

    test('非法输入（步数/体重 ≤ 0）返回 0', () {
      expect(estimateKcalFromStepsWalk(steps: 0, weightKg: 60), 0);
      expect(estimateKcalFromStepsWalk(steps: 1000, weightKg: 0), 0);
    });
  });

  group('mergeSteps（系统步数 + 手动/截图步数合计）', () {
    test('系统 + 手动叠加 / 仅手动（unsupported）/ 仅系统', () {
      expect(mergeSteps(systemSteps: 6200, manualSteps: 1466), 7666);
      expect(mergeSteps(manualSteps: 1466), 1466);
      expect(mergeSteps(systemSteps: 6200), 6200);
    });

    test('两者皆无或皆为 0 → null（UI 走「—」）', () {
      expect(mergeSteps(), isNull);
      expect(mergeSteps(systemSteps: 0, manualSteps: 0), isNull);
      expect(mergeSteps(systemSteps: null, manualSteps: null), isNull);
    });
  });
}
