import 'package:eatwise/features/settings/domain/bmi.dart';
import 'package:flutter_test/flutter_test.dart';

/// BMI 纯函数测试（薄荷走查 P1：中国成人标准 WS/T 428-2013）。
void main() {
  test('BMI = 体重 ÷ 身高 m²', () {
    expect(computeBmi(heightCm: 176, weightKg: 75), closeTo(24.22, 0.01));
    expect(computeBmi(heightCm: 162, weightKg: 55), closeTo(20.96, 0.01));
  });

  test('区间判定（偏低 <18.5 / 标准 18.5–24 / 偏高 24–28 / 肥胖 ≥28）', () {
    expect(classifyBmi(17.0), BmiZone.underweight);
    expect(classifyBmi(18.4), BmiZone.underweight);
    // 边界归上侧：18.5 属标准、24 属偏高、28 属肥胖。
    expect(classifyBmi(18.5), BmiZone.normal);
    expect(classifyBmi(22.0), BmiZone.normal);
    expect(classifyBmi(23.9), BmiZone.normal);
    expect(classifyBmi(24.0), BmiZone.overweight);
    expect(classifyBmi(27.9), BmiZone.overweight);
    expect(classifyBmi(28.0), BmiZone.obese);
    expect(classifyBmi(35.0), BmiZone.obese);
  });
}
