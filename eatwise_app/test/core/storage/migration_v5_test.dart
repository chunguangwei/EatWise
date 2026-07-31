import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, Table, TableInfo, Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v4 → v5 迁移测试：v4 库（foods 无自定义食物字段，含历史数据）
/// 打开后 onUpgrade 补 isCustom/customSyncPending/customClientRequestId
/// 三列，历史食物数据完整保留且默认非自定义。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v5');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v4 库（user_version=4，v4 口径 foods + 一条食物数据）。
  Future<void> seedV4Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    // v4 口径 foods（无 isCustom/customSyncPending/customClientRequestId）。
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
      INSERT INTO foods (id, name_zh, name_en, kcal_per100g,
        protein_per100g, carb_per100g, fat_per100g)
      VALUES ('f-rice', '白米饭', 'White Rice', 116, 2.6, 25.9, 0.3)
    ''');
    await seed.runCustom('PRAGMA user_version = 4');
    await seed.close();
  }

  test('v4 → v6：foods 补自定义食物字段 + 贡献状态字段，历史数据保留且默认非自定义', () async {
    await seedV4Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 6);

    // 历史行完整保留，新列走默认值（非自定义/无 pending/无幂等键）。
    final food = (await db.foodDao.getById('f-rice'))!;
    expect(food.nameZh, '白米饭');
    expect(food.kcalPer100g, 116);
    expect(food.isCustom, isFalse);
    expect(food.customSyncPending, isFalse);
    expect(food.customClientRequestId, '');

    // 新口径自定义食物入账正常（isCustom + pending + 幂等键）。
    await db.foodDao.upsertAll(<FoodsCompanion>[
      const FoodsCompanion(
        id: Value('custom-1'),
        nameZh: Value('手工丸子'),
        nameEn: Value('手工丸子'),
        kcalPer100g: Value(200),
        proteinPer100g: Value(10),
        carbPer100g: Value(20),
        fatPer100g: Value(5),
        isCustom: Value(true),
        customSyncPending: Value(true),
        customClientRequestId: Value('req-1'),
      ),
    ]);
    final custom = (await db.foodDao.getById('custom-1'))!;
    expect(custom.isCustom, isTrue);
    expect(custom.customSyncPending, isTrue);
    expect(custom.customClientRequestId, 'req-1');

    // 升级后的 user_version 落为 6（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 6);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v4 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=4）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
