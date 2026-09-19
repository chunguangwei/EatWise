/// 拍照识别（端侧视觉）纯函数层：prompt 模板 + 宽松解析 + 食物库匹配 +
/// 置信度策略。零 Flutter/插件依赖，可单测。
///
/// Prompt 在端侧营养估算 spike §6 v5 定稿基础上改视觉版：多模态同一份
/// 营养约束话术，输出升级为**多行明细协议**（组合餐拆分 + AI 估份量）：
/// 每种主要食物一行 `中文名 => 英文名 => 估算克数 => 每100g四营养`。
/// 采样参数沿用 v5（temperature=0.15, topK=1, seed=42）。
library;

import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/recognition/domain/nutrition_label_ocr_logic.dart'
    show kKjPerKcal;
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';

/// 视觉版 system instruction（v5 营养约束逐字保留，加识别/命名/份量/
/// 包装标签提取约束）。
///
/// 多行明细协议（真机反馈驱动）：组合餐拆成主要组成食物逐行输出；
/// 估算克数按图中实际份量（常识锚点写进 prompt）；
/// 命名约束（「只给类别词」反馈后加固）：最具体常见食物名，禁止类别词；
/// 双语输出（USDA 库英文为主，英文精确匹配命中率显著更高）；
/// few-shot 示例定死输出格式、命名粒度与组合餐拆分方式；
/// 包装食品：营养表照抄（kJ 单位标记透出，Dart 层换算）+ 净含量直填克数
/// + 品牌品名；散装食物：参照物（手/筷子/碗盘）比例估算克数。
const String kPhotoRecognitionSystemPrompt =
    '你是食物拍照识别助手。用户给你一张餐食照片，你识别画面中的食物并逐条估算份量与营养。'
    '画面中每种主要食物输出一行；只有一种食物就只输出一行；'
    '组合餐（如炒饭、套餐）要拆成主要组成食物，每个组成一行。'
    '估算克数按图中实际份量（常识参考：一碗米饭约200克，一包薯片约60克，'
    '一盘菜约250克，一个鸡蛋约50克）。'
    '食物名必须是最具体的常见中文食物名（如 米饭、番茄炒蛋、苹果、鸡胸肉），'
    '禁止只输出类别词（水果、蔬菜、肉类、主食、饮料、零食、菜肴这类词都不可以）；'
    '不要品牌名，不要份量和形容词（红富士就写苹果）。'
    '英文名给最常见的通用名（generic name，小写，如 potato chips、fried rice）。'
    '按通常食用状态估算每100克可食部营养：米饭、面条等主食指煮熟后的成品，'
    '菜名指烧制完成的成品菜，肉蛋水果按生鲜。'
    '常见食物每100克热量参考范围：蔬菜20-50千卡，水果30-90千卡，熟主食110-150千卡，'
    '瘦肉蛋100-200千卡，肥肉菜品250-500千卡，含糖饮料35-50千卡。'
    '一般规律：新鲜水果蔬菜水分高，碳水化合物通常不超过25克/100克（干果除外）；'
    '可乐、果汁等纯饮料的脂肪和蛋白质为0。'
    '散装食物估算克数时利用画面参照物判断大小（手、筷子、常见碗盘直径约11-13厘米），按参照物比例估算实际份量。'
    '如果画面中是带包装的食品且包装上有可读的营养成分表：优先照抄标签上的每100克数值（能量如果是千焦，照抄数值并在数字后标注 kJ；是千卡则标注 kcal），不要自己换算；包装上有净含量（如 净含量：50克）时，估算克数直接填净含量数值；食物名用包装上的品牌加品名（如 清叶堂洋芋片）。'
    '示例：一碗白米饭 → 米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3；'
    '一包薯片 → 薯片 => potato chips => 60 => 536 => 7 => 53 => 32。'
    '包装食品示例：一袋清叶堂洋芋片（营养表 每100克：能量2141千焦、蛋白质6.1克、碳水53.0克、脂肪30.7克；净含量50克）→\n'
    '清叶堂洋芋片 => potato chips => 50 => 2141 kJ => 6.1 => 53.0 => 30.7。'
    '组合餐示例，一份火腿蛋炒饭（一碗）→ 三行：\n'
    '米饭 => rice => 200 => 116 => 2.6 => 23 => 0.3\n'
    '鸡蛋 => egg => 50 => 144 => 13.3 => 2.8 => 8.8\n'
    '火腿 => ham => 30 => 145 => 16 => 2 => 8\n'
    '每行格式：中文名 => 英文名 => 估算克数 => 每100克热量 => 每100克蛋白质 => '
    '每100克碳水 => 每100克脂肪，单位分别是克、千卡、克、克、克。'
    '只写名称、数字和 =>，每行一条，不要任何其他文字。'
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

