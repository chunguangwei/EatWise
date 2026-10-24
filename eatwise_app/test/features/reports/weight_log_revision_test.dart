import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/time/day_change.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart'
    show nutritionGoalProvider;
import 'package:eatwise/features/fasting/presentation/plan_progress_bar.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _WeightSource implements ReportsDataSource {
  _WeightSource(this.store);

  final WeightLogStore store;
  int weightReads = 0;

  @override
  Future<List<DailyNutritionCache>> nutritionRange(
    String from,
    String to,
  ) async => const <DailyNutritionCache>[];

  @override
  Future<List<FastingRecord>> fastingRange(String from, String to) async =>
      const <FastingRecord>[];

  @override
  Future<List<FastingRecord>> fastingAll() async => const <FastingRecord>[];

  @override
  Future<Map<String, double>> weightRange(String from, String to) {
    weightReads += 1;
    return Future<Map<String, double>>.value(store.loadRange(from, to));
  }
}

const _goal = NutritionGoal(
  bmr: null,
  tdee: null,
  targetKcal: 2000,
  proteinG: 100,
  carbG: 200,
  fatG: 60,
  usedFallback: false,
  configVersion: 'test',
);

void main() {
  test('保存、删除、远端合并与 tombstone 实际变更后递增 revision', () async {
    final store = WeightLogStore.inMemory();
    final events = <int>[];
    final subscription = store.changes.listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await store.close();
    });

    await store.save('2026-07-27', 65.0);
    expect(store.revision, 1);
    expect(await store.remove('2026-07-27'), isTrue);
    expect(store.revision, 2);

    final remote =
        <
          ({
            String date,
            double kg,
            double? bodyFatPct,
            String updatedAtUtc,
            String? serverId,
          })
        >[
          (
            date: '2026-07-28',
            kg: 64.5,
            bodyFatPct: null,
            updatedAtUtc: '2026-07-28T01:00:00.000Z',
            serverId: 'srv-1',
          ),
        ];
    await store.mergeRemote(remote);
    expect(store.revision, 3);
    await store.mergeRemote(remote);
    expect(store.revision, 3, reason: '重复下行没有实际变化，不重复通知');

    await store.mergeRemote(
      const <
        ({
          String date,
          double kg,
          double? bodyFatPct,
          String updatedAtUtc,
          String? serverId,
        })
      >[],
      tombstones: const <({String id, String date})>[
        (id: 'srv-1', date: '2026-07-28'),
      ],
    );
    expect(store.revision, 4);
    expect(store.recordCount(), 0);
    expect(events, <int>[1, 2, 3, 4]);
  });

  test('已打开的趋势、上周小结和月报随下行 revision 自动重取', () async {
    final store = WeightLogStore.inMemory();
    final source = _WeightSource(store);
    final container = ProviderContainer(
      overrides: <Override>[
        reportsNowProvider.overrideWithValue(DateTime(2026, 7, 28, 14)),
        reportsDataSourceProvider.overrideWithValue(source),
        weightLogStoreProvider.overrideWithValue(store),
        nutritionGoalProvider.overrideWithValue(_goal),
      ],
    );
    final reportSubscription = container.listen(
      reportWeightProvider,
      (_, _) {},
    );
    final weeklySubscription = container.listen(
      weeklySummaryProvider,
      (_, _) {},
    );
    final monthlySubscription = container.listen(
      monthlyReportProvider,
      (_, _) {},
    );
    addTearDown(() async {
      reportSubscription.close();
      weeklySubscription.close();
      monthlySubscription.close();
      container.dispose();
      await store.close();
    });

    await container.read(reportWeightProvider.future);
    await container.read(weeklySummaryProvider.future);
    await container.read(monthlyReportProvider.future);
    final readsBefore = source.weightReads;

    await store.mergeRemote(<
      ({
        String date,
        double kg,
        double? bodyFatPct,
        String updatedAtUtc,
        String? serverId,
      })
    >[
      (
        date: '2026-07-28',
        kg: 63.8,
        bodyFatPct: null,
        updatedAtUtc: '2026-07-28T02:00:00.000Z',
        serverId: 'srv-new',
      ),
    ]);

    var latest =
        container.read(reportWeightProvider).valueOrNull ??
        const <String, double>{};
    for (
      var i = 0;
      i < 50 &&
          (latest['2026-07-28'] != 63.8 ||
              source.weightReads < readsBefore + 3);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      latest =
          container.read(reportWeightProvider).valueOrNull ??
          const <String, double>{};
    }
    expect(latest['2026-07-28'], 63.8);
    expect(
      source.weightReads,
      greaterThanOrEqualTo(readsBefore + 3),
      reason: '趋势、上周小结、月报各自因同源 revision 重取一次',
    );
  });

  testWidgets('首页 latest/earliest 在页面打开后随同源 revision 刷新', (tester) async {
    final now = DateTime(2026, 7, 28, 12);
    final store = WeightLogStore.inMemory();
    final container = ProviderContainer(
      overrides: <Override>[
        localDayClockProvider.overrideWithValue(() => now),
        weightLogStoreProvider.overrideWithValue(store),
      ],
    );
    var disposed = false;
    Future<void> disposeResources() async {
      if (disposed) return;
      disposed = true;
      container.dispose();
      await store.close();
    }

    addTearDown(disposeResources);
    container.listen(latestWeightLogProvider, (_, _) {});
    container.listen(earliestWeightLogUtcProvider, (_, _) {});
    expect(await container.read(latestWeightLogProvider.future), isNull);
    expect(await container.read(earliestWeightLogUtcProvider.future), isNull);

    await store.save('2026-07-28', 65.0);
    await tester.pump();
    await tester.pump();
    expect(container.read(latestWeightLogProvider).valueOrNull, 65.0);
    expect(
      container.read(earliestWeightLogUtcProvider).valueOrNull,
      DateTime.parse('2026-07-28').millisecondsSinceEpoch ~/ 1000,
    );

    await store.mergeRemote(<
      ({
        String date,
        double kg,
        double? bodyFatPct,
        String updatedAtUtc,
        String? serverId,
      })
    >[
      (
        date: '2026-07-27',
        kg: 66.0,
        bodyFatPct: null,
        updatedAtUtc: '2026-07-27T02:00:00.000Z',
        serverId: 'srv-earlier',
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(container.read(latestWeightLogProvider).valueOrNull, 65.0);
    expect(
      container.read(earliestWeightLogUtcProvider).valueOrNull,
      DateTime.parse('2026-07-27').millisecondsSinceEpoch ~/ 1000,
    );

    await disposeResources();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
