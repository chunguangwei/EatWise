import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// WaterLog DAO 测试（PRD M3 功能点 4）：入账 / 当日累计 / D-11 撤销。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
    addTearDown(() async => db.close());
  });

  WaterLogsCompanion log({
    required String localId,
    String userId = 'anonymous',
    required int amountMl,
    String datetimeUtc = '2026-07-29T01:00:00.000Z',
    String localDate = '2026-07-29',
  }) {
    return WaterLogsCompanion(
      localId: Value(localId),
      userId: Value(userId),
      amountMl: Value(amountMl),
      datetimeUtc: Value(datetimeUtc),
      localDate: Value(localDate),
      createdAtUtc: Value(datetimeUtc),
    );
  }

  test('入账：insertLog 后可按主键取回', () async {
    await db.waterLogDao.insertLog(log(localId: 'w-1', amountMl: 200));
    final stored = await db.waterLogDao.getByLocalId('w-1');
    expect(stored, isNotNull);
    expect(stored!.amountMl, 200);
    expect(stored.localDate, '2026-07-29');
  });

  test('当日累计：按用户 + 归属日聚合，他日/他人不计入', () async {
    await db.waterLogDao.insertLog(log(localId: 'w-1', amountMl: 200));
    await db.waterLogDao.insertLog(
      log(localId: 'w-2', amountMl: 500, datetimeUtc: '2026-07-29T02:00:00Z'),
    );
    await db.waterLogDao.insertLog(
      log(localId: 'w-3', amountMl: 300, localDate: '2026-07-28'),
    );
    await db.waterLogDao.insertLog(
      log(localId: 'w-4', amountMl: 999, userId: 'u-other'),
    );

    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-29'), 700);
    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-28'), 300);
    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-30'), 0);

    final logs = await db.waterLogDao.logsForDate('anonymous', '2026-07-29');
    expect(logs.map((e) => e.localId), <String>['w-1', 'w-2']);
  });

  test('当日累计流：入账后实时刷新（乐观更新）', () async {
    final seen = <int>[];
    final sub = db.waterLogDao
        .watchTotalForDate('anonymous', '2026-07-29')
        .listen(seen.add);
    await pumpEventQueue();
    await db.waterLogDao.insertLog(log(localId: 'w-1', amountMl: 200));
    await pumpEventQueue();
    expect(seen, <int>[0, 200]);
    await sub.cancel();
  });

  test('撤销：deleteLog 物理删除，累计回落；不存在返回 0', () async {
    await db.waterLogDao.insertLog(log(localId: 'w-1', amountMl: 200));
    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-29'), 200);

    expect(await db.waterLogDao.deleteLog('w-1'), 1);
    expect(await db.waterLogDao.totalForDate('anonymous', '2026-07-29'), 0);
    expect(await db.waterLogDao.getByLocalId('w-1'), isNull);

    expect(await db.waterLogDao.deleteLog('w-ghost'), 0);
  });
}
