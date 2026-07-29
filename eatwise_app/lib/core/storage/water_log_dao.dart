import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'water_log_dao.g.dart';

/// WaterLog DAO（PRD M3 饮水轻量记录：入账 / 当日累计 / D-11 撤销）。
@DriftAccessor(tables: <Type>[WaterLogs])
class WaterLogDao extends DatabaseAccessor<AppDatabase>
    with _$WaterLogDaoMixin {
  WaterLogDao(super.db);

  /// 入账（UI 经 [watchTotalForDate] 流立即可见，乐观更新）。
  Future<void> insertLog(WaterLogsCompanion log) {
    return into(waterLogs).insert(log);
  }

  /// 按本地主键取单条。
  Future<WaterLog?> getByLocalId(String localId) {
    return (select(
      waterLogs,
    )..where((e) => e.localId.equals(localId))).getSingleOrNull();
  }

  /// D-11 撤销窗内撤回该条（纯本地记录，物理删除），返回删除行数。
  Future<int> deleteLog(String localId) {
    return (delete(waterLogs)..where((e) => e.localId.equals(localId))).go();
  }

  /// 某日全部饮水记录（按时间升序）。
  Future<List<WaterLog>> logsForDate(String userId, String localDate) {
    return (select(waterLogs)
          ..where(
            (e) => e.userId.equals(userId) & e.localDate.equals(localDate),
          )
          ..orderBy(<OrderingTerm Function(WaterLogs)>[
            (e) => OrderingTerm.asc(e.datetimeUtc),
          ]))
        .get();
  }

  /// 某日累计饮水量（毫升，无记录为 0）。
  Future<int> totalForDate(String userId, String localDate) {
    final sum = waterLogs.amountMl.sum();
    final query = selectOnly(waterLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        waterLogs.userId.equals(userId) & waterLogs.localDate.equals(localDate),
      );
    return query.map((row) => row.read(sum) ?? 0).getSingle();
  }

  /// 某日累计饮水量流（记录页轻量区实时刷新）。
  Stream<int> watchTotalForDate(String userId, String localDate) {
    final sum = waterLogs.amountMl.sum();
    final query = selectOnly(waterLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        waterLogs.userId.equals(userId) & waterLogs.localDate.equals(localDate),
      );
    return query.map((row) => row.read(sum) ?? 0).watchSingle();
  }
}
