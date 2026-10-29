import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/application/pending_sync.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late RecordRepository repo;
  late FakeRecordRemote remote;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    repo = RecordRepository(
      db: db,
      remote: remote,
      location: tz.UTC,
      userId: 'u-1',
    );
    final engine = RecordSyncEngine(
      repository: repo,
      prefs: await SharedPreferences.getInstance(),
    );
    container = ProviderContainer(
      overrides: [
        recordRepositoryProvider.overrideWithValue(repo),
        recordSyncEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(engine.dispose);
  });
  tearDown(() async {
    container.dispose();
    await repo.dispose();
    await db.close();
  });
  Future<String> syncedEntry() async {
    final entry = await repo.addEntry(
      RecordDraft(
        foodId: 'f-rice',
        amountG: 100,
        mealUtc: DateTime.utc(2026, 10, 29),
        source: EntrySource.manual,
      ),
    );
    await repo.flushEntry(entry.localId);
    return entry.localId;
  }

  test(
    'offline deletion remains visible as pending until acknowledged',
    () async {
      final id = await syncedEntry();
      remote.mode = FakeRemoteMode.offline;
      await repo.deleteEntry(id);
      expect(await repo.entriesForDate(DateTime.utc(2026, 10, 29)), isEmpty);
      expect(await repo.watchPendingCount().first, 1);
      expect(await db.foodEntryDao.watchPendingCount('other-user').first, 0);
      remote.mode = FakeRemoteMode.success;
      await repo.retryPending();
      expect(await db.foodEntryDao.getByLocalId(id), isNull);
      expect(await repo.watchPendingCount().first, 0);
    },
  );
  test(
    'manual retry reports failed deletion and later actual success',
    () async {
      final id = await syncedEntry();
      remote.mode = FakeRemoteMode.offline;
      await repo.deleteEntry(id);
      final retry = container.read(recordManualSyncProvider);
      expect(await retry(), PendingSyncResult.network);
      expect(await db.foodEntryDao.getByLocalId(id), isNotNull);
      remote.mode = FakeRemoteMode.success;
      expect(await retry(), PendingSyncResult.success);
      expect(await db.foodEntryDao.getByLocalId(id), isNull);
    },
  );
  test(
    'server-confirmed tombstone is not sent back as another deletion',
    () async {
      final id = await syncedEntry();
      await db.foodEntryDao.markDeleted(id);
      expect(await repo.watchPendingCount().first, 0);
      expect(await db.foodEntryDao.deletePendingEntries('u-1'), isEmpty);
      final pushes = remote.pushCount;
      await repo.retryPending();
      expect(remote.pushCount, pushes);
    },
  );
  test(
    'unknown create deleted locally remains pending without a server id',
    () async {
      remote.mode = FakeRemoteMode.offline;
      final entry = await repo.addEntry(
        RecordDraft(
          foodId: 'f-rice',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 10, 29),
          source: EntrySource.manual,
        ),
      );
      await repo.flushEntry(entry.localId);
      expect(
        (await db.foodEntryDao.getByLocalId(
          entry.localId,
        ))!.createRequestSnapshot,
        isNotNull,
      );
      await repo.deleteEntry(entry.localId);
      expect(await repo.watchPendingCount().first, 1);
      expect(
        (await db.foodEntryDao.deletePendingEntries('u-1')).single.serverId,
        isNull,
      );
      // A tombstone never sent to the server needs no upload.
      await db.foodEntryDao.updateEntry(
        entry.localId,
        const FoodEntriesCompanion(createRequestSnapshot: Value(null)),
      );
      expect(await repo.watchPendingCount().first, 0);
    },
  );
}
