import 'package:eatwise/core/sync/foreground_sync_observer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 前台回切同步触发器：resumed 触发 / 1 分钟节流 / 登录门控 / 非 resumed 忽略。
void main() {
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
