import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'exercise_log_dao.g.dart';

/// ExerciseLog DAO（手动记运动：入账 / 今日列表 / 今日合计 / 删除 +
/// 两态同步：pending 队列查询、上行回填、tombstone）。
///
/// 聚合口径（与 WaterLogDao 一致）：本地 tombstone（deleted=true，待上行
/// delete op）不计入当日列表与合计，与「撤销即时生效」UI 语义一致。
@DriftAccessor(tables: <Type>[ExerciseLogs])
class ExerciseLogDao extends DatabaseAccessor<AppDatabase>
    with _$ExerciseLogDaoMixin {
  ExerciseLogDao(super.db);

  /// 入账（UI 经 [watchLogsForDate] / [watchTotalKcalForDate] 流立即可见）。
  Future<void> insertLog(ExerciseLogsCompanion log) {
    return into(exerciseLogs).insert(log);
  }

  /// 按本地主键取单条。
  Future<ExerciseLog?> getByLocalId(String localId) {
    return (select(
      exerciseLogs,
    )..where((e) => e.localId.equals(localId))).getSingleOrNull();
  }

  /// 按幂等键取单条（下行对账本机待发记录）。
  Future<ExerciseLog?> getByClientRequestId(String clientRequestId) {
    return (select(exerciseLogs)
          ..where((e) => e.clientRequestId.equals(clientRequestId)))
        .getSingleOrNull();
  }

  /// 按服务端主键取单条（多端/重装下行对账）。
  Future<ExerciseLog?> getByServerId(String serverId) {
    return (select(
      exerciseLogs,
    )..where((e) => e.serverId.equals(serverId))).getSingleOrNull();
  }

  /// 删除该条（物理删除：从未上行的撤销/删除），返回删除行数。
  Future<int> deleteLog(String localId) {
    return (delete(exerciseLogs)..where((e) => e.localId.equals(localId))).go();
  }

  /// 已上行记录的删除：置 tombstone（deleted=true 并回到 pending 待上行
  /// delete op），聚合查询即时排除。
  Future<void> markTombstone(String localId) {
    return (update(
      exerciseLogs,
    )..where((e) => e.localId.equals(localId))).write(
      const ExerciseLogsCompanion(
        deleted: Value(true),
        syncState: Value(ExerciseSyncState.pending),
      ),
    );
  }

  /// 待上行队列（含 tombstone；同步引擎批量 push 数据源）。
  Future<List<ExerciseLog>> pendingForUser(String userId) {
    return (select(exerciseLogs)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.syncState.equalsValue(ExerciseSyncState.pending),
          )
          ..orderBy(<OrderingTerm Function(ExerciseLogs)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .get();
  }

  /// 上行 create 成功回填：serverId + synced。
  Future<void> markSynced(String localId, String serverId) {
    return (update(
      exerciseLogs,
    )..where((e) => e.localId.equals(localId))).write(
      ExerciseLogsCompanion(
        serverId: Value(serverId),
        syncState: const Value(ExerciseSyncState.synced),
      ),
    );
  }

  /// 下行覆盖（多端/重装）：本地行已同步则整行替换服务端值。
  Future<void> applyServerRow(String localId, ExerciseLogsCompanion row) {
    return (update(
      exerciseLogs,
    )..where((e) => e.localId.equals(localId))).write(row);
  }

  /// 某日全部运动记录（按创建时间升序，排除 tombstone）。
  Future<List<ExerciseLog>> logsForDate(String userId, String localDate) {
    return (select(exerciseLogs)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.localDate.equals(localDate) &
                e.deleted.equals(false),
          )
          ..orderBy(<OrderingTerm Function(ExerciseLogs)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .get();
  }

  /// 某日运动消耗合计（kcal，无记录为 0，排除 tombstone）。
  Future<double> totalKcalForDate(String userId, String localDate) {
    final sum = exerciseLogs.kcal.sum();
    final query = selectOnly(exerciseLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        exerciseLogs.userId.equals(userId) &
            exerciseLogs.localDate.equals(localDate) &
            exerciseLogs.deleted.equals(false),
      );
    return query.map((row) => row.read(sum) ?? 0).getSingle();
  }

  /// 某日运动记录流（弹层今日列表实时刷新，排除 tombstone）。
  Stream<List<ExerciseLog>> watchLogsForDate(String userId, String localDate) {
    return (select(exerciseLogs)
          ..where(
            (e) =>
                e.userId.equals(userId) &
                e.localDate.equals(localDate) &
                e.deleted.equals(false),
          )
          ..orderBy(<OrderingTerm Function(ExerciseLogs)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .watch();
  }

  /// 某日运动消耗合计流（首页预算行 / 数据页消耗卡实时刷新，排除 tombstone）。
  Stream<double> watchTotalKcalForDate(String userId, String localDate) {
    final sum = exerciseLogs.kcal.sum();
    final query = selectOnly(exerciseLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        exerciseLogs.userId.equals(userId) &
            exerciseLogs.localDate.equals(localDate) &
            exerciseLogs.deleted.equals(false),
      );
    return query.map((row) => row.read(sum) ?? 0).watchSingle();
  }

  /// 某日步数合计流（数据页「步数」展示合并：系统步数 + 本合计；
  /// 无记录为 0，排除 tombstone）。
  Stream<int> watchTotalStepsForDate(String userId, String localDate) {
    final sum = exerciseLogs.steps.sum();
    final query = selectOnly(exerciseLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        exerciseLogs.userId.equals(userId) &
            exerciseLogs.localDate.equals(localDate) &
            exerciseLogs.deleted.equals(false),
      );
    return query.map((row) => row.read(sum) ?? 0).watchSingle();
  }
}
