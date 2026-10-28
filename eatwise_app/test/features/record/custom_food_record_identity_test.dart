import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

class _TransactionGateDatabase extends AppDatabase {
  _TransactionGateDatabase() : super(NativeDatabase.memory());
  bool delayNextTransaction = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    if (delayNextTransaction) {
      delayNextTransaction = false;
      entered.complete();
      await release.future;
    }
    return super.transaction(action, requireNew: requireNew);
  }
}

void main() {
  late _TransactionGateDatabase db;
  late RecordRepository repository;
  RecordDraft draft(String id) => RecordDraft(
    foodId: id,
    amountG: 100,
    mealUtc: DateTime.utc(2026, 10, 28, 4),
    source: EntrySource.manual,
  );

  setUp(() async {
    db = _TransactionGateDatabase();
    await db.foodDao.upsertAll([
      FoodsCompanion.insert(
        id: 'custom-original',
        nameZh: '自制食品',
        nameEn: 'Custom',
        kcalPer100g: 200,
        proteinPer100g: 5,
        carbPer100g: 10,
        fatPer100g: 2,
        isCustom: const Value(true),
        ownerUserId: const Value('user-1'),
        customOriginLocalId: const Value('custom-original'),
      ),
    ]);
    repository = RecordRepository(
      db: db,
      remote: FakeRecordRemote(mode: FakeRemoteMode.offline),
      location: tz.UTC,
      userId: 'user-1',
    );
  });
  tearDown(() async {
    await repository.dispose();
    await db.close();
  });

  test('入账事务开始前createACK remap完成，解析最终食品id后插入并聚合', () async {
    db.delayNextTransaction = true;
    final saving = repository.addEntry(draft('custom-original'));
    await db.entered.future;
    await db.foodDao.remapCustomFoodId(
      'custom-original',
      'server-1',
      ownerUserId: 'user-1',
    );
    db.release.complete();
    final entry = await saving;
    expect(entry.foodId, 'server-1');
    expect(entry.kcal, 200);
    expect(await db.foodDao.getById(entry.foodId), isNotNull);
    expect(
      (await db.foodEntryDao.entriesForDate(
        'user-1',
        '2026-10-28',
      )).single.foodId,
      'server-1',
    );
  });

  test('旧详情持有临时id在remap后仍可入账，使用当前食品营养快照', () async {
    await db.foodDao.remapCustomFoodId(
      'custom-original',
      'server-1',
      ownerUserId: 'user-1',
    );
    final food = (await db.foodDao.getById('server-1'))!;
    await db.foodDao.upsertAll([
      food.toCompanion(false).copyWith(kcalPer100g: const Value(300)),
    ]);
    final entry = await repository.addEntry(draft('custom-original'));
    expect(entry.foodId, 'server-1');
    expect(entry.kcal, 300);
  });

  test('临时身份解析不得跨owner访问其他账号食品', () async {
    await db.foodDao.remapCustomFoodId(
      'custom-original',
      'server-1',
      ownerUserId: 'user-1',
    );
    final other = RecordRepository(
      db: db,
      remote: FakeRecordRemote(mode: FakeRemoteMode.offline),
      location: tz.UTC,
      userId: 'user-2',
    );
    addTearDown(other.dispose);
    await expectLater(
      other.addEntry(draft('custom-original')),
      throwsArgumentError,
    );
    expect(
      await db.foodEntryDao.entriesForDate('user-2', '2026-10-28'),
      isEmpty,
    );
  });
}
