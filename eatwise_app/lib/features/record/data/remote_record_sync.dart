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
  });

  /// 原始 change 项（entry 全量视图或 {tombstone:{id,deletedAt}}）。
  final List<Map<String, dynamic>> changes;
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
  /// serverId + baseVersion 供服务端 LWW 冲突检测，§2.3/§3.1）。
  Map<String, dynamic> _opFor(FoodEntry entry) {
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
    var hasMore = true;
    while (hasMore) {
      final page = await pullPage(syncToken: token);
      for (final change in page.changes) {
        await _applyChange(db, userId, change);
      }
      token = page.nextSyncToken;
      hasMore = page.hasMore;
    }
    return token;
  }

  Future<void> _applyChange(
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
      }
      return;
    }
    final serverId = change['id'] as String?;
    final clientRequestId = change['clientRequestId'] as String?;
    if (serverId == null) return;
    // 先按幂等键对账（本机待发记录），再按服务端主键（多端/重装）。
    FoodEntry? local;
    if (clientRequestId != null) {
      local = await db.foodEntryDao.getByClientRequestId(clientRequestId);
    }
    local ??= await db.foodEntryDao.getByServerId(serverId);
    if (local != null && local.syncStatus != SyncStatus.synced) {
      // 本地有未上行修改：不被下行覆盖（§2.4），上行冲突由 push 处理。
      return;
    }
    final foodId = change['foodId'] as String?;
    if (foodId == null || await db.foodDao.getById(foodId) == null) {
      // 本地食物库缺该条目（种子未覆盖）：跳过，待食物库刷新后重拉。
      return;
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
