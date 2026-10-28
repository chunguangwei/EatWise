import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/session_lease.dart';
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
/// 创建请求先落本地并冻结原键/原载荷；ACK 确认后再 PATCH 最新草稿。
/// customSyncPending 同时覆盖创建与编辑，下次同步由 retryPending 补传。
final class CustomFoodRepository {
  CustomFoodRepository({
    required this.db,
    required this.remote,
    this.existingFoodIdsFn,
    this.userId = 'anonymous',
  });

  /// 本地库。
  final AppDatabase db;

  /// 当前账号；匿名只允许本地保存，retry 不上行。
  final String userId;

  /// 远程端（生产 RemoteCustomFoodApi；测试 Fake）。
  final CustomFoodRemote remote;

  /// 服务端存续核验（POST /foods/batch-get 命中集；null = 不核验，
  /// 404 不推断晋升，保留本地草稿并提示错误）。
  ///
  /// 为什么需要核验（走查）：owner 删除吃 404 的旧假设「404 ⇒ 晋升共享」
  /// 在「管理台手工软删该行 / 他端已删」时不成立——已删食物会被错误地
  /// 戴上「已共享」徽标留在库里。核验仅在 404 时发起（廉价）。
  final Future<Set<String>> Function(List<String> foodIds)? existingFoodIdsFn;

  static final Random _random = Random.secure();

  // Database-scoped locks survive provider/repository recreation. Local edits
  // remain immediate; only transport is serialized for a food identity.
  static final _locks = Expando<Map<String, Future<Food?>>>();
  Map<String, Future<Food?>> get _uploads =>
      _locks[db] ??= <String, Future<Food?>>{};

  Future<T> _inSession<T>(Future<T> Function() work) {
    final api = remote;
    return api is RemoteCustomFoodApi
        ? withApiSession(api.dio, work, userId: userId)
        : work();
  }

