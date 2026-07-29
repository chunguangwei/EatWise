import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 体重日志端口测试（PRD M3 功能点 4）：写入 / 同日覆写取最新 /
/// M6 趋势（DriftReportsDataSource.weightRange）直接读到新数据。
void main() {
  late SharedPreferences prefs;
  late WeightLogStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    store = WeightLogStore(prefs);
  });

  test('写入：save 后 loadRange 可读（含端点，区间外排除）', () async {
    await store.save('2026-07-27', 65.5);
    await store.save('2026-07-29', 64.8);

    final range = store.loadRange('2026-07-27', '2026-07-28');
    expect(range, <String, double>{'2026-07-27': 65.5});
    expect(store.loadRange('2026-07-27', '2026-07-29').length, 2);
  });

  test('同日重复记录取最新（覆写）', () async {
    await store.save('2026-07-29', 70.0);
    await store.save('2026-07-29', 70.6);

    expect(store.loadRange('2026-07-29', '2026-07-29'), <String, double>{
      '2026-07-29': 70.6,
    });
  });

  test('内存兜底实现与 SharedPreferences 实现行为一致', () async {
    final memory = WeightLogStore.inMemory();
    await memory.save('2026-07-29', 65.4);
    expect(memory.loadRange('2026-07-29', '2026-07-29'), <String, double>{
      '2026-07-29': 65.4,
    });
  });

  test('联测：录入写入后 M6 趋势聚合（weightRange）直接读到', () async {
    final db = AppDatabase.memory();
    addTearDown(() async => db.close());
    final dataSource = DriftReportsDataSource(db, store, userId: 'anonymous');

    // 录入入口写入端口 → M6 趋势数据源立即可读。
    await store.save('2026-07-28', 65.5);
    await store.save('2026-07-29', 65.0);

    final trend = await dataSource.weightRange('2026-07-28', '2026-07-29');
    expect(trend, <String, double>{'2026-07-28': 65.5, '2026-07-29': 65.0});

    // 同日覆写后趋势同样取最新。
    await store.save('2026-07-29', 64.6);
    final updated = await dataSource.weightRange('2026-07-28', '2026-07-29');
    expect(updated['2026-07-29'], 64.6);
  });
}
