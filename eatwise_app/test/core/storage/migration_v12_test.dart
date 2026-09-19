import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v11 → v12 迁移测试：v11 库（exercise_logs 无同步字段，含两条
/// 历史记录）打开后 onUpgrade 补 clientRequestId/serverId/syncState/deleted
/// 四列（两态上行，2026-09-19 拍板），历史数据完整保留且幂等键回填为
/// localId（UUIDv4；默认 '' 会让服务端唯一约束把多条历史行压成一条）。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v12');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v11 库（user_version=11，v11 口径 exercise_logs + 两条记录，
  /// localId 用真实 UUIDv4 形态）。
  Future<void> seedV11Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    await seed.runCustom('''
      CREATE TABLE exercise_logs (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        type_key TEXT NOT NULL,
        duration_min INTEGER NOT NULL,
        kcal REAL NOT NULL,
        source TEXT,
        steps INTEGER,
        local_date TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      INSERT INTO exercise_logs (local_id, user_id, type_key, duration_min,
        kcal, source, steps, local_date, created_at_utc)
      VALUES
        ('3f6b1a2e-1111-4111-8111-aaaaaaaaaaa1', 'anonymous', 'walk', 0, 68,
         'screenshot', 1466, '2026-09-19', '2026-09-19T02:00:00.000Z'),
        ('3f6b1a2e-2222-4222-8222-bbbbbbbbbbb2', 'anonymous', 'jog', 30, 210,
         NULL, NULL, '2026-09-19', '2026-09-19T03:00:00.000Z')
    ''');
    await seed.runCustom('PRAGMA user_version = 11');
    await seed.close();
  }

  test('v11 → v12：补两态同步字段，历史行 pending + 幂等键回填 localId，可上行', () async {
    await seedV11Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 12);

    // 历史行完整保留：默认 pending（待上行）+ 幂等键 = localId（UUIDv4）。
    const id1 = '3f6b1a2e-1111-4111-8111-aaaaaaaaaaa1';
    const id2 = '3f6b1a2e-2222-4222-8222-bbbbbbbbbbb2';
    final row1 = (await db.exerciseLogDao.getByLocalId(id1))!;
    expect(row1.steps, 1466);
    expect(row1.source, 'screenshot');
    expect(row1.syncState, ExerciseSyncState.pending);
    expect(row1.clientRequestId, id1);
    expect(row1.serverId, isNull);
    expect(row1.deleted, isFalse);

    // 两条历史行幂等键互不相同（服务端唯一约束不塌缩）。
    final row2 = (await db.exerciseLogDao.getByLocalId(id2))!;
    expect(row2.clientRequestId, id2);
    expect(row2.clientRequestId == row1.clientRequestId, isFalse);

    // 历史行进 pending 队列（首轮同步即上行）；按幂等键可对账。
    final pending = await db.exerciseLogDao.pendingForUser('anonymous');
    expect(pending.map((e) => e.localId), containsAll(<String>[id1, id2]));
    expect((await db.exerciseLogDao.getByClientRequestId(id1))!.localId, id1);

    // 上行回填 + tombstone 口径可用。
    await db.exerciseLogDao.markSynced(id1, 'srv-1');
    await db.exerciseLogDao.markTombstone(id1);
    final tomb = (await db.exerciseLogDao.getByLocalId(id1))!;
    expect(tomb.deleted, isTrue);
    expect(tomb.syncState, ExerciseSyncState.pending); // 待上行 delete op
    // tombstone 不计入当日合计。
    expect(
      await db.exerciseLogDao.totalKcalForDate('anonymous', '2026-09-19'),
      210,
    );

    // 升级后的 user_version 落为 12（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 12);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v11 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=11）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
