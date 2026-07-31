import 'package:eatwise/features/record/domain/record_models.dart';

/// 自定义食物来源（对齐服务端 CreateCustomFoodDto.source 枚举）。
enum CustomFoodSource {
  /// 用户手动填写。
  manual,

  /// AI 估算预填（必须带「估算」标记确认后保存）。
  llmEstimate,
}

/// CustomFoodSource → 服务端 source 字符串。
String customFoodSourceName(CustomFoodSource source) => switch (source) {
  CustomFoodSource.manual => 'manual',
  CustomFoodSource.llmEstimate => 'llm-estimate',
};

/// AI 估算结果（POST /foods/estimate；估算值仅作「估算」标记使用）。
final class FoodEstimate {
  const FoodEstimate({required this.per100g, required this.confidence});

  /// 每 100g 四营养估算值。
  final NutritionSnapshot per100g;

  /// 置信度（'high' | 'medium' | 'low'）。
  final String confidence;

  /// 低置信度：UI 额外提示核对数值。
  bool get isLowConfidence => confidence == 'low';
}

/// 自定义食物提交草稿（弹层表单 → 仓储）。
final class CustomFoodDraft {
  const CustomFoodDraft({
    required this.nameZh,
    required this.aliasesZh,
    required this.per100g,
    required this.source,
    this.nameEn,
    this.aliasesEn = const <String>[],
  });

  /// 菜名（必填，trim 后 1–50 字，服务端同口径）。
  final String nameZh;

  /// 英文名（可选）。
  final String? nameEn;

  /// 中文别名（远端 aliases 中英混合统一进中文别名列，与 K1 缓存口径一致）。
  final List<String> aliasesZh;

  /// 英文别名。
  final List<String> aliasesEn;

  /// 每 100g 四营养（全部 >0；kcal ≤900，宏量 ≤100）。
  final NutritionSnapshot per100g;

  /// 来源（manual / llm-estimate）。
  final CustomFoodSource source;
}
