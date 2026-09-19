import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'exercise_log_dao.g.dart';

/// ExerciseLog DAO（手动记运动：入账 / 今日列表 / 今日合计 / 删除）。
///
/// 纯本地口径：无同步字段，删除即物理删除（D-11 撤销与弹层删除同一语义）。
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

  /// 删除该条（物理删除），返回删除行数。
  Future<int> deleteLog(String localId) {
    return (delete(exerciseLogs)..where((e) => e.localId.equals(localId))).go();
  }

  /// 某日全部运动记录（按创建时间升序）。
  Future<List<ExerciseLog>> logsForDate(String userId, String localDate) {
    return (select(exerciseLogs)
          ..where(
            (e) => e.userId.equals(userId) & e.localDate.equals(localDate),
          )
          ..orderBy(<OrderingTerm Function(ExerciseLogs)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .get();
  }

  /// 某日运动消耗合计（kcal，无记录为 0）。
  Future<double> totalKcalForDate(String userId, String localDate) {
    final sum = exerciseLogs.kcal.sum();
    final query = selectOnly(exerciseLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        exerciseLogs.userId.equals(userId) &
            exerciseLogs.localDate.equals(localDate),
      );
    return query.map((row) => row.read(sum) ?? 0).getSingle();
  }

  /// 某日运动记录流（弹层今日列表实时刷新）。
  Stream<List<ExerciseLog>> watchLogsForDate(String userId, String localDate) {
    return (select(exerciseLogs)
          ..where(
            (e) => e.userId.equals(userId) & e.localDate.equals(localDate),
          )
          ..orderBy(<OrderingTerm Function(ExerciseLogs)>[
            (e) => OrderingTerm.asc(e.createdAtUtc),
          ]))
        .watch();
  }

  /// 某日运动消耗合计流（首页预算行 / 数据页消耗卡实时刷新）。
  Stream<double> watchTotalKcalForDate(String userId, String localDate) {
    final sum = exerciseLogs.kcal.sum();
    final query = selectOnly(exerciseLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        exerciseLogs.userId.equals(userId) &
            exerciseLogs.localDate.equals(localDate),
      );
    return query.map((row) => row.read(sum) ?? 0).watchSingle();
  }

  /// 某日步数合计流（数据页「步数」展示合并：系统步数 + 本合计；
  /// 无记录为 0）。
  Stream<int> watchTotalStepsForDate(String userId, String localDate) {
    final sum = exerciseLogs.steps.sum();
    final query = selectOnly(exerciseLogs)
      ..addColumns(<Expression<Object>>[sum])
      ..where(
        exerciseLogs.userId.equals(userId) &
            exerciseLogs.localDate.equals(localDate),
      );
    return query.map((row) => row.read(sum) ?? 0).watchSingle();
  }
}
