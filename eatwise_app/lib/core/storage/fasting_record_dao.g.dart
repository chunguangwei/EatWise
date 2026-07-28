// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fasting_record_dao.dart';

// ignore_for_file: type=lint
mixin _$FastingRecordDaoMixin on DatabaseAccessor<AppDatabase> {
  $FastingRecordsTable get fastingRecords => attachedDatabase.fastingRecords;
  FastingRecordDaoManager get managers => FastingRecordDaoManager(this);
}

class FastingRecordDaoManager {
  final _$FastingRecordDaoMixin _db;
  FastingRecordDaoManager(this._db);
  $$FastingRecordsTableTableManager get fastingRecords =>
      $$FastingRecordsTableTableManager(
        _db.attachedDatabase,
        _db.fastingRecords,
      );
}
