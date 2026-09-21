import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'water_log_dao.g.dart';

/// WaterLog DAO（PRD M3 饮水轻量记录：入账 / 当日累计 / D-11 撤销 +
/// 两态同步：pending 队列查询、上行回填、tombstone）。
///
/// 聚合口径：本地 tombstone（deleted=true，待上行 delete op）不计入
/// 当日累计与列表，与「撤销即时生效」UI 语义一致。
@DriftAccessor(tables: <Type>[WaterLogs])
class WaterLogDao extends DatabaseAccessor<AppDatabase>
    with _$WaterLogDaoMixin {
  WaterLogDao(super.db);

  /// 入账（UI 经 [watchTotalForDate] 流立即可见，乐观更新）。
  Future<void> insertLog(WaterLogsCompanion log) {
    return into(waterLogs).insert(log);
  }

  /// 登录换挂（审计#1 匿名数据迁移）：把 [fromUserId] 名下全部记录
  /// （含 synced / tombstone）改挂 [toUserId]。返回换挂行数。
  Future<int> reassignUser(String fromUserId, String toUserId) {
    return (update(waterLogs)..where((e) => e.userId.equals(fromUserId))).write(
      WaterLogsCompanion(userId: Value(toUserId)),
    );
  }

  /// 按本地主键取单条。
  Future<WaterLog?> getByLocalId(String localId) {
    return (select(
      waterLogs,
    )..where((e) => e.localId.equals(localId))).getSingleOrNull();
  }

  /// 按幂等键取单条（下行对账本机待发记录）。
  Future<WaterLog?> getByClientRequestId(String clientRequestId) {
    return (select(waterLogs)
          ..where((e) => e.clientRequestId.equals(clientRequestId)))
        .getSingleOrNull();
  }

  /// 按服务端主键取单条（多端/重装下行对账）。
  Future<WaterLog?> getByServerId(String serverId) {
    return (select(
      waterLogs,
    )..where((e) => e.serverId.equals(serverId))).getSingleOrNull();
  }

  /// D-11 撤销窗内撤回该条（从未上行的记录物理删除），返回删除行数。
  Future<int> deleteLog(String localId) {
    return (delete(waterLogs)..where((e) => e.localId.equals(localId))).go();
  }

  /// 已上行记录的撤销：置 tombstone（deleted=true 并回到 pending 待上行
  /// delete op），聚合查询即时排除。
  Future<void> markTombstone(String localId) {
    return (update(waterLogs)..where((e) => e.localId.equals(localId))).write(
      const WaterLogsCompanion(
        deleted: Value(true),
        syncState: Value(WaterSyncState.pending),
      ),
    );
  }

  /// 待上行队列（含 tombstone；同步引擎批量 push 数据源）。
  Future<List<WaterLog>> pendingForUser(String userId) {
    return (select(waterLogs)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.syncState.equalsValue(WaterSyncState.pending),
          )
          ..orderBy(<OrderingTerm Function(WaterLogs)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .get();
  }

  /// 上行 create 成功回填：serverId + synced。
  Future<void> markSynced(String localId, String serverId) {
    return (update(waterLogs)..where((e) => e.localId.equals(localId))).write(
      WaterLogsCompanion(
        serverId: Value(serverId),
        syncState: const Value(WaterSyncState.synced),
      ),
    );
  }

  /// 下行覆盖（多端/重装）：本地行已同步则整行替换服务端值。
  Future<void> applyServerRow(String localId, WaterLogsCompanion row) {
    return (update(
      waterLogs,
    )..where((e) => e.localId.equals(localId))).write(row);
  }

  /// 某日全部饮水记录（按时间升序，排除 tombstone）。
  Future<List<WaterLog>> logsForDate(String userId, String localDate) {
    return (select(waterLogs)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.localDate.equals(localDate) &
                e.deleted.equals(false),
          )
          ..orderBy(<OrderingTerm Function(WaterLogs)>[
            (e) => OrderingTerm.asc(e.datetimeUtc),
          ]))
        .get();
  }

  /// 某日累计饮水量（毫升，无记录为 0，排除 tombstone）。
  Future<int> totalForDate(String userId, String localDate) {
    final sum = waterLogs.amountMl.sum();
    final query = selectOnly(waterLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        waterLogs.userId.equals(userId) &
            waterLogs.localDate.equals(localDate) &
            waterLogs.deleted.equals(false),
      );
    return query.map((row) => row.read(sum) ?? 0).getSingle();
  }

  /// 某日累计饮水量流（记录页轻量区实时刷新，排除 tombstone）。
  Stream<int> watchTotalForDate(String userId, String localDate) {
    final sum = waterLogs.amountMl.sum();
    final query = selectOnly(waterLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        waterLogs.userId.equals(userId) &
            waterLogs.localDate.equals(localDate) &
            waterLogs.deleted.equals(false),
      );
    return query.map((row) => row.read(sum) ?? 0).watchSingle();
  }
}
