import 'package:eatwise/features/record/domain/macro_energy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 供能比例纯函数测试（阶段 E 食物详情页三圆环）。
void main() {
  test('重量 → 供能 → 占比（4/4/9 换算，D-04 §2.1）', () {
    // 白米饭每 100g：蛋白质 2.6 / 碳水 25.9 / 脂肪 0.3。
    final r = computeMacroEnergyBreakdown(
      proteinG: 2.6,
      carbG: 25.9,
      fatG: 0.3,
    );
    expect(r.protein.kcal, closeTo(10.4, 1e-9));
    expect(r.carb.kcal, closeTo(103.6, 1e-9));
    expect(r.fat.kcal, closeTo(2.7, 1e-9));
    expect(r.totalKcal, closeTo(116.7, 1e-9));
    // 供能占比 ≠ 重量占比：碳水重量占 90%，供能占 ~88.8%。
    expect(r.carb.share, closeTo(103.6 / 116.7, 1e-9));
    expect(r.protein.share, closeTo(10.4 / 116.7, 1e-9));
    expect(r.fat.share, closeTo(2.7 / 116.7, 1e-9));
  });

  test('脂肪供能效率是碳水的 2.25 倍（人话注释依据）', () {
    const ratio = fatKcalPerGram / carbKcalPerGram;
    expect(ratio, 2.25);
    expect(fatKcalPerGram / proteinKcalPerGram, 2.25);
  });

  test('三项皆 0：总供能为 0，占比全部返回 0（不除零）', () {
    final r = computeMacroEnergyBreakdown(proteinG: 0, carbG: 0, fatG: 0);
    expect(r.totalKcal, 0);
    expect(r.protein.share, 0);
    expect(r.carb.share, 0);
    expect(r.fat.share, 0);
  });

  test('单一营养素：占比为 1', () {
    final r = computeMacroEnergyBreakdown(proteinG: 10, carbG: 0, fatG: 0);
    expect(r.protein.share, 1);
    expect(r.carb.share, 0);
    expect(r.fat.share, 0);
  });

  test('占比之和为 1', () {
    final r = computeMacroEnergyBreakdown(
      proteinG: 13.3,
      carbG: 2.8,
      fatG: 8.8,
    );
    expect(r.protein.share + r.carb.share + r.fat.share, closeTo(1, 1e-9));
  });

  test('千卡 → 步数：37 步/kcal（薄荷口径估算，待背书）', () {
    // 薄荷反推锚点：149 kcal ≈ 5546 步（37.2 步/kcal 取整 37）。
    expect(stepsFromKcal(149), 5513);
    expect(stepsFromKcal(116), 4292);
    expect(stepsFromKcal(0), 0);
    expect(stepsFromKcal(-5), 0);
    // 小份量四舍五入。
    expect(stepsFromKcal(0.5), 19);
  });
}
