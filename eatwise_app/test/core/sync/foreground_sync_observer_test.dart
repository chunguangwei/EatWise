import 'package:eatwise/core/sync/foreground_sync_observer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 前台回切同步触发器：resumed 触发 / 1 分钟节流 / 登录门控 / 非 resumed 忽略。
void main() {
  testWidgets('前台 pending 每 30 秒重试，恢复前台绕过普通节流', (tester) async {
    var syncs = 0;
    final observer = ForegroundSyncObserver(
      isLoggedIn: () => true,
      hasPending: () => true,
      triggerSync: () => syncs++,
    );
    addTearDown(observer.dispose);
    observer.updateConditions();
    expect(syncs, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(syncs, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(syncs, 2);
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(syncs, 2);
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 3);
    observer.dispose();
    await tester.pump();
  });

  testWidgets('清空、登出、销毁均取消重试；匿名 pending 不发送', (tester) async {
    var loggedIn = false;
    var pending = true;
    var syncs = 0;
    final observer = ForegroundSyncObserver(
      isLoggedIn: () => loggedIn,
      hasPending: () => pending,
      triggerSync: () => syncs++,
    );
    observer.updateConditions();
    await tester.pump(const Duration(minutes: 1));
    expect(syncs, 0);
    loggedIn = true;
    observer.updateConditions();
    expect(syncs, 1);
    pending = false;
    observer.updateConditions();
    await tester.pump(const Duration(minutes: 1));
    expect(syncs, 1);
    pending = true;
    observer.updateConditions();
    expect(syncs, 2);
    loggedIn = false;
    observer.updateConditions();
    await tester.pump(const Duration(minutes: 1));
    expect(syncs, 2);
    loggedIn = true;
    observer.updateConditions();
    expect(syncs, 3);
    observer.dispose();
    observer.updateConditions();
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 1));
    expect(syncs, 3);
  });

  testWidgets('后台启动不重试，pending 计数通知不重置 30 秒时钟', (tester) async {
    var syncs = 0;
    final observer = ForegroundSyncObserver(
      isLoggedIn: () => true,
      hasPending: () => true,
      initialState: AppLifecycleState.paused,
      triggerSync: () => syncs++,
    );
    addTearDown(observer.dispose);
    observer.updateConditions();
    await tester.pump(const Duration(minutes: 1));
    expect(syncs, 0);
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 1);
    await tester.pump(const Duration(seconds: 20));
    observer.updateConditions();
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(syncs, 2);
    observer.dispose();
    await tester.pump();
  });

  test('resumed 触发一轮同步；节流与登录门控', () {
    var now = DateTime(2026, 9, 30, 12);
    var syncs = 0;
    var loggedIn = true;
    final observer = ForegroundSyncObserver(
      isLoggedIn: () => loggedIn,
      triggerSync: () => syncs++,
      now: () => now,
    );

    // 首次回前台触发。
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 1);

    // 最小间隔内反复切前后台不重复触发。
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 1);

    // 超过最小间隔后再触发。
    now = now.add(
      ForegroundSyncObserver.minInterval + const Duration(seconds: 1),
    );
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 2);

    // 未登录不触发（与 main 冷启动触发块同口径）。
    loggedIn = false;
    now = now.add(const Duration(minutes: 2));
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(syncs, 2);

    // 非 resumed 状态不触发。
    observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
    observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(syncs, 2);
  });
}
