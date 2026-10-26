import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v15');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  Future<void> seedV14Database() async {
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
        fat_per100g REAL NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        custom_sync_pending INTEGER NOT NULL DEFAULT 0,
        custom_client_request_id TEXT NOT NULL DEFAULT '',
        custom_sync_fail_count INTEGER NOT NULL DEFAULT 0,
        custom_sync_failed INTEGER NOT NULL DEFAULT 0,
        contribution_status TEXT
      )
    ''');
    await seed.runCustom('''
      INSERT INTO foods (id, name_zh, name_en, kcal_per100g,
        protein_per100g, carb_per100g, fat_per100g, is_custom,
        custom_sync_pending, custom_client_request_id)
      VALUES
        ('cf-legacy', '历史私房菜', 'Legacy dish', 100, 5, 5, 5, 1, 1, 'req-legacy'),
        ('shared-legacy', '共享米饭', 'Shared rice', 116, 2, 25, 0, 0, 0, '')
    ''');
    await seed.runCustom('CREATE TABLE water_logs (local_id TEXT PRIMARY KEY)');
    await seed.runCustom(
      'CREATE TABLE exercise_logs (local_id TEXT PRIMARY KEY)',
    );
    await seed.runCustom(
      'CREATE TABLE fasting_records (local_id TEXT PRIMARY KEY)',
    );
    await seed.runCustom('PRAGMA user_version = 14');
    await seed.close();
  }

  test('v14 → v15：owner/source 同增量补齐，历史个人食物不删除且延迟到首次登录认领', () async {
    await seedV14Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 16);
    final legacy = (await db.foodDao.getById('cf-legacy'))!;
    expect(legacy.nameZh, '历史私房菜');
    expect(legacy.customSyncPending, isTrue);
    expect(legacy.customClientRequestId, 'req-legacy');
    expect(legacy.ownerUserId, isNull);
    expect(legacy.source, 'manual');
    expect((await db.foodDao.getById('shared-legacy'))!.ownerUserId, isNull);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 16);
    for (final table in <String>[
      'water_logs',
      'exercise_logs',
      'fasting_records',
    ]) {
      final columns = await db.customSelect('PRAGMA table_info($table)').get();
      expect(columns.map((row) => row.data['name']), contains('last_error'));
    }
  });
}

final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
