import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'fasting_record_dao.g.dart';

/// FastingRecord DAO（M5：断食历史落库，streak 结算与 M6 趋势数据源）。
@DriftAccessor(tables: <Type>[FastingRecords])
class FastingRecordDao extends DatabaseAccessor<AppDatabase>
    with _$FastingRecordDaoMixin {
  FastingRecordDao(super.db);

  /// 幂等入账：localId = `userId-attributionDate`，同归属日重复关闭不重复写入
  /// （对应状态机幂等要求：同一归属日达标事件不重复 +1）。
  Future<void> upsertRecord(FastingRecordsCompanion record) {
    return into(fastingRecords).insertOnConflictUpdate(record);
  }

  /// 按幂等键取单条（上行重试对账用）。
  Future<FastingRecord?> getByClientRequestId(String clientRequestId) {
    return (select(fastingRecords)
          ..where((r) => r.clientRequestId.equals(clientRequestId)))
        .getSingleOrNull();
  }

  /// 登录换挂（审计#1 匿名数据迁移）：userId 与 localId
  /// （= `userId-attributionDate`，主键）随归属一并改写。
  /// UPDATE OR IGNORE：若 uid 名下已存在同归属日记录撞主键则跳过该行
  /// （理论不存在——匿名期服务端无该用户数据，下行也不会把真实 uid 的
  /// 断食记录带进匿名命名空间），残留的 anonymous 行随后删除（同日以
  /// uid 侧为准）。返回换挂行数。
  Future<int> reassignUser(String fromUserId, String toUserId) async {
    final moved = await customUpdate(
      'UPDATE OR IGNORE fasting_records '
      "SET user_id = ?, local_id = ? || '-' || attribution_date "
      'WHERE user_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(toUserId),
        Variable<String>(toUserId),
        Variable<String>(fromUserId),
      ],
      updates: <ResultSetImplementation<Object?, Object?>>{fastingRecords},
    );
    await (delete(
      fastingRecords,
    )..where((r) => r.userId.equals(fromUserId))).go();
    return moved;
  }

  /// 指定用户的全部达标归属日（含已补签），streak 本地推演数据源。
  Future<Set<String>> qualifiedDates(String userId) async {
    final rows =
        await (selectOnly(fastingRecords)
              ..addColumns(<Expression<Object>>[fastingRecords.attributionDate])
              ..where(
                fastingRecords.userId.equals(userId) &
                    fastingRecords.qualified.equals(true),
              ))
            .get();
    return rows.map((r) => r.read(fastingRecords.attributionDate)!).toSet();
  }

  /// 指定用户的断食历史（按归属日升序；M6 趋势用）。
  Future<List<FastingRecord>> recordsOf(String userId) {
    return (select(fastingRecords)
          ..where((r) => r.userId.equals(userId))
          ..orderBy(<OrderingTerm Function(FastingRecords)>[
            (r) => OrderingTerm.asc(r.attributionDate),
          ]))
        .get();
  }

  /// 更新同步状态（F2 上行成功/失败回写）。
  Future<void> updateSyncStatus(String localId, SyncStatus status) {
    return (update(fastingRecords)..where((r) => r.localId.equals(localId)))
        .write(FastingRecordsCompanion(syncStatus: Value(status)));
  }

  /// 按服务端主键取单条（/sync 下行 tombstone 对账）。
  Future<FastingRecord?> getByServerId(String serverId) {
    return (select(
      fastingRecords,
    )..where((r) => r.serverId.equals(serverId))).getSingleOrNull();
  }

  /// 按本地主键取单条（/sync 下行按归属日对账：localId=userId-attributionDate）。
  Future<FastingRecord?> getByLocalId(String localId) {
    return (select(
      fastingRecords,
    )..where((r) => r.localId.equals(localId))).getSingleOrNull();
  }

  /// 待上行队列（/sync fastingRecord 通道：pending 含 tombstone；
  /// 同步引擎批量 push 数据源，口径同 WaterLogDao.pendingForUser）。
  Future<List<FastingRecord>> pendingForUser(String userId) {
    return (select(fastingRecords)
          ..where(
            (r) =>
                r.userId.equals(userId) &
                r.syncStatus.equalsValue(SyncStatus.pending),
          )
          ..orderBy(<OrderingTerm Function(FastingRecords)>[
            (r) => OrderingTerm.asc(r.attributionDate),
          ]))
        .get();
  }

  /// /sync 上行 create 成功回填：serverId + synced。
  Future<void> markSynced(String localId, String serverId) {
    return (update(
      fastingRecords,
    )..where((r) => r.localId.equals(localId))).write(
      FastingRecordsCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.synced),
      ),
    );
  }

  /// 下行对账回填 serverId（本地行内容「本机为准」不覆盖，仅补主键映射）。
  Future<void> fillServerId(String localId, String serverId) {
    return (update(fastingRecords)..where((r) => r.localId.equals(localId)))
        .write(FastingRecordsCompanion(serverId: Value(serverId)));
  }

  /// 物理删除（tombstone 上行 ack/NOT_FOUND 后清理；下行 tombstone 应用）。
  Future<int> deleteRecord(String localId) {
    return (delete(
      fastingRecords,
    )..where((r) => r.localId.equals(localId))).go();
  }
}
