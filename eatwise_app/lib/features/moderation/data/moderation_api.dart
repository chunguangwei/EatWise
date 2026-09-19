import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 审批中心候选条目（GET /moderation/food-candidates 视图子集：
/// 名称/营养值/条码/提交人/时间 + 纠错建议值对照）。
final class ModerationCandidate {
  const ModerationCandidate({
    required this.id,
    required this.foodId,
    required this.submitterUserId,
    required this.kind,
    required this.createdAt,
    this.nameZh,
    this.nameEn,
    this.barcode,
    this.evidenceImageUrl,
    this.per100g,
    this.suggestionPer100g,
    this.suggestionNameZh,
  });

  /// 候选 id。
  final String id;

  /// 被贡献的食物 id。
  final String foodId;

  /// 提交人用户 id（服务端候选 userId）。
  final String submitterUserId;

  /// 贡献类型（custom/barcode/correction，复用众包枚举）。
  final FoodContributionKind kind;

  /// 提交时间。
  final DateTime createdAt;

  /// 食物名（食物已删等异常态为 null，UI 回退 foodId）。
  final String? nameZh;
  final String? nameEn;

  /// 条码号（仅 kind=barcode）。
  final String? barcode;

  /// 佐证照片 URL（仅 kind=barcode）。
  final String? evidenceImageUrl;

  /// 当前每 100g 四营养（异常态为 null）。
  final NutritionSnapshot? per100g;

  /// 纠错建议每 100g 四营养（仅 kind=correction）。
  final NutritionSnapshot? suggestionPer100g;

  /// 纠错建议中文名（仅 kind=correction 且建议改名）。
  final String? suggestionNameZh;

  /// 服务端 JSON → 模型（信封已解包后的 item）。
  factory ModerationCandidate.fromJson(Map<String, dynamic> json) {
    NutritionSnapshot? snapshotOf(Object? raw) {
      if (raw is! Map<String, dynamic>) return null;
      return NutritionSnapshot(
        kcal: (raw['kcal'] as num?)?.toDouble() ?? 0,
        proteinG: (raw['proteinG'] as num?)?.toDouble() ?? 0,
        carbG: (raw['carbG'] as num?)?.toDouble() ?? 0,
        fatG: (raw['fatG'] as num?)?.toDouble() ?? 0,
      );
    }

    final suggestion = json['suggestion'];
    final suggestionMap = suggestion is Map<String, dynamic>
        ? suggestion
        : null;
    return ModerationCandidate(
      id: json['id'] as String? ?? '',
      foodId: json['foodId'] as String? ?? '',
      submitterUserId: json['userId'] as String? ?? '',
      kind: foodContributionKindFrom(json['kind'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      nameZh: json['nameZh'] as String?,
      nameEn: json['nameEn'] as String?,
      barcode: json['barcode'] as String?,
      evidenceImageUrl: json['evidenceImageUrl'] as String?,
      per100g: snapshotOf(json['per100g']),
      suggestionPer100g: snapshotOf(suggestionMap?['per100g']),
      suggestionNameZh: suggestionMap?['nameZh'] as String?,
    );
  }
}

/// 审批中心候选分页（游标分页，createdAt 升序先入先审）。
final class ModerationCandidatePage {
  const ModerationCandidatePage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ModerationCandidate> items;
  final String? nextCursor;
  final bool hasMore;
}

/// 审批中心远程端抽象（生产 dio；测试 Fake）。
abstract interface class ModerationRemote {
  /// pending 候选队列（游标分页）。
  Future<ModerationCandidatePage> listPending({String? cursor, int limit = 20});

  /// 审核（approve / reject；reject 可带原因）。
  Future<void> review(
    String candidateId, {
    required String action,
    String? reason,
  });
}

/// REST 实现（信封已由 EnvelopeInterceptor 解包）。
final class RemoteModerationApi implements ModerationRemote {
  RemoteModerationApi({required this.dio});

  /// 已装配 dio。
  final Dio dio;

  @override
  Future<ModerationCandidatePage> listPending({
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/moderation/food-candidates',
        queryParameters: <String, dynamic>{
          'status': 'pending',
          'limit': limit,
          'cursor': ?cursor,
        },
      );
      final body = response.data ?? const <String, dynamic>{};
      final items = (body['items'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => ModerationCandidate.fromJson(e as Map<String, dynamic>))
          .toList();
      final pageInfo = body['pageInfo'];
      final pageInfoMap = pageInfo is Map<String, dynamic>
          ? pageInfo
          : const <String, dynamic>{};
      return ModerationCandidatePage(
        items: items,
        nextCursor: pageInfoMap['nextCursor'] as String?,
        hasMore: pageInfoMap['hasMore'] == true,
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> review(
    String candidateId, {
    required String action,
    String? reason,
  }) async {
    try {
      await dio.post<Map<String, dynamic>>(
        '/moderation/food-candidates/$candidateId/review',
        data: <String, dynamic>{
          'action': action,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}

/// 内存 Fake（测试注入；审核动作按 id 从队列移除，与服务端终态出队同口径）。
final class FakeModerationRemote implements ModerationRemote {
  /// 可注入的 pending 队列。
  List<ModerationCandidate> pending = <ModerationCandidate>[];

  /// 已收到的审核动作（`id:action:reason`）。
  final List<String> receivedReviews = <String>[];

  /// 注入审核失败（业务错误原样上抛 UI 提示）。
  Object? reviewError;

  /// 注入列表失败。
  Object? listError;

  @override
  Future<ModerationCandidatePage> listPending({
    String? cursor,
    int limit = 20,
  }) async {
    if (listError != null) throw listError!;
    // 游标 = 偏移量（与服务端 offset 游标同语义，测试简化明文）。
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final page = pending.skip(offset).take(limit).toList();
    final nextOffset = offset + limit;
    return ModerationCandidatePage(
      items: page,
      nextCursor: nextOffset < pending.length ? '$nextOffset' : null,
      hasMore: nextOffset < pending.length,
    );
  }

  @override
  Future<void> review(
    String candidateId, {
    required String action,
    String? reason,
  }) async {
    if (reviewError != null) throw reviewError!;
    receivedReviews.add('$candidateId:$action:${reason ?? ''}');
    pending = pending.where((c) => c.id != candidateId).toList();
  }
}
