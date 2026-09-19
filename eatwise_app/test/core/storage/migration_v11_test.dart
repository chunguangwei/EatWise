import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, Table, TableInfo, Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v10 → v11 迁移测试：v10 库（exercise_logs 无 steps 列，含一条
/// 截图导入记录）打开后 onUpgrade 补 steps 可空列，历史数据完整保留；
/// 新口径写入步数快照正常。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v11');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v10 库（user_version=10，v10 口径 exercise_logs + 一条记录）。
  Future<void> seedV10Database() async {
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
        local_date TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    await seed.runCustom('''
      INSERT INTO exercise_logs (local_id, user_id, type_key, duration_min,
        kcal, source, local_date, created_at_utc)
      VALUES ('e-1', 'anonymous', 'summary', 0, 67, 'screenshot',
        '2026-09-19', '2026-09-19T02:00:00.000Z')
    ''');
    await seed.runCustom('PRAGMA user_version = 10');
    await seed.close();
  }

  test('v10 → v11：exercise_logs 补 steps 可空列，历史记录为 null，步数可写入并合计', () async {
    await seedV10Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 12);

    // 历史行完整保留，steps 为 null。
    final stored = (await db.exerciseLogDao.getByLocalId('e-1'))!;
    expect(stored.typeKey, 'summary');
    expect(stored.source, 'screenshot');
    expect(stored.steps, isNull);

    // 新口径写入步数快照正常，当日合计可读。
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion.insert(
        localId: 'e-2',
        userId: 'anonymous',
        typeKey: 'walk',
        durationMin: 0,
        kcal: 52,
        localDate: '2026-09-19',
        createdAtUtc: '2026-09-19T03:00:00.000Z',
        steps: const Value(1466),
      ),
    );
    expect((await db.exerciseLogDao.getByLocalId('e-2'))!.steps, 1466);
    expect(
      await db.exerciseLogDao
          .watchTotalStepsForDate('anonymous', '2026-09-19')
          .first,
      1466,
    );

    // 升级后的 user_version 落为 12（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 12);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v10 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=10）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
