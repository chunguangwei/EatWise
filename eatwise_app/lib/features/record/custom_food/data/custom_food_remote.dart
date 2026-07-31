import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 自定义食物远程端抽象（K2：/foods/estimate + /foods/custom；
/// 生产走 dio，测试注入 Fake）。
abstract interface class CustomFoodRemote {
  /// AI 营养估算（未配置 LLM → 503 ESTIMATE_UNAVAILABLE，客户端降级手动填写）。
  Future<FoodEstimate> estimate(String name, {String? description});

  /// 创建自定义食物（幂等 clientRequestId；返回服务端分配的食物 ID）。
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  });
}

/// 估算不可用（503 ESTIMATE_UNAVAILABLE / 超时 / 网络错误）的统一判定：
/// 三种情况 UI 都降级「估算暂不可用，请手动填写」，不阻断手动输入。
bool isEstimateUnavailable(Object error) {
  if (error is NetworkApiException || error is TimeoutApiException) return true;
  return error is BusinessApiException &&
      (error.code == 'ESTIMATE_UNAVAILABLE' || error.httpStatus == 503);
}

/// REST 实现（信封已由 EnvelopeInterceptor 解包，response.data 即 data 段）。
final class RemoteCustomFoodApi implements CustomFoodRemote {
  RemoteCustomFoodApi({required this.dio});

  /// 已装配 dio。
  final Dio dio;

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/foods/estimate',
        data: <String, dynamic>{
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
        },
      );
      final body = response.data ?? const <String, dynamic>{};
      final per =
          (body['per100g'] as Map<String, dynamic>? ??
          const <String, dynamic>{});
      return FoodEstimate(
        per100g: NutritionSnapshot(
          kcal: (per['kcal'] as num?)?.toDouble() ?? 0,
          proteinG: (per['proteinG'] as num?)?.toDouble() ?? 0,
          carbG: (per['carbG'] as num?)?.toDouble() ?? 0,
          fatG: (per['fatG'] as num?)?.toDouble() ?? 0,
        ),
        confidence: body['confidence'] as String? ?? 'low',
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/foods/custom',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          'nameZh': draft.nameZh,
          if (draft.nameEn != null && draft.nameEn!.isNotEmpty)
            'nameEn': draft.nameEn,
          'aliasesZh': draft.aliasesZh,
          'aliasesEn': draft.aliasesEn,
          'per100g': <String, dynamic>{
            'kcal': draft.per100g.kcal,
            'proteinG': draft.per100g.proteinG,
            'carbG': draft.per100g.carbG,
            'fatG': draft.per100g.fatG,
          },
          'source': customFoodSourceName(draft.source),
        },
      );
      return response.data?['id'] as String? ?? '';
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}

/// Fake 远程端可注入模式：成功 / 估算不可用（503）/ 离线。
enum FakeCustomFoodMode { success, estimateUnavailable, offline }

/// 内存 Fake 远程端（任务约束：不写真实网络；与 FakeRecordRemote 同法）。
///
/// - success：估算返回可注入的 [estimateResult]（默认 high 置信度样例），
///   创建分配服务端 ID 且按 clientRequestId 幂等（重复上行返回首次结果）；
/// - estimateUnavailable：估算抛 503 ESTIMATE_UNAVAILABLE（创建仍成功）；
/// - offline：估算/创建均抛 NetworkApiException（离线降级本地 pending）。
final class FakeCustomFoodRemote implements CustomFoodRemote {
  FakeCustomFoodRemote({this.mode = FakeCustomFoodMode.success});

  /// 当前模式（测试中可随时切换，如「先离线再联网」）。
  FakeCustomFoodMode mode;

  /// 可注入的估算结果（null 时用默认 high 置信度样例）。
  FoodEstimate? estimateResult;

  /// 已收到的估算次数。
  int estimateCount = 0;

  /// 已收到的 clientRequestId 列表（服务端幂等表替身，§2.2）。
  final List<String> receivedRequestIds = <String>[];

  int _serverSeq = 0;

  @override
  Future<FoodEstimate> estimate(String name, {String? description}) async {
    estimateCount++;
    switch (mode) {
      case FakeCustomFoodMode.offline:
        throw const NetworkApiException();
      case FakeCustomFoodMode.estimateUnavailable:
        throw const BusinessApiException(
          httpStatus: 503,
          code: 'ESTIMATE_UNAVAILABLE',
          message: '估算暂不可用，请手动填写',
        );
      case FakeCustomFoodMode.success:
        return estimateResult ??
            const FoodEstimate(
              per100g: NutritionSnapshot(
                kcal: 200,
                proteinG: 10,
                carbG: 20,
                fatG: 5,
              ),
              confidence: 'high',
            );
    }
  }

  @override
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    if (mode == FakeCustomFoodMode.offline) {
      throw const NetworkApiException();
    }
    // 幂等：同一 clientRequestId 重复上行返回首次分配，不重复创建（§2.2）。
    if (receivedRequestIds.contains(clientRequestId)) {
      return 'srv-food-$clientRequestId';
    }
    receivedRequestIds.add(clientRequestId);
    _serverSeq++;
    return 'srv-food-$_serverSeq';
  }
}
