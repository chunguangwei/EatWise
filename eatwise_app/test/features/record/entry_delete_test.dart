import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// 已入账记录删除回归（真机走查 bug：记录后无删除入口）。
/// 未上行 → 本地物理删；已上行 → tombstone + delete op 上行，ack 后物理清除；
/// 列表与聚合缓存即时排除。
void main() {
  late AppDatabase db;
  late FakeRecordRemote remote;
  late tz.Location location;

  setUpAll(() => initRecordTestTimeZones());

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    location = tz.getLocation('Asia/Shanghai');
  });

  tearDown(() => db.close());

  RecordRepository repo({
    Duration undoWindow = const Duration(milliseconds: 20),
  }) {
    return RecordRepository(
      db: db,
      remote: remote,
      location: location,
      undoWindow: undoWindow,
    );
  }

  RecordDraft draft({String foodId = 'f-rice', double amountG = 100}) {
    return RecordDraft(
      foodId: foodId,
      amountG: amountG,
      mealUtc: DateTime.utc(2026, 7, 28, 4), // 上海 12:00 → 归属 2026-07-28
      source: EntrySource.manual,
    );
  }

  Future<FoodEntry> addSynced(RecordRepository repository) async {
    final entry = await repository.addEntry(draft());
    await repository.flushEntry(entry.localId);
    final synced = await db.foodEntryDao.getByLocalId(entry.localId);
    expect(synced!.syncStatus, SyncStatus.synced);
    return synced;
  }

  test('已上行记录删除：立即从列表/聚合消失，在线 delete op ack 后物理清除', () async {
    final repository = repo();
    final entry = await addSynced(repository);
    final cacheBefore = await db.foodEntryDao.getDailyNutrition(
      'anonymous',
      '2026-07-28',
    );
    expect(cacheBefore!.entryCount, 1);

    expect(await repository.deleteEntry(entry.localId), isTrue);

    // 列表与聚合即时排除（不等网络）。
    final rows = await db.foodEntryDao.entriesForDate(
      'anonymous',
      '2026-07-28',
    );
    expect(rows, isEmpty);
    final cacheAfter = await db.foodEntryDao.getDailyNutrition(
      'anonymous',
      '2026-07-28',
    );
    expect(cacheAfter!.entryCount, 0);

    // 在线即时上行 delete，ack → 物理清除。
    expect(await db.foodEntryDao.getByLocalId(entry.localId), isNull);

    // retryPending 无残留。
    final pushed = await repository.retryPending();
    expect(pushed, 0);
    await repository.dispose();
  });

  test('删除后 delete op 可重试：失败保持 tombstone，成功后清除', () async {
    final repository = repo();
    final entry = await addSynced(repository);
    remote.mode = FakeRemoteMode.retryableFailure;
    await repository.deleteEntry(entry.localId);
    remote.mode = FakeRemoteMode.retryableFailure;
    await repository.retryPending();
    final still = await db.foodEntryDao.getByLocalId(entry.localId);
    expect(still!.deleted, isTrue, reason: '失败保留 tombstone 待下轮');

    remote.mode = FakeRemoteMode.success;
    await repository.retryPending();
    expect(await db.foodEntryDao.getByLocalId(entry.localId), isNull);
    await repository.dispose();
  });

  test('未上行记录删除：本地物理删（云端无此行，不产生 delete op）', () async {
    remote.mode = FakeRemoteMode.offline;
    final repository = repo();
    final entry = await repository.addEntry(draft()); // 离线 pending
    remote.mode = FakeRemoteMode.success;

    expect(await repository.deleteEntry(entry.localId), isTrue);
    expect(await db.foodEntryDao.getByLocalId(entry.localId), isNull);

    // retryPending 不再扫到它（无 delete op 上行）。
    final pushed = await repository.retryPending();
    expect(pushed, 0);
    await repository.dispose();
  });

  test('不存在的 localId 删除返回 false', () async {
    final repository = repo();
    expect(await repository.deleteEntry('nope'), isFalse);
    await repository.dispose();
  });
}
