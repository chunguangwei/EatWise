import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手动记运动仓储测试（设备级纯本地）：入账 / 今日列表 / 今日合计 / 删除
/// （D-11 撤销同一入口）。
void main() {
  late AppDatabase db;
  late ExerciseLogRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    repo = ExerciseLogRepository(
      db: db,
      clock: () => DateTime.utc(2026, 9, 19, 10),
    );
    addTearDown(() async => db.close());
  });

  test('入账：add 后按主键取回，字段为入账快照', () async {
    final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
    final stored = await db.exerciseLogDao.getByLocalId(log.localId);
    expect(stored, isNotNull);
    expect(stored!.typeKey, 'jog');
    expect(stored.durationMin, 30);
    expect(stored.kcal, 210);
    expect(stored.userId, 'anonymous');
    expect(stored.localDate, '2026-09-19');
  });

  test('入账校验：时长为负 / 热量 ≤ 0 抛 ArgumentError（时长 0 合法：截图汇总导入）', () async {
    expect(
      () => repo.add(typeKey: 'jog', durationMin: -1, kcal: 100),
      throwsArgumentError,
    );
    expect(
      () => repo.add(typeKey: 'jog', durationMin: 30, kcal: 0),
      throwsArgumentError,
    );
    // 时长 0（截图活动统计导入无时长口径）+ 来源标记。
    final imported = await repo.add(
      typeKey: 'summary',
      durationMin: 0,
      kcal: 320,
      source: ExerciseLogRepository.sourceScreenshot,
    );
    expect(imported.durationMin, 0);
    expect(imported.source, 'screenshot');
  });

  test('今日合计：多条叠加，他日/他人不计入', () async {
    await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
    await repo.add(typeKey: 'yoga', durationMin: 40, kcal: 120);
    // 他日记录（直接走 DAO 落历史日期）。
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion.insert(
        localId: 'x-old',
        userId: 'anonymous',
        typeKey: 'walk',
        durationMin: 60,
        kcal: 200,
        localDate: '2026-09-18',
        createdAtUtc: '2026-09-18T10:00:00.000Z',
      ),
    );
    // 他人记录。
    await db.exerciseLogDao.insertLog(
      ExerciseLogsCompanion.insert(
        localId: 'x-other',
        userId: 'u-other',
        typeKey: 'walk',
        durationMin: 60,
        kcal: 999,
        localDate: '2026-09-19',
        createdAtUtc: '2026-09-19T09:00:00.000Z',
      ),
    );

    expect(await repo.totalKcalForDate('2026-09-19'), 330);
    expect(await repo.totalKcalForDate('2026-09-18'), 200);
    expect(await repo.totalKcalForDate('2026-09-20'), 0);

    final logs = await repo.logsForDate('2026-09-19');
    expect(logs, hasLength(2));
    expect(logs.map((e) => e.typeKey), <String>['jog', 'yoga']);
  });

  test('合计流：入账后实时刷新（乐观更新）', () async {
    final seen = <double>[];
    final sub = repo.watchTotalKcalForDate('2026-09-19').listen(seen.add);
    await pumpEventQueue();
    await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
    await pumpEventQueue();
    expect(seen, <double>[0, 210]);
    await sub.cancel();
  });

  test('删除（D-11 撤销同一入口）：物理删除，合计回落；不存在返回 false', () async {
    final log = await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
    expect(await repo.totalKcalForDate('2026-09-19'), 210);

    expect(await repo.delete(log.localId), isTrue);
    expect(await repo.totalKcalForDate('2026-09-19'), 0);
    expect(await db.exerciseLogDao.getByLocalId(log.localId), isNull);

    expect(await repo.delete('ghost'), isFalse);
  });

  test('步数快照：随记录落库，当日合计流聚合（步数持久化）', () async {
    final log = await repo.add(
      typeKey: 'walk',
      durationMin: 0,
      kcal: 68,
      steps: 1466,
    );
    expect(log.steps, 1466);

    // 无步数记录不计入步数合计；步数 ≤ 0 拒绝。
    await repo.add(typeKey: 'jog', durationMin: 30, kcal: 210);
    expect(
      () => repo.add(typeKey: 'walk', durationMin: 0, kcal: 50, steps: 0),
      throwsArgumentError,
    );

    final seen = <int>[];
    final sub = repo.watchTotalStepsForDate('2026-09-19').listen(seen.add);
    await pumpEventQueue();
    expect(seen, <int>[1466]);
    await sub.cancel();

    // 删除后步数合计回落。
    expect(await repo.delete(log.localId), isTrue);
    expect(await repo.watchTotalStepsForDate('2026-09-19').first, 0);
  });
}
