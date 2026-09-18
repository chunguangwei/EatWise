/// 三大营养素供能比例纯函数（阶段 E 食物详情页三圆环，薄荷对标合并设计）。
///
/// 圆环展示的是**供能比例**而非重量比例：换算系数沿用 D-04 §2.1
/// （蛋白质/碳水 4 kcal/g、脂肪 9 kcal/g），脂肪供能效率是碳水和蛋白质
/// 的 2.25 倍——详情页人话注释据此编写，避免薄荷当年「用户误读为重量
/// 比例」的坑。
library;

/// 单个营养素的供能换算结果。
final class MacroEnergy {
  const MacroEnergy({
    required this.grams,
    required this.kcal,
    required this.share,
  });

  /// 重量（g，输入原值）。
  final double grams;

  /// 供能（kcal）= grams × 系数。
  final double kcal;

  /// 占三大营养素总供能的比例（0–1）；总供能为 0 时恒 0。
  final double share;
}

/// 三大营养素供能拆解。
final class MacroEnergyBreakdown {
  const MacroEnergyBreakdown({
    required this.protein,
    required this.carb,
    required this.fat,
    required this.totalKcal,
  });

  /// 蛋白质供能拆解。
  final MacroEnergy protein;

  /// 碳水供能拆解。
  final MacroEnergy carb;

  /// 脂肪供能拆解。
  final MacroEnergy fat;

  /// 三大营养素合计供能（kcal）。
  final double totalKcal;
}

/// 蛋白质供能系数（kcal/g，D-04 §2.1）。
const double proteinKcalPerGram = 4;

/// 碳水供能系数（kcal/g，D-04 §2.1）。
const double carbKcalPerGram = 4;

/// 脂肪供能系数（kcal/g，D-04 §2.1）。
const double fatKcalPerGram = 9;

/// 千卡 → 步数换算系数（步/kcal，薄荷走查 P1「大约需走 N 步」）。
/// 薄荷口径反推：149 kcal → 5546 步 ≈ 37.2 步/kcal，取整 37。
/// 属估算假设，数值改动必须先过营养/运动学背书。
const double stepsPerKcal = 37;

/// 千卡 → 「大约需走 N 步」（四舍五入到整数步；负值按 0 计）。
int stepsFromKcal(double kcal) => kcal <= 0 ? 0 : (kcal * stepsPerKcal).round();

/// 重量 → 供能 → 占比。总供能为 0（如三项皆 0）时所有 share 返回 0，
/// 调用方据此走「无供能数据」展示，不做除零。
MacroEnergyBreakdown computeMacroEnergyBreakdown({
  required double proteinG,
  required double carbG,
  required double fatG,
}) {
  final proteinKcal = proteinG * proteinKcalPerGram;
  final carbKcal = carbG * carbKcalPerGram;
  final fatKcal = fatG * fatKcalPerGram;
  final total = proteinKcal + carbKcal + fatKcal;
  double shareOf(double kcal) => total <= 0 ? 0 : kcal / total;
  return MacroEnergyBreakdown(
    protein: MacroEnergy(
      grams: proteinG,
      kcal: proteinKcal,
      share: shareOf(proteinKcal),
    ),
    carb: MacroEnergy(grams: carbG, kcal: carbKcal, share: shareOf(carbKcal)),
    fat: MacroEnergy(grams: fatG, kcal: fatKcal, share: shareOf(fatKcal)),
    totalKcal: total,
  );
}
