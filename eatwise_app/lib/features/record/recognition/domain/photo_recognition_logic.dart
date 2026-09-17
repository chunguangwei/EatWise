/// 拍照识别（端侧视觉）纯函数层：prompt 模板 + 宽松解析 + 食物库匹配 +
/// 置信度策略。零 Flutter/插件依赖，可单测。
///
/// Prompt 在端侧营养估算 spike §6 v5 定稿基础上改视觉版：多模态同一份
/// 营养约束话术，输出从「四个数字」扩展为「食物名 + 四个数字」一行。
/// 采样参数沿用 v5（temperature=0.15, topK=1, seed=42）。
library;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/storage/database.dart';

/// 视觉版 system instruction（v5 营养约束逐字保留，加识别与命名约束）。
///
/// 命名约束（真机反馈「只给类别词」后加固）：必须输出**最具体的常见
/// 食物名**，禁止只输出类别词；双语输出（USDA 库英文为主，英文名精确
/// 匹配命中率显著高于中文模糊匹配）；few-shot 示例定死输出格式与粒度。
const String kPhotoRecognitionSystemPrompt =
    '你是食物拍照识别助手。用户给你一张餐食照片，你识别画面中最主要的一种食物，'
    '并估算其每100克可食部的营养。'
    '按通常食用状态估算：米饭、面条等主食指煮熟后的成品，菜名指烧制完成的成品菜，肉蛋水果按生鲜。'
    '食物名必须是最具体的常见中文食物名（如 米饭、番茄炒蛋、苹果、鸡胸肉），'
    '禁止只输出类别词（水果、蔬菜、肉类、主食、饮料、零食、菜肴这类词都不可以）；'
    '不要品牌名，不要份量和形容词（红富士就写苹果）。'
    '同时给出最常见的英文通用名（generic name，小写，如 potato chips、fried rice）。'
    '示例：一碗白米饭 → 米饭 => rice => 116 => 2.6 => 23 => 0.3；'
    '一盘番茄炒鸡蛋 → 番茄炒蛋 => tomato egg stir-fry => 120 => 6 => 8 => 7；'
    '一包薯片 → 薯片 => potato chips => 536 => 7 => 53 => 32。'
    '常见食物每100克热量参考范围：蔬菜20-50千卡，水果30-90千卡，熟主食110-150千卡，'
    '瘦肉蛋100-200千卡，肥肉菜品250-500千卡，含糖饮料35-50千卡。'
    '一般规律：新鲜水果蔬菜水分高，碳水化合物通常不超过25克/100克（干果除外）；'
    '可乐、果汁等纯饮料的脂肪和蛋白质为0。'
    '只输出一行，格式为：中文名 => 英文名 => 热量 => 蛋白质 => 碳水 => 脂肪，'
    '单位分别是千卡、克、克、克（每100克）。只写名称、数字和 =>，不要任何其他文字。'
    '看不清或画面不是食物时，只输出：无法识别。';

/// 类别词黑名单（解析层兜底，prompt 已禁止输出这些词）：
/// 命中即「识别不够具体」——置信度强制降档走「请确认」。**精确匹配**
/// （忽略大小写与首尾空白），「水果捞」「水果沙拉」这类具体名不误伤。
const Set<String> kGenericFoodCategoryWords = <String>{
  // 中文类别词
  '水果',
  '蔬菜',
  '肉',
  '肉类',
  '主食',
  '饮料',
  '零食',
  '菜肴',
  '食物',
  '菜品',
  '早餐',
  '午餐',
  '晚餐',
  // 英文类别词
  'fruit',
  'fruits',
  'vegetable',
  'vegetables',
  'meat',
  'staple',
  'beverage',
  'drink',
  'snack',
  'dish',
  'food',
  'meal',
};

/// 识别名是否只命中类别词（不够具体）。
bool isGenericCategoryName(String name) {
  return kGenericFoodCategoryWords.contains(name.trim().toLowerCase());
}

/// 视觉版 user 模板（图片随消息一并送入，文本只需点题）。
String buildPhotoRecognitionPrompt() {
  return '识别这张照片中的主要食物。\n结果：';
}

/// 解析出的视觉识别结果（食物名 + 每 100g 估算营养值）。
final class ParsedPhotoRecognition {
  const ParsedPhotoRecognition({
    required this.name,
    this.nameEn,
    required this.values,
  });

