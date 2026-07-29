// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'water_log_dao.dart';

// ignore_for_file: type=lint
mixin _$WaterLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $WaterLogsTable get waterLogs => attachedDatabase.waterLogs;
  WaterLogDaoManager get managers => WaterLogDaoManager(this);
}

class WaterLogDaoManager {
  final _$WaterLogDaoMixin _db;
  WaterLogDaoManager(this._db);
  $$WaterLogsTableTableManager get waterLogs =>
      $$WaterLogsTableTableManager(_db.attachedDatabase, _db.waterLogs);
}
