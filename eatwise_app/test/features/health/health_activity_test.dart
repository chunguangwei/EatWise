import 'package:eatwise/features/health/domain/health_activity.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阶段 D 领域纯函数：步数粗估 / 结余口径 / 摘要展示取值。
void main() {
  group('estimateKcalFromSteps（步数 → 消耗粗估，备用换算）', () {
    test('默认 60 kg：万步 ≈ 240 kcal', () {
      expect(estimateKcalFromSteps(10000), closeTo(240, 0.01));
    });

    test('体重加权：80 kg 万步 ≈ 320 kcal', () {
      expect(estimateKcalFromSteps(10000, weightKg: 80), closeTo(320, 0.01));
    });

    test('零步/负步归零', () {
      expect(estimateKcalFromSteps(0), 0);
      expect(estimateKcalFromSteps(-100), 0);
    });
  });

  group('energyBalanceKcal（摄入 − 消耗结余）', () {
    test('盈余为正，缺口为负', () {
      expect(
        energyBalanceKcal(intakeKcal: 1500, burnKcal: 245),
        closeTo(1255, 0.01),
      );
      expect(
        energyBalanceKcal(intakeKcal: 1200, burnKcal: 1500),
        closeTo(-300, 0.01),
      );
    });
  });

  group('HealthTodaySummary', () {
    test('全空判定', () {
      expect(const HealthTodaySummary().isEmpty, isTrue);
      expect(const HealthTodaySummary(steps: 100).isEmpty, isFalse);
    });

    test('displayBurnKcal：系统活动能量优先，缺失时按步数粗估兜底', () {
      const withEnergy = HealthTodaySummary(steps: 5000, activeEnergyKcal: 200);
      expect(withEnergy.displayBurnKcal, 200);
      const stepsOnly = HealthTodaySummary(steps: 5000);
      expect(stepsOnly.displayBurnKcal, closeTo(120, 0.01));
      const none = HealthTodaySummary();
      expect(none.displayBurnKcal, isNull);
    });
  });
}