  /// 模型给出的中文食物名（已去前缀/杂质）。
  final String name;

  /// 模型给出的英文通用名（六段双语格式才有；五段兼容输出为 null）。
  final String? nameEn;

  /// 模型估算的每 100g 营养（只作匹配参考与存疑判定，不入账）。
  final OnDeviceNutritionValues values;
}

/// 宽松解析正则（六段双语主格式）：`中文名 => 英文名 => a => b => c => d`，
/// 英文段须以字母开头（与五段格式互撞时此正则优先），容忍行内前后杂质。
final RegExp _parseBilingualRegex = RegExp(
  r'([^\s=>\d][^=>\n]*?)\s*=>\s*([A-Za-z][^=>\n]*?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 宽松解析正则（五段兼容格式）：全文本取第一组 `名 => a => b => c => d`，
/// 容忍行内前后杂质与尾部多余 `=>`（沿用 v5 文本版的宽松策略）。
final RegExp _parseRegex = RegExp(
  r'([^\s=>\d][^=>\n]*?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 识别名前缀杂质（模型偶发复述「食物：」「结果：」等提示词片段）。
final RegExp _namePrefixRegex = RegExp(r'^(食物|结果|名称|答案)\s*[:：]\s*');

/// detail 透出长度上限（字符数；超出部分以 … 收尾，总长度 ≤ 上限+1）。
const int kRecognitionDetailMaxLength = 80;

/// 模型原文 → 可透出给用户的单行详情：压缩全部空白（含换行/制表）为
/// 单个空格、去首尾空白、超长截断加省略号。空白-only 输入返回空串。
String cleanRecognitionDetail(String raw) {
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= kRecognitionDetailMaxLength) return collapsed;
  return '${collapsed.substring(0, kRecognitionDetailMaxLength)}…';
}

/// 解析视觉模型输出原文；六段（双语）优先、五段（旧格式）兼容回退；
/// 匹配失败/「无法识别」返回 null（上层走降级）。
ParsedPhotoRecognition? parsePhotoRecognitionOutput(String text) {
  final bilingual = _parseBilingualRegex.firstMatch(text);
  if (bilingual != null) {
    final values = [
      for (var i = 3; i <= 6; i++)
        double.tryParse(bilingual.group(i)!) ?? double.nan,
    ];
    if (values.any((v) => !v.isFinite)) return null;
    final name = bilingual.group(1)!.replaceAll(_namePrefixRegex, '').trim();
    if (name.isEmpty || name.contains('无法识别')) return null;
    final nameEn = bilingual.group(2)!.trim();
    return ParsedPhotoRecognition(
      name: name,
      nameEn: nameEn.isEmpty ? null : nameEn,
      values: OnDeviceNutritionValues(
        kcal: values[0],
        proteinG: values[1],
        carbsG: values[2],
        fatG: values[3],
      ),
    );
  }
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

/// 用识别名搜食物库并取最优条目：先中文名精确/模糊匹配，未命中再用
/// [nameEn] 匹配（USDA 库英文为主，双语输出命中率显著提升）；
/// 均无结果返回 null（上层走降级）。
///
/// [search] 即仓储的 searchFoods（本地 drift 双语 LIKE）。
Future<FoodNameMatch?> matchFoodByName(
  Future<List<Food>> Function(String query) search,
  String name, {
  String? nameEn,
}) async {
  final byZh = await _matchOnce(search, name);
  if (byZh != null) return byZh;
  final en = nameEn?.trim() ?? '';
  if (en.isEmpty) return null;
  return _matchOnce(search, en);
}

/// 单关键词匹配：中/英文名精确命中优先，否则取搜索首条（LIKE 模糊）。
Future<FoodNameMatch?> _matchOnce(
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
/// - sanity-clamp 命中（[isNutritionEstimateDubious]）或名字只命中类别词
///   黑名单（[isGenericCategoryName]，识别不够具体）→ 0.5，必标「请确认」；
/// - 名字精确命中食物库 → 0.85（库内精准营养值兜底，只需确认份量）；
/// - 仅模糊命中 → 0.6，低于 RecognizedCandidate 低置信阈值 0.7，标「请确认」。
double photoRecognitionConfidence({
  required bool dubious,
  required bool exactNameMatch,
  bool tooGeneric = false,
}) {
  if (dubious || tooGeneric) return 0.5;
  return exactNameMatch ? 0.85 : 0.6;
}
