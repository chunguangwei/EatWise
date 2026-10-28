import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';

import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/remote_record_sync.dart';
import 'package:eatwise/features/record/domain/meal_type.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:timezone/timezone.dart' as tz;

/// T7 校验拒绝回滚事件（UI 提示「这条记录没被保存」用，§4.1 文案）。
final class RecordSyncFailure {
  const RecordSyncFailure({required this.localId, required this.code});

  /// 被回滚记录的本地主键。
  final String localId;

  /// 服务端校验错误码。
  final String code;
}

/// M3 记录仓库：乐观更新入账 + 四态同步 + D-11 撤销窗 + 聚合重算。
///
/// 状态迁移对齐《规格-数据同步与四态持久化》§1.3：
/// T1 在线确认 → submitting（撤销窗结束才上行）；T2 离线确认 → pending；
/// T3 撤销窗内撤销 → 本地删除；T4 上行成功 → synced 回填；
/// T5 可重试失败 → pending；T6 409 → conflicted；T7 4xx → 回滚删除；
/// T8 网络恢复/手动重试 → 批量上行；T9/T10 编辑 → localVersion+1。
final class RecordRepository {
  RecordRepository({
    required this.db,
    required this.remote,
    required this._location,
    this._locationResolver,
    this.undoWindow = const Duration(seconds: 10),
    DateTime Function()? clock,
    this.userId = 'anonymous',
  }) : _clock = clock ?? DateTime.now,
       _session = remote is RemoteRecordSync
           ? SessionLease.capture(remote.dio)
           : SessionLease.current;

  /// 本地数据库。
  final AppDatabase db;

  /// 同步远程端。
  final RecordRemote remote;

  /// 设备时区（归属日换算，D-07）。
  final tz.Location _location;
  final tz.Location Function()? _locationResolver;

  /// Read at use time so travel does not recreate this repository or its undo timers.
  tz.Location get location => _locationResolver?.call() ?? _location;
  final DateTime Function() _clock;
  // 固定构造时的登录代际；旧 Timer 不得在同账号重新登录后借新令牌发送。
  final SessionLease? _session;
  final Random _random = Random();

  /// D-11 撤销窗时长（默认 10 秒；测试可注入更短值）。
  final Duration undoWindow;

  /// 归属用户（未登录 anonymous，T18）。
  final String userId;

  final Map<String, Timer> _pushTimers = <String, Timer>{};
  final Map<String, DateTime> _undoDeadlines = <String, DateTime>{};
  final StreamController<RecordSyncFailure> _failures =
      StreamController<RecordSyncFailure>.broadcast();

  final Map<String, Future<void>> _activePushes = <String, Future<void>>{};
  bool _disposed = false;

  /// Provider 会话结束后不再发送请求或应用迟到回执。
  bool get isDisposed => _disposed;

  /// T7 回滚事件流。
  Stream<RecordSyncFailure> get failures => _failures.stream;

