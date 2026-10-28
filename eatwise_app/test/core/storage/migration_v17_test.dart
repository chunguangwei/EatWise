import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v16→v17 保留旧pending原键、来源、owner与终态，新快照可延迟冻结', () async {
    final dir = await Directory.systemTemp.createTemp('eatwise-v17-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/eatwise.db');
    final seed = NativeDatabase(file);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    await seed.runCustom('''
      CREATE TABLE foods (
        id TEXT NOT NULL PRIMARY KEY, name_zh TEXT NOT NULL,
        name_en TEXT NOT NULL, aliases_zh TEXT NOT NULL DEFAULT '[]',
        aliases_en TEXT NOT NULL DEFAULT '[]', kcal_per100g REAL NOT NULL,
        protein_per100g REAL NOT NULL, carb_per100g REAL NOT NULL,
        fat_per100g REAL NOT NULL, is_custom INTEGER NOT NULL DEFAULT 0,
        owner_user_id TEXT, source TEXT NOT NULL DEFAULT 'manual',
        custom_sync_pending INTEGER NOT NULL DEFAULT 0,
        custom_client_request_id TEXT NOT NULL DEFAULT '',
        custom_sync_fail_count INTEGER NOT NULL DEFAULT 0,
        custom_sync_failed INTEGER NOT NULL DEFAULT 0,
        contribution_status TEXT
      )
    ''');
    await seed.runCustom('''
      INSERT INTO foods (id,name_zh,name_en,kcal_per100g,protein_per100g,
        carb_per100g,fat_per100g,is_custom,owner_user_id,source,
        custom_sync_pending,custom_client_request_id,custom_sync_fail_count,
        custom_sync_failed)
      VALUES ('custom-original','旧食品','Old food',100,5,10,2,1,'user-1',
        'llm-estimate',1,'original-request',5,1)
    ''');
    await seed.runCustom('PRAGMA user_version = 16');
    await seed.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = (await db.select(db.foods).get()).single;
    expect(row.id, 'custom-original');
    expect(row.customClientRequestId, 'original-request');
    expect(row.customOriginLocalId, 'custom-original');
    expect(row.nameZh, '旧食品');
    expect(row.ownerUserId, 'user-1');
    expect(row.source, 'llm-estimate');
    expect(row.customSyncPending, isTrue);
    expect(row.customSyncFailed, isTrue);
    expect(row.customSyncFailCount, 5);
    expect(row.customLocalVersion, 0);
    expect(row.customCreateRequestSnapshot, isNull);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data['user_version'],
      17,
    );
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
