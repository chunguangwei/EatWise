/// 拍照识别（端侧视觉）纯函数层：prompt 模板 + 宽松解析 + 食物库匹配 +
/// 置信度策略。零 Flutter/插件依赖，可单测。
///
/// Prompt 在端侧营养估算 spike §6 v5 定稿基础上改视觉版：多模态同一份
/// 营养约束话术，输出从「四个数字」扩展为「食物名 + 四个数字」一行。
/// 采样参数沿用 v5（temperature=0.15, topK=1, seed=42）。
library;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/storage/database.dart';

/// 视觉版 system instruction（v5 营养约束逐字保留，仅加识别与命名约束）。
const String kPhotoRecognitionSystemPrompt =
    '你是食物拍照识别助手。用户给你一张餐食照片，你识别画面中最主要的一种食物，'
    '并估算其每100克可食部的营养。'
    '按通常食用状态估算：米饭、面条等主食指煮熟后的成品，菜名指烧制完成的成品菜，肉蛋水果按生鲜。'
    '食物名用最常见的通用中文名（如 米饭、番茄炒蛋、鸡胸肉），不要品牌名，不要份量和形容词。'
    '常见食物每100克热量参考范围：蔬菜20-50千卡，水果30-90千卡，熟主食110-150千卡，'
    '瘦肉蛋100-200千卡，肥肉菜品250-500千卡，含糖饮料35-50千卡。'
    '一般规律：新鲜水果蔬菜水分高，碳水化合物通常不超过25克/100克（干果除外）；'
    '可乐、果汁等纯饮料的脂肪和蛋白质为0。'
    '只输出一行，格式为：食物名 => 热量 => 蛋白质 => 碳水 => 脂肪，'
    '单位分别是千卡、克、克、克（每100克）。只写食物名、数字和 =>，不要任何其他文字。'
    '看不清或画面不是食物时，只输出：无法识别。';

/// 视觉版 user 模板（图片随消息一并送入，文本只需点题）。
String buildPhotoRecognitionPrompt() {
  return '识别这张照片中的主要食物。\n结果：';
}

/// 解析出的视觉识别结果（食物名 + 每 100g 估算营养值）。
final class ParsedPhotoRecognition {
  const ParsedPhotoRecognition({required this.name, required this.values});

  /// 模型给出的食物名（已去前缀/杂质）。
  final String name;

  /// 模型估算的每 100g 营养（只作匹配参考与存疑判定，不入账）。
  final OnDeviceNutritionValues values;
}

/// 宽松解析正则：全文本取第一组 `名 => a => b => c => d`，
/// 容忍行内前后杂质与尾部多余 `=>`（沿用 v5 文本版的宽松策略）。
final RegExp _parseRegex = RegExp(
  r'([^\s=>\d][^=>\n]*?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 食物名前缀杂质（模型偶发复述「食物：」「结果：」等提示词片段）。
final RegExp _namePrefixRegex = RegExp(r'^(食物|结果|名称|答案)\s*[:：]\s*');

/// 解析视觉模型输出原文；匹配失败/「无法识别」返回 null（上层走降级）。
ParsedPhotoRecognition? parsePhotoRecognitionOutput(String text) {
  final m = _parseRegex.firstMatch(text);
  if (m == null) return null;
  final values = [
    for (var i = 2; i <= 5; i++) double.tryParse(m.group(i)!) ?? double.nan,
  ];
  if (values.any((v) => !v.isFinite)) return null;
  final name = m.group(1)!.replaceAll(_namePrefixRegex, '').trim();
  if (name.isEmpty || name.contains('无法识别')) return null;
  return ParsedPhotoRecognition(
    name: name,
    values: OnDeviceNutritionValues(
      kcal: values[0],
      proteinG: values[1],
      carbsG: values[2],
      fatG: values[3],
    ),
  );
}

/// 食物库匹配结果（命中条目 + 是否名字精确相等）。
final class FoodNameMatch {
  const FoodNameMatch({required this.food, required this.exact});

  final Food food;

  /// 识别名与库内中/英文名精确相等（忽略大小写与首尾空白）。
  final bool exact;
}

/// 用识别名搜食物库并取最优条目：中/英文名精确命中优先，
/// 否则取搜索首条（LIKE 模糊命中）；无结果返回 null（上层走降级）。
///
/// [search] 即仓储的 searchFoods（本地 drift 双语 LIKE）。
Future<FoodNameMatch?> matchFoodByName(
  Future<List<Food>> Function(String query) search,
  String name,
) async {
  final query = name.trim();
  if (query.isEmpty) return null;
  final hits = await search(query);
  if (hits.isEmpty) return null;
  final normalized = query.toLowerCase();
  for (final food in hits) {
    if (food.nameZh.trim().toLowerCase() == normalized ||
        food.nameEn.trim().toLowerCase() == normalized) {
      return FoodNameMatch(food: food, exact: true);
    }
  }
  return FoodNameMatch(food: hits.first, exact: false);
}

/// 候选置信度策略（端侧模型无原生置信度，按信号合成）：
/// - sanity-clamp 命中（[isNutritionEstimateDubious]）→ 0.5，必标「请确认」；
/// - 名字精确命中食物库 → 0.85（库内精准营养值兜底，只需确认份量）；
/// - 仅模糊命中 → 0.6，低于 RecognizedCandidate 低置信阈值 0.7，标「请确认」。
double photoRecognitionConfidence({
  required bool dubious,
  required bool exactNameMatch,
}) {
  if (dubious) return 0.5;
  return exactNameMatch ? 0.85 : 0.6;
}
