import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
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

/// 自定义食物删除结果（404 服务端已不存在时按「已删除」级联清理，
/// alreadyGone 供 UI 出「已从本地移除」友好文案，与管理员删除同口径）。
final class CustomFoodDeleteResult {
  const CustomFoodDeleteResult({
    required this.removed,
    this.alreadyGone = false,
  });

  /// 本地级联删除的历史记录条数。
  final int removed;

  /// 服务端已不存在该行（404 核验查无）——本地已按已删除清理。
  final bool alreadyGone;
}

/// 自定义食物仓储（K2：远端直调 + 本地 drift 落库）。
///
/// 离线策略〔假设〕：/sync/push ops 协议未支持 foodCustom entity（服务端
/// sync.service 仅识别 entry/waterLog），故不走 op 队列——保存时直调
/// /foods/custom；网络失败则仅落本地并置 customSyncPending，联网后经
/// [retryPending] 以原 clientRequestId 幂等重试（由自定义食物流程入口
///  opportunistic 触发，待主代理决定是否挂进 syncNow 链路）。
final class CustomFoodRepository {
  CustomFoodRepository({
    required this.db,
    required this.remote,
    this.existingFoodIdsFn,
  });

  /// 本地库。
  final AppDatabase db;

  /// 远程端（生产 RemoteCustomFoodApi；测试 Fake）。
  final CustomFoodRemote remote;

  /// 服务端存续核验（POST /foods/batch-get 命中集；null = 不核验，
  /// 404 一律按「同步时窗晋升共享」旧口径处理）。
  ///
  /// 为什么需要核验（走查）：owner 删除吃 404 的旧假设「404 ⇒ 晋升共享」
  /// 在「管理台手工软删该行 / 他端已删」时不成立——已删食物会被错误地
  /// 戴上「已共享」徽标留在库里。核验仅在 404 时发起（廉价）。
  final Future<Set<String>> Function(List<String> foodIds)? existingFoodIdsFn;

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
  ///
  /// 条码商品补录：[barcode] 与 [evidenceImageUrl] 成对传入（营养表佐证照片
  /// URL，先经 POST /uploads 取得）；409 CONFLICT（同条码已上架）不改本地
  /// 状态原样上抛，由 UI 走「已在库」分支。
  Future<String> contribute(
    String foodId, {
    String? barcode,
    String? evidenceImageUrl,
  }) async {
    try {
      final status = await remote.contribute(
        foodId,
        clientRequestId: _uuid(),
        barcode: barcode,
        evidenceImageUrl: evidenceImageUrl,
      );
      await db.foodDao.setContributionStatus(foodId, status);
      return status;
    } on BusinessApiException catch (e) {
      if (e.code == 'FOOD_CONTRIBUTE_REJECTED') {
        await db.foodDao.setContributionStatus(foodId, 'rejected');
      }
      rethrow;
    }
  }

  /// 已有共享食物的数据纠错（薄荷走查 P3，食物详情页「数据有误？」入口）：
  /// 直调 /foods/:id/correction（幂等 clientRequestId），成功返回候选状态。
  /// 不写本地库（目标为共享食物，审核状态由「我的贡献」列表下行展示）；
  /// 网络/业务错误原样上抛，由 UI 提示（表单保留可重试）。
  Future<String> submitCorrection(String foodId, CustomFoodDraft draft) {
    return remote.submitCorrection(foodId, draft, clientRequestId: _uuid());
  }

  /// 编辑自定义食物（PATCH，无幂等键）：先本地后远端。
  ///
  /// companion 只带上行可编辑列——drift insertOnConflictUpdate 跳过缺省列，
  /// isCustom/contributionStatus 等标记不受扰动。
  /// 网络/超时错误静默〔已定口径：自定义食物行主要服务创建者设备，
  /// 离线编辑保留本地值，下次联网不重试（更新 LWW 无语义可重放）〕；
  /// 4xx/5xx 业务错误上抛 UI 提示。返回编辑后的最新本地行。
  ///
  /// pending 行（离线新建尚未上行）例外：服务端还没有这条行，PATCH 必 404——
  /// 只改本地并**轮换 customClientRequestId**：retryPending 以行当前内容 +
  /// 该键重放 create，若沿用旧键，「离线新建 → 编辑 → 联网重放」会用旧幂等键
  /// 带新内容打服务端（首次注册的是旧内容）→ PAYLOAD_MISMATCH 永久卡 pending。
  Future<Food> update(Food food, CustomFoodDraft draft) async {
    final companion = FoodsCompanion(
      id: Value(food.id),
      nameZh: Value(draft.nameZh),
      nameEn: Value(draft.nameEn ?? draft.nameZh),
      aliasesZh: Value(jsonEncode(draft.aliasesZh)),
      aliasesEn: Value(jsonEncode(draft.aliasesEn)),
      kcalPer100g: Value(draft.per100g.kcal),
      proteinPer100g: Value(draft.per100g.proteinG),
      carbPer100g: Value(draft.per100g.carbG),
      fatPer100g: Value(draft.per100g.fatG),
    );
    if (food.customSyncPending) {
      await db.foodDao.upsertAll(<FoodsCompanion>[
        companion.copyWith(customClientRequestId: Value(_uuid())),
      ]);
      return (await db.foodDao.getById(food.id))!;
    }
    await db.foodDao.upsertAll(<FoodsCompanion>[companion]);
    try {
      await remote.updateCustom(food.id, draft);
    } on ApiException catch (e) {
      if (e is BusinessApiException && e.code == 'NOT_FOUND') {
        // 同步时窗：审核通过后本地行还没翻 approved（秒批/离线审批），
        // 服务端已晋升共享（isCustom=false）→ 404。自愈：本地写 approved
        // （动作行门控随即隐藏），改抛专用码给 UI 出人话引导。
        await db.foodDao.setContributionStatus(food.id, 'approved');
        throw const FoodApprovedSharedApiException();
      }
      if (e is! NetworkApiException && e is! TimeoutApiException) rethrow;
    }
    return (await db.foodDao.getById(food.id))!;
  }

