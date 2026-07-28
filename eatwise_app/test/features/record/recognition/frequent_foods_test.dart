import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/recognition/data/frequent_foods.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';

/// 常吃聚合查询测试（PRD M3 常吃复用：历史高频 Top N）。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FrequentFoodsQuery query;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    db = AppDatabase.memory();
    await seedFoods(db);
    repository = RecordRepository(
      db: db,
      // 离线模式：不启动上行计时器，测试无需关心撤销窗。
      remote: FakeRecordRemote(mode: FakeRemoteMode.offline),
      location: tz.getLocation('Asia/Shanghai'),
    );
    query = FrequentFoodsQuery(db);
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  Future<void> log(String foodId, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await repository.addEntry(
        RecordDraft(
          foodId: foodId,
          amountG: 100,
          mealUtc: DateTime.now().toUtc(),
          source: EntrySource.manual,
        ),
      );
    }
  }

  test('按录入次数降序返回高频食物', () async {
    await log('f-rice', times: 3);
    await log('f-egg', times: 2);
    await log('f-chicken');
    final top = await query.topFrequent('anonymous');
    expect(top.map((f) => f.id), <String>['f-rice', 'f-egg', 'f-chicken']);
  });

  test('limit 截断 Top N', () async {
    await log('f-rice', times: 3);
    await log('f-egg', times: 2);
    await log('f-chicken');
    final top = await query.topFrequent('anonymous', limit: 2);
    expect(top.map((f) => f.id), <String>['f-rice', 'f-egg']);
  });

  test('已删除（撤销/tombstone）的记录不计入', () async {
    await log('f-chicken', times: 5);
    await log('f-rice', times: 2);
    // 撤销全部鸡胸肉记录（D-11 撤销窗内删除）。
    final entries = await repository.entriesForDate(DateTime.now().toUtc());
    for (final entry in entries.where((e) => e.foodId == 'f-chicken')) {
      await repository.undo(entry.localId);
    }
    final top = await query.topFrequent('anonymous');
    expect(top.map((f) => f.id), <String>['f-rice']);
  });

  test('其他用户的记录不计入；无历史时为空', () async {
    final otherRepo = RecordRepository(
      db: db,
      remote: FakeRecordRemote(mode: FakeRemoteMode.offline),
      location: tz.getLocation('Asia/Shanghai'),
      userId: 'someone-else',
    );
    await otherRepo.addEntry(
      RecordDraft(
        foodId: 'f-rice',
        amountG: 100,
        mealUtc: DateTime.now().toUtc(),
        source: EntrySource.manual,
      ),
    );
    expect(await query.topFrequent('anonymous'), isEmpty);
    expect((await query.topFrequent('someone-else')).single.id, 'f-rice');
  });
}
