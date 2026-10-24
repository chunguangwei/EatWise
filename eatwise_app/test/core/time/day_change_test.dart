import 'package:eatwise/core/time/day_change.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('跨午夜只通知新日期，dispose 后无 pending timer', (tester) async {
    var now = DateTime(2026, 10, 24, 23, 59, 59);
    final container = ProviderContainer(
      overrides: <Override>[localDayClockProvider.overrideWithValue(() => now)],
    );
    var disposed = false;
    void disposeContainer() {
      if (disposed) return;
      disposed = true;
      container.dispose();
    }

    addTearDown(disposeContainer);
    final emitted = <DateTime>[];
    final subscription = container.listen(
      localDayProvider,
      (_, next) => emitted.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(container.read(localDayProvider), DateTime(2026, 10, 24));

    now = DateTime(2026, 10, 25, 0, 0, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(container.read(localDayProvider), DateTime(2026, 10, 25));
    expect(emitted, <DateTime>[DateTime(2026, 10, 24), DateTime(2026, 10, 25)]);

    disposeContainer();
    await tester.pump(const Duration(days: 2));
  });

  testWidgets('回前台立即滚到新今天，不受登录态或同步节流影响', (tester) async {
    var now = DateTime(2026, 10, 24, 23, 30);
    final container = ProviderContainer(
      overrides: <Override>[localDayClockProvider.overrideWithValue(() => now)],
    );
    var disposed = false;
    void disposeContainer() {
      if (disposed) return;
      disposed = true;
      container.dispose();
    }

    addTearDown(disposeContainer);
    expect(container.read(localDayProvider), DateTime(2026, 10, 24));

    now = DateTime(2026, 10, 25, 8);
    container
        .read(localDayProvider.notifier)
        .didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();

    expect(container.read(localDayProvider), DateTime(2026, 10, 25));
    expect(container.read(reportsNowProvider), now);
    expect(container.read(reportWindowProvider).to, '2026-10-25');

    disposeContainer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('选中日只在原选旧今天时跟随，不抢手动历史日期', (tester) async {
    var now = DateTime(2026, 10, 24, 23, 30);
    final container = ProviderContainer(
      overrides: <Override>[localDayClockProvider.overrideWithValue(() => now)],
    );
    var disposed = false;
    void disposeContainer() {
      if (disposed) return;
      disposed = true;
      container.dispose();
    }

    addTearDown(disposeContainer);
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 24));

    container.read(selectedDateProvider.notifier).prevDay();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 23));
    now = DateTime(2026, 10, 25, 0, 10);
    container.read(localDayProvider.notifier).refresh();
    await tester.pump();
    expect(
      container.read(selectedDateProvider),
      DateTime(2026, 10, 23),
      reason: '用户手动查看的历史日保持不动',
    );

    container.read(selectedDateProvider.notifier).backToToday();
    expect(container.read(selectedDateProvider), DateTime(2026, 10, 25));
    now = DateTime(2026, 10, 26, 7);
    container.read(localDayProvider.notifier).refresh();
    await tester.pump();
    expect(
      container.read(selectedDateProvider),
      DateTime(2026, 10, 26),
      reason: '选中日原本是旧今天，跨日后继续跟随新今天',
    );

    disposeContainer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
