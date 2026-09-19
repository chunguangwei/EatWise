import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, Table, TableInfo, Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v9 → v10 迁移测试：v9 库（exercise_logs 无 source 列，含一条
/// 手动录入记录）打开后 onUpgrade 补 source 可空列（null=手动录入），
/// 历史数据完整保留；新口径写入 'screenshot' 来源标记正常。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v10');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v9 库（user_version=9，v9 口径 exercise_logs + 一条记录）。
  Future<void> seedV9Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    await seed.runCustom('''
      CREATE TABLE exercise_logs (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        type_key TEXT NOT NULL,
        duration_min INTEGER NOT NULL,
        kcal REAL NOT NULL,
        local_date TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      INSERT INTO exercise_logs (local_id, user_id, type_key, duration_min,
        kcal, local_date, created_at_utc)
      VALUES ('e-1', 'anonymous', 'jog', 30, 210, '2026-09-19',
        '2026-09-19T02:00:00.000Z')
    ''');
    await seed.runCustom('PRAGMA user_version = 9');
    await seed.close();
  }

  test('v9 → v10：exercise_logs 补 source 可空列，历史记录为 null（手动录入）', () async {
    await seedV9Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 10);

    // 历史行完整保留，source 为 null（手动录入）。
    final stored = (await db.exerciseLogDao.getByLocalId('e-1'))!;
    expect(stored.typeKey, 'jog');
    expect(stored.kcal, 210);
    expect(stored.source, isNull);

    // 新口径写入来源标记正常。
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion.insert(
        localId: 'e-2',
        userId: 'anonymous',
        typeKey: 'summary',
        durationMin: 0,
        kcal: 350,
        localDate: '2026-09-19',
        createdAtUtc: '2026-09-19T03:00:00.000Z',
        source: const Value('screenshot'),
      ),
    );
    expect((await db.exerciseLogDao.getByLocalId('e-2'))!.source, 'screenshot');

    // 升级后的 user_version 落为 10（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 10);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v9 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=9）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
