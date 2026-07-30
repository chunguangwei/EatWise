import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, Table, TableInfo, Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v2 → v4 迁移测试：v2 库（无 water_logs）打开后 onUpgrade 新增
/// WaterLogs（v3）并补两态同步字段（v4），且 v2 旧数据完整保留。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v3');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v2 库（user_version=2，四张 v2 表 + 一条食物数据）。
  Future<void> seedV2Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    // v2 四表（列名对齐 drift snake_case 生成口径）。
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
    await seed.runCustom('''
      CREATE TABLE food_entries (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        server_id TEXT NULL,
        client_request_id TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        local_version INTEGER NOT NULL DEFAULT 1,
        server_version INTEGER NULL,
        server_updated_at TEXT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        datetime_utc TEXT NOT NULL,
        local_date TEXT NOT NULL,
        food_id TEXT NOT NULL REFERENCES foods (id),
        amount_g REAL NOT NULL,
        kcal REAL NOT NULL,
        protein_g REAL NOT NULL,
        carb_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        source TEXT NOT NULL,
        note TEXT NULL,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      CREATE TABLE daily_nutrition_caches (
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        entry_count INTEGER NOT NULL DEFAULT 0,
        kcal REAL NOT NULL DEFAULT 0,
        protein_g REAL NOT NULL DEFAULT 0,
        carb_g REAL NOT NULL DEFAULT 0,
        fat_g REAL NOT NULL DEFAULT 0,
        is_local_estimate INTEGER NOT NULL DEFAULT 1,
        updated_at_utc TEXT NOT NULL,
        PRIMARY KEY (user_id, date)
      )
    ''');
    await seed.runCustom('''
      CREATE TABLE fasting_records (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        attribution_date TEXT NOT NULL,
        start_utc INTEGER NOT NULL,
        end_utc INTEGER NOT NULL,
        actual_sec INTEGER NOT NULL,
        planned_sec INTEGER NOT NULL,
        extended_minutes INTEGER NOT NULL,
        result TEXT NOT NULL,
        qualified INTEGER NOT NULL,
        client_request_id TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      INSERT INTO foods (id, name_zh, name_en, kcal_per100g,
        protein_per100g, carb_per100g, fat_per100g)
      VALUES ('f-rice', '白米饭', 'White Rice', 116, 2.6, 25.9, 0.3)
    ''');
    await seed.runCustom('PRAGMA user_version = 2');
    await seed.close();
  }

  test('v2 → v4：onUpgrade 新增 water_logs + v4 同步字段，v2 数据完整保留', () async {
    await seedV2Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 4);

    // 迁移后 water_logs 可写可读（v4 同步字段走默认值）。
    await db.waterLogDao.insertLog(
      const WaterLogsCompanion(
        localId: Value('w-1'),
        userId: Value('anonymous'),
        amountMl: Value(300),
        datetimeUtc: Value('2026-07-29T01:00:00.000Z'),
        localDate: Value('2026-07-29'),
        createdAtUtc: Value('2026-07-29T01:00:00.000Z'),
      ),
    );
    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-29'), 300);
    final log = (await db.waterLogDao.getByLocalId('w-1'))!;
    expect(log.syncState, WaterSyncState.pending);
    expect(log.clientRequestId, '');

    // v2 旧数据完整保留（foods 可经生成 DAO 正常读取）。
    final food = await db.foodDao.getById('f-rice');
    expect(food, isNotNull);
    expect(food!.nameZh, '白米饭');
    expect(food.kcalPer100g, 116);

    // 升级后的 user_version 落为 4（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 4);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v2 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=2）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
