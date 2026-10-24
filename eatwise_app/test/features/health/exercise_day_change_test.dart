import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/time/day_change.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('运动消耗、步数和今日列表随本地日变化切换查询', (tester) async {
    final db = AppDatabase.memory();
    var now = DateTime(2026, 10, 24, 23, 30);
    final repository = ExerciseLogRepository(db: db, clock: () => now);
    final container = ProviderContainer(
      overrides: <Override>[
        localDayClockProvider.overrideWithValue(() => now),
        exerciseLogRepositoryProvider.overrideWithValue(repository),
      ],
    );
    var disposed = false;
    Future<void> disposeResources() async {
      if (disposed) return;
      disposed = true;
      container.dispose();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await db.close();
    }

    addTearDown(disposeResources);

    await repository.add(
      typeKey: 'walk',
      durationMin: 20,
      kcal: 100,
      steps: 500,
    );
    expect(await container.read(todayExerciseKcalProvider.future), 100);
    expect(await container.read(todayExerciseStepsProvider.future), 500);
    expect(
      (await container.read(todayExerciseLogsProvider.future)).single.kcal,
      100,
    );

    now = DateTime(2026, 10, 25, 8);
    await repository.add(
      typeKey: 'walk',
      durationMin: 30,
      kcal: 200,
      steps: 800,
    );
    container.read(localDayProvider.notifier).refresh();
    await tester.pump();

    expect(await container.read(todayExerciseKcalProvider.future), 200);
    expect(await container.read(todayExerciseStepsProvider.future), 800);
    final logs = await container.read(todayExerciseLogsProvider.future);
    expect(logs.single.kcal, 200);
    expect(logs.single.localDate, '2026-10-25');

    await disposeResources();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
