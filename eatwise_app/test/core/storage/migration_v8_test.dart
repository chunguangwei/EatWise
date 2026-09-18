import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, Table, TableInfo, Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v7 → v8 迁移测试：v7 库（food_entries 无 meal_type，含历史
/// 饮食记录）打开后 onUpgrade 补 meal_type 可空列（历史记录无餐次，
/// 展示归入「其他」组），历史数据完整保留。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v8');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v7 库（user_version=7，v7 口径 food_entries + 一条记录）。
  Future<void> seedV7Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    // v7 口径 food_entries（含 during_fast，无 meal_type）。foods 需存在（外键引用）。
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
        fat_per100g REAL NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        custom_sync_pending INTEGER NOT NULL DEFAULT 0,
        custom_client_request_id TEXT NOT NULL DEFAULT '',
        contribution_status TEXT
      )
    ''');
    await seed.runCustom('''
      INSERT INTO foods (id, name_zh, name_en, kcal_per100g,
        protein_per100g, carb_per100g, fat_per100g)
      VALUES ('f-rice', '米饭', 'Rice', 116, 2.6, 25.9, 0.3)
    ''');
    await seed.runCustom('''
      CREATE TABLE food_entries (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        server_id TEXT,
        client_request_id TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        local_version INTEGER NOT NULL DEFAULT 1,
        server_version INTEGER,
        server_updated_at TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
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
        note TEXT,
        during_fast INTEGER NOT NULL DEFAULT 0,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      INSERT INTO food_entries (local_id, user_id, client_request_id,
        sync_status, datetime_utc, local_date, food_id, amount_g, kcal,
        protein_g, carb_g, fat_g, source, created_at_utc, updated_at_utc)
      VALUES ('l-1', 'anonymous', 'req-1', 'pending',
        '2026-09-18T01:10:00.000Z', '2026-09-18', 'f-rice', 200, 232,
        5.2, 51.8, 0.6, 'manual',
        '2026-09-18T01:10:00.000Z', '2026-09-18T01:10:00.000Z')
    ''');
    await seed.runCustom('PRAGMA user_version = 7');
    await seed.close();
  }

  test('v7 → v8：food_entries 补 mealType 可空列，历史数据保留且无餐次（归「其他」组）', () async {
    await seedV7Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 8);

    // 历史行完整保留，新列为 null（无餐次 → 展示归「其他」组）。
    final entry = (await db.foodEntryDao.getByLocalId('l-1'))!;
    expect(entry.foodId, 'f-rice');
    expect(entry.amountG, 200);
    expect(entry.duringFast, isFalse);
    expect(entry.mealType, isNull);

    // 新口径写入餐次正常。
    await db.foodEntryDao.updateEntry(
      'l-1',
      const FoodEntriesCompanion(mealType: Value(MealType.lunch)),
    );
    expect(
      (await db.foodEntryDao.getByLocalId('l-1'))!.mealType,
      MealType.lunch,
    );

    // 升级后的 user_version 落为 8（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 8);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v7 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=7）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
