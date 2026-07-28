import 'dart:async';

import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_scheduler.dart';
import 'package:eatwise/features/fasting/application/fasting_system_events.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../tz_test_helper.dart';

/// FastingNotificationScheduler 测试（《规格-M2》§7.2：单一 reschedule 入口、
/// 先 cancelAll 再重建、权限拒绝降级）。
void main() {
  const plan = FastingPlan.plan16x8;
  const channel = NotificationChannelConfig(id: 'fasting_reminders', name: 'T');
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  int utc(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 7, day, hour, minute).millisecondsSinceEpoch ~/ 1000;

  FastingNotificationScheduler buildScheduler(
    FakeNotificationService service, {
    required tz.Location Function() locationResolver,
    int Function()? nowUtcSec,
  }) {
    return FastingNotificationScheduler(
      notifications: service,
      textResolver: (n) => (title: 'T', body: n.kind.name),
      channel: channel,
      locationResolver: locationResolver,
      nowUtcSec: nowUtcSec ?? () => utc(28, 0),
    );
  }

  group('reschedule 调用序列与排程', () {
    test('先 cancelAll 再按序排程（§7.2.5），文案经 resolver 注入', () async {
      final service = FakeNotificationService();
      final scheduler = buildScheduler(service, locationResolver: () => bjt);

      final result = await scheduler.reschedule(plan: plan);

      expect(service.calls.first, 'cancelAll');
      expect(service.calls[1], 'permissionStatus');
      expect(
        service.calls.sublist(2),
        List.filled(6, 'scheduleZoned'),
      ); // 48h 窗口 6 条
      expect(result.degraded, isFalse);
      expect(result.scheduledCount, 6);
      // 触发时刻与计划一致且升序
      expect(service.scheduled.map((e) => e.triggerAtUtcSec).toList(), [
        utc(28, 3, 45),
        utc(28, 4),
        utc(28, 12),
        utc(29, 3, 45),
        utc(29, 4),
        utc(29, 12),
      ]);
      // 文案走 resolver（i18n 适配层），渠道透传
      expect(service.scheduled.first.title, 'T');
      expect(service.scheduled.first.body, 'eatSoon');
      expect(service.scheduled.first.channel, channel);
      expect(service.scheduled.first.id, result.plan.first.id);
    });

    test('时区变化：先 cancelAll 再按新时区重建（T14，D-09）', () async {
      final service = FakeNotificationService();
      var location = bjt;
      final scheduler = buildScheduler(
        service,
        locationResolver: () => location,
      );

      await scheduler.reschedule(plan: plan);
      final bjtTriggers = service.scheduled
          .map((e) => e.triggerAtUtcSec)
          .toList();

      // 北京 → 纽约（§6-B8 飞行场景）：UTC 锚点语义不变，触发时刻按新时区墙钟
      location = tz.getLocation('America/New_York');
      await scheduler.reschedule(
        plan: plan,
        reason: RescheduleReason.timezoneChange,
      );
      final nyTriggers = service.scheduled
          .map((e) => e.triggerAtUtcSec)
          .toList();

      expect(service.calls.where((c) => c == 'cancelAll'), hasLength(2));
      expect(nyTriggers, isNot(bjtTriggers)); // 触发时刻已按新时区重建
      // now = utc(28, 0) = 纽约 d-1 20:00 EDT → 之后第一个进食开始 = 纽约 d 12:00
      expect(nyTriggers.first, utc(28, 15, 45));
      expect(nyTriggers[1], utc(28, 16));
    });

    test('延长后重排：当前周期锚点后移 30min（T5/T6）', () async {
      final service = FakeNotificationService();
      final scheduler = buildScheduler(service, locationResolver: () => bjt);

      final result = await scheduler.reschedule(
        plan: plan,
        extensionMinutes: 30,
        reason: RescheduleReason.extensionApplied,
      );

      expect(result.reason, RescheduleReason.extensionApplied);
      expect(service.scheduled[0].triggerAtUtcSec, utc(28, 4, 15)); // eatSoon
      expect(service.scheduled[1].triggerAtUtcSec, utc(28, 4, 30)); // eatStart
      expect(service.scheduled[2].triggerAtUtcSec, utc(28, 12, 30)); // fastEnd
    });
  });

  group('降级路径（合规 §3：权限拒绝不阻断计时）', () {
    test('权限拒绝：不排程、不抛异常，返回降级标志', () async {
      final service = FakeNotificationService()
        ..status = NotificationPermissionStatus.denied;
      final scheduler = buildScheduler(service, locationResolver: () => bjt);

      final result = await scheduler.reschedule(plan: plan);

      expect(result.degraded, isTrue);
      expect(result.permissionStatus, NotificationPermissionStatus.denied);
      expect(result.scheduledCount, 0);
      expect(service.scheduled, isEmpty);
      // cancelAll 仍执行（清理旧排程），但无 scheduleZoned
      expect(service.calls, ['cancelAll', 'permissionStatus']);
    });

    test('NO_PLAN：仅清空，不算降级', () async {
      final service = FakeNotificationService();
      final scheduler = buildScheduler(service, locationResolver: () => bjt);

      final result = await scheduler.reschedule(plan: null);

      expect(result.degraded, isFalse);
      expect(result.scheduledCount, 0);
      expect(service.calls, ['cancelAll', 'permissionStatus']);
    });

    test('权限未确定（notDetermined）：同样降级不排程', () async {
      final service = FakeNotificationService()
        ..status = NotificationPermissionStatus.notDetermined;
      final scheduler = buildScheduler(service, locationResolver: () => bjt);

      final result = await scheduler.reschedule(plan: plan);

      expect(result.degraded, isTrue);
      expect(result.scheduledCount, 0);
    });
  });

  group('系统事件绑定（T14/T15/B14）', () {
    test('事件 → 重排原因映射', () {
      expect(
        rescheduleReasonForSystemEvent(FastingSystemEvent.timezoneChanged),
        RescheduleReason.timezoneChange,
      );
      expect(
        rescheduleReasonForSystemEvent(FastingSystemEvent.clockChanged),
        RescheduleReason.clockChanged,
      );
      expect(
        rescheduleReasonForSystemEvent(FastingSystemEvent.bootCompleted),
        RescheduleReason.bootCompleted,
      );
    });

    test('时区事件触发全量重排（先 cancelAll 再重建）', () async {
      final service = FakeNotificationService();
      final source = FakeSystemEventSource();
      final scheduler = buildScheduler(service, locationResolver: () => bjt);
      final binder = FastingNotificationEventBinder(
        scheduler: scheduler,
        source: source,
        planProvider: () => plan,
      )..start();
      addTearDown(binder.stop);

      source.emit(FastingSystemEvent.timezoneChanged);
      await _pumpUntil(() => service.scheduled.length == 6);

      expect(service.calls.first, 'cancelAll');
      expect(service.scheduled, hasLength(6));
    });

    test('重启事件触发重排；NO_PLAN 时仅清空', () async {
      final service = FakeNotificationService();
      final source = FakeSystemEventSource();
      final scheduler = buildScheduler(service, locationResolver: () => bjt);
      final binder = FastingNotificationEventBinder(
        scheduler: scheduler,
        source: source,
        planProvider: () => null, // NO_PLAN
      )..start();
      addTearDown(binder.stop);

      source.emit(FastingSystemEvent.bootCompleted);
      await _pumpUntil(() => service.calls.isNotEmpty);

      expect(service.calls, ['cancelAll', 'permissionStatus']);
      expect(service.scheduled, isEmpty);
    });
  });
}

class FakeNotificationService implements NotificationService {
  final calls = <String>[];
  final scheduled = <ScheduledNotification>[];
  var status = NotificationPermissionStatus.granted;

  @override
  Future<void> initialize({NotificationChannelConfig? channel}) async {}

  @override
  Future<NotificationPermissionStatus> requestPermission() async => status;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    calls.add('permissionStatus');
    return status;
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    NotificationChannelConfig? channel,
    String? payload,
  }) async {}

  @override
  Future<void> scheduleZoned(ScheduledNotification notification) async {
    calls.add('scheduleZoned');
    scheduled.add(notification);
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    scheduled.clear();
  }
}

class FakeSystemEventSource implements FastingSystemEventSource {
  final _controller = StreamController<FastingSystemEvent>.broadcast();

  @override
  Stream<FastingSystemEvent> get events => _controller.stream;

  void emit(FastingSystemEvent event) => _controller.add(event);
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '条件在等待期内未满足');
}
