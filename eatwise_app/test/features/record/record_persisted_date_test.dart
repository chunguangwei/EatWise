import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

void main() {
  late AppDatabase db;
  late tz.Location current;
  late RecordRepository repository;
  RecordDraft draft() => RecordDraft(
    foodId: 'f-rice',
    amountG: 100,
    mealUtc: DateTime.utc(2026, 7, 28, 1),
    source: EntrySource.manual,
  );
  setUpAll(initRecordTestTimeZones);
  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    current = tz.getLocation('Asia/Shanghai');
    repository = RecordRepository(
      db: db,
      userId: 'u-1',
      remote: FakeRecordRemote(mode: FakeRemoteMode.offline),
      location: current,
      locationResolver: () => current,
    );
  });
  tearDown(() async {
    await repository.dispose();
    await db.close();
  });

  test('旅行换区后撤销按记录持久localDate清空原聚合，不留下旧日热量', () async {
    final entry = await repository.addEntry(draft());
    expect(
      (await db.foodEntryDao.getDailyNutrition('u-1', '2026-07-28'))!.kcal,
      116,
    );
    current = tz.getLocation('America/New_York');
    expect(await repository.undo(entry.localId), isTrue);
    final original = await db.foodEntryDao.getDailyNutrition(
      'u-1',
      '2026-07-28',
    );
    expect(original!.entryCount, 0);
    expect(original.kcal, 0);
    expect(
      await db.foodEntryDao.getDailyNutrition('u-1', '2026-07-27'),
      isNull,
    );
  });

  test('旅行换区后编辑及删除均重算记录原归属日', () async {
    final entry = await repository.addEntry(draft());
    current = tz.getLocation('America/New_York');
    await repository.updateEntry(entry.localId, amountG: 200);
    expect(
      (await db.foodEntryDao.getDailyNutrition('u-1', '2026-07-28'))!.kcal,
      232,
    );
    await repository.deleteEntry(entry.localId);
    expect(
      (await db.foodEntryDao.getDailyNutrition('u-1', '2026-07-28'))!.kcal,
      0,
    );
    expect(
      await db.foodEntryDao.getDailyNutrition('u-1', '2026-07-27'),
      isNull,
    );
  });

  test('一次入账只读取一次设备时区，localDate餐次和聚合使用同一归属', () async {
    var calls = 0;
    final changing = RecordRepository(
      db: db,
      userId: 'u-1',
      remote: FakeRecordRemote(mode: FakeRemoteMode.offline),
      location: current,
      locationResolver: () => ++calls == 1
          ? tz.getLocation('Asia/Shanghai')
          : tz.getLocation('America/New_York'),
    );
    addTearDown(changing.dispose);
    final entry = await changing.addEntry(draft());
    expect(entry.localDate, '2026-07-28');
    expect(entry.mealType, MealType.breakfast);
    expect(
      (await db.foodEntryDao.getDailyNutrition('u-1', entry.localDate))!.kcal,
      116,
    );
    expect(calls, 1);
  });
}
