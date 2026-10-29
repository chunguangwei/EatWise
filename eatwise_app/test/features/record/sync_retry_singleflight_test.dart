import 'dart:async';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/data/record_sync_engine.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

final class _Remote implements RecordRemote {
  @override
  bool isOnline = false;
  final entered = Completer<void>();
  final gate = Completer<void>();
  var pushes = 0;
  bool fail = false;
  bool retryable = false;
  @override
  Future<PushOutcome> push(FoodEntry entry) async {
    pushes++;
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    if (fail) throw const NetworkApiException();
    if (retryable) return const PushRetryable('NETWORK_ERROR');
    return PushAck(
      serverId: 'server-1',
      serverVersion: 1,
      serverUpdatedAtUtc: DateTime.utc(2026, 10, 29).toIso8601String(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(AppDatabase, RecordRepository, RecordSyncEngine, _Remote)>
  setup() async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.memory();
    await seedFoods(db);
    final remote = _Remote();
    final repo = RecordRepository(
      db: db,
      remote: remote,
      location: tz.UTC,
      userId: 'u-1',
    );
    final engine = RecordSyncEngine(
      repository: repo,
      prefs: await SharedPreferences.getInstance(),
    );
    addTearDown(() async {
      engine.dispose();
      await repo.dispose();
      await db.close();
    });
    await repo.addEntry(
      RecordDraft(
        foodId: 'f-rice',
        amountG: 100,
        mealUtc: DateTime.utc(2026, 10, 29),
        source: EntrySource.manual,
      ),
    );
    remote.isOnline = true;
    return (db, repo, engine, remote);
  }

  test(
    'manual caller joins an in-flight retry and waits for the real upload',
    () async {
      final (_, _, engine, remote) = await setup();
      final first = engine.syncNow();
      await remote.entered.future;
      var completed = false;
      final second = engine.syncNow().then((_) {
        completed = true;
      });
      await Future<void>.value();
      await Future<void>.value();
      final premature = completed;
      remote.gate.complete();
      await Future.wait([first, second]);
      expect(premature, isFalse);
      expect(remote.pushes, 1);
    },
  );
  test(
    'same live engine uploads pending data after network recovery without restart',
    () async {
      final (db, _, engine, remote) = await setup();
      remote.retryable = true;
      remote.gate.complete();
      await engine.syncNow();
      expect(
        (await db.select(db.foodEntries).get()).single.syncStatus,
        SyncStatus.pending,
      );
      remote.retryable = false;
      await engine.syncNow();
      expect(
        (await db.select(db.foodEntries).get()).single.syncStatus,
        SyncStatus.synced,
      );
      expect(remote.pushes, 2);
    },
  );
  test(
    'manual retry surfaces network failure while automatic callers remain safe',
    () async {
      final (_, _, engine, remote) = await setup();
      remote.fail = true;
      remote.gate.complete();
      await expectLater(
        engine.syncNow(propagateErrors: true),
        throwsA(isA<NetworkApiException>()),
      );
      await engine.syncNow();
      expect(remote.pushes, 2);
    },
  );
}
