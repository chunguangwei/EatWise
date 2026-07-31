import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 自定义食物保存结果（保存后立即可搜可记：直接回填记录结果卡）。
final class CustomFoodSaveResult {
  const CustomFoodSaveResult({
    required this.food,
    required this.uploaded,
    this.contributeSubmitted = false,
    this.contributionFailed = false,
  });

  /// 落库后的食物行（isCustom=true）。
  final Food food;

  /// 是否已上行 /foods/custom；false = 离线仅落本地 pending。
  final bool uploaded;

  /// 保存时勾选共享且贡献提交成功（UI 显示「已提交审核」）。
  final bool contributeSubmitted;

  /// 保存时勾选共享但贡献失败/拒收（原因已在弹层内展示，不再弹二次动作）。
  final bool contributionFailed;
}

/// 自定义食物仓储（K2：远端直调 + 本地 drift 落库）。
///
/// 离线策略〔假设〕：/sync/push ops 协议未支持 foodCustom entity（服务端
/// sync.service 仅识别 entry/waterLog），故不走 op 队列——保存时直调
/// /foods/custom；网络失败则仅落本地并置 customSyncPending，联网后经
/// [retryPending] 以原 clientRequestId 幂等重试（由自定义食物流程入口
///  opportunistic 触发，待主代理决定是否挂进 syncNow 链路）。
final class CustomFoodRepository {
  CustomFoodRepository({required this.db, required this.remote});

  /// 本地库。
  final AppDatabase db;

  /// 远程端（生产 RemoteCustomFoodApi；测试 Fake）。
  final CustomFoodRemote remote;

  static final Random _random = Random.secure();

  /// 保存自定义食物：先远端（幂等 clientRequestId），离线降级本地 pending；
  /// 本地落库后立即可搜可记。
  Future<CustomFoodSaveResult> save(CustomFoodDraft draft) async {
    final clientRequestId = _uuid();
    var localId = 'custom-$clientRequestId';
    var pending = false;
    try {
      final serverId = await remote.createCustom(
        draft,
        clientRequestId: clientRequestId,
      );
      // 远端成功：以服务端 ID 为本地主键（与 K1 搜索结果一致）。
      if (serverId.isNotEmpty) localId = serverId;
    } on ApiException catch (e) {
      if (e is NetworkApiException || e is TimeoutApiException) {
        pending = true; // 离线：仅落本地，联网后 retryPending 上行
      } else {
        rethrow; // 4xx/5xx 业务错误上抛 UI 提示
      }
    }
    await db.foodDao.upsertAll(<FoodsCompanion>[
      FoodsCompanion(
        id: Value(localId),
        nameZh: Value(draft.nameZh),
        nameEn: Value(draft.nameEn ?? draft.nameZh),
        aliasesZh: Value(jsonEncode(draft.aliasesZh)),
        aliasesEn: Value(jsonEncode(draft.aliasesEn)),
        kcalPer100g: Value(draft.per100g.kcal),
        proteinPer100g: Value(draft.per100g.proteinG),
        carbPer100g: Value(draft.per100g.carbG),
        fatPer100g: Value(draft.per100g.fatG),
        isCustom: const Value(true),
        customSyncPending: Value(pending),
        customClientRequestId: Value(pending ? clientRequestId : ''),
      ),
    ]);
    final food = await db.foodDao.getById(localId);
    return CustomFoodSaveResult(food: food!, uploaded: !pending);
  }

  /// 贡献自定义食物为共享候选（幂等 clientRequestId）。
  ///
  /// 成功：返回候选状态（pending/approved/rejected）并落本地
  /// contributionStatus（搜索行状态标签数据源）；机审拒收（400
  /// FOOD_CONTRIBUTE_REJECTED）落 rejected 后原样上抛（message 为服务端
  /// 双语原因）；网络/超时错误不改本地状态直接上抛。
  /// 〔假设〕服务端无按 foodId 批量查候选状态的端点，状态以本方法写入的
  /// 本地值为准 + approved 社区食物下行时标记（见 food_search_remote）。
  Future<String> contribute(String foodId) async {
    try {
      final status = await remote.contribute(foodId, clientRequestId: _uuid());
      await db.foodDao.setContributionStatus(foodId, status);
      return status;
    } on BusinessApiException catch (e) {
      if (e.code == 'FOOD_CONTRIBUTE_REJECTED') {
        await db.foodDao.setContributionStatus(foodId, 'rejected');
      }
      rethrow;
    }
  }

  /// 联网后重试 pending 自定义食物（幂等键复用，重复上行不产生重复条目）。
  /// 返回本轮上行成功条数。
  Future<int> retryPending() async {
    final rows = await db.foodDao.pendingCustomFoods();
    var synced = 0;
    for (final row in rows) {
      try {
        await remote.createCustom(
          _draftFromRow(row),
          clientRequestId: row.customClientRequestId,
        );
        await db.foodDao.markCustomSynced(row.id);
        synced++;
      } on ApiException catch (e) {
        // 仍离线：整批留待下轮；业务错误保持 pending 下轮重试。
        if (e is NetworkApiException || e is TimeoutApiException) break;
      }
    }
    return synced;
  }

  /// Foods 行 → 上行草稿（retryPending 用）。
  CustomFoodDraft _draftFromRow(Food row) {
    List<String> decode(String json) =>
        (jsonDecode(json) as List<dynamic>? ?? const <dynamic>[])
            .cast<String>();
    return CustomFoodDraft(
      nameZh: row.nameZh,
      nameEn: row.nameEn,
      aliasesZh: decode(row.aliasesZh),
      aliasesEn: decode(row.aliasesEn),
      per100g: NutritionSnapshot(
        kcal: row.kcalPer100g,
        proteinG: row.proteinPer100g,
        carbG: row.carbPer100g,
        fatG: row.fatPer100g,
      ),
      source: CustomFoodSource.manual,
    );
  }

  /// UUIDv4（幂等键/本地主键用，与 record_repository 同口径）。
  static String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
