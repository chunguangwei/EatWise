import 'package:eatwise/core/notification/local_notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/fasting/tz_test_helper.dart';

/// LocalNotificationService 的 MethodChannel 调用序列测试
/// （flutter_local_notifications 插件通道 mock；flutter_test 默认
/// defaultTargetPlatform = android，覆盖 Android 路径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'dexterous.com/flutter/local_notifications';
  const channel = MethodChannel(channelName);
  const reminderChannel = NotificationChannelConfig(
    id: 'fasting_reminders',
    name: '断食提醒',
    description: '进食窗口与断食窗口的到点提醒',
  );

  final calls = <MethodCall>[];
  var notificationsGranted = true;
  var canExactAlarm = true;

  setUpAll(() async {
    await initTestTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    // 纯单测环境无 dartPluginRegistrant，手动注册 Android 平台实现
    // （走 MethodChannel，由下方 mock handler 接管）。
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() {
    calls.clear();
    notificationsGranted = true;
    canExactAlarm = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'requestNotificationsPermission':
              return notificationsGranted;
            case 'areNotificationsEnabled':
              return notificationsGranted;
            case 'canScheduleExactNotifications':
              return canExactAlarm;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> methods() => calls.map((c) => c.method).toList();

  group('初始化与渠道', () {
    test('initialize：插件初始化 + 注册 Android 通知渠道（i18n 渠道名）', () async {
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);

      expect(methods(), ['initialize', 'createNotificationChannel']);
      final args = calls[1].arguments as Map<dynamic, dynamic>;
      expect(args['id'], 'fasting_reminders');
      expect(args['name'], '断食提醒');
      expect(args['description'], '进食窗口与断食窗口的到点提醒');
    });
  });

  group('权限（合规 §3.2：拒绝降级，不阻断计时）', () {
    test('requestPermission 授权 → granted', () async {
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);
      calls.clear();

      expect(
        await service.requestPermission(),
        NotificationPermissionStatus.granted,
      );
      expect(methods(), ['requestNotificationsPermission']);
    });

    test('requestPermission 拒绝 → denied（不抛异常）', () async {
      notificationsGranted = false;
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);

      expect(
        await service.requestPermission(),
        NotificationPermissionStatus.denied,
      );
    });

    test('permissionStatus 映射 areNotificationsEnabled', () async {
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);
      expect(
        await service.permissionStatus(),
        NotificationPermissionStatus.granted,
      );

      notificationsGranted = false;
      expect(
        await service.permissionStatus(),
        NotificationPermissionStatus.denied,
      );
    });
  });

  group('排程', () {
    test('scheduleZoned：UTC 锚点按设备时区渲染，精确闹钟已授权用 exact 模式', () async {
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);
      calls.clear();

      final trigger =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 24 * 3600;
      await service.scheduleZoned(
        ScheduledNotification(
          id: 42,
          title: 'EatWise',
          body: '可以进食啦',
          channel: reminderChannel,
          triggerAtUtcSec: trigger,
        ),
      );

      expect(methods(), ['canScheduleExactNotifications', 'zonedSchedule']);
      final args = calls[1].arguments as Map<dynamic, dynamic>;
      expect(args['id'], 42);
      expect(args['title'], 'EatWise');
      expect(args['body'], '可以进食啦');
      // UTC 锚点 → 设备时区（tz.local = Asia/Shanghai）墙钟
      expect(args['timeZoneName'], 'Asia/Shanghai');
      final local = tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(trigger * 1000, isUtc: true),
        tz.local,
      );
      expect(args['scheduledDateTimeISO8601'], local.toIso8601String());
      final specifics = args['platformSpecifics'] as Map<dynamic, dynamic>;
      expect(specifics['scheduleMode'], 'exactAllowWhileIdle');
      expect(specifics['channelId'], 'fasting_reminders');
    });

    test('scheduleZoned：SCHEDULE_EXACT_ALARM 未授权 → 降级不精确闹钟（合规 §3.2）', () async {
      canExactAlarm = false;
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);
      calls.clear();

      final trigger =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 24 * 3600;
      await service.scheduleZoned(
        ScheduledNotification(
          id: 7,
          title: 't',
          body: 'b',
          channel: reminderChannel,
          triggerAtUtcSec: trigger,
        ),
      );

      final args =
          calls.firstWhere((c) => c.method == 'zonedSchedule').arguments
              as Map<dynamic, dynamic>;
      final specifics = args['platformSpecifics'] as Map<dynamic, dynamic>;
      expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
    });

    test('showNow 即时通知与 cancelAll 清空', () async {
      final service = LocalNotificationService();
      await service.initialize(channel: reminderChannel);
      calls.clear();

      await service.showNow(id: 1, title: 't', body: 'b');
      await service.cancelAll();

      expect(methods(), ['show', 'cancelAll']);
      final args = calls[0].arguments as Map<dynamic, dynamic>;
      expect(args['id'], 1);
      expect(args['title'], 't');
      expect(args['body'], 'b');
    });
  });
}
