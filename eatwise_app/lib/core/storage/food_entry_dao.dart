import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'food_entry_dao.g.dart';

/// FoodEntry DAO（四态持久化 + DailyNutrition 聚合缓存）。
@DriftAccessor(tables: <Type>[FoodEntries, DailyNutritionCaches])
class FoodEntryDao extends DatabaseAccessor<AppDatabase>
    with _$FoodEntryDaoMixin {
  FoodEntryDao(super.db);

  /// 入账（乐观更新：UI 经流订阅立即可见）。
  Future<void> insertEntry(FoodEntriesCompanion entry) {
    return into(foodEntries).insert(entry);
  }

  /// 按本地主键取单条。
  Future<FoodEntry?> getByLocalId(String localId) {
    return (select(
      foodEntries,
    )..where((e) => e.localId.equals(localId))).getSingleOrNull();
  }

  /// 按服务端主键取单条（增量下行对账用，§2.4）。
  Future<FoodEntry?> getByServerId(String serverId) {
    return (select(
      foodEntries,
    )..where((e) => e.serverId.equals(serverId))).getSingleOrNull();
  }

  /// 按幂等键取单条（增量下行与本地待发记录对账用，§2.2/§2.4）。
  Future<FoodEntry?> getByClientRequestId(String clientRequestId) {
    return (select(foodEntries)
          ..where((e) => e.clientRequestId.equals(clientRequestId)))
        .getSingleOrNull();
  }

  /// 本地软删（tombstone）：服务端下行删除时置位（保留行供查询幂等）。
  Future<void> markDeleted(String localId) {
    return (update(foodEntries)..where((e) => e.localId.equals(localId))).write(
      const FoodEntriesCompanion(deleted: Value(true)),
    );
  }

  /// 更新单条（份量/快照/同步字段等）。
  Future<void> updateEntry(String localId, FoodEntriesCompanion entry) {
    return (update(
      foodEntries,
    )..where((e) => e.localId.equals(localId))).write(entry);
  }

  /// 级联改写食物引用（离线自定义食物上行后 id 重映射用：
  /// 指向旧本地 id 的记录统一改指服务端 id）。
  Future<void> remapFoodId(String oldFoodId, String newFoodId) {
    return (update(foodEntries)..where((e) => e.foodId.equals(oldFoodId)))
        .write(FoodEntriesCompanion(foodId: Value(newFoodId)));
  }

  /// 登录换挂（审计#1 匿名数据迁移）：把 [fromUserId] 名下全部记录
  /// （含 synced / tombstone——它们本就属于真实用户，只是归属标记）改挂
  /// [toUserId]。serverId 同值冲突理论不存在：匿名期服务端无该用户记录，
  /// 下行行不会与匿名行同属双方。返回换挂行数。
  Future<int> reassignUser(String fromUserId, String toUserId) {
    return (update(foodEntries)..where((e) => e.userId.equals(fromUserId)))
        .write(FoodEntriesCompanion(userId: Value(toUserId)));
  }

  /// 清空 [userId] 名下聚合缓存（匿名记录换挂后调用：缓存行随记录换主
  /// 成为孤儿，防退回匿名登录后旧缓存假显；真实用户的缓存由回填修复/
  /// 入账重算补建）。
  Future<int> deleteUserDailyCaches(String userId) {
    return (delete(
      dailyNutritionCaches,
    )..where((c) => c.userId.equals(userId))).go();
  }

  /// 物理删除（D-11 撤销窗内撤回 / T7 校验拒绝回滚，此时上行未成功，
  /// 云端无此记录，无需 tombstone）。
  Future<void> deleteEntry(String localId) {
    return (delete(foodEntries)..where((e) => e.localId.equals(localId))).go();
  }

  /// 用户删除：软删为 tombstone（已上行行的删除须以 delete op 上行，
  /// 服务端软删后下行同步到其他设备；未上行的撤销走 [deleteEntry]）。
  Future<void> tombstoneEntry(String localId, String updatedAtUtc) {
    return (update(foodEntries)..where((e) => e.localId.equals(localId))).write(
      FoodEntriesCompanion(
        deleted: const Value(true),
        updatedAtUtc: Value(updatedAtUtc),
      ),
    );
  }

  /// 已软删、已上行（持 serverId）待 delete op 上行的行（同 [pendingEntries]
  /// 供 retryPending 扫尾；delete ack 后物理清除）。
  Future<List<FoodEntry>> deletePendingEntries(String userId) {
    return (select(foodEntries)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.deleted.equals(true) &
                e.serverId.isNotNull(),
          )
          ..orderBy(<OrderingTerm Function(FoodEntries)>[
            (e) => OrderingTerm.asc(e.updatedAtUtc),
          ]))
        .get();
  }

  /// 指定用户全部待上行记录（重试用，按创建时间升序，§2.3 批内顺序）。
  Future<List<FoodEntry>> pendingEntries(String userId) {
    return (select(foodEntries)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.syncStatus.equalsValue(SyncStatus.pending) &
                e.deleted.equals(false),
          )
          ..orderBy(<OrderingTerm Function(FoodEntries)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .get();
  }

  /// 「待同步 N 条」计数流（§4.1：pending + submitting + conflicted > 0 时
  /// 展示入口；删除窗内的新增同样计入）。
  Stream<int> watchPendingCount(String userId) {
    final count = foodEntries.localId.count();
    final query = selectOnly(foodEntries)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        foodEntries.userId.equals(userId) &
            foodEntries.deleted.equals(false) &
            foodEntries.syncStatus.equalsValue(SyncStatus.synced).not(),
      );
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// 某日有效记录（聚合与记录列表用，排除 tombstone）。
  Future<List<FoodEntry>> entriesForDate(String userId, String localDate) {
    return (select(foodEntries)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.localDate.equals(localDate) &
                e.deleted.equals(false),
          )
          ..orderBy(<OrderingTerm Function(FoodEntries)>[
            (e) => OrderingTerm.asc(e.datetimeUtc),
          ]))
        .get();
  }

  /// 指定食物的全部有效记录（候选驳回联动清理用，排除 tombstone）。
  Future<List<FoodEntry>> entriesForFood(String userId, String foodId) {
    return (select(foodEntries)..where(
          (e) =>
              e.userId.equals(userId) &
              e.foodId.equals(foodId) &
              e.deleted.equals(false),
        ))
        .get();
  }

  /// 某日有效记录流（薄荷走查优化点 2：记录页「今日记录」餐次分组列表，
  /// 排除 tombstone，按就餐时间升序）。
  Stream<List<FoodEntry>> watchEntriesForDate(String userId, String localDate) {
    return (select(foodEntries)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.localDate.equals(localDate) &
                e.deleted.equals(false),
          )
          ..orderBy(<OrderingTerm Function(FoodEntries)>[
            (e) => OrderingTerm.asc(e.datetimeUtc),
          ]))
        .watch();
  }

  /// 某日「断食期用餐」记录条数流（阶段 C：记录页今日聚合行标记用，
  /// 排除 tombstone）。
  Stream<int> watchDuringFastCount(String userId, String localDate) {
    final count = foodEntries.localId.count();
    final query = selectOnly(foodEntries)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        foodEntries.userId.equals(userId) &
            foodEntries.localDate.equals(localDate) &
            foodEntries.deleted.equals(false) &
            foodEntries.duringFast.equals(true),
      );
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// 有饮食记录的归属日集合（去重升序，排除 tombstone；聚合缓存回填
  /// 扫描用——v1.12.5 走查：旧版本下行遗留记录不经重算，须主动扫描）。
  /// [fromDate] 非空时只返回不早于该日的日期（近 N 天廉价窗口）。
  Future<List<String>> datesWithEntries(String userId, {String? fromDate}) {
    final query = selectOnly(foodEntries, distinct: true)
      ..addColumns(<Expression<Object>>[foodEntries.localDate])
      ..where(
        foodEntries.userId.equals(userId) &
            foodEntries.deleted.equals(false) &
            (fromDate == null
                ? const Constant(true)
                : foodEntries.localDate.isBiggerOrEqualValue(fromDate)),
      )
      ..orderBy(<OrderingTerm>[OrderingTerm.asc(foodEntries.localDate)]);
    return query.map((row) => row.read(foodEntries.localDate)!).get();
  }

  /// 某日记录的最新本地修改时间（UTC ISO8601；缓存过期判定用——
  /// entries 比 cache 新即过期。无记录返回 null）。
  Future<String?> maxEntryUpdatedAt(String userId, String localDate) {
    final latest = foodEntries.updatedAtUtc.max();
    final query = selectOnly(foodEntries)
      ..addColumns(<Expression<Object>>[latest])
      ..where(
        foodEntries.userId.equals(userId) &
            foodEntries.localDate.equals(localDate) &
            foodEntries.deleted.equals(false),
      );
    return query.map((row) => row.read(latest)).getSingle();
  }

  /// 从 FoodEntry 营养快照重算某日聚合并写入缓存（§2.6 本地预估）。
  Future<void> recomputeDailyNutrition(
    String userId,
    String localDate, {
    required String updatedAtUtc,
  }) async {
    final kcalSum = foodEntries.kcal.sum();
    final proteinSum = foodEntries.proteinG.sum();
    final carbSum = foodEntries.carbG.sum();
    final fatSum = foodEntries.fatG.sum();
    final entryCount = foodEntries.localId.count();
    final query = selectOnly(foodEntries)
      ..addColumns(<Expression<Object>>[
        kcalSum,
        proteinSum,
        carbSum,
        fatSum,
        entryCount,
      ])
      ..where(
        foodEntries.userId.equals(userId) &
            foodEntries.localDate.equals(localDate) &
            foodEntries.deleted.equals(false),
      );
    final row = await query.getSingle();
    await into(dailyNutritionCaches).insertOnConflictUpdate(
      DailyNutritionCachesCompanion(
        userId: Value(userId),
        date: Value(localDate),
        entryCount: Value(row.read(entryCount) ?? 0),
        kcal: Value(row.read(kcalSum) ?? 0),
        proteinG: Value(row.read(proteinSum) ?? 0),
        carbG: Value(row.read(carbSum) ?? 0),
        fatG: Value(row.read(fatSum) ?? 0),
        isLocalEstimate: const Value(true),
        updatedAtUtc: Value(updatedAtUtc),
      ),
    );
  }

  /// 某日聚合缓存流（记录页展示「本地预估」用）。
  Stream<DailyNutritionCache?> watchDailyNutrition(
    String userId,
    String localDate,
  ) {
    return (select(dailyNutritionCaches)
          ..where((c) => c.userId.equals(userId) & c.date.equals(localDate)))
        .watchSingleOrNull();
  }

  /// 取某日聚合缓存（一次性读取）。
  Future<DailyNutritionCache?> getDailyNutrition(
    String userId,
    String localDate,
  ) {
    return (select(dailyNutritionCaches)
          ..where((c) => c.userId.equals(userId) & c.date.equals(localDate)))
        .getSingleOrNull();
  }

  /// 日期区间聚合缓存流（M4 数据页近 7 日趋势用；含端点，按日期升序）。
  Stream<List<DailyNutritionCache>> watchDailyNutritionRange(
    String userId,
    String fromDate,
    String toDate,
  ) {
    return (select(dailyNutritionCaches)
          ..where(
            (c) =>
                c.userId.equals(userId) &
                c.date.isBetweenValues(fromDate, toDate),
          )
          ..orderBy(<OrderingTerm Function(DailyNutritionCaches)>[
            (c) => OrderingTerm.asc(c.date),
          ]))
        .watch();
  }
}