  /// Persist identity and the exact first request before any network await.
  Future<CustomFoodSaveResult> save(CustomFoodDraft draft) =>
      _inSession(() async {
        final key = _uuid();
        final localId = 'custom-$key';
        await db.foodDao.upsertAll([
          _draftCompanion(localId, draft).copyWith(
            isCustom: const Value(true),
            ownerUserId: Value(userId),
            customSyncPending: const Value(true),
            customClientRequestId: Value(key),
            customOriginLocalId: Value(localId),
            customCreateRequestSnapshot: Value(_encodeDraft(draft)),
          ),
        ]);
        checkActiveSession();
        Food? food;
        try {
          if (userId != 'anonymous') food = await _upload(localId, userId);
        } on ApiException catch (e) {
          if (e is! NetworkApiException && e is! TimeoutApiException) rethrow;
        }
        checkActiveSession();
        food ??= await db.foodDao.customFoodByIdentity(
          localId,
          ownerUserId: userId,
        );
        checkActiveSession();
        return CustomFoodSaveResult(
          food: food!,
          uploaded: !food.customSyncPending,
        );
      });

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
    await _requireOwnedFood(foodId);
    checkActiveSession();
    try {
      final status = await remote.contribute(
        foodId,
        clientRequestId: _uuid(),
        barcode: barcode,
        evidenceImageUrl: evidenceImageUrl,
      );
      await db.foodDao.setContributionStatus(
        foodId,
        status,
        ownerUserId: userId,
      );
      return status;
    } on BusinessApiException catch (e) {
      if (e.code == 'FOOD_CONTRIBUTE_REJECTED') {
        await db.foodDao.setContributionStatus(
          foodId,
          'rejected',
          ownerUserId: userId,
        );
      }
      rethrow;
    }
  }

  Future<Food> _requireOwnedFood(String foodId, {String? ownerUserId}) async {
    final owner = ownerUserId ?? userId;
    final food =
        await db.foodDao.customFoodByIdentity(foodId, ownerUserId: owner) ??
        await db.foodDao.getById(foodId);
    final legacyAnonymous = owner == 'anonymous' && food?.ownerUserId == null;
    if (food == null ||
        !food.isCustom ||
        (food.ownerUserId != owner && !legacyAnonymous)) {
      throw const BusinessApiException(
        httpStatus: 403,
        code: 'FORBIDDEN',
        message: '无权操作该自定义食物',
      );
    }
    return food;
  }

  /// 已有共享食物的数据纠错（薄荷走查 P3，食物详情页「数据有误？」入口）：
  /// 直调 /foods/:id/correction（幂等 clientRequestId），成功返回候选状态。
  /// 不写本地库（目标为共享食物，审核状态由「我的贡献」列表下行展示）；
  /// 网络/业务错误原样上抛，由 UI 提示（表单保留可重试）。
  Future<String> submitCorrection(String foodId, CustomFoodDraft draft) {
    return remote.submitCorrection(foodId, draft, clientRequestId: _uuid());
  }

  /// Persist latest intent first. An unresolved create keeps its original
  /// identity and payload, then uploads the latest edit with PATCH after ACK.
  Future<Food> update(Food food, CustomFoodDraft draft) => _inSession(() async {
    late Food owned;
    late Food updated;
    await db.transaction(() async {
      checkActiveSession();
      owned = await _requireOwnedFood(food.id);
      checkActiveSession();
      final snapshot =
          owned.customCreateRequestSnapshot ??
          (owned.customClientRequestId.isNotEmpty
              ? _encodeDraft(_draftFromRow(owned))
              : null);
      await db.foodDao.upsertAll([
        _draftCompanion(owned.id, draft).copyWith(
          customSyncPending: const Value(true),
          customCreateRequestSnapshot: Value(snapshot),
          customLocalVersion: Value(owned.customLocalVersion + 1),
          customSyncFailCount: const Value(0),
          customSyncFailed: const Value(false),
        ),
      ]);
      checkActiveSession();
      updated = (await db.foodDao.getById(owned.id, ownerUserId: userId))!;
      checkActiveSession();
    });
    // Do not wait on a create whose response is still unknown. Its upload loop
    // will observe the new generation once the original ACK arrives.
    if (owned.customClientRequestId.isEmpty &&
        userId != 'anonymous' &&
        !_uploads.containsKey(
          _lockKey(owned.customOriginLocalId ?? owned.id, userId),
        )) {
      try {
        final result = await _upload(owned.id, userId);
        if (result != null) return result;
      } on ApiException catch (e) {
        if (e is! NetworkApiException && e is! TimeoutApiException) rethrow;
      }
    }
    checkActiveSession();
    return updated;
  });

  FoodsCompanion _draftCompanion(String id, CustomFoodDraft draft) =>
      FoodsCompanion(
        id: Value(id),
        nameZh: Value(draft.nameZh),
        nameEn: Value(draft.nameEn ?? draft.nameZh),
        aliasesZh: Value(jsonEncode(draft.aliasesZh)),
        aliasesEn: Value(jsonEncode(draft.aliasesEn)),
        kcalPer100g: Value(draft.per100g.kcal),
        proteinPer100g: Value(draft.per100g.proteinG),
        carbPer100g: Value(draft.per100g.carbG),
        fatPer100g: Value(draft.per100g.fatG),
        source: Value(customFoodSourceName(draft.source)),
      );

  String _encodeDraft(CustomFoodDraft draft) => jsonEncode({
    'nameZh': draft.nameZh,
    'nameEn': draft.nameEn,
    'aliasesZh': draft.aliasesZh,
    'aliasesEn': draft.aliasesEn,
    'kcal': draft.per100g.kcal,
    'protein': draft.per100g.proteinG,
    'carb': draft.per100g.carbG,
    'fat': draft.per100g.fatG,
    'source': customFoodSourceName(draft.source),
  });

  CustomFoodDraft _decodeDraft(String snapshot) {
    final json = jsonDecode(snapshot) as Map<String, dynamic>;
    return CustomFoodDraft(
      nameZh: json['nameZh'] as String,
      nameEn: json['nameEn'] as String?,
      aliasesZh: (json['aliasesZh'] as List).cast<String>(),
      aliasesEn: (json['aliasesEn'] as List).cast<String>(),
      per100g: NutritionSnapshot(
        kcal: (json['kcal'] as num).toDouble(),
        proteinG: (json['protein'] as num).toDouble(),
        carbG: (json['carb'] as num).toDouble(),
        fatG: (json['fat'] as num).toDouble(),
      ),
      source: json['source'] == 'llm-estimate'
          ? CustomFoodSource.llmEstimate
          : CustomFoodSource.manual,
    );
  }

  bool _sameDraft(Food row, CustomFoodDraft draft) =>
      row.nameZh == draft.nameZh &&
      row.nameEn == (draft.nameEn ?? draft.nameZh) &&
      row.aliasesZh == jsonEncode(draft.aliasesZh) &&
      row.aliasesEn == jsonEncode(draft.aliasesEn) &&
      row.kcalPer100g == draft.per100g.kcal &&
      row.proteinPer100g == draft.per100g.proteinG &&
      row.carbPer100g == draft.per100g.carbG &&
      row.fatPer100g == draft.per100g.fatG &&
      row.source == customFoodSourceName(draft.source);

  String _lockKey(String id, String owner) => '$owner/$id';

  Future<Food?> _upload(String id, String owner) async {
    final row = await db.foodDao.customFoodByIdentity(id, ownerUserId: owner);
    checkActiveSession();
    if (row == null) return null;
    final key = _lockKey(row.customOriginLocalId ?? row.id, owner);
    final running = _uploads[key];
    if (running != null) return running;
    final completion = Completer<Food?>();
    final future = completion.future;
    _uploads[key] = future;
    completion.complete(_uploadLoop(row.id, owner));
    return future.whenComplete(() {
      _uploads.removeWhere((_, value) => identical(value, future));
    });
  }

  Future<Food?> _prepareUploadRow(String id, String owner) => db.transaction(
    () async {
      checkActiveSession();
      final row = await db.foodDao.customFoodByIdentity(id, ownerUserId: owner);
      checkActiveSession();
      if (row == null ||
          row.customClientRequestId.isEmpty ||
          row.customCreateRequestSnapshot != null) {
        return row;
      }
      await db.foodDao.freezeLegacyCustomCreate(
        row.id,
        ownerUserId: owner,
        snapshot: _encodeDraft(_draftFromRow(row)),
        originLocalId: row.customOriginLocalId ?? row.id,
      );
      checkActiveSession();
      return db.foodDao.getById(row.id, ownerUserId: owner);
    },
  );

  Future<Food?> _uploadLoop(String id, String owner) async {
    var currentId = id;
    while (true) {
      checkActiveSession();
      final row = await _prepareUploadRow(currentId, owner);
      checkActiveSession();
      if (row == null ||
          !row.isCustom ||
          row.ownerUserId != owner ||
          !row.customSyncPending ||
          row.customSyncFailed) {
        return row;
      }
      currentId = row.id;
      final sent = row;
      try {
        if (sent.customClientRequestId.isNotEmpty) {
          final serverId = await remote.createCustom(
            _decodeDraft(sent.customCreateRequestSnapshot!),
            clientRequestId: sent.customClientRequestId,
          );
          checkActiveSession();
          if (serverId.isEmpty) throw const NetworkApiException();
          final oldId = currentId;
          await db.transaction(() async {
            checkActiveSession();
            final latest = await db.foodDao.customFoodByIdentity(
              oldId,
              ownerUserId: owner,
            );
            checkActiveSession();
            if (latest == null || latest.ownerUserId != owner) return;
            if (serverId != latest.id) {
              await db.foodDao.remapCustomFoodId(
                latest.id,
                serverId,
                ownerUserId: owner,
              );
            }
            await db.foodDao.acknowledgeCustomCreate(
              serverId,
              ownerUserId: owner,
              sentVersion:
                  _sameDraft(
                    sent,
                    _decodeDraft(sent.customCreateRequestSnapshot!),
                  )
                  ? sent.customLocalVersion
                  : -1,
            );
            checkActiveSession();
          });
          // Both old and new identities refer to this same active transport.
          currentId = serverId;
        } else {
          await remote.updateCustom(currentId, _draftFromRow(sent));
          checkActiveSession();
          await db.foodDao.markCustomSynced(
            currentId,
            ownerUserId: owner,
            sentVersion: sent.customLocalVersion,
          );
          checkActiveSession();
        }
      } on ApiException catch (e) {
        checkActiveSession();
        if (e is SessionChangedException) rethrow;
        if (sent.customClientRequestId.isNotEmpty) {
          final confirmed = await db.foodDao.customFoodByIdentity(
            currentId,
            ownerUserId: owner,
          );
          checkActiveSession();
          if (confirmed != null && confirmed.customClientRequestId.isEmpty) {
            currentId = confirmed.id;
            continue; // Exact downlink identity supersedes a late/lost create ACK.
          }
        }

        if (e is BusinessApiException &&
            e.code == 'NOT_FOUND' &&
            sent.customClientRequestId.isEmpty) {
          final existing = await existingFoodIdsFn?.call([currentId]);
          checkActiveSession();
          final latest = await db.foodDao.getById(
            currentId,
            ownerUserId: owner,
          );
          checkActiveSession();
          if (latest?.customLocalVersion == sent.customLocalVersion) {
            if (existing?.contains(currentId) == true) {
              await db.foodDao.setContributionStatus(
                currentId,
                'approved',
                ownerUserId: owner,
              );
              checkActiveSession();
            }
            // Missing server rows stop automatic retries but retain local data
            // and the ordinary delete/manual retry actions.
            await db.foodDao.writeCustomSyncFailure(
              currentId,
              ownerUserId: owner,
              failCount: sent.customSyncFailCount + 1,
              failed: true,
              sentVersion: sent.customLocalVersion,
            );
          }
          if (existing?.contains(currentId) == true) {
            throw const FoodApprovedSharedApiException();
          }
          rethrow;
        }
        if (e is BusinessApiException && _isPermanentFailure(e)) {
          await db.foodDao.writeCustomSyncFailure(
            currentId,
            ownerUserId: owner,
            failCount: sent.customSyncFailCount + 1,
            failed: sent.customSyncFailCount + 1 >= kTerminalFailThreshold,
            sentVersion: sent.customLocalVersion,
          );
          checkActiveSession();
        }
        rethrow;
      }
    }
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
  }) => _inSession(() async {
    var target = await _requireOwnedFood(food.id, ownerUserId: userId);
    checkActiveSession();
    final running =
        _uploads[_lockKey(target.customOriginLocalId ?? target.id, userId)];
    if (running != null) {
      target = await running ?? target;
      checkActiveSession();
    }
    final latest = await db.foodDao.getById(target.id, ownerUserId: userId);
    checkActiveSession();
    if (latest != null &&
        latest.customClientRequestId.isNotEmpty &&
        userId != 'anonymous') {
      target = await _upload(latest.id, userId) ?? latest;
      checkActiveSession();
    }
    final key = _lockKey(target.customOriginLocalId ?? target.id, userId);
    final gate = Completer<Food?>();
    _uploads[key] = gate.future;
    try {
      return await _delete(
        target,
        recordRepository: recordRepository,
        userId: userId,
      );
    } finally {
      _uploads.removeWhere((candidate, _) => candidate == key);
      gate.complete();
    }
  });

  Future<CustomFoodDeleteResult> _delete(
    Food food, {
    required RecordRepository recordRepository,
    required String userId,
  }) async {
    await _requireOwnedFood(food.id, ownerUserId: userId);
    try {
      if (userId != 'anonymous') await remote.deleteCustom(food.id);
      checkActiveSession();
    } on ApiException catch (e) {
      if (e is BusinessApiException && e.code == 'NOT_FOUND') {
        final verify = existingFoodIdsFn;
        if (verify != null) {
          final existing = await verify(<String>[food.id]);
          checkActiveSession();
          if (existing.contains(food.id)) {
            // 同步时窗内服务端已晋升共享 → 404：自愈写 approved，
            // 本地行/历史记录一律不动（共享食物不该被本地删除）。
            await db.foodDao.setContributionStatus(
              food.id,
              'approved',
              ownerUserId: userId,
            );
            throw const FoodApprovedSharedApiException();
          }
          return CustomFoodDeleteResult(
            removed: await _cascadeLocalDelete(food, recordRepository, userId),
            alreadyGone: true,
          );
        }
        rethrow;
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
    checkActiveSession();
    for (final e in entries) {
      await recordRepository.deleteEntry(e.localId);
      checkActiveSession();
    }
    await db.foodDao.deleteById(food.id, ownerUserId: userId, customOnly: true);
    return entries.length;
  }

  /// 联网后重试 pending 自定义食物（幂等键复用，重复上行不产生重复条目）。
  /// 返回本轮上行成功条数。
  ///
  /// 终态收敛：customSyncFailed 行跳过（停重试，详情页可手动重试）；
  /// 仅明确永久 4xx（VALIDATION / PAYLOAD_MISMATCH 等）按行累计
  /// customSyncFailCount；匿名、401/403/429/5xx 与网络错误不计数。
  /// 连续 ≥[kTerminalFailThreshold]
  /// 次 → 转终态失败（停重试 + UI 失败徽标）——永败项不再每轮重复上行，
  /// 引用该食物的记录也不再被守卫口径成片卡死（快照放行）。
  /// 上行成功后以服务端返回的 id 重映射本地食物行，并同事务级联更新
  /// food_entries.foodId 引用——离线期间用临时 id（custom-*）记账的记录
  /// 上行时服务端 snapshotOf 需按服务端 id 查到食物，不重映射会让这些
  /// 记录永远卡 pending。
  Future<int> retryPending([String? ownerUserId]) {
    final remote = this.remote;
    if (remote is RemoteCustomFoodApi) {
      return withApiSession(
        remote.dio,
        () => _retryPending(ownerUserId),
        userId: ownerUserId ?? userId,
      );
    }
    return _retryPending(ownerUserId);
  }

  Future<int> _retryPending(String? ownerUserId) async {
    final owner = ownerUserId ?? userId;
    if (owner == 'anonymous') return 0;
    final rows = await db.foodDao.pendingCustomFoods(ownerUserId: owner);
    checkActiveSession();
    var synced = 0;
    for (final row in rows) {
      checkActiveSession();
      if (row.customSyncFailed) continue;
      try {
        final result = await _upload(row.id, owner);
        checkActiveSession();
        if (result != null && !result.customSyncPending) synced++;
      } on ApiException catch (e) {
        checkActiveSession();
        if (e is SessionChangedException) rethrow;
        if (e is NetworkApiException || e is TimeoutApiException) break;
        if (e is BusinessApiException &&
            (e.isRetryable || e.httpStatus == 401 || e.httpStatus == 403)) {
          break;
        }
      }
    }
    return synced;
  }

  static bool _isPermanentFailure(BusinessApiException e) {
    const permanentCodes = <String>{
      'VALIDATION_ERROR',
      'VALIDATION_FAILED',
      'PAYLOAD_MISMATCH',
      'IDEMPOTENCY_PAYLOAD_MISMATCH',
    };
    return e.httpStatus == 422 || permanentCodes.contains(e.code);
  }

  /// 连续明确永久失败转终态的阈值；401/403/429/5xx 与网络错误不计数。
  static const int kTerminalFailThreshold = 5;

  /// 手动重试终态失败的自定义食物（详情页「重试同步」）。
  Future<bool> retryFailedNow(String foodId) => _inSession(() async {
    if (userId == 'anonymous') return false;
    final before = await db.foodDao.customFoodByIdentity(
      foodId,
      ownerUserId: userId,
    );
    checkActiveSession();
    if (before == null || !before.isCustom) return false;
    await db.foodDao.resetCustomSyncFailure(before.id, ownerUserId: userId);
    checkActiveSession();
    await retryPending();
    checkActiveSession();
    final after = await db.foodDao.customFoodByIdentity(
      foodId,
      ownerUserId: userId,
    );
    checkActiveSession();
    return after == null || !after.customSyncPending;
  });

  /// Foods 行 → 上行草稿（retryPending 用），保留创建时来源。
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
      source: row.source == 'llm-estimate' || row.source == 'llmEstimate'
          ? CustomFoodSource.llmEstimate
          : CustomFoodSource.manual,
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
