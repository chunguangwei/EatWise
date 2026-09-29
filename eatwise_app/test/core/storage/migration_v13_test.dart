import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// schema v12 → v13/v14 迁移测试：v12 库（fasting_records 无 serverId/deleted
/// 列，含一 pending 一 synced 两条历史记录）打开后 onUpgrade 补两列
/// （fastingRecord 全量进 /sync，2026-09-29 拍板），历史数据完整保留——
/// pending 行待首轮 /sync 上行（服务端按归属日幂等收敛），synced 行
/// serverId 缺省 null（下行对账回填，内容本机为准）。
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eatwise_mig_v13');
    dbFile = File('${dir.path}/eatwise.db');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
  });

  /// 手工落一个 v12 库（user_version=12，v12 口径 fasting_records + 两条记录；
  /// foods 按 v12 口径建空表——v14 迁移（并行批次 Foods 自定义食物终态列）
  /// 会对 foods 补列）。
  Future<void> seedV12Database() async {
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
        contribution_status TEXT
      )
    ''');
    await seed.runCustom('''
      CREATE TABLE fasting_records (
        local_id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        attribution_date TEXT NOT NULL,
        start_utc INTEGER NOT NULL,
        end_utc INTEGER NOT NULL,
        actual_sec INTEGER NOT NULL,
        planned_sec INTEGER NOT NULL,
        extended_minutes INTEGER NOT NULL,
        result TEXT NOT NULL,
        qualified INTEGER NOT NULL,
        client_request_id TEXT NOT NULL,
        sync_status INTEGER NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');
    // sync_status 为 textEnum 名称口径（EnumNameConverter）。
    await seed.runCustom('''
      INSERT INTO fasting_records (local_id, user_id, attribution_date,
        start_utc, end_utc, actual_sec, planned_sec, extended_minutes, result,
        qualified, client_request_id, sync_status, created_at_utc)
      VALUES
        ('u-1-2026-07-30', 'u-1', '2026-07-30', 1785403200, 1785460800, 57600,
         57600, 0, 'completedOnTime', 1, 'cr-old-pending', 'pending',
         '2026-07-30T12:00:00.000Z'),
        ('u-1-2026-07-31', 'u-1', '2026-07-31', 1785489600, 1785547200, 57600,
         57600, 0, 'brokenEarly', 0, 'cr-old-synced', 'synced',
         '2026-07-31T12:00:00.000Z')
    ''');
    await seed.runCustom('PRAGMA user_version = 12');
    await seed.close();
  }

  test('v12 → v13：fasting_records 补 serverId/deleted，历史行保留且队列口径正确', () async {
    await seedV12Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(() async => db.close());

    expect(db.schemaVersion, 14);

    // 历史行完整保留：serverId 缺省 null、deleted 缺省 false。
    final pending = (await db.fastingRecordDao.getByLocalId('u-1-2026-07-30'))!;
    expect(pending.attributionDate, '2026-07-30');
    expect(pending.syncStatus, SyncStatus.pending);
    expect(pending.serverId, isNull);
    expect(pending.deleted, isFalse);
    expect(pending.clientRequestId, 'cr-old-pending'); // 幂等键 v2 起已有，无需回填

    final synced = (await db.fastingRecordDao.getByLocalId('u-1-2026-07-31'))!;
    expect(synced.syncStatus, SyncStatus.synced);
    expect(synced.serverId, isNull);
    expect(synced.deleted, isFalse);

    // pending 历史行进 /sync 上行队列（首轮同步经归属日幂等收敛）。
    final queue = await db.fastingRecordDao.pendingForUser('u-1');
    expect(queue.map((r) => r.localId), <String>['u-1-2026-07-30']);

    // 升级后的 user_version 落为 14（重开不再重复迁移；v14 为 Foods 自定义食物终态收敛列）。
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(versionRow.data['user_version'], 14);
  });
}

/// 裸 executor 的 ensureOpen 宿主（无表，仅用于手工落 v12 schema；
/// 初始打开的建库迁移不影响——随后 PRAGMA 显式置 user_version=12）。
final class _RawSeedDatabase extends GeneratedDatabase {
  _RawSeedDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  int get schemaVersion => 1;
}
