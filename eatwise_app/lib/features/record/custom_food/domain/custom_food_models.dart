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

/// 贡献类型（服务端 kind：普通自定义食物贡献 / 条码商品补录 / 已有食物数据纠错）。
enum FoodContributionKind {
  /// 普通自定义食物贡献（无条码）。
  custom,

  /// 扫码未命中补录（带条码 + 营养表佐证照片）。
  barcode,

  /// 已有共享食物的数据纠错（食物详情页「数据有误？」入口，建议值在服务端
  /// 候选 suggestion 字段；客户端精简视图不含建议值）。
  correction,
}

/// 贡献类型字符串 → 枚举（未知/缺省按 custom 处理，不隐藏条目）。
FoodContributionKind foodContributionKindFrom(String? raw) => switch (raw) {
  'barcode' => FoodContributionKind.barcode,
  'correction' => FoodContributionKind.correction,
  _ => FoodContributionKind.custom,
};

/// 我的贡献条目（GET /foods/contributions 精简视图；v1.13.23 起服务端带
/// 关联食物名 [nameZh]/[nameEn]——纠错类候选目标是共享库食物，本地库未必
/// 有该行，裸 foodId 上屏是底线问题（v1.13.22 走查 cf_d661fdaa）；
/// 旧服务端/已删食物为 null 时客户端回退本地库按 [foodId] 解析，再不行
/// 回退展示 [foodId]）。
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
    this.nameZh,
    this.nameEn,
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

  /// 关联食物中文名（服务端视图带；null = 旧服务端或食物已删）。
  final String? nameZh;

  /// 关联食物英文名（同上）。
  final String? nameEn;

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
      nameZh: json['nameZh'] as String?,
      nameEn: json['nameEn'] as String?,
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