  /// 乐观更新入账（T1/T2）：先写本地库（UI 经流立即展示），
  /// 在线 → submitting 并启动撤销窗，窗结束上行；离线 → pending。
  Future<FoodEntry> addEntry(RecordDraft draft) async {
    _checkActive();
    if (!isFoodAmountInRange(draft.amountG)) {
      throw ArgumentError.value(
        draft.amountG,
        'amountG',
        '份量必须为 0.1–5000 克的有限数值',
      );
    }
    final localId = _uuid();
    final online = remote.isOnline;
    final mealLocal = tz.TZDateTime.from(draft.mealUtc.toUtc(), location);
    final attributedDate = localDateOf(
      draft.mealUtc.toUtc().millisecondsSinceEpoch ~/ 1000,
      mealLocal.location,
    ).toIsoString();
    // 入账、聚合与结果回读必须一起成功；任何一步失败都回滚，避免 UI
    // 收到失败后重试，却把已经落库的上一条再记一次。
    final saved = await _transaction(() async {
      _checkActive();
      // Resolve the current owned identity and nutrition inside this same
      // transaction: create ACK/downlink may have remapped a stale detail id.
      final food =
          await db.foodDao.getById(draft.foodId, ownerUserId: userId) ??
          await db.foodDao.customFoodByIdentity(
            draft.foodId,
            ownerUserId: userId,
          );
      _checkActive();
      if (food == null) {
        throw ArgumentError.value(draft.foodId, 'foodId', '食物不存在于食物库');
      }
      final snapshot = NutritionSnapshot.forAmount(food, draft.amountG);
      final nowUtc = _clock().toUtc();
      final nowIso = nowUtc.toIso8601String();
      final entry = FoodEntriesCompanion(
        localId: Value(localId),
        userId: Value(userId),
        clientRequestId: Value(_uuid()),
        syncStatus: Value(online ? SyncStatus.submitting : SyncStatus.pending),
        serverId: const Value(null),
        serverVersion: const Value(null),
        serverUpdatedAt: const Value(null),
        retryCount: const Value(0),
        lastError: const Value(null),
        deleted: const Value(false),
        datetimeUtc: Value(draft.mealUtc.toUtc().toIso8601String()),
        localDate: Value(attributedDate),
        foodId: Value(food.id),
        amountG: Value(draft.amountG),
        kcal: Value(snapshot.kcal),
        proteinG: Value(snapshot.proteinG),
        carbG: Value(snapshot.carbG),
        fatG: Value(snapshot.fatG),
        source: Value(draft.source),
        note: Value(draft.note),
        duringFast: Value(draft.duringFast),
        // 餐次（优化点 2）：未显式选择时按就餐时间本地小时智能预判。
        mealType: Value(draft.mealType ?? suggestMealType(mealLocal.hour)),
        createdAtUtc: Value(nowIso),
        updatedAtUtc: Value(nowIso),
      );
      await db.foodEntryDao.insertEntry(entry);
      await _recompute(attributedDate);
      final result = (await db.foodEntryDao.getByLocalId(localId))!;
      _checkActive();
      return result;
    });
    // 提交成功后才开始撤销窗与上行，防止失败事务泄漏远程请求或撤销状态。
    if (_disposed) return saved;
    if (online) {
      _schedulePush(localId, undoable: true);
    } else {
      // 离线也允许撤销（T2：纯本地回滚），仅记录撤销截止时刻。
      _undoDeadlines[localId] = _clock().toUtc().add(undoWindow);
    }
    return saved;
  }

  /// D-11 撤销：撤销窗内撤回该条（T3，乐观更新回滚，本地删除）。
  /// 返回是否撤销成功；窗口已过或记录不存在 → false。
  Future<bool> undo(String localId) async {
    final deadline = _undoDeadlines[localId];
    if (deadline == null || !_clock().toUtc().isBefore(deadline)) {
      return false;
    }
    // 删除与聚合共享事务；成功后才取消窗口，失败时用户仍可再次撤销。
    return deleteEntry(localId);
  }

  /// 用户删除即时落本地事务并重算。已发出但结果未知的 create 保留原
  /// 请求和 tombstone，取得 serverId 后再删除，避免下行把记录复活。
  Future<bool> deleteEntry(String localId) async {
    _checkActive();
    final removed = await _transaction(() async {
      _checkActive();
      final entry = await db.foodEntryDao.getByLocalId(localId);
      if (entry == null || entry.userId != userId || entry.deleted) {
        return false;
      }
      if (entry.serverId == null && entry.createRequestSnapshot == null) {
        await db.foodEntryDao.deleteEntry(localId);
      } else {
        await db.foodEntryDao.tombstoneEntry(
          localId,
          _clock().toUtc().toIso8601String(),
          // 未知 create 必须保留原键，供重放与下行对账。
          clientRequestId: entry.createRequestSnapshot != null
              ? entry.clientRequestId
              : _uuid(),
          localVersion: entry.localVersion + 1,
        );
      }
      await _recompute(entry.localDate);
      _checkActive();
      return true;
    });
    if (!removed) return false;
    _cancelPush(localId);
    // 在途 create 会在回执后处理最新意图，不阻塞用户等待旧网络请求。
    if (!_disposed && remote.isOnline && !_activePushes.containsKey(localId)) {
      await _push(localId);
    }
    return true;
  }

