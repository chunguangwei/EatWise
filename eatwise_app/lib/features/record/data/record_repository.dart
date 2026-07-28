import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';

import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
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
    required this.location,
    this.undoWindow = const Duration(seconds: 10),
    DateTime Function()? clock,
    this.userId = 'anonymous',
  }) : _clock = clock ?? DateTime.now;

  /// 本地数据库。
  final AppDatabase db;

  /// 同步远程端。
  final RecordRemote remote;

  /// 设备时区（归属日换算，D-07）。
  final tz.Location location;
  final DateTime Function() _clock;
  final Random _random = Random();

  /// D-11 撤销窗时长（默认 10 秒；测试可注入更短值）。
  final Duration undoWindow;

  /// 归属用户（未登录 anonymous，T18）。
  final String userId;

  final Map<String, Timer> _pushTimers = <String, Timer>{};
  final Map<String, DateTime> _undoDeadlines = <String, DateTime>{};
  final StreamController<RecordSyncFailure> _failures =
      StreamController<RecordSyncFailure>.broadcast();

  /// T7 回滚事件流。
  Stream<RecordSyncFailure> get failures => _failures.stream;

  /// 乐观更新入账（T1/T2）：先写本地库（UI 经流立即展示），
  /// 在线 → submitting 并启动撤销窗，窗结束上行；离线 → pending。
  Future<FoodEntry> addEntry(RecordDraft draft) async {
    if (draft.amountG <= 0) {
      throw ArgumentError.value(draft.amountG, 'amountG', '份量必须大于 0');
    }
    final food = await db.foodDao.getById(draft.foodId);
    if (food == null) {
      throw ArgumentError.value(draft.foodId, 'foodId', '食物不存在于食物库');
    }
    final snapshot = NutritionSnapshot.forAmount(food, draft.amountG);
    final nowUtc = _clock().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final localId = _uuid();
    final online = remote.isOnline;
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
      localDate: Value(_localDateOf(draft.mealUtc)),
      foodId: Value(draft.foodId),
      amountG: Value(draft.amountG),
      kcal: Value(snapshot.kcal),
      proteinG: Value(snapshot.proteinG),
      carbG: Value(snapshot.carbG),
      fatG: Value(snapshot.fatG),
      source: Value(draft.source),
      note: Value(draft.note),
      createdAtUtc: Value(nowIso),
      updatedAtUtc: Value(nowIso),
    );
    await db.foodEntryDao.insertEntry(entry);
    if (online) {
      _schedulePush(localId, undoable: true);
    } else {
      // 离线也允许撤销（T2：纯本地回滚），仅记录撤销截止时刻。
      _undoDeadlines[localId] = nowUtc.add(undoWindow);
    }
    await _recompute(draft.mealUtc);
    return (await db.foodEntryDao.getByLocalId(localId))!;
  }

  /// D-11 撤销：撤销窗内撤回该条（T3，乐观更新回滚，本地删除）。
  /// 返回是否撤销成功；窗口已过或记录不存在 → false。
  Future<bool> undo(String localId) async {
    final deadline = _undoDeadlines[localId];
    if (deadline == null || !_clock().toUtc().isBefore(deadline)) {
      return false;
    }
    final entry = await db.foodEntryDao.getByLocalId(localId);
    if (entry == null) return false;
    _cancelPush(localId);
    await db.foodEntryDao.deleteEntry(localId);
    await _recompute(DateTime.parse(entry.datetimeUtc));
    return true;
  }

  /// 份量修改实时重算营养（US-3.1）：快照随份量重算，localVersion+1。
  /// synced 记录被编辑 → 重新生成 clientRequestId 并转 submitting 待上行
  /// （T9）；pending/submitting 原位修改保留状态（T10）。
  Future<FoodEntry> updateAmount(String localId, double amountG) async {
    if (amountG <= 0) {
      throw ArgumentError.value(amountG, 'amountG', '份量必须大于 0');
    }
    final entry = await db.foodEntryDao.getByLocalId(localId);
    if (entry == null) {
      throw ArgumentError.value(localId, 'localId', '记录不存在');
    }
    final food = await db.foodDao.getById(entry.foodId);
    if (food == null) {
      throw StateError('记录引用的食物不存在: ${entry.foodId}');
    }
    final snapshot = NutritionSnapshot.forAmount(food, amountG);
    final nowIso = _clock().toUtc().toIso8601String();
    final wasSynced = entry.syncStatus == SyncStatus.synced;
    await db.foodEntryDao.updateEntry(
      localId,
      FoodEntriesCompanion(
        amountG: Value(amountG),
        kcal: Value(snapshot.kcal),
        proteinG: Value(snapshot.proteinG),
        carbG: Value(snapshot.carbG),
        fatG: Value(snapshot.fatG),
        localVersion: Value(entry.localVersion + 1),
        clientRequestId: Value(wasSynced ? _uuid() : entry.clientRequestId),
        syncStatus: Value(wasSynced ? SyncStatus.submitting : entry.syncStatus),
        updatedAtUtc: Value(nowIso),
      ),
    );
    if (wasSynced) {
      _schedulePush(localId, undoable: false);
    }
    await _recompute(DateTime.parse(entry.datetimeUtc));
    return (await db.foodEntryDao.getByLocalId(localId))!;
  }

  /// 撤销窗到期后的上行入口（公开以便「立即重试」与测试驱动窗口结束）。
  Future<void> flushEntry(String localId) async {
    _cancelPush(localId);
    await _push(localId);
  }

  /// 批量上行全部 pending（T8：网络恢复 / 手动「立即重试」）。
  /// 返回本次尝试上行的条数。
  Future<int> retryPending() async {
    final pendings = await db.foodEntryDao.pendingEntries(userId);
    for (final entry in pendings) {
      await _push(entry.localId);
    }
    return pendings.length;
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
    return db.foodDao.searchFoods(query, limit: limit);
  }

  /// 释放资源：取消全部待发上行与事件流。
  Future<void> dispose() async {
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

  /// 上行单条并按结果迁移四态（T4/T5/T6/T7）。
  Future<void> _push(String localId) async {
    final entry = await db.foodEntryDao.getByLocalId(localId);
    if (entry == null || entry.deleted) return;
    if (entry.syncStatus == SyncStatus.synced) return;
    final outcome = await remote.push(entry);
    switch (outcome) {
      case PushAck():
        await db.foodEntryDao.updateEntry(
          localId,
          FoodEntriesCompanion(
            serverId: Value(outcome.serverId),
            serverVersion: Value(outcome.serverVersion),
            serverUpdatedAt: Value(outcome.serverUpdatedAtUtc),
            syncStatus: const Value(SyncStatus.synced),
            retryCount: const Value(0),
            lastError: const Value(null),
          ),
        );
      case PushRetryable():
        await db.foodEntryDao.updateEntry(
          localId,
          FoodEntriesCompanion(
            syncStatus: const Value(SyncStatus.pending),
            retryCount: Value(entry.retryCount + 1),
            lastError: Value(outcome.code),
          ),
        );
      case PushReject():
        // T7：4xx 校验拒绝 → 回滚乐观更新（本地删除），提示用户重新提交。
        await db.foodEntryDao.deleteEntry(localId);
        await _recompute(DateTime.parse(entry.datetimeUtc));
        _failures.add(RecordSyncFailure(localId: localId, code: outcome.code));
      case PushConflict():
        // T6/T11：409 且自动合并未覆盖 → conflicted 入冲突队列。
        await db.foodEntryDao.updateEntry(
          localId,
          FoodEntriesCompanion(
            syncStatus: const Value(SyncStatus.conflicted),
            lastError: const Value('VERSION_CONFLICT'),
          ),
        );
    }
  }

  /// 重算该记录归属日的聚合缓存（份量修改/撤销/回滚后实时刷新）。
  Future<void> _recompute(DateTime mealUtc) {
    return db.foodEntryDao.recomputeDailyNutrition(
      userId,
      _localDateOf(mealUtc),
      updatedAtUtc: _clock().toUtc().toIso8601String(),
    );
  }

  /// 归属日 = 就餐 UTC 时间按设备时区换算的本地自然日（D-07）。
  String _localDateOf(DateTime utc) {
    final epochSec = utc.toUtc().millisecondsSinceEpoch ~/ 1000;
    return localDateOf(epochSec, location).toIsoString();
  }

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
