import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v5 → v6 迁移测试：v5 库（foods 无 contributionStatus，含自定义
/// 食物历史数据）打开后 onUpgrade 补 contributionStatus 可空列，历史数据
/// 完整保留且默认 null（未贡献 → 搜索行显示「自定义」标签）。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v6');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v5 库（user_version=5，v5 口径 foods + 一条自定义食物）。
  Future<void> seedV5Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    // v5 口径 foods（无 contributionStatus）。
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
        custom_client_request_id TEXT NOT NULL DEFAULT ''
      )
    ''');
    await seed.runCustom('''
      INSERT INTO foods (id, name_zh, name_en, kcal_per100g,
        protein_per100g, carb_per100g, fat_per100g, is_custom,
        custom_sync_pending, custom_client_request_id)
      VALUES ('srv-food-1', '手工丸子', '手工丸子', 200, 10, 20, 5, 1, 0, 'req-1')
    ''');
    // v1 既有 food_entries（v7 迁移补列目标；裸种子库补全，口径不含 during_fast）。
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
        food_id TEXT NOT NULL,
        amount_g REAL NOT NULL,
        kcal REAL NOT NULL,
        protein_g REAL NOT NULL,
        carb_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        source TEXT NOT NULL,
        note TEXT,
        created_at_utc TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('PRAGMA user_version = 5');
    await seed.close();
  }

  test('v5 → v7：foods 补 contributionStatus，历史数据保留且默认未贡献', () async {
    await seedV5Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 10);

    // 历史行完整保留，新列默认 null（未贡献 → 标签仍为「自定义」）。
    final food = (await db.foodDao.getById('srv-food-1'))!;
    expect(food.nameZh, '手工丸子');
    expect(food.isCustom, isTrue);
    expect(food.customClientRequestId, 'req-1');
    expect(food.contributionStatus, isNull);

    // 新口径写入贡献状态正常（pending → 「审核中」标签）。
    await db.foodDao.setContributionStatus('srv-food-1', 'pending');
    final updated = (await db.foodDao.getById('srv-food-1'))!;
    expect(updated.contributionStatus, 'pending');

    // 升级后的 user_version 落为 10（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 10);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v5 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=5）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
