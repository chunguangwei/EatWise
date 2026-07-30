import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, Table, TableInfo, Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v3 → v4 迁移测试：v3 库（water_logs 无同步字段，含历史数据）
/// 打开后 onUpgrade 补 clientRequestId/serverId/syncState/deleted 四列，
/// 历史饮水数据完整保留且默认 pending。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v4');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v3 库（user_version=3，v3 口径 water_logs + 一条饮水数据）。
  Future<void> seedV3Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    await seed.runCustom('''
      CREATE TABLE foods (
        id TEXT NOT NULL PRIMARY KEY,
        name_zh TEXT NOT NULL,
        name_en TEXT NOT NULL,
        aliases_zh TEXT NOT NULL DEFAULT '[]',
        aliases_en TEXT NOT NULL DEFAULT '[]',
        kcal_per100g REAL NOT NULL,
        protein_per100g REAL NOT NULL,
        carb_per100g REAL NOT NULL,
        fat_per100g REAL NOT NULL
      )
    ''');
    // v3 口径 water_logs（无 clientRequestId/serverId/syncState/deleted）。
    await seed.runCustom('''
      CREATE TABLE water_logs (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        amount_ml INTEGER NOT NULL,
        datetime_utc TEXT NOT NULL,
        local_date TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      INSERT INTO water_logs (local_id, user_id, amount_ml, datetime_utc,
        local_date, created_at_utc)
      VALUES ('w-old', 'anonymous', 300, '2026-07-28T01:00:00.000Z',
        '2026-07-28', '2026-07-28T01:00:00.000Z')
    ''');
    await seed.runCustom('PRAGMA user_version = 3');
    await seed.close();
  }

  test('v3 → v4：water_logs 补同步字段，历史数据保留且默认 pending', () async {
    await seedV3Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 4);

    // 历史行完整保留，新列走默认值（pending/无 serverId/无幂等键/非 tombstone）。
    final old = (await db.waterLogDao.getByLocalId('w-old'))!;
    expect(old.amountMl, 300);
    expect(old.localDate, '2026-07-28');
    expect(old.syncState, WaterSyncState.pending);
    expect(old.serverId, isNull);
    expect(old.clientRequestId, '');
    expect(old.deleted, isFalse);
    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-28'), 300);

    // 新口径入账正常（带幂等键）。
    await db.waterLogDao.insertLog(
      const WaterLogsCompanion(
        localId: Value('w-new'),
        userId: Value('anonymous'),
        amountMl: Value(200),
        datetimeUtc: Value('2026-07-29T01:00:00.000Z'),
        localDate: Value('2026-07-29'),
        clientRequestId: Value('c-new'),
        createdAtUtc: Value('2026-07-29T01:00:00.000Z'),
      ),
    );
    final newLog = (await db.waterLogDao.getByLocalId('w-new'))!;
    expect(newLog.clientRequestId, 'c-new');
    expect(newLog.syncState, WaterSyncState.pending);

    // 升级后的 user_version 落为 4（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 4);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v3 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=3）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
