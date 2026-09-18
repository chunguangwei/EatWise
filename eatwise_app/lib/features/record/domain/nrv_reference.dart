/// NRV（营养素参考值）常量与每 100g 明细行计算（薄荷走查 P1：食物详情
/// 营养素表 NRV% 列）。
///
/// NRV 国标值来源：GB 28050-2011《食品安全国家标准 预包装食品营养标签
/// 通则》附录 A——能量 8400 kJ、蛋白质 60 g、脂肪 60 g、碳水化合物 300 g、
/// 钠 2000 mg。数值为国标定值，改动必须同步规格文档。
library;

import 'package:eatwise/features/record/recognition/domain/nutrition_label_ocr_logic.dart'
    show kKjPerKcal;

/// 能量 NRV（kJ，GB 28050-2011 附录 A）。
const double nrvEnergyKj = 8400;

/// 蛋白质 NRV（g，GB 28050-2011 附录 A）。
const double nrvProteinG = 60;

/// 脂肪 NRV（g，GB 28050-2011 附录 A）。
const double nrvFatG = 60;

/// 碳水化合物 NRV（g，GB 28050-2011 附录 A）。
const double nrvCarbG = 300;

/// 钠 NRV（mg，GB 28050-2011 附录 A）。
const double nrvSodiumMg = 2000;

/// NRV 明细行营养素种类（展示顺序即枚举顺序：能量在前，对齐国标标签格式）。
enum NrvNutrient { energy, protein, carb, fat, sodium }

/// 一行 NRV 明细：含量（已换算为行单位）+ NRV%。
final class NrvRow {
  const NrvRow({
    required this.nutrient,
    required this.amount,
    required this.nrvPercent,
  });

  /// 营养素种类。
  final NrvNutrient nutrient;

  /// 每 100g 含量（能量行为 kJ，钠行为 mg，其余为 g）。
  final double amount;

  /// NRV% = 含量 ÷ NRV × 100（四舍五入到整数百分比前的原值）。
  final double nrvPercent;
}

/// 每 100g 营养明细 → NRV 行列表。
///
/// 只有传入了数据的营养素才出行（食物库当前只有四项、无钠字段，
/// sodiumMgPer100g 缺省不出行；后续食物库补字段后透传即可）。
List<NrvRow> computeNrvRows({
  required double kcalPer100g,
  required double proteinPer100g,
  required double carbPer100g,
  required double fatPer100g,
  double? sodiumMgPer100g,
}) {
  return <NrvRow>[
    NrvRow(
      nutrient: NrvNutrient.energy,
      amount: kcalPer100g * kKjPerKcal,
      nrvPercent: kcalPer100g * kKjPerKcal / nrvEnergyKj * 100,
    ),
    NrvRow(
      nutrient: NrvNutrient.protein,
      amount: proteinPer100g,
      nrvPercent: proteinPer100g / nrvProteinG * 100,
    ),
    NrvRow(
      nutrient: NrvNutrient.carb,
      amount: carbPer100g,
      nrvPercent: carbPer100g / nrvCarbG * 100,
    ),
    NrvRow(
      nutrient: NrvNutrient.fat,
      amount: fatPer100g,
      nrvPercent: fatPer100g / nrvFatG * 100,
    ),
    if (sodiumMgPer100g != null)
      NrvRow(
        nutrient: NrvNutrient.sodium,
        amount: sodiumMgPer100g,
        nrvPercent: sodiumMgPer100g / nrvSodiumMg * 100,
      ),
  ];
}
