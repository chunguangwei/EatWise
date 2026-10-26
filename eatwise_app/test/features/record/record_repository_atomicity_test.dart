import 'dart:async';

import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/food_entry_dao.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

void main() {
  late _FaultInjectingDatabase db;
  late FakeRecordRemote remote;
  late DateTime now;

  final draft = RecordDraft(
    foodId: 'f-rice',
    amountG: 100,
    mealUtc: DateTime.utc(2026, 7, 28, 4),
    source: EntrySource.manual,
  );

  RecordRepository repository({
    Duration undoWindow = const Duration(seconds: 10),
  }) {
    final repo = RecordRepository(
      db: db,
      remote: remote,
      location: tz.getLocation('Asia/Shanghai'),
      undoWindow: undoWindow,
      clock: () => now,
    );
    addTearDown(repo.dispose);
    return repo;
  }

  setUpAll(initRecordTestTimeZones);

  setUp(() async {
    db = _FaultInjectingDatabase();
    await seedFoods(db);
    remote = FakeRecordRemote();
    now = DateTime.utc(2026, 7, 28, 4);
  });

  tearDown(() => db.close());

  test('聚合写入后失败回滚记录与缓存，用户重试只入账一次', () async {
    final repo = repository();
    db.entries.afterNextRecompute = () async {
      throw StateError('一次性聚合失败');
    };

    await expectLater(repo.addEntry(draft), throwsStateError);

    expect(await repo.entriesForDate(draft.mealUtc), isEmpty);
    expect(
      await db.entries.getDailyNutrition('anonymous', '2026-07-28'),
      isNull,
    );
    expect(remote.pushCount, 0);

    final saved = await repo.addEntry(draft);
    expect(await repo.entriesForDate(draft.mealUtc), [saved]);
    final daily = await db.entries.getDailyNutrition('anonymous', '2026-07-28');
    expect(daily!.entryCount, 1);
    expect(daily.kcal, 116);
  });

  test('最终回读失败同样回滚记录与缓存，重试不累加失败记录', () async {
    final repo = repository();
    db.entries.failNextRead = true;

    await expectLater(repo.addEntry(draft), throwsStateError);

    expect(await repo.entriesForDate(draft.mealUtc), isEmpty);
    expect(
      await db.entries.getDailyNutrition('anonymous', '2026-07-28'),
      isNull,
    );

    final saved = await repo.addEntry(draft);
    expect(await repo.entriesForDate(draft.mealUtc), [saved]);
    final daily = await db.entries.getDailyNutrition('anonymous', '2026-07-28');
    expect(daily!.entryCount, 1);
    expect(daily.kcal, 116);
  });

  test('聚合尚未完成时不得上行，本地提交成功后才启动上行', () async {
    final repo = repository(undoWindow: Duration.zero);
    final recomputeStarted = Completer<void>();
    final finishRecompute = Completer<void>();
    db.entries.afterNextRecompute = () async {
      recomputeStarted.complete();
      await finishRecompute.future;
    };

    final adding = repo.addEntry(draft);
    await recomputeStarted.future;
    // 让先前已排入事件队列的零时长上行 Timer 执行；不靠延时猜数据库速度。
    await Future<void>(() {});
    final pushesBeforeCommit = remote.pushCount;
    finishRecompute.complete();
    final saved = await adding;
    final synced = await db.entries
        .watchEntriesForDate('anonymous', '2026-07-28')
        .firstWhere(
          (entries) =>
              entries.length == 1 &&
              entries.single.syncStatus == SyncStatus.synced,
        );

    expect(pushesBeforeCommit, 0);
    expect(remote.pushCount, 1);
    expect(synced.single.localId, saved.localId);
  });

  for (final operation in ['edit', 'delete', 'undo']) {
    test('$operation 聚合失败时记录与缓存一起回滚，且不发送远程请求', () async {
      final repo = repository();
      final saved = await repo.addEntry(draft);
      db.entries.afterNextRecompute = () async {
        throw StateError('一次性聚合失败');
      };
      final Future<Object?> mutation;
      switch (operation) {
        case 'edit':
          mutation = repo.updateEntry(saved.localId, amountG: 200);
        case 'delete':
          mutation = repo.deleteEntry(saved.localId);
        default:
          mutation = repo.undo(saved.localId);
      }
      await expectLater(mutation, throwsStateError);
      final current = await db.entries.getByLocalId(saved.localId);
      expect(current, saved);
      final daily = (await db.entries.getDailyNutrition(
        'anonymous',
        '2026-07-28',
      ))!;
      expect(daily.entryCount, 1);
      expect(daily.kcal, 116);
      expect(remote.pushCount, 0);
      if (operation == 'undo') {
        expect(await repo.undo(saved.localId), isTrue);
      }
    });
  }

  for (final online in [true, false]) {
    test('${online ? '在线' : '离线'}慢写入完成后仍享有完整撤销窗', () async {
      if (!online) remote.mode = FakeRemoteMode.offline;
      final repo = repository();
      db.entries.afterNextRecompute = () async {
        // 模拟本地写入跨过 10 秒撤销窗口，避免真实等待。
        now = now.add(const Duration(seconds: 11));
      };

      final saved = await repo.addEntry(draft);

      expect(await repo.undo(saved.localId), isTrue);
      expect(await repo.entriesForDate(draft.mealUtc), isEmpty);
      expect(remote.pushCount, 0);
    });
  }
}

// 写入、聚合和查询都落真实 SQLite；只在指定的一次 DAO 调用后失败或等待。
class _FaultInjectingDatabase extends AppDatabase {
  _FaultInjectingDatabase() : super(NativeDatabase.memory());

  late final _FaultInjectingEntryDao entries = _FaultInjectingEntryDao(this);

  @override
  FoodEntryDao get foodEntryDao => entries;
}

class _FaultInjectingEntryDao extends FoodEntryDao {
  _FaultInjectingEntryDao(super.db);

  Future<void> Function()? afterNextRecompute;
  bool failNextRead = false;

  @override
  Future<void> recomputeDailyNutrition(
    String userId,
    String localDate, {
    required String updatedAtUtc,
  }) async {
    await super.recomputeDailyNutrition(
      userId,
      localDate,
      updatedAtUtc: updatedAtUtc,
    );
    final afterRecompute = afterNextRecompute;
    afterNextRecompute = null;
    if (afterRecompute != null) await afterRecompute();
  }

  @override
  Future<FoodEntry?> getByLocalId(String localId) async {
    final entry = await super.getByLocalId(localId);
    if (failNextRead) {
      failNextRead = false;
      throw StateError('一次性回读失败');
    }
    return entry;
  }
}
