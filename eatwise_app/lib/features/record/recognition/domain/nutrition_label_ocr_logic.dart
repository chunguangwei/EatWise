/// 营养表拍照 OCR（端侧视觉）纯函数层：prompt 模板 + 宽松解析 + kJ→kcal
/// 换算 + 合理性校验。零 Flutter/插件依赖，可单测。
///
/// 输出协议（单行五段）：`能量数值 单位 => 蛋白质 => 碳水 => 脂肪`，
/// 能量单位按包装印刷照抄（中国营养表多为 kJ；1kcal = 4.184kJ 在 Dart
/// 侧换算，不信模型口算）。采样参数沿用 v5（低温 topK=1）。
library;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';

/// kJ → kcal 换算系数（1 kcal = 4.184 kJ）。
const double kKjPerKcal = 4.184;

/// 营养表 OCR system instruction（读表专用；能量单位照抄防换算幻觉）。
const String kNutritionLabelOcrSystemPrompt =
    '你是营养成分表读表助手。用户给你一张包装营养成分表的照片，你读出'
    '「每100克」或「每100毫升」那一列的四个数值：能量、蛋白质、碳水化合物、脂肪。'
    '注意：中国营养表的能量单位通常是千焦（kJ），请照抄表中印刷的数值和单位，'
    '不要自己换算；进口食品可能是千卡（kcal）。'
    '如果表中有每份/每包等多列数值，只读每100克（或每100毫升）那一列。'
    '只输出一行，格式为：能量数值 单位 => 蛋白质 => 碳水 => 脂肪，'
    '例如 能量1540千焦 蛋白质7.2克 碳水53.0克 脂肪32.1克 的表 → 1540 kJ => 7.2 => 53.0 => 32.1；'
    '能量2016kJ 蛋白质8.0克 碳水0克 脂肪89克 → 2016 kJ => 8.0 => 0 => 89。'
    '只写数字、单位和 =>，不要任何其他文字。看不清或不是营养成分表时，只输出：无法识别。';

/// 营养表 OCR user 模板（图片随消息一并送入）。
String buildNutritionLabelPrompt() {
  return '读出这张营养成分表的每100克数值。\n结果：';
}

/// 宽松解析正则：全文本取第一组 `数值[单位] => a => b => c`，
/// 单位可选（kJ/kcal/千焦/千卡，大小写不敏感），容忍前后杂质。
final RegExp _labelRegex = RegExp(
  r'(\d+(?:\.\d+)?)\s*([kK][jJ]|[kK][cC][aA][lL]|千焦|千卡)?\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 解析营养表 OCR 输出原文 → 每 100g 营养值（kJ 已换算 kcal）；
/// 匹配失败/「无法识别」返回 null（上层走降级）。
OnDeviceNutritionValues? parseNutritionLabelOutput(String text) {
  final m = _labelRegex.firstMatch(text);
  if (m == null) return null;
  final energyRaw = double.tryParse(m.group(1)!);
  final protein = double.tryParse(m.group(3)!);
  final carb = double.tryParse(m.group(4)!);
  final fat = double.tryParse(m.group(5)!);
  final values = [energyRaw, protein, carb, fat];
  if (values.any((v) => v == null || !v.isFinite)) return null;
  final unit = (m.group(2) ?? '').toLowerCase();
  // kJ/千焦 → kcal 换算（Dart 侧定值，不信模型口算）；kcal/缺省照用。
  final kcal = (unit == 'kj' || unit == '千焦')
      ? energyRaw! / kKjPerKcal
      : energyRaw!;
  return OnDeviceNutritionValues(
    kcal: double.parse(kcal.toStringAsFixed(1)),
    proteinG: protein!,
    carbsG: carb!,
    fatG: fat!,
  );
}

/// 读数合理性校验：复用 sanity-clamp（宏量超限/折算偏差），另加
/// 热量物理上限（每 100g 不可能超过 900 千卡，纯油脂也就 ~900）。
bool isNutritionLabelReadingDubious(OnDeviceNutritionValues v) {
  if (v.kcal <= 0 || v.kcal > 900) return true;
  return isNutritionEstimateDubious(v);
}
