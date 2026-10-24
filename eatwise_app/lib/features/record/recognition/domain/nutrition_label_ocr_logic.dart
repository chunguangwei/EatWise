/// 营养表拍照 OCR（端侧视觉）纯函数层：prompt 模板 + 严格解析 + kJ→kcal
/// 换算 + 合理性校验。零 Flutter/插件依赖，可单测。
///
/// 输出协议（单行五段）：`能量数值 单位 => 蛋白质 => 碳水 => 脂肪 => per100g`。
/// 能量单位与计量基准都必须明确，缺省时不猜单位、不把每份/每100ml 当每100g。
library;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';

/// kJ → kcal 换算系数（1 kcal = 4.184 kJ）。
const double kKjPerKcal = 4.184;

/// 当前可安全自动填入克数表单的计量基准。
enum NutritionLabelBasis { per100g }

/// 营养表 OCR system instruction（读表专用；能量单位照抄防换算幻觉）。
const String kNutritionLabelOcrSystemPrompt =
    '你是营养成分表读表助手。用户给你一张包装营养成分表的照片，你只读'
    '「每100克」那一列的四个数值：能量、蛋白质、碳水化合物、脂肪。'
    '注意：中国营养表的能量单位通常是千焦（kJ），请照抄表中印刷的数值和单位，'
    '不要自己换算；进口食品可能是千卡（kcal）。'
    '每100毫升、每份或每包没有密度/明确份量时不能当作每100克，直接输出无法识别。'
    '只输出一行，格式为：能量数值 单位 => 蛋白质 => 碳水 => 脂肪 => per100g。'
    '能量单位必须明确写出 kJ/kcal/千焦/千卡，最后一段固定写 per100g。'
    '例如 能量1540千焦 蛋白质7.2克 碳水53.0克 脂肪32.1克 的表 → 1540 kJ => 7.2 => 53.0 => 32.1 => per100g；'
    '能量2016kJ 蛋白质8.0克 碳水0克 脂肪89克 → 2016 kJ => 8.0 => 0 => 89 => per100g。'
    '不要其他解释。看不清或不是营养成分表时，只输出：无法识别。';

/// 营养表 OCR user 模板（图片随消息一并送入）。
String buildNutritionLabelPrompt() {
  return '读出这张营养成分表的每100克数值。\n结果：';
}

/// 整行严格匹配：数字不接受负号、千分位或科学计数法片段；能量单位与
/// per100g 计量基准必填，避免从非法数字中部截取出一个“看似正确”的值。
final RegExp _labelRegex = RegExp(
  r'^\s*(\d+(?:\.\d+)?)\s*(kJ|kcal|千焦|千卡)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(per100g)\s*$',
  caseSensitive: false,
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
  final unit = m.group(2)!.toLowerCase();
  // kJ/千焦 → kcal 换算（Dart 侧定值，不信模型口算）；kcal/千卡照用。
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
  if (v.kcal < 0 || v.kcal > 900) return true;
  return isNutritionEstimateDubious(v);
}
