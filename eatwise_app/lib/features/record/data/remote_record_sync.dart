import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

/// 批量上行单批上限（规格 §2.3 〔假设〕）。
const int kSyncPushBatchSize = 100;

/// /sync/pull 一页结果（规格 §2.4：syncToken 游标翻页）。
final class SyncPullPage {
  const SyncPullPage({
    required this.changes,
    required this.nextSyncToken,
    required this.hasMore,
    this.waterLogChanges = const <Map<String, dynamic>>[],
    this.exerciseLogChanges = const <Map<String, dynamic>>[],
  });

  /// 原始 change 项（entry 全量视图或 {tombstone:{id,deletedAt}}）。
  final List<Map<String, dynamic>> changes;

  /// 饮水记录 change 项（waterLog 全量视图或 {tombstone:{entity,id,deletedAt}}）。
  final List<Map<String, dynamic>> waterLogChanges;

  /// 运动记录 change 项（exerciseLog 全量视图或 {tombstone:{entity,id,deletedAt}}）。
  final List<Map<String, dynamic>> exerciseLogChanges;
  final String? nextSyncToken;
  final bool hasMore;
}

/// 真实同步远程端（M7，替换 FakeRecordRemote 注入；Fake 保留供测试）。
///
/// - 上行：POST /sync/push（规格 §2.3 ops 协议，≤100/批串行）；
///   逐条 applied/conflict/error 映射四态迁移所需的 [PushOutcome]：
///   网络/超时/5xx/429/401 → [PushRetryable]（T5 保数据，401 为登出场景
///   数据按 T15 保留待重登后续传）；其余 4xx → [PushReject]（T7 回滚）。
/// - 下行：GET /sync/pull（syncToken 增量，§2.4），落 drift 时
///   不覆盖本地 pending/submitting/conflicted 记录（§2.4 防腐）。
final class RemoteRecordSync implements RecordRemote {
  RemoteRecordSync({required this.dio, required this.location});

  /// 已装配 dio。
  final Dio dio;

  /// 设备时区（归属日换算，D-07）。
  final tz.Location location;
  final Random _random = Random();

  bool _online = true;

  /// 最近一次请求结果推断的在线状态（无 connectivity 依赖的轻量口径：
  /// 网络错误翻转离线，任一成功请求翻回在线）。
  @override
  bool get isOnline => _online;

  /// 测试注入在线状态。
  @visibleForTesting
  set online(bool value) => _online = value;

  // ===== 上行 =====

  @override
  Future<PushOutcome> push(FoodEntry entry) async {
    final outcomes = await pushBatch(<FoodEntry>[entry]);
    return outcomes.first;
  }

  /// 批量上行（≤[kSyncPushBatchSize]/批，分批串行，§2.3）。
  /// 返回与 [entries] 等长、同序的逐条结果。
  Future<List<PushOutcome>> pushBatch(List<FoodEntry> entries) async {
    final outcomes = <PushOutcome>[];
    for (var i = 0; i < entries.length; i += kSyncPushBatchSize) {
      final chunk = entries.sublist(
        i,
        i + kSyncPushBatchSize > entries.length
            ? entries.length
            : i + kSyncPushBatchSize,
      );
      outcomes.addAll(await _pushChunk(chunk));
    }
    return outcomes;
  }

