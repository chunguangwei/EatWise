import 'package:eatwise/features/record/domain/nrv_reference.dart';
import 'package:flutter_test/flutter_test.dart';

/// NRV% 明细行纯函数测试（薄荷走查 P1：GB 28050-2011 附录 A 国标值）。
void main() {
  test('国标 NRV 值（GB 28050-2011 附录 A）', () {
    expect(nrvEnergyKj, 8400);
    expect(nrvProteinG, 60);
    expect(nrvFatG, 60);
    expect(nrvCarbG, 300);
    expect(nrvSodiumMg, 2000);
  });

  test('四项数据：能量换算 kJ 出行，无钠不出钠行，顺序能量在前', () {
    // 白米饭每 100g：116 kcal / 蛋白质 2.6 / 碳水 25.9 / 脂肪 0.3。
    final rows = computeNrvRows(
      kcalPer100g: 116,
      proteinPer100g: 2.6,
      carbPer100g: 25.9,
      fatPer100g: 0.3,
    );
    expect(rows.map((r) => r.nutrient), <NrvNutrient>[
      NrvNutrient.energy,
      NrvNutrient.protein,
      NrvNutrient.carb,
      NrvNutrient.fat,
    ]);
    // 能量：116 × 4.184 = 485.344 kJ；NRV% = 485.344 / 8400 × 100 ≈ 5.78。
    expect(rows[0].amount, closeTo(485.344, 1e-9));
    expect(rows[0].nrvPercent.round(), 6);
    // 蛋白质 2.6 / 60 → 4%。
    expect(rows[1].nrvPercent.round(), 4);
    // 碳水 25.9 / 300 → 9%。
    expect(rows[2].nrvPercent.round(), 9);
    // 脂肪 0.3 / 60 → 1%（0.5 四舍五入）。
    expect(rows[3].nrvPercent.round(), 1);
  });

  test('传入钠数据时追加钠行（NRV 2000mg）', () {
    final rows = computeNrvRows(
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbPer100g: 10,
      fatPer100g: 3,
      sodiumMgPer100g: 500,
    );
    expect(rows.length, 5);
    expect(rows.last.nutrient, NrvNutrient.sodium);
    expect(rows.last.amount, 500);
    expect(rows.last.nrvPercent, 25);
  });
}
