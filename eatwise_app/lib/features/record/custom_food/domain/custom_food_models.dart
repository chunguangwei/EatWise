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

/// AI 估算结果（端侧小模型 / 用户自配 API 产物；估算值仅作「估算」标记使用）。
final class FoodEstimate {
  const FoodEstimate({required this.per100g, required this.confidence});

  /// 每 100g 四营养估算值。
  final NutritionSnapshot per100g;

  /// 置信度（'high' | 'medium' | 'low'）。
  final String confidence;

  /// 低置信度：UI 额外提示核对数值。
  bool get isLowConfidence => confidence == 'low';
}

/// 拍照识别未收录场景的表单预填（识别名 + 模型每 100g 估值）：
/// 与「AI 估算」预填同款「端侧估算，请确认」徽标/存疑提示，
/// 估值只作表单初值，用户可改名/改值，确认保存后才入库。
final class CustomFoodEstimatePrefill {
  const CustomFoodEstimatePrefill({
    required this.name,
    required this.per100g,
    required this.lowConfidence,
    this.nameEn,
  });

  /// 识别出的食物名（菜名初值）。
  final String name;

  /// 英文通用名（双语识别时才有；英文名/别名辅助）。
  final String? nameEn;

  /// 模型估算的每 100g 四营养（四营养输入初值）。
  final NutritionSnapshot per100g;

  /// 低置信（sanity-clamp dubious 或类别词）→ 「估算存疑，请核对」。
  final bool lowConfidence;
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

/// 众包贡献状态（对齐服务端 FoodCandidateStatus）。
enum FoodContributionStatus {
  /// 待人工审核。
  pending,

  /// 审核通过（食物已晋升共享库）。
  approved,

  /// 审核拒绝（[FoodContribution.reason] 为拒绝原因）。
  rejected,
}

/// 贡献状态 → 服务端 status 字符串（查询参数口径）。
String foodContributionStatusName(FoodContributionStatus status) =>
    switch (status) {
      FoodContributionStatus.pending => 'pending',
      FoodContributionStatus.approved => 'approved',
      FoodContributionStatus.rejected => 'rejected',
    };

/// 贡献状态字符串 → 枚举（未知/缺省按 pending 展示，不隐藏条目）。
FoodContributionStatus foodContributionStatusFrom(String? raw) => switch (raw) {
  'approved' => FoodContributionStatus.approved,
  'rejected' => FoodContributionStatus.rejected,
  _ => FoodContributionStatus.pending,
};

/// 贡献类型（服务端 kind：普通自定义食物贡献 / 条码商品补录）。
enum FoodContributionKind {
  /// 普通自定义食物贡献（无条码）。
  custom,

  /// 扫码未命中补录（带条码 + 营养表佐证照片）。
  barcode,
}

/// 贡献类型字符串 → 枚举（未知/缺省按 custom 处理，不隐藏条目）。
FoodContributionKind foodContributionKindFrom(String? raw) => raw == 'barcode'
    ? FoodContributionKind.barcode
    : FoodContributionKind.custom;

/// 我的贡献条目（GET /foods/contributions 精简视图；食物名由本地库按
/// [foodId] 解析，解析不到时 UI 回退展示 [foodId]）。
final class FoodContribution {
  const FoodContribution({
    required this.id,
    required this.foodId,
    required this.status,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
    this.kind = FoodContributionKind.custom,
    this.barcode,
  });

  /// 候选 id。
  final String id;

  /// 被贡献的食物 id。
  final String foodId;

  /// 审核状态。
  final FoodContributionStatus status;

  /// 拒绝原因（仅 rejected 有值）。
  final String? reason;

  /// 提交时间。
  final DateTime createdAt;

  /// 末次状态变更时间。
  final DateTime updatedAt;

  /// 贡献类型（barcode = 扫码未命中补录，UI 展示条码徽标 + 条码号）。
  final FoodContributionKind kind;

  /// 条码号（仅 kind=barcode 有值）。
  final String? barcode;

  /// 服务端 JSON → 模型（信封已由 EnvelopeInterceptor 解包后的 item）。
  factory FoodContribution.fromJson(Map<String, dynamic> json) {
    return FoodContribution(
      id: json['id'] as String? ?? '',
      foodId: json['foodId'] as String? ?? '',
      status: foodContributionStatusFrom(json['status'] as String?),
      reason: json['reason'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: foodContributionKindFrom(json['kind'] as String?),
      barcode: json['barcode'] as String?,
    );
  }
}

/// 我的贡献分页结果。
final class FoodContributionPage {
  const FoodContributionPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  /// 本页条目（createdAt 降序）。
  final List<FoodContribution> items;

  /// 符合条件的总条数。
  final int total;

  /// 当前页（从 1 起）。
  final int page;

  /// 页大小。
  final int pageSize;

  /// 是否还有下一页。
  bool get hasMore => page * pageSize < total;

  /// 服务端 JSON → 分页结果。
  factory FoodContributionPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const <dynamic>[];
    return FoodContributionPage(
      items: raw
          .map((e) => FoodContribution.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? raw.length,
      page: json['page'] as int? ?? 1,
      pageSize: json['pageSize'] as int? ?? raw.length,
    );
  }
}