  Future<List<PushOutcome>> _pushChunk(List<FoodEntry> chunk) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/sync/push',
        data: <String, dynamic>{'ops': chunk.map(_opFor).toList()},
      );
      _online = true;
      final body = response.data ?? const <String, dynamic>{};
      final results = (body['results'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
      final byRequestId = <String, Map<String, dynamic>>{
        for (final r in results) r['clientRequestId']! as String: r,
      };
      return chunk.map((entry) {
        final result = byRequestId[entry.clientRequestId];
        if (result == null) return const PushRetryable('MISSING_RESULT');
        return _outcomeOf(result);
      }).toList();
    } on DioException catch (e) {
      final outcome = _outcomeFromError(toApiException(e));
      return List<PushOutcome>.filled(chunk.length, outcome);
    }
  }

  /// FoodEntry → sync/push op（create 无 serverId；update 携带
  /// serverId + baseVersion 供服务端 LWW 冲突检测，§2.3/§3.1；
  /// 用户删除的已上行行（deleted=true）→ delete op，ack 后物理清除）。
  Map<String, dynamic> _opFor(FoodEntry entry) {
    if (entry.deleted) {
      return <String, dynamic>{
        'clientRequestId': entry.clientRequestId,
        'entity': 'foodEntry',
        'op': 'delete',
        if (entry.serverId != null) 'serverId': entry.serverId,
        'payload': <String, dynamic>{},
      };
    }
    final payload = <String, dynamic>{
      'eatenAt': entry.datetimeUtc,
      'foodId': entry.foodId,
      'grams': entry.amountG,
      'inputMethod': entry.source.name,
    };
    if (entry.serverId == null) {
      return <String, dynamic>{
        'clientRequestId': entry.clientRequestId,
        'entity': 'foodEntry',
        'op': 'create',
        'payload': payload,
      };
    }
    return <String, dynamic>{
      'clientRequestId': entry.clientRequestId,
      'entity': 'foodEntry',
      'op': 'update',
      'serverId': entry.serverId,
      'baseVersion': ?entry.serverVersion,
      'payload': payload,
    };
  }

  PushOutcome _outcomeOf(Map<String, dynamic> result) {
    final status = result['status'] as String? ?? 'error';
    final serverEntry = result['serverEntry'];
    final entryMap = serverEntry is Map<String, dynamic> ? serverEntry : null;
    switch (status) {
      case 'applied':
        return PushAck(
          serverId: entryMap?['id'] as String? ?? '',
          serverVersion: (entryMap?['version'] as num?)?.toInt() ?? 1,
          serverUpdatedAtUtc:
              entryMap?['updatedAt'] as String? ??
              DateTime.now().toUtc().toIso8601String(),
        );
      case 'conflict':
        return PushConflict(
          serverVersion: (entryMap?['version'] as num?)?.toInt() ?? 0,
          serverUpdatedAtUtc:
              entryMap?['updatedAt'] as String? ??
              DateTime.now().toUtc().toIso8601String(),
        );
      default:
        final code =
            (result['error'] as Map<String, dynamic>?)?['code'] as String? ??
            'INTERNAL_ERROR';
        if (code == 'INTERNAL_ERROR') return PushRetryable(code);
        return PushReject(code);
    }
  }

  /// 请求级失败（整批同结果）：网络/超时/5xx/429/401 → 可重试（T5）；
  /// 其余 4xx → 校验拒绝（T7）。
  PushOutcome _outcomeFromError(ApiException error) {
    if (error is NetworkApiException || error is TimeoutApiException) {
      _online = false;
      return PushRetryable(error.code);
    }
    if (error is BusinessApiException) {
      if (error.isRetryable || error.httpStatus == 401) {
        return PushRetryable(error.code);
      }
      return PushReject(error.code);
    }
    return const PushRetryable('NETWORK_ERROR');
  }

  // ===== 下行 =====

  /// 拉一页增量（首次同步不传 [syncToken] → 全量，§2.4）。
  Future<SyncPullPage> pullPage({String? syncToken, int limit = 200}) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/sync/pull',
        queryParameters: <String, dynamic>{
          'syncToken': ?syncToken,
          'limit': limit,
        },
      );
      _online = true;
      final body = response.data ?? const <String, dynamic>{};
      return SyncPullPage(
        changes: (body['changes'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>(),
        waterLogChanges:
            (body['waterLogChanges'] as List<dynamic>? ?? const <dynamic>[])
                .cast<Map<String, dynamic>>(),
        exerciseLogChanges:
            (body['exerciseLogChanges'] as List<dynamic>? ?? const <dynamic>[])
                .cast<Map<String, dynamic>>(),
        nextSyncToken: body['syncToken'] as String?,
        hasMore: body['hasMore'] == true,
      );
    } on DioException catch (e) {
      final error = toApiException(e);
      if (error is NetworkApiException || error is TimeoutApiException) {
        _online = false;
      }
      throw error;
    }
  }

  /// 增量下行入库：游标翻页直到 hasMore=false，返回最新 syncToken
  /// （调用方持久化）。syncToken 失效（INVALID_SYNC_TOKEN）→ 全量重拉。
  ///
  /// 落库规则（§2.4）：本地存在未上行修改（非 synced）的记录不被下行
  /// 覆盖；tombstone 仅软删已同步记录（删改冲突双份保留待人工处理）。
  /// 防丢约束：某条 change 因本地食物库缺条目被跳过时，返回的游标停留在
  /// 首个发生跳过的页面之前——该 change 未落库，token 不得越过它，
  /// 下轮（食物库刷新后）从旧游标重拉补齐（重放对已落库行幂等）。
  Future<String?> pullDown(
    AppDatabase db,
    String userId,
    String? syncToken,
  ) async {
    String? token = syncToken;
    try {
      token = await _pullPages(db, userId, token);
    } on ApiException catch (e) {
      if (e is BusinessApiException && e.code == 'INVALID_SYNC_TOKEN') {
        token = await _pullPages(db, userId, null);
      } else {
        rethrow;
      }
    }
    return token;
  }

  Future<String?> _pullPages(
    AppDatabase db,
    String userId,
    String? syncToken,
  ) async {
    String? token = syncToken;
    // 首个发生跳过的页面之前的游标（存在跳过时返回它，不持久化新 token）。
    String? firstSkippedPageToken;
    // 下行落库涉及的归属日集合（结束后统一重算聚合缓存——下行入库不经
    // 仓储 _recompute，不重算则首页今日汇总/信号卡拿不到重装恢复的记录，
    // v1.12.4 走查「有记录但首页不显示」根因）。
    final affectedDates = <String>{};
    var hasMore = true;
    while (hasMore) {
      final pageTokenBefore = token;
      final page = await pullPage(syncToken: token);
      var pageSkipped = false;
      for (final change in page.changes) {
        final result = await _applyChange(db, userId, change);
        pageSkipped = result.skipped || pageSkipped;
        final affected = result.affectedDate;
        if (affected != null) affectedDates.add(affected);
      }
      for (final change in page.waterLogChanges) {
        await _applyWaterChange(db, userId, change);
      }
      for (final change in page.exerciseLogChanges) {
        await _applyExerciseChange(db, userId, change);
      }
      if (pageSkipped) firstSkippedPageToken ??= pageTokenBefore;
      token = page.nextSyncToken;
      hasMore = page.hasMore;
    }
    // 聚合缓存重算（§2.6 本地预估；下行 insert/update/tombstone 即时生效）。
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final localDate in affectedDates) {
      await db.foodEntryDao.recomputeDailyNutrition(
        userId,
        localDate,
        updatedAtUtc: nowIso,
      );
    }
    return firstSkippedPageToken ?? token;
  }

  /// 饮水记录下行入库（两态轻量口径）：本地 pending 不被下行覆盖；
  /// tombstone 仅清除已同步行。
  Future<void> _applyWaterChange(
    AppDatabase db,
    String userId,
    Map<String, dynamic> change,
  ) async {
    final tombstone = change['tombstone'];
    if (tombstone is Map<String, dynamic>) {
      final local = await db.waterLogDao.getByServerId(
        tombstone['id']! as String,
      );
      if (local != null && local.syncState == WaterSyncState.synced) {
        await db.waterLogDao.deleteLog(local.localId);
      }
      return;
    }
    final serverId = change['id'] as String?;
    if (serverId == null) return;
    final clientRequestId = change['clientRequestId'] as String?;
    WaterLog? local;
    if (clientRequestId != null) {
      local = await db.waterLogDao.getByClientRequestId(clientRequestId);
    }
    local ??= await db.waterLogDao.getByServerId(serverId);
    if (local != null && local.syncState == WaterSyncState.pending) {
      // 本地未上行：不被下行覆盖（上行 create 幂等键对账后回填）。
      return;
    }
    final loggedAt =
        change['loggedAt'] as String? ??
        DateTime.now().toUtc().toIso8601String();
    final companion = WaterLogsCompanion(
      userId: Value(userId),
      serverId: Value(serverId),
      clientRequestId: Value(clientRequestId ?? ''),
      syncState: const Value(WaterSyncState.synced),
      deleted: const Value(false),
      amountMl: Value((change['amountMl'] as num?)?.toInt() ?? 0),
      datetimeUtc: Value(loggedAt),
      localDate: Value(
        change['localDate'] as String? ??
            _localDateOf(DateTime.parse(loggedAt)),
      ),
    );
    if (local != null) {
      await db.waterLogDao.applyServerRow(local.localId, companion);
    } else {
      await db.waterLogDao.insertLog(
        companion.copyWith(
          localId: Value(_uuid()),
          createdAtUtc: Value(loggedAt),
        ),
      );
    }
  }

  /// 运动记录下行入库（两态轻量口径，与 [_applyWaterChange] 同法）：
  /// 本地 pending 不被下行覆盖；tombstone 仅清除已同步行。
  Future<void> _applyExerciseChange(
    AppDatabase db,
    String userId,
    Map<String, dynamic> change,
  ) async {
    final tombstone = change['tombstone'];
    if (tombstone is Map<String, dynamic>) {
      final local = await db.exerciseLogDao.getByServerId(
        tombstone['id']! as String,
      );
      if (local != null && local.syncState == ExerciseSyncState.synced) {
        await db.exerciseLogDao.deleteLog(local.localId);
      }
      return;
    }
    final serverId = change['id'] as String?;
    if (serverId == null) return;
    final clientRequestId = change['clientRequestId'] as String?;
    ExerciseLog? local;
    if (clientRequestId != null) {
      local = await db.exerciseLogDao.getByClientRequestId(clientRequestId);
    }
    local ??= await db.exerciseLogDao.getByServerId(serverId);
    if (local != null && local.syncState == ExerciseSyncState.pending) {
      // 本地未上行：不被下行覆盖（上行 create 幂等键对账后回填）。
      return;
    }
    final loggedAt =
        change['loggedAt'] as String? ??
        DateTime.now().toUtc().toIso8601String();
    final companion = ExerciseLogsCompanion(
      userId: Value(userId),
      serverId: Value(serverId),
      clientRequestId: Value(clientRequestId ?? ''),
      syncState: const Value(ExerciseSyncState.synced),
      deleted: const Value(false),
      typeKey: Value(change['typeKey'] as String? ?? 'other'),
      durationMin: Value((change['durationMin'] as num?)?.toInt() ?? 0),
      kcal: Value((change['kcal'] as num?)?.toDouble() ?? 0),
      steps: Value((change['steps'] as num?)?.toInt()),
      source: Value(change['source'] as String?),
      localDate: Value(
        change['localDate'] as String? ??
            _localDateOf(DateTime.parse(loggedAt)),
      ),
    );
    if (local != null) {
      await db.exerciseLogDao.applyServerRow(local.localId, companion);
    } else {
      await db.exerciseLogDao.insertLog(
        companion.copyWith(
          localId: Value(_uuid()),
          createdAtUtc: Value(loggedAt),
        ),
      );
    }
  }

  /// 应用单条 entry change。返回是否因本地食物库缺条目被跳过未落库
  /// （调用方据此回退游标，保证该 change 下轮重拉不丢）+ 实际落库/软删
  /// 影响的归属日（供调用方重算聚合缓存）。
  Future<({bool skipped, String? affectedDate})> _applyChange(
    AppDatabase db,
    String userId,
    Map<String, dynamic> change,
  ) async {
    final tombstone = change['tombstone'];
    if (tombstone is Map<String, dynamic>) {
      final local = await db.foodEntryDao.getByServerId(
        tombstone['id']! as String,
      );
      // 删改冲突（D-20 不可合并）：本地有未同步修改 → 双份保留，不软删。
      if (local != null && local.syncStatus == SyncStatus.synced) {
        await db.foodEntryDao.markDeleted(local.localId);
        return (skipped: false, affectedDate: local.localDate);
      }
      return (skipped: false, affectedDate: null);
    }
    final serverId = change['id'] as String?;
    final clientRequestId = change['clientRequestId'] as String?;
    if (serverId == null) return (skipped: false, affectedDate: null);
    // 先按幂等键对账（本机待发记录），再按服务端主键（多端/重装）。
    FoodEntry? local;
    if (clientRequestId != null) {
      local = await db.foodEntryDao.getByClientRequestId(clientRequestId);
    }
    local ??= await db.foodEntryDao.getByServerId(serverId);
    if (local != null && local.syncStatus != SyncStatus.synced) {
      // 本地有未上行修改：不被下行覆盖（§2.4），上行冲突由 push 处理。
      return (skipped: false, affectedDate: null);
    }
    final foodId = change['foodId'] as String?;
    if (foodId == null || await db.foodDao.getById(foodId) == null) {
      // 本地食物库缺该条目（种子未覆盖）：跳过不落库；游标由 _pullPages
      // 回退到本页之前，待食物库刷新后重拉补齐。
      return (skipped: true, affectedDate: null);
    }
    final snapshot = change['nutritionSnapshot'];
    final snapshotMap = snapshot is Map<String, dynamic>
        ? snapshot
        : const <String, dynamic>{};
    final eatenAt = change['eatenAt']! as String;
    final updatedAt =
        change['updatedAt'] as String? ??
        DateTime.now().toUtc().toIso8601String();
    final version = (change['version'] as num?)?.toInt() ?? 1;
    final grams = (change['grams'] as num?)?.toDouble() ?? 0;
    final inputMethod = change['inputMethod'] as String? ?? 'manual';
    final companion = FoodEntriesCompanion(
      userId: Value(userId),
      serverId: Value(serverId),
      clientRequestId: Value(clientRequestId ?? _uuid()),
      syncStatus: const Value(SyncStatus.synced),
      serverVersion: Value(version),
      serverUpdatedAt: Value(updatedAt),
      retryCount: const Value(0),
      deleted: const Value(false),
      datetimeUtc: Value(eatenAt),
      localDate: Value(_localDateOf(DateTime.parse(eatenAt))),
      foodId: Value(foodId),
      amountG: Value(grams),
      kcal: Value((snapshotMap['kcal'] as num?)?.toDouble() ?? 0),
      proteinG: Value((snapshotMap['proteinG'] as num?)?.toDouble() ?? 0),
      carbG: Value((snapshotMap['carbsG'] as num?)?.toDouble() ?? 0),
      fatG: Value((snapshotMap['fatG'] as num?)?.toDouble() ?? 0),
      source: Value(_sourceOf(inputMethod)),
      updatedAtUtc: Value(updatedAt),
    );
    if (local != null) {
      await db.foodEntryDao.updateEntry(local.localId, companion);
    } else {
      await db.foodEntryDao.insertEntry(
        companion.copyWith(
          localId: Value(_uuid()),
          // 本地无创建时刻概念，统一以服务端时间为准（D-07 客户端时钟不可信）。
          createdAtUtc: Value(updatedAt),
          lastError: const Value(null),
        ),
      );
    }
    return (
      skipped: false,
      affectedDate: _localDateOf(DateTime.parse(eatenAt)),
    );
  }

  /// 归属日 = 就餐 UTC 按设备时区换算的本地自然日（D-07）。
  String _localDateOf(DateTime utc) {
    final epochSec = utc.toUtc().millisecondsSinceEpoch ~/ 1000;
    return localDateOf(epochSec, location).toIsoString();
  }

  EntrySource _sourceOf(String inputMethod) {
    for (final source in EntrySource.values) {
      if (source.name == inputMethod) return source;
    }
    return EntrySource.manual;
  }

  /// UUIDv4（下行新行本地主键）。
  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