/// 解析出的单条识别明细（多行协议逐行产物）。
final class ParsedPhotoItem {
  const ParsedPhotoItem({
    required this.name,
    this.nameEn,
    this.grams,
    required this.values,
    this.fromLabel = false,
  });

  /// 中文食物名（已去前缀/杂质）。
  final String name;

  /// 英文通用名（六/七段格式才有；五段兼容输出为 null）。
  final String? nameEn;

  /// 模型估算的实际克数（七段格式才有；兼容旧格式为 null → 服务层默认
  /// 100g；包装食品有净含量时为净含量值）。原始值未 clamp，合理性判定
  /// 见 [isPhotoGramsSuspicious]。
  final double? grams;

  /// 每 100g 营养（kJ 已在解析层换算 kcal）。散装=模型估算（只作匹配
  /// 参考/存疑判定/表单初值，不直接入账）；包装=标签照抄值（ground
  /// truth，sanity-clamp 只警告不覆盖，见 [fromLabel]）。
  final OnDeviceNutritionValues values;

  /// 是否来自包装营养表照抄（热量段带单位标记）。
  final bool fromLabel;
}

/// 克数合理区间（超出按可疑标低置信，值 clamp 回区间内）。
const double kPhotoGramsMin = 1;
const double kPhotoGramsMax = 2000;

/// 克数是否越界可疑（<1 或 >2000；如「3000g 米饭」型顽固错误）。
bool isPhotoGramsSuspicious(double grams) {
  return grams < kPhotoGramsMin || grams > kPhotoGramsMax;
}

/// 克数 clamp 到合理区间（明细卡/入账用）。
double clampPhotoGrams(double grams) {
  return grams.clamp(kPhotoGramsMin, kPhotoGramsMax);
}

/// 七段主格式（含估算克数）：`中文名 => 英文名 => 克数 => 热量[单位] => 3个宏量`。
/// 热量段允许单位后缀（kJ/千焦 → 包装营养表照抄场景，Dart 层统一换算
/// kcal，数值换算不放模型侧）；无单位 = 散装估算路径（fromLabel=false）。
final RegExp _itemWithGramsRegex = RegExp(
  r'([^\s=>\d][^=>]*?)\s*=>\s*([A-Za-z][^=>]*?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)(?:\s*(kJ|kcal|千焦|千卡))?\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
  caseSensitive: false,
);

/// 六段兼容格式（无克数）：`中文名 => 英文名 => 4个营养数字`
/// （英文段须以字母开头，与五段格式区分）。
final RegExp _itemBilingualRegex = RegExp(
  r'([^\s=>\d][^=>]*?)\s*=>\s*([A-Za-z][^=>]*?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 五段兼容格式（无英文名无克数）：`名 => 4个营养数字`（v5 宽松策略）。
final RegExp _itemLegacyRegex = RegExp(
  r'([^\s=>\d][^=>]*?)\s*=>\s*'
  r'(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)\s*=>\s*(\d+(?:\.\d+)?)',
);

/// 食物名前缀杂质（模型偶发复述「食物：」「结果：」等提示词片段）。
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

/// 解析视觉模型输出原文 → 明细列表。**逐行独立解析**：七段主格式 →
/// 六段（无克数）→ 五段（无英文名无克数）依次回退；单条目解析失败
/// 跳过该行不拖垮整体；空行/杂质行忽略；「无法识别」行自然落空。
/// 全部落空返回空列表（上层按 parse_failed 走降级）。
List<ParsedPhotoItem> parsePhotoRecognitionItems(String text) {
  final items = <ParsedPhotoItem>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final item = _parseItemLine(line);
    if (item != null) items.add(item);
  }
  return items;
}

