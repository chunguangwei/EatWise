import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/anonymous_data_migrator.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/streak/application/streak_local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// 匿名 → 登录数据换挂迁移测试（联动审计#1 + #6）。
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late AnonymousDataMigrator migrator;

  setUp(() async {
    db = AppDatabase.memory();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    migrator = AnonymousDataMigrator(db: db, prefs: prefs);
    await seedFoods(db);
    addTearDown(() async => db.close());
  });

  Future<FastingRecord?> fastingByLocalId(String localId) {
    return (db.select(
      db.fastingRecords,
    )..where((r) => r.localId.equals(localId))).getSingleOrNull();
  }

  Future<void> insertAnonymousRows() async {
    await db.foodEntryDao.insertEntry(
      const FoodEntriesCompanion(
        localId: Value('l-food'),
        userId: Value('anonymous'),
        clientRequestId: Value('cr-food'),
        syncStatus: Value(SyncStatus.pending),
        localVersion: Value(1),
        retryCount: Value(0),
        deleted: Value(false),
        datetimeUtc: Value('2026-09-18T01:10:00.000Z'),
        localDate: Value('2026-09-18'),
        foodId: Value('f-rice'),
        amountG: Value(200),
        kcal: Value(232),
        proteinG: Value(5.2),
        carbG: Value(51.8),
        fatG: Value(0.6),
        source: Value(EntrySource.manual),
        createdAtUtc: Value('2026-09-18T01:10:00.000Z'),
        updatedAtUtc: Value('2026-09-18T01:10:00.000Z'),
      ),
    );
    await db.waterLogDao.insertLog(
      WaterLogsCompanion.insert(
        localId: 'l-water',
        userId: 'anonymous',
        amountMl: 300,
        datetimeUtc: '2026-09-18T01:00:00.000Z',
        localDate: '2026-09-18',
        createdAtUtc: '2026-09-18T01:00:00.000Z',
      ),
    );
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion.insert(
        localId: 'l-ex',
        userId: 'anonymous',
        typeKey: 'walk',
        durationMin: 30,
        kcal: 120,
        localDate: '2026-09-18',
        createdAtUtc: '2026-09-18T01:00:00.000Z',
      ),
    );
    await db.fastingRecordDao.upsertRecord(
      const FastingRecordsCompanion(
        localId: Value('anonymous-2026-09-18'),
        userId: Value('anonymous'),
        attributionDate: Value('2026-09-18'),
        startUtc: Value(1),
        endUtc: Value(2),
        actualSec: Value(3600),
        plannedSec: Value(3600),
        extendedMinutes: Value(0),
        result: Value('COMPLETED'),
        qualified: Value(true),
        clientRequestId: Value('cr-fasting'),
        syncStatus: Value(SyncStatus.pending),
        createdAtUtc: Value('2026-09-18T12:00:00.000Z'),
      ),
    );
  }

  group('AnonymousDataMigrator drift 换挂', () {
    test('四表 anonymous 行换挂到真实 uid；断食记录 localId 同步改写', () async {
      await insertAnonymousRows();

      expect(await migrator.migrateIfNeeded('u-1'), isTrue);

      final entry = await db.foodEntryDao.getByLocalId('l-food');
      expect(entry!.userId, 'u-1');
      // pending 状态保持——换挂后即进入真实 uid 的上行队列。
      expect(entry.syncStatus, SyncStatus.pending);
      final water = await db.waterLogDao.getByLocalId('l-water');
      expect(water!.userId, 'u-1');
      final ex = await db.exerciseLogDao.getByLocalId('l-ex');
      expect(ex!.userId, 'u-1');
      final fasting = await fastingByLocalId('u-1-2026-09-18');
      expect(fasting!.userId, 'u-1');
      expect(await fastingByLocalId('anonymous-2026-09-18'), isNull);
      // 按 uid 查询立即可见（假空消除）。
      expect(await db.fastingRecordDao.qualifiedDates('u-1'), {'2026-09-18'});
    });

    test('同日撞主键（理论不存在）：uid 侧为准，匿名残留删除', () async {
      await insertAnonymousRows();
      await db.fastingRecordDao.upsertRecord(
        const FastingRecordsCompanion(
          localId: Value('u-1-2026-09-18'),
          userId: Value('u-1'),
          attributionDate: Value('2026-09-18'),
          startUtc: Value(9),
          endUtc: Value(10),
          actualSec: Value(7200),
          plannedSec: Value(7200),
          extendedMinutes: Value(0),
          result: Value('COMPLETED'),
          qualified: Value(true),
          clientRequestId: Value('cr-uid'),
          syncStatus: Value(SyncStatus.synced),
          createdAtUtc: Value('2026-09-18T12:00:00.000Z'),
        ),
      );

      await migrator.migrateIfNeeded('u-1');

      final kept = await fastingByLocalId('u-1-2026-09-18');
      expect(kept!.clientRequestId, 'cr-uid'); // 未被匿名行覆盖
      expect(
        await db.fastingRecordDao.getByClientRequestId('cr-fasting'),
        isNull,
      );
    });

    test('幂等：二次调用 no-op；匿名态直接跳过', () async {
      await insertAnonymousRows();
      expect(await migrator.migrateIfNeeded('u-1'), isTrue);
      expect(await migrator.migrateIfNeeded('u-1'), isFalse);
      expect(prefs.getBool('anon_migrated_v1_u-1'), isTrue);
      // 未登录态永不迁移。
      expect(await migrator.migrateIfNeeded('anonymous'), isFalse);
    });

    test('匿名聚合缓存孤儿行清空（真实 uid 侧由回填重建）', () async {
      await db.foodEntryDao.insertEntry(
        const FoodEntriesCompanion(
          localId: Value('l-food'),
          userId: Value('anonymous'),
          clientRequestId: Value('cr-food'),
          syncStatus: Value(SyncStatus.synced),
          localVersion: Value(1),
          retryCount: Value(0),
          deleted: Value(false),
          datetimeUtc: Value('2026-09-18T01:10:00.000Z'),
          localDate: Value('2026-09-18'),
          foodId: Value('f-rice'),
          amountG: Value(200),
          kcal: Value(232),
          proteinG: Value(5.2),
          carbG: Value(51.8),
          fatG: Value(0.6),
          source: Value(EntrySource.manual),
          createdAtUtc: Value('2026-09-18T01:10:00.000Z'),
          updatedAtUtc: Value('2026-09-18T01:10:00.000Z'),
        ),
      );
      await db.foodEntryDao.recomputeDailyNutrition(
        'anonymous',
        '2026-09-18',
        updatedAtUtc: '2026-09-18T01:10:00.000Z',
      );

      await migrator.migrateIfNeeded('u-1');

      expect(
        await db.foodEntryDao.getDailyNutrition('anonymous', '2026-09-18'),
        isNull,
      );
    });
  });

  group('prefs 命名空间换挂', () {
    test('体重日志：匿名条目并入，同日以已登录侧为准，匿名键删除', () async {
      await prefs.setString(
        'reports.weightLogs.v2.anonymous',
        '{"2026-09-16":{"kg":70.5,"clientRequestId":"a1",'
            '"updatedAtUtc":"2026-09-16T00:00:00.000Z","synced":false},'
            '"2026-09-17":{"kg":70.0,"clientRequestId":"a2",'
            '"updatedAtUtc":"2026-09-17T00:00:00.000Z","synced":false}}',
      );
      await prefs.setString(
        'reports.weightLogs.v2.u-1',
        '{"2026-09-17":{"kg":69.8,"clientRequestId":"u1",'
            '"updatedAtUtc":"2026-09-17T08:00:00.000Z","synced":true}}',
      );

      await migrator.migrateIfNeeded('u-1');

      final store = WeightLogStore(prefs, userId: 'u-1');
      final merged = store.loadEntries('2026-09-01', '2026-09-30');
      expect(merged.keys, containsAll(<String>['2026-09-16', '2026-09-17']));
      expect(merged['2026-09-17']!.kg, 69.8); // 同日 uid 侧为准
      expect(merged['2026-09-17']!.synced, isTrue);
      expect(merged['2026-09-16']!.kg, 70.5); // 匿名独有日期并入
      expect(store.pendingEntries().map((e) => e.key), ['2026-09-16']);
      expect(prefs.getString('reports.weightLogs.v2.anonymous'), isNull);
    });

    test('streak：弹窗并集、幂等键同日 uid 侧为准、引擎快照 uid 缺失才搬', () async {
      await prefs.setString(
        'streak.engine.anonymous',
        '{"qualifiedDates":["2026-09-17"]}',
      );
      await prefs.setStringList(
        'streak.shownBreakPopups.anonymous',
        const <String>['2026-09-10'],
      );
      await prefs.setStringList('streak.shownBreakPopups.u-1', const <String>[
        '2026-09-12',
      ]);
      await prefs.setString(
        'streak.reportRequestIds.anonymous',
        '{"2026-09-17":"req-anon","2026-09-16":"req-anon-16"}',
      );
      await prefs.setString(
        'streak.reportRequestIds.u-1',
        '{"2026-09-17":"req-uid"}',
      );

      await migrator.migrateIfNeeded('u-1');

      final store = SharedPreferencesStreakLocalStore(prefs, userId: 'u-1');
      expect(store.loadEngine(), isNotNull); // uid 侧缺失 → 匿名快照搬入
      expect(store.loadEngine()!.qualifiedDates, {'2026-09-17'});
      expect(store.loadShownBreakPopups(), {'2026-09-10', '2026-09-12'});
      expect(store.loadReportRequestId('2026-09-17'), 'req-uid');
      expect(store.loadReportRequestId('2026-09-16'), 'req-anon-16');
      expect(prefs.getString('streak.engine.anonymous'), isNull);
      expect(prefs.getStringList('streak.shownBreakPopups.anonymous'), isNull);
      expect(prefs.getString('streak.reportRequestIds.anonymous'), isNull);
    });

    test('无匿名数据：迁移仍标完成，uid 侧键不受影响', () async {
      await prefs.setString(
        'reports.weightLogs.v2.u-1',
        '{"2026-09-17":{"kg":69.8,"clientRequestId":"u1",'
            '"updatedAtUtc":"2026-09-17T08:00:00.000Z","synced":true}}',
      );

      expect(await migrator.migrateIfNeeded('u-1'), isTrue);

      final store = WeightLogStore(prefs, userId: 'u-1');
      expect(store.loadRange('2026-09-17', '2026-09-17'), {'2026-09-17': 69.8});
      expect(prefs.getBool('anon_migrated_v1_u-1'), isTrue);
    });
  });

  group('streak 旧全局键迁移（审计#6）', () {
    test('登录用户构造期：旧全局键 rename 进 uid 命名空间后删除', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'streak.engine': '{"qualifiedDates":["2026-09-15"]}',
        'streak.shownBreakPopups': <String>['2026-09-01'],
        'streak.reportRequestIds': '{"2026-09-15":"req-legacy"}',
      });
      final p = await SharedPreferences.getInstance();
      final store = SharedPreferencesStreakLocalStore(p, userId: 'u-9');
      expect(store.loadEngine()!.qualifiedDates, {'2026-09-15'});
      expect(store.loadShownBreakPopups(), {'2026-09-01'});
      expect(store.loadReportRequestId('2026-09-15'), 'req-legacy');
      expect(p.getString('streak.engine'), isNull);
      expect(p.getStringList('streak.shownBreakPopups'), isNull);
      expect(p.getString('streak.reportRequestIds'), isNull);
      // 新写入落命名空间键，不再回写旧全局键。
      store.markBreakPopupShown('2026-09-02');
      expect(
        p.getStringList('streak.shownBreakPopups.u-9'),
        contains('2026-09-02'),
      );
      expect(p.getStringList('streak.shownBreakPopups'), isNull);
    });

    test('命名空间已有值时旧全局值退役（不覆盖新代际）', () async {
      await prefs.setString('streak.engine', '{"qualifiedDates":["old"]}');
      await prefs.setString('streak.engine.u-9', '{"qualifiedDates":["new"]}');
      final store = SharedPreferencesStreakLocalStore(prefs, userId: 'u-9');
      expect(store.loadEngine()!.qualifiedDates, {'new'});
      expect(prefs.getString('streak.engine'), isNull);
    });

    test('匿名态不搬旧键（anonymous 命名空间与旧键等价独立）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'streak.engine': '{"qualifiedDates":["2026-09-15"]}',
      });
      final p = await SharedPreferences.getInstance();
      SharedPreferencesStreakLocalStore(p); // userId 默认 anonymous
      expect(p.getString('streak.engine'), isNotNull);
    });
  });

  group('RecordSyncEngine 挂接', () {
    test('登录态首轮 syncNow：匿名行换挂 + pending 进入上行队列 + 标记落盘', () async {
      await insertAnonymousRows();
      final repo = RecordRepository(
        db: db,
        remote: FakeRecordRemote(),
        location: tz.UTC,
        userId: 'u-1',
      );
      final engine = RecordSyncEngine(
        repository: repo,
        prefs: prefs,
        anonymousMigrator: migrator,
      );

      await engine.syncNow();

      final entry = await db.foodEntryDao.getByLocalId('l-food');
      expect(entry!.userId, 'u-1');
      expect(prefs.getBool('anon_migrated_v1_u-1'), isTrue);
      // 换挂后的 pending 记录被本轮上行队列捞起（Fake success → 非 pending）。
      expect(entry.syncStatus, isNot(SyncStatus.pending));
      await repo.dispose();
    });

    test('匿名态 syncNow 不迁移、不落标记', () async {
      await insertAnonymousRows();
      final repo = RecordRepository(
        db: db,
        remote: FakeRecordRemote(),
        location: tz.UTC,
        userId: 'anonymous',
      );
      final engine = RecordSyncEngine(
        repository: repo,
        prefs: prefs,
        anonymousMigrator: migrator,
      );

      await engine.syncNow();

      final entry = await db.foodEntryDao.getByLocalId('l-food');
      expect(entry!.userId, 'anonymous');
      expect(prefs.getBool('anon_migrated_v1_anonymous'), isNull);
      await repo.dispose();
    });
  });
}
