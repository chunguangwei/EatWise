// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise_log_dao.dart';

// ignore_for_file: type=lint
mixin _$ExerciseLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $ExerciseLogsTable get exerciseLogs => attachedDatabase.exerciseLogs;
  ExerciseLogDaoManager get managers => ExerciseLogDaoManager(this);
}

class ExerciseLogDaoManager {
  final _$ExerciseLogDaoMixin _db;
  ExerciseLogDaoManager(this._db);
  $$ExerciseLogsTableTableManager get exerciseLogs =>
      $$ExerciseLogsTableTableManager(_db.attachedDatabase, _db.exerciseLogs);
}