/// 单行解析：七段 → 六段 → 五段回退；名字为空/「无法识别」/数字非法 → null。
ParsedPhotoItem? _parseItemLine(String line) {
  final full = _itemWithGramsRegex.firstMatch(line);
  if (full != null) {
    return _buildItem(
      rawName: full.group(1)!,
      nameEn: full.group(2),
      gramsGroup: full.group(3),
      energyGroup: full.group(4)!,
      energyUnit: full.group(5),
      macroGroups: <String>[full.group(6)!, full.group(7)!, full.group(8)!],
    );
  }
  final bilingual = _itemBilingualRegex.firstMatch(line);
  if (bilingual != null) {
    return _buildItem(
      rawName: bilingual.group(1)!,
      nameEn: bilingual.group(2),
      gramsGroup: null,
      energyGroup: bilingual.group(3)!,
      energyUnit: null,
      macroGroups: <String>[
        bilingual.group(4)!,
        bilingual.group(5)!,
        bilingual.group(6)!,
      ],
    );
  }
  final legacy = _itemLegacyRegex.firstMatch(line);
  if (legacy != null) {
    return _buildItem(
      rawName: legacy.group(1)!,
      nameEn: null,
      gramsGroup: null,
      energyGroup: legacy.group(2)!,
      energyUnit: null,
      macroGroups: <String>[
        legacy.group(3)!,
        legacy.group(4)!,
        legacy.group(5)!,
      ],
    );
  }
  return null;
}

