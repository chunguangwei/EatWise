import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v15 → v16 保留全部记录并冻结未知 create，已同步行不新增请求', () async {
    final dir = await Directory.systemTemp.createTemp('eatwise-v16-');
    final file = File('${dir.path}/eatwise.db');
    addTearDown(() => dir.delete(recursive: true));
    final seed = NativeDatabase(file);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    await seed.runCustom('''
      CREATE TABLE food_entries (
        local_id TEXT NOT NULL PRIMARY KEY, user_id TEXT NOT NULL,
        server_id TEXT, client_request_id TEXT NOT NULL, sync_status TEXT NOT NULL,
        local_version INTEGER NOT NULL DEFAULT 1, server_version INTEGER,
        server_updated_at TEXT, retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT, deleted INTEGER NOT NULL DEFAULT 0,
        datetime_utc TEXT NOT NULL, local_date TEXT NOT NULL, food_id TEXT NOT NULL,
        amount_g REAL NOT NULL, kcal REAL NOT NULL, protein_g REAL NOT NULL,
        carb_g REAL NOT NULL, fat_g REAL NOT NULL, source TEXT NOT NULL,
        note TEXT, during_fast INTEGER NOT NULL DEFAULT 0, meal_type TEXT,
        created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL
      )
    ''');
    for (final row in [
      ['pending-row', 'pending', null, 0],
      ['submitting-row', 'submitting', null, 0],
      ['deleted-row', 'pending', null, 1],
      ['synced-row', 'synced', 'server-1', 0],
    ]) {
      await seed.runInsert(
        '''
        INSERT INTO food_entries (local_id, user_id, server_id, client_request_id,
          sync_status, deleted, datetime_utc, local_date, food_id, amount_g, kcal,
          protein_g, carb_g, fat_g, source, meal_type, created_at_utc, updated_at_utc)
        VALUES (?, 'user-1', ?, ?, ?, ?, '2026-10-25T04:00:00.000Z', '2026-10-25',
          'rice', 100, 116, 2.6, 25.9, 0.3, 'manual', 'lunch',
          '2026-10-25T04:00:00.000Z', '2026-10-25T04:00:00.000Z')
      ''',
        [row[0], row[2], 'request-${row[0]}', row[1], row[3]],
      );
    }
    await seed.runCustom('PRAGMA user_version = 15');
    await seed.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final rows = await db.select(db.foodEntries).get();
    expect(rows, hasLength(4));
    for (final row in rows) {
      expect(row.amountG, 100);
      expect(row.kcal, 116);
      expect(row.localDate, '2026-10-25');
      if (row.syncStatus == SyncStatus.synced) {
        expect(row.createRequestSnapshot, isNull);
        expect(row.serverId, 'server-1');
      } else {
        expect(row.createRequestSnapshot, isNotNull);
        final original = FoodEntry.fromJson(
          jsonDecode(row.createRequestSnapshot!) as Map<String, dynamic>,
        );
        expect(original.clientRequestId, row.clientRequestId);
        expect(original.amountG, 100);
        expect(original.deleted, isFalse);
        expect(row.deleted, row.localId == 'deleted-row');
      }
    }
    expect(
      (await db.foodEntryDao.deletePendingEntries('user-1')).single.localId,
      'deleted-row',
    );
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 17);
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