  /// 删除自定义食物（DELETE）：先远端后本地——409 FOOD_UNDER_REVIEW /
  /// 网络错误直接上抛，本地一切不动（可重试）；远端成功后本地两态级联：
  /// 每条历史记录走 [RecordRepository.deleteEntry]（含 tombstone/物理删
  /// 两态 + 逐条归属日聚合重算），最后物理删食物行。返回本地删除的
  /// 历史记录条数（提示文案用；服务端 deletedEntries 为权威口径，本地
  /// 条数用于即时反馈）。
  ///
  /// 404 NOT_FOUND（行已不在服务端）：核验存续后分流——仍在=同步时窗
  /// 晋升共享（自愈写 approved + 抛专用码，本地不动）；查无=按「已删除」
  /// 处理，本地照样级联清理并返回 alreadyGone（与管理员删除 404 友好
  /// 口径对齐，v1.13.20 走查：管理台手工软删的行 owner 删除曾假戴
  /// 「已共享」徽标滞留）。
  Future<CustomFoodDeleteResult> delete(
    Food food, {
    required RecordRepository recordRepository,
    required String userId,
  }) async {
    try {
      await remote.deleteCustom(food.id);
    } on ApiException catch (e) {
      if (e is BusinessApiException && e.code == 'NOT_FOUND') {
        final verify = existingFoodIdsFn;
        if (verify != null) {
          final existing = await verify(<String>[food.id]);
          if (existing.contains(food.id)) {
            // 同步时窗内服务端已晋升共享 → 404：自愈写 approved，
            // 本地行/历史记录一律不动（共享食物不该被本地删除）。
            await db.foodDao.setContributionStatus(food.id, 'approved');
            throw const FoodApprovedSharedApiException();
          }
          return CustomFoodDeleteResult(
            removed: await _cascadeLocalDelete(food, recordRepository, userId),
            alreadyGone: true,
          );
        }
        // 未装配核验：保持旧口径（一律按晋升共享处理）。
        await db.foodDao.setContributionStatus(food.id, 'approved');
        throw const FoodApprovedSharedApiException();
      }
      rethrow;
    }
    return CustomFoodDeleteResult(
      removed: await _cascadeLocalDelete(food, recordRepository, userId),
    );
  }

  /// 本地两态级联：记录逐条 [RecordRepository.deleteEntry]（含 tombstone/
  /// 物理删 + 逐条归属日聚合重算）+ 物理删食物行。返回删除条数。
  Future<int> _cascadeLocalDelete(
    Food food,
    RecordRepository recordRepository,
    String userId,
  ) async {
    final entries = await db.foodEntryDao.entriesForFood(userId, food.id);
    for (final e in entries) {
      await recordRepository.deleteEntry(e.localId);
    }
    await db.foodDao.deleteById(food.id);
    return entries.length;
  }

  /// 联网后重试 pending 自定义食物（幂等键复用，重复上行不产生重复条目）。  /// 返回本轮上行成功条数。
  ///
  /// 上行成功后以服务端返回的 id 重映射本地食物行，并同事务级联更新
  /// food_entries.foodId 引用——离线期间用临时 id（custom-*）记账的记录
  /// 上行时服务端 snapshotOf 需按服务端 id 查到食物，不重映射会让这些
  /// 记录永远卡 pending。
  Future<int> retryPending() async {
    final rows = await db.foodDao.pendingCustomFoods();
    var synced = 0;
    for (final row in rows) {
      try {
        final serverId = await remote.createCustom(
          _draftFromRow(row),
          clientRequestId: row.customClientRequestId,
        );
        if (serverId.isNotEmpty && serverId != row.id) {
          await db.transaction(() async {
            await db.foodDao.remapCustomFoodId(row.id, serverId);
            await db.foodEntryDao.remapFoodId(row.id, serverId);
          });
        } else {
          // 服务端未返回新 id（防御）：仅清 pending，主键不变。
          await db.foodDao.markCustomSynced(row.id);
        }
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
