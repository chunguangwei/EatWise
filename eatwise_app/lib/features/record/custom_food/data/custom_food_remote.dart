import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';

/// 自定义食物远程端抽象（K2：/foods/custom + 贡献；
/// 生产走 dio，测试注入 Fake）。AI 估算不走服务端（编排器两级：
/// 端侧 → 用户自配 API）。
abstract interface class CustomFoodRemote {
  /// 创建自定义食物（幂等 clientRequestId；返回服务端分配的食物 ID）。
  Future<String> createCustom(
    CustomFoodDraft draft, {
    required String clientRequestId,
  });

  /// 贡献自定义食物为共享候选（POST /foods/custom/:id/contribute，幂等
  /// clientRequestId；返回候选状态 pending/approved/rejected；
  /// 机审拒收抛 400 FOOD_CONTRIBUTE_REJECTED，message 为服务端双语原因）。
  ///
  /// 条码商品补录（扫码未命中场景）：[barcode] 与 [evidenceImageUrl] 必须
  /// 成对传入（服务端同口径校验，缺任一为 400 VALIDATION_ERROR）；同条码
  /// 已有 approved 候选抛 409 CONFLICT（已上架，无需重复贡献）。
  Future<String> contribute(
    String foodId, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  });

  /// 我的贡献批量查询（GET /foods/contributions，需认证，只返回本人候选；
  /// createdAt 降序，页码分页）。[status] 缺省返回全部状态。
  Future<FoodContributionPage> getContributions({
    FoodContributionStatus? status,
    int page = 1,
    int pageSize = 20,
  });

  /// 已有共享食物的数据纠错（POST /foods/:id/correction，幂等 clientRequestId；
  /// 食物详情页「数据有误？」入口，返回候选状态 pending/approved/rejected；
  /// 目标不存在/自定义食物 404，营养越界 400，机审拒收 400
  /// FOOD_CONTRIBUTE_REJECTED）。
  Future<String> submitCorrection(
    String foodId,
    CustomFoodDraft draft, {
    required String clientRequestId,
  });

  /// 编辑自定义食物（PATCH /foods/custom/:id，body 同创建去 clientRequestId，
  /// 不做幂等〔已定口径：更新 LWW，重放同值无害〕；owner 不匹配/不存在 404，
  /// 名称/营养校验与创建同口径 400 → BusinessApiException 上抛）。
  Future<void> updateCustom(String foodId, CustomFoodDraft draft);

  /// 删除自定义食物（DELETE /foods/custom/:id）：返回服务端级联软删的
  /// 历史记录条数（deletedEntries）；审核中候选 409 FOOD_UNDER_REVIEW，
  /// 非 owner/不存在 404。
  Future<int> deleteCustom(String foodId);
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

  @override
  Future<String> contribute(
    String foodId, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/foods/custom/$foodId/contribute',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          // barcode 与 evidenceImageUrl 必须成对（服务端契约）：调用方保证
          // 同传同不传，这里防御性按成对才上行。
          if (barcode != null && evidenceImageUrl != null) ...<String, dynamic>{
            'barcode': barcode,
            'evidenceImageUrl': evidenceImageUrl,
          },
        },
      );
      return response.data?['status'] as String? ?? 'pending';
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<FoodContributionPage> getContributions({
    FoodContributionStatus? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/foods/contributions',
        queryParameters: <String, dynamic>{
          if (status != null) 'status': foodContributionStatusName(status),
          'page': page,
          'pageSize': pageSize,
        },
      );
      return FoodContributionPage.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<String> submitCorrection(
    String foodId,
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/foods/$foodId/correction',
        data: <String, dynamic>{
          'clientRequestId': clientRequestId,
          'nameZh': draft.nameZh,
          'per100g': <String, dynamic>{
            'kcal': draft.per100g.kcal,
            'proteinG': draft.per100g.proteinG,
            'carbG': draft.per100g.carbG,
            'fatG': draft.per100g.fatG,
          },
        },
      );
      return response.data?['status'] as String? ?? 'pending';
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> updateCustom(String foodId, CustomFoodDraft draft) async {
    try {
      // body 与 createCustom 同构，仅去 clientRequestId（更新不做幂等键）。
      await dio.patch<Map<String, dynamic>>(
        '/foods/custom/$foodId',
        data: <String, dynamic>{
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
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<int> deleteCustom(String foodId) async {
    try {
      final response = await dio.delete<Map<String, dynamic>>(
        '/foods/custom/$foodId',
      );
      return (response.data?['deletedEntries'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}

/// Fake 远程端可注入模式：成功 / 离线。
enum FakeCustomFoodMode { success, offline }

/// 内存 Fake 远程端（任务约束：不写真实网络；与 FakeRecordRemote 同法）。
///
/// - success：创建分配服务端 ID 且按 clientRequestId 幂等（重复上行返回
///   首次结果）；
/// - offline：创建/贡献均抛 NetworkApiException（离线降级本地 pending）。
final class FakeCustomFoodRemote implements CustomFoodRemote {
  FakeCustomFoodRemote({this.mode = FakeCustomFoodMode.success});

  /// 当前模式（测试中可随时切换，如「先离线再联网」）。
  FakeCustomFoodMode mode;

  /// 已收到的 clientRequestId 列表（服务端幂等表替身，§2.2）。
  final List<String> receivedRequestIds = <String>[];

  /// 可注入的贡献结果状态（默认 pending）。
  String contributeStatus = 'pending';

  /// 注入贡献拒收（400 FOOD_CONTRIBUTE_REJECTED，双语 message 同服务端口径）。
  bool contributeRejected = false;

  /// 注入条码已上架冲突（409 CONFLICT，同服务端条码查重口径）。
  bool contributeConflict = false;

  /// 已收到的贡献幂等键列表（`foodId:clientRequestId`）。
  final List<String> receivedContributeIds = <String>[];

  /// 已收到的条码补录参数列表（`foodId|barcode|evidenceImageUrl`，
  /// 断言 barcode + evidenceImageUrl 成对上行用）。
  final List<String> receivedContributeBarcodes = <String>[];

  /// 贡献幂等表（clientRequestId → 首次返回的状态）。
  final Map<String, String> _contributeIdem = <String, String>{};

  /// 可注入的我的贡献列表（服务端 createdAt 降序口径由测试数据保证，Fake
  /// 只做状态过滤 + 页码切片）。
  List<FoodContribution> contributions = <FoodContribution>[];

  /// 已收到的查询参数（`status/page/pageSize`，断言查询口径用）。
  final List<String> receivedContributionQueries = <String>[];

  int _serverSeq = 0;

  /// 已收到的纠错请求（`foodId:clientRequestId`，断言上行用）。
  final List<String> receivedCorrectionIds = <String>[];

  /// 纠错幂等表（clientRequestId → 首次返回的状态）。
  final Map<String, String> _correctionIdem = <String, String>{};

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

  @override
  Future<String> contribute(
    String foodId, {
    required String clientRequestId,
    String? barcode,
    String? evidenceImageUrl,
  }) async {
    if (mode == FakeCustomFoodMode.offline) {
      throw const NetworkApiException();
    }
    // 幂等：同一 clientRequestId 重放返回首次结果（与服务端口径一致）。
    final cached = _contributeIdem[clientRequestId];
    if (cached != null) return cached;
    if (contributeConflict) {
      throw const BusinessApiException(
        httpStatus: 409,
        code: 'CONFLICT',
        message: '该条码商品已上架共享库，无需重复贡献',
      );
    }
    if (contributeRejected) {
      throw const BusinessApiException(
        httpStatus: 400,
        code: 'FOOD_CONTRIBUTE_REJECTED',
        message: '食物名称未通过审核，无法贡献到共享食物库',
      );
    }
    receivedContributeIds.add('$foodId:$clientRequestId');
    if (barcode != null || evidenceImageUrl != null) {
      receivedContributeBarcodes.add('$foodId|$barcode|$evidenceImageUrl');
    }
    _contributeIdem[clientRequestId] = contributeStatus;
    return contributeStatus;
  }

  @override
  Future<FoodContributionPage> getContributions({
    FoodContributionStatus? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (mode == FakeCustomFoodMode.offline) {
      throw const NetworkApiException();
    }
    receivedContributionQueries.add(
      '${status == null ? 'all' : status.name}/$page/$pageSize',
    );
    final all = contributions
        .where((c) => status == null || c.status == status)
        .toList();
    final offset = (page - 1) * pageSize;
    return FoodContributionPage(
      items: all.skip(offset).take(pageSize).toList(),
      total: all.length,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<String> submitCorrection(
    String foodId,
    CustomFoodDraft draft, {
    required String clientRequestId,
  }) async {
    if (mode == FakeCustomFoodMode.offline) {
      throw const NetworkApiException();
    }
    // 幂等：同一 clientRequestId 重放返回首次结果（与服务端口径一致）。
    final cached = _correctionIdem[clientRequestId];
    if (cached != null) return cached;
    receivedCorrectionIds.add('$foodId:$clientRequestId');
    _correctionIdem[clientRequestId] = 'pending';
    return 'pending';
  }

  /// 已收到的更新/删除请求 ID（断言上行用）。
  final List<String> receivedUpdateIds = <String>[];
  final List<String> receivedDeleteIds = <String>[];

  /// 注入删除冲突（409 FOOD_UNDER_REVIEW，审核中候选不可删）。
  bool deleteUnderReview = false;

  /// 注入「已晋升共享」404（服务端 promote 后 findCustomFoodById 查不到，
  /// PATCH/DELETE 同款 NOT_FOUND；测仓储层同步时窗自愈用）。
  bool approvedShared = false;

  /// deleteCustom 返回的级联删除记录条数（默认 0）。
  int deleteEntriesReturned = 0;

  @override
  Future<void> updateCustom(String foodId, CustomFoodDraft draft) async {
    if (mode == FakeCustomFoodMode.offline) {
      throw const NetworkApiException();
    }
    if (approvedShared) {
      throw const BusinessApiException(
        httpStatus: 404,
        code: 'NOT_FOUND',
        message: '资源不存在',
      );
    }
    receivedUpdateIds.add('$foodId|${draft.nameZh}');
  }

  @override
  Future<int> deleteCustom(String foodId) async {
    if (mode == FakeCustomFoodMode.offline) {
      throw const NetworkApiException();
    }
    if (deleteUnderReview) {
      throw const BusinessApiException(
        httpStatus: 409,
        code: 'FOOD_UNDER_REVIEW',
        message: '该食物正在审核中，无法删除',
      );
    }
    if (approvedShared) {
      throw const BusinessApiException(
        httpStatus: 404,
        code: 'NOT_FOUND',
        message: '资源不存在',
      );
    }
    receivedDeleteIds.add(foodId);
    return deleteEntriesReturned;
  }
}