  /// 份量/餐次和聚合一起提交。未知 create 的原请求冻结在独立快照，
  /// 当前行保存最新份量；获得 create 回执后再换键发送 update。
  Future<FoodEntry> updateEntry(
    String localId, {
    required double amountG,
    MealType? mealType,
  }) async {
    _checkActive();
    if (!isFoodAmountInRange(amountG)) {
      throw ArgumentError.value(amountG, 'amountG', '份量必须为 0.1–5000 克的有限数值');
    }
    var schedulePush = false;
    final saved = await _transaction(() async {
      _checkActive();
      final entry = await db.foodEntryDao.getByLocalId(localId);
      if (entry == null || entry.userId != userId || entry.deleted) {
        throw ArgumentError.value(localId, 'localId', '记录不存在');
      }
      final food = await db.foodDao.getById(entry.foodId, ownerUserId: userId);
      if (food == null) throw StateError('记录引用的食物不存在: ${entry.foodId}');
      final newMealType = mealType ?? entry.mealType;
      final nowIso = _clock().toUtc().toIso8601String();
      if (amountG == entry.amountG) {
        // 餐次是纯本地列，不能轮换请求键或触发上行。
        await db.foodEntryDao.updateEntry(
          localId,
          FoodEntriesCompanion(
            mealType: Value(newMealType),
            updatedAtUtc: Value(nowIso),
          ),
        );
      } else {
        final snapshot = NutritionSnapshot.forAmount(food, amountG);
        schedulePush = entry.syncStatus == SyncStatus.synced;
        await db.foodEntryDao.updateEntry(
          localId,
          FoodEntriesCompanion(
            amountG: Value(amountG),
            mealType: Value(newMealType),
            kcal: Value(snapshot.kcal),
            proteinG: Value(snapshot.proteinG),
            carbG: Value(snapshot.carbG),
            fatG: Value(snapshot.fatG),
            localVersion: Value(entry.localVersion + 1),
            clientRequestId: Value(
              entry.createRequestSnapshot != null
                  ? entry.clientRequestId
                  : _uuid(),
            ),
            syncStatus: Value(
              schedulePush ? SyncStatus.submitting : entry.syncStatus,
            ),
            updatedAtUtc: Value(nowIso),
          ),
        );
      }
      await _recompute(entry.localDate);
      final result = (await db.foodEntryDao.getByLocalId(localId))!;
      _checkActive();
      return result;
    });
    if (!_disposed && schedulePush) _schedulePush(localId, undoable: false);
    return saved;
  }

  /// 撤销窗到期后的上行入口（公开以便「立即重试」与测试驱动窗口结束）。
  Future<void> flushEntry(String localId) async {
    _cancelPush(localId);
    await _push(localId);
  }

  /// 批量上行全部未同步记录（T8：网络恢复 / 手动「立即重试」/ 引擎每轮）。
  /// 先扫已删除待 delete op 的 tombstone 行（用户删除已上行记录，
  /// ack/NOT_FOUND 后物理清除），再上行 pending + submitting + conflicted：
  /// - submitting = 在线入账等待撤销窗 Timer——进程被杀 Timer 即丢失，行会
  ///   永久滞留「待同步」（换机丢失，走查 L1）；上行 Timer 仍在内存
  ///   （_pushTimers 命中）的行跳过，保 D-11 语义、Timer 到点自己上行
  ///   （_undoDeadlines 离线入账也登记且无 Timer，不能作跳过依据）；
  /// - conflicted = 409 冲突行，重试以记录的 serverVersion 为新基线上行，
  ///   服务端 LWW 收敛（走查 L3：旧逻辑 conflicted 无任何出口）。
  /// 返回尝试条数。
  Future<int> retryPending() async {
    if (_disposed) return 0;
    checkActiveSession();
    final deletePendings = await db.foodEntryDao.deletePendingEntries(userId);
    checkActiveSession();
    for (final entry in deletePendings) {
      if (_disposed) return 0;
      checkActiveSession();
      await _push(entry.localId);
    }
    if (_disposed) return 0;
    final pendings = await db.foodEntryDao.pendingEntries(
      userId,
      statuses: const <SyncStatus>{
        SyncStatus.pending,
        SyncStatus.submitting,
        SyncStatus.conflicted,
      },
    );
    var attempted = deletePendings.length;
    for (final entry in pendings) {
      if (_disposed) return attempted;
      checkActiveSession();
      if (_pushTimers.containsKey(entry.localId)) continue;
      await _push(entry.localId);
      attempted += 1;
    }
    return attempted;
  }