/// 构造明细条目（统一名字清理与数字校验）。热量段带单位（kJ/千焦）时
/// 在 Dart 层按 1kcal=4.184kJ 换算（不信模型口算），并标记 fromLabel
///（包装营养表照抄 = ground truth，sanity-clamp 只警告不覆盖）。
ParsedPhotoItem? _buildItem({
  required String rawName,
  required String? nameEn,
  required String? gramsGroup,
  required String energyGroup,
  required String? energyUnit,
  required List<String> macroGroups,
}) {
  final name = rawName.replaceAll(_namePrefixRegex, '').trim();
  if (name.isEmpty || name.contains('无法识别')) return null;
  final grams = gramsGroup == null ? null : double.tryParse(gramsGroup);
  if (gramsGroup != null && (grams == null || !grams.isFinite)) return null;
  final energyRaw = double.tryParse(energyGroup);
  final macros = [
    for (final group in macroGroups) double.tryParse(group) ?? double.nan,
  ];
  if (energyRaw == null || !energyRaw.isFinite) return null;
  if (macros.any((v) => !v.isFinite)) return null;
  final unit = (energyUnit ?? '').toLowerCase();
  final fromLabel = unit.isNotEmpty;
  // kJ/千焦 → kcal（Dart 层定值换算）；kcal/千卡/缺省照用。
  final kcal = (unit == 'kj' || unit == '千焦')
      ? double.parse((energyRaw / kKjPerKcal).toStringAsFixed(1))
      : energyRaw;
  final en = nameEn?.trim() ?? '';
  return ParsedPhotoItem(
    name: name,
    nameEn: en.isEmpty ? null : en,
    grams: grams,
    values: OnDeviceNutritionValues(
      kcal: kcal,
      proteinG: macros[0],
      carbsG: macros[1],
      fatG: macros[2],
    ),
    fromLabel: fromLabel,
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

/// 单条解析明细 → 明细候选（拍照识别与自由记文本共用同一管线）：
/// 库匹配（中文→英文回退，D-16 映射回自建核心库）+ 克数 clamp +
/// 置信度合成。命中用库内精准每 100g（模型值只参与存疑判定）；
/// 未命中保留模型估值并标低置信（0.4，明细卡标「请确认」）。
Future<RecognizedMealItem> recognizedMealItemFromParsed(
  Future<List<Food>> Function(String query) searchFoods,
  ParsedPhotoItem parsed,
) async {
  final match = await matchFoodByName(
    searchFoods,
    parsed.name,
    nameEn: parsed.nameEn,
  );
  final rawGrams = parsed.grams ?? 100;
  final gramsSuspicious = isPhotoGramsSuspicious(rawGrams);
  final grams = clampPhotoGrams(rawGrams);
  final dubious = isNutritionEstimateDubious(parsed.values);
  // 类别词兜底（prompt 已禁，命中即「不够具体」→ 必走请确认）。
  final tooGeneric = isGenericCategoryName(parsed.name);
  // 包装标签照抄值是 ground truth：sanity-clamp 只警告不覆盖——不走
  // dubious 降级，命中按匹配档置信，未命中 0.6（仍低于阈值，明细行
  // 「请确认」徽标即警告通道；数值永不改写）。
  if (parsed.fromLabel) {
    final food = match?.food;
    return RecognizedMealItem(
      name: food?.nameZh ?? parsed.name,
      nameEn: food?.nameEn ?? parsed.nameEn,
      grams: grams,
      per100g: NutritionSnapshot(
        kcal: food?.kcalPer100g ?? parsed.values.kcal,
        proteinG: food?.proteinPer100g ?? parsed.values.proteinG,
        carbG: food?.carbPer100g ?? parsed.values.carbsG,
        fatG: food?.fatPer100g ?? parsed.values.fatG,
      ),
      confidence: food == null ? 0.6 : (match!.exact ? 0.9 : 0.75),
      food: food,
      fromLabel: true,
    );
  }
  if (match != null) {
    final food = match.food;
    return RecognizedMealItem(
      name: food.nameZh, // 库内规范名（展示/搜索一致）
      nameEn: food.nameEn,
      grams: grams,
      per100g: NutritionSnapshot(
        kcal: food.kcalPer100g,
        proteinG: food.proteinPer100g,
        carbG: food.carbPer100g,
        fatG: food.fatPer100g,
      ),
      confidence: photoRecognitionConfidence(
        dubious: dubious || gramsSuspicious,
        exactNameMatch: match.exact,
        tooGeneric: tooGeneric,
      ),
      food: food,
    );
  }
  return RecognizedMealItem(
    name: parsed.name,
    nameEn: parsed.nameEn,
    grams: grams,
    per100g: NutritionSnapshot(
      kcal: parsed.values.kcal,
      proteinG: parsed.values.proteinG,
      carbG: parsed.values.carbsG,
      fatG: parsed.values.fatG,
    ),
    // 库未命中：模型估值兜底，必低置信。
    confidence: 0.4,
  );
}

/// 识别名模糊查询序列（库未收录时在确认弹层找「相似食物」用）：
/// 全名 → 逐字去尾（≥2 字止，如「牛肉炒时蔬」→ 牛肉炒时 → 牛肉炒 → 牛肉）；
/// 含空格/连字符的先按分词取前段（如「potato chips」→ potato chips → potato；
/// 「清叶堂洋芋片」品牌前缀场景则后段递减由调用方再试——本函数只生成
/// 前缀递减序列，保持简单可测）。去重保序，不含空串。
List<String> fuzzyQueryCandidates(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return const <String>[];
  final queries = <String>[];
  void add(String q) {
    final t = q.trim();
    if (t.isNotEmpty && !queries.contains(t)) queries.add(t);
  }

  // 空格/连字符分词：全名 + 逐级去尾 token（英文/含品牌场景）。
  final tokens = trimmed.split(RegExp(r'[\s\-／/]+'));
  if (tokens.length > 1) {
    for (var i = tokens.length; i >= 1; i--) {
      add(tokens.sublist(0, i).join(' '));
    }
    return queries;
  }
  // CJK 前缀递减（≥2 字止）。
  for (var len = trimmed.length; len >= 2; len--) {
    add(trimmed.substring(0, len));
  }
  return queries;
}
