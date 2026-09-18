import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v8 → v9 迁移测试：v8 库（无 exercise_logs）打开后 onUpgrade
/// 新建 exercise_logs 表（手动记运动，设备级纯本地），可正常读写。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v9');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v8 库（user_version=8，无 exercise_logs）。
  Future<void> seedV8Database() async {
    final seed = NativeDatabase(dbFile);
    await seed.ensureOpen(_RawSeedDatabase(seed));
    await seed.runCustom('PRAGMA user_version = 8');
    await seed.close();
  }

  test('v8 → v9：新建 exercise_logs 表，可入账/合计/删除，user_version 落 9', () async {
    await seedV8Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 9);

    // 新表读写正常。
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion.insert(
        localId: 'e-1',
        userId: 'anonymous',
        typeKey: 'jog',
        durationMin: 30,
        kcal: 210,
        localDate: '2026-09-19',
        createdAtUtc: '2026-09-19T02:00:00.000Z',
      ),
    );
    final stored = await db.exerciseLogDao.getByLocalId('e-1');
    expect(stored, isNotNull);
    expect(stored!.typeKey, 'jog');
    expect(
      await db.exerciseLogDao.totalKcalForDate('anonymous', '2026-09-19'),
      210,
    );
    expect(await db.exerciseLogDao.deleteLog('e-1'), 1);

    // 升级后的 user_version 落为 9（重开不再重复迁移）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 9);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v8 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=8）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