  /// 「待同步 N 条」计数流（§4.1）。
  Stream<int> watchPendingCount() {
    return db.foodEntryDao.watchPendingCount(userId);
  }

  /// 某日聚合缓存流（本地预估，§2.6）。
  Stream<DailyNutritionCache?> watchDailyNutrition(DateTime dayUtc) {
    return db.foodEntryDao.watchDailyNutrition(userId, _localDateOf(dayUtc));
  }

  /// 某日记录列表（排除 tombstone）。
  Future<List<FoodEntry>> entriesForDate(DateTime dayUtc) {
    return db.foodEntryDao.entriesForDate(userId, _localDateOf(dayUtc));
  }

  /// 双语食物搜索（D-15/D-16）。
  Future<List<Food>> searchFoods(String query, {int limit = 20}) {
    return db.foodDao.searchFoods(query, limit: limit, ownerUserId: userId);
  }

  /// 语音录入词典全量加载（食物库量级约 7.5k 条，内存可行；
  /// 不复用 searchFoods 的 limit 截断——截断会让尾部词条永远匹配不到）。
  Future<List<Food>> allFoodsForVoiceDict() {
    return db.foodDao.allFoods(ownerUserId: userId);
  }

  /// 释放资源：取消全部待发上行与事件流。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _pushTimers.values) {
      timer.cancel();
    }
    _pushTimers.clear();
    _undoDeadlines.clear();
    await _failures.close();
  }

  // ---- 内部 ----

  /// 启动撤销窗（T1 假设：窗内不发上行请求，窗结束才上行）。
  void _schedulePush(String localId, {required bool undoable}) {
    if (_disposed) return;
    _cancelPush(localId);
    if (undoable) {
      _undoDeadlines[localId] = _clock().toUtc().add(undoWindow);
    }
    _pushTimers[localId] = Timer(undoWindow, () {
      _pushTimers.remove(localId);
      _undoDeadlines.remove(localId);
      unawaited(_push(localId));
    });
  }

  void _cancelPush(String localId) {
    _pushTimers.remove(localId)?.cancel();
    _undoDeadlines.remove(localId);
  }

  void _checkActive() {
    if (_disposed) throw _RecordSessionClosed();
    _session?.check();
    checkActiveSession();
  }

  Future<T> _transaction<T>(Future<T> Function() work) {
    return db.transaction(() async {
      _checkActive();
      final result = await work();
      _checkActive();
      return result;
    });
  }

  /// 同一进程合并重复触发；可靠性由数据库快照承担，重启不依赖此锁。
  Future<void> _push(String localId) async {
    if (_disposed) return;
    final active = _activePushes[localId];
    if (active != null) return active;
    final session = _session;
    final pushing =
        (session == null
                ? _pushUntilSettled(localId)
                : session.run(() => _pushUntilSettled(localId)))
            .onError<_RecordSessionClosed>((_, _) {})
            .onError<SessionChangedException>((_, _) {});
    _activePushes[localId] = pushing;
    try {
      await pushing;
    } finally {
      unawaited(_activePushes.remove(localId));
    }
  }

  Future<void> _pushUntilSettled(String localId) async {
    var followUp = true;
    while (followUp && !_disposed) {
      final sent = await _transaction(() async {
        if (_disposed) return null;
        final entry = await db.foodEntryDao.getByLocalId(localId);
        if (_disposed || entry == null || entry.userId != userId) return null;
        final frozen = entry.createRequestSnapshot;
        if (entry.deleted && entry.serverId == null && frozen == null) {
          await db.foodEntryDao.deleteEntry(localId);
          await _recompute(entry.localDate);
          return null;
        }
        if (!entry.deleted && entry.syncStatus == SyncStatus.synced) {
          return null;
        }
        if (!entry.deleted) {
          final food = await db.foodDao.getById(
            entry.foodId,
            ownerUserId: userId,
          );
          if (_disposed ||
              food == null ||
              (food.customSyncPending && !food.customSyncFailed)) {
            return null;
          }
        }
        if (frozen != null) {
          // 归属是本地身份，不在 wire payload 内；匿名记录注册认领后
          // 用当前 owner 续传，原请求键/食物/份量仍按冻结值重放。
          return FoodEntry.fromJson(
            jsonDecode(frozen) as Map<String, dynamic>,
          ).copyWith(userId: entry.userId);
        }
        if (entry.serverId == null) {
          await db.foodEntryDao.updateEntry(
            localId,
            FoodEntriesCompanion(
              createRequestSnapshot: Value(jsonEncode(entry.toJson())),
            ),
          );
        }
        return entry;
      });
      if (_disposed || sent == null) return;
      checkActiveSession();
      final outcome = await remote.push(sent);
      if (_disposed) return;
      checkActiveSession();
      RecordSyncFailure? failure;
      followUp = await _transaction(() async {
        if (_disposed) return false;
        final current = await db.foodEntryDao.getByLocalId(localId);
        if (_disposed || current == null || current.userId != userId) {
          return false;
        }
        final sameGeneration =
            current.clientRequestId == sent.clientRequestId &&
            current.localVersion == sent.localVersion &&
            current.foodId == sent.foodId &&
            current.deleted == sent.deleted;
        final unresolvedCreate = sent.serverId == null && !sent.deleted;
        // 旧库可能已用同键改过 payload。mismatch 不是「云端没创建」的证明：
        // 保留请求/用户意图，后续 pull 会按原键绑定 serverId 再继续。
        if (unresolvedCreate &&
            outcome is PushReject &&
            outcome.code == 'IDEMPOTENCY_PAYLOAD_MISMATCH' &&
            current.serverId == null) {
          await _markRetry(current, outcome.code);
          return false;
        }
        if (!sameGeneration) {
          if (unresolvedCreate &&
              outcome is PushRetryable &&
              current.serverId == null) {
            await _markRetry(current, outcome.code);
            return false;
          }
          if (unresolvedCreate &&
              outcome is PushReject &&
              current.serverId == null) {
            if (current.deleted) {
              await db.foodEntryDao.deleteEntry(localId);
              await _recompute(current.localDate);
              return false;
            }
            await db.foodEntryDao.updateEntry(
              localId,
              FoodEntriesCompanion(
                createRequestSnapshot: const Value(null),
                clientRequestId: Value(_uuid()),
                syncStatus: const Value(SyncStatus.pending),
                lastError: const Value(null),
              ),
            );
            return false;
          }
          if (unresolvedCreate &&
              outcome is PushConflict &&
              current.serverId == null) {
            await _markRetry(current, 'VERSION_CONFLICT');
            return false;
          }
          await _requeueChangedEntry(sent, current, outcome);
          return unresolvedCreate && outcome is PushAck;
        }
        switch (outcome) {
          case PushAck():
            if (current.deleted) {
              await db.foodEntryDao.deleteEntry(localId);
              await _recompute(current.localDate);
              break;
            }
            await db.foodEntryDao.updateEntry(
              localId,
              FoodEntriesCompanion(
                serverId: Value(outcome.serverId),
                serverVersion: Value(outcome.serverVersion),
                serverUpdatedAt: Value(outcome.serverUpdatedAtUtc),
                syncStatus: const Value(SyncStatus.synced),
                createRequestSnapshot: const Value(null),
                retryCount: const Value(0),
                lastError: const Value(null),
              ),
            );
          case PushRetryable():
            await _markRetry(current, outcome.code);
          case PushReject():
            if (current.deleted && outcome.code != 'NOT_FOUND') {
              await _markRetry(current, outcome.code);
              break;
            }
            await db.foodEntryDao.deleteEntry(localId);
            await _recompute(current.localDate);
            if (!current.deleted) {
              failure = RecordSyncFailure(localId: localId, code: outcome.code);
            }
          case PushConflict():
            await db.foodEntryDao.updateEntry(
              localId,
              FoodEntriesCompanion(
                syncStatus: Value(
                  current.deleted ? SyncStatus.pending : SyncStatus.conflicted,
                ),
                serverVersion: Value(outcome.serverVersion),
                serverUpdatedAt: Value(outcome.serverUpdatedAtUtc),
                lastError: const Value('VERSION_CONFLICT'),
              ),
            );
        }
        return false;
      });
      if (!_disposed && failure != null) _failures.add(failure!);
    }
  }

  Future<void> _markRetry(FoodEntry current, String code) {
    return db.foodEntryDao.updateEntry(
      current.localId,
      FoodEntriesCompanion(
        syncStatus: const Value(SyncStatus.pending),
        retryCount: Value(current.retryCount + 1),
        lastError: Value(code),
      ),
    );
  }

  Future<void> _requeueChangedEntry(
    FoodEntry sent,
    FoodEntry current,
    PushOutcome outcome,
  ) async {
    final requestId = current.clientRequestId == sent.clientRequestId
        ? _uuid()
        : current.clientRequestId;
    var companion = FoodEntriesCompanion(
      clientRequestId: Value(requestId),
      syncStatus: const Value(SyncStatus.pending),
      lastError: const Value(null),
    );
    switch (outcome) {
      case PushAck():
        companion = companion.copyWith(
          createRequestSnapshot: const Value(null),
          serverId: Value(outcome.serverId),
          serverVersion: Value(outcome.serverVersion),
          serverUpdatedAt: Value(outcome.serverUpdatedAtUtc),
        );
      case PushConflict():
        companion = companion.copyWith(
          serverVersion: Value(outcome.serverVersion),
          serverUpdatedAt: Value(outcome.serverUpdatedAtUtc),
        );
      case PushRetryable():
      case PushReject():
        break;
    }
    await db.foodEntryDao.updateEntry(current.localId, companion);
  }

  /// 重算该记录归属日的聚合缓存（份量修改/撤销/回滚后实时刷新）。
  Future<void> _recompute(String persistedLocalDate) {
    return db.foodEntryDao.recomputeDailyNutrition(
      userId,
      persistedLocalDate,
      updatedAtUtc: _clock().toUtc().toIso8601String(),
    );
  }

  /// 归属日 = 就餐 UTC 时间按设备时区换算的本地自然日（D-07）。
  String _localDateOf(DateTime utc) {
    final epochSec = utc.toUtc().millisecondsSinceEpoch ~/ 1000;
    return localDateOf(epochSec, location).toIsoString();
  }

  /// 归属日键（公开版 [_localDateOf]）：todayEntriesProvider 等查询侧的
  /// 「今日」口径。必须用本仓储的 [location] 换算，不能另用进程本地时区
  /// （`date.toLocal()`）——CI（TZ=UTC）16:00–24:00 时段北京已是次日，
  /// 写入侧（repo.location=Asia/Shanghai）与进程本地日期分叉，曾致
  /// 「今日记录」在 CI 查不到（v1.14.0 CI 红根因）。
  String localDateKeyOf(DateTime utc) => _localDateOf(utc);

  /// UUIDv4（幂等键/本地主键用，§1.2/§2.2）。
  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

final class _RecordSessionClosed extends StateError {
  _RecordSessionClosed() : super('记录会话已结束');
}
