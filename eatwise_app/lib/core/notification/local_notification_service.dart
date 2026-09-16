import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// [NotificationService] 的生产实现：flutter_local_notifications 双端封装
/// （D-17 选型；《技术选型与双端架构》§3 本地通知桥接表）。
///
/// - iOS：UNUserNotificationCenter，权限 alert/badge/sound；
/// - Android：NotificationChannel + 精确闹钟（SCHEDULE_EXACT_ALARM，
///   未授权自动降级不精确闹钟，合规 §3.2）；
/// - 纯本地通知，不依赖 APNs/FCM/厂商推送通道在线（D-09）。
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// 缺省渠道（initialize 未指定时的防御兜底；生产路径 main.dart 总是
  /// 显式传入 fastingReminderChannel）。渠道名/描述是系统设置页可见文案，
  /// 必须走 i18n（D-15），跟随当前 slang 语言即时取值。
  static NotificationChannelConfig get fallbackChannel {
    final t = LocaleSettings.currentLocale.buildSync();
    return NotificationChannelConfig(
      id: 'general_reminders',
      name: t.notify.channel.general.name,
      description: t.notify.channel.general.description,
    );
  }

  NotificationChannelConfig _channel = fallbackChannel;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize({NotificationChannelConfig? channel}) async {
    final effective = channel ?? fallbackChannel;
    _channel = effective;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      // 权限弹窗时机跟随功能（合规 §3：用时申请），初始化时不弹。
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );
    if (_isAndroid) {
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          effective.id,
          effective.name,
          description: effective.description,
          importance: Importance.high,
        ),
      );
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final granted = await _android?.requestNotificationsPermission();
        return (granted ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      case TargetPlatform.iOS:
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return (granted ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      case TargetPlatform.macOS:
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return (granted ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        // 非目标平台（D-14：仅 iOS/Android），按未确定处理。
        return NotificationPermissionStatus.notDetermined;
    }
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final enabled = await _android?.areNotificationsEnabled();
        return (enabled ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      case TargetPlatform.iOS:
        final options = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return (options?.isEnabled ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      case TargetPlatform.macOS:
        final options = await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return (options?.isEnabled ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return NotificationPermissionStatus.notDetermined;
    }
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    NotificationChannelConfig? channel,
    String? payload,
  }) async {
    final effective = channel ?? _channel;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _detailsFor(effective),
      payload: payload,
    );
  }

  @override
  Future<void> scheduleZoned(ScheduledNotification notification) async {
    // D-07：UTC 锚点 → 设备当前时区的本地墙钟（§6-B11 夏令时由时区语义兜底）。
    final scheduledDate = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(
        notification.triggerAtUtcSec * 1000,
        isUtc: true,
      ),
      tz.local,
    );
    await _plugin.zonedSchedule(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      scheduledDate: scheduledDate,
      notificationDetails: _detailsFor(notification.channel),
      payload: notification.payload,
      androidScheduleMode: await _androidScheduleMode(),
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  /// Android 12+ 精确闹钟降级（合规 §3.2）：未授予 SCHEDULE_EXACT_ALARM 时
  /// 退化为不精确闹钟，提醒可能延迟数分钟，但不抛异常、不阻断计时。
  Future<AndroidScheduleMode> _androidScheduleMode() async {
    if (_isAndroid) {
      final canExact = await _android?.canScheduleExactNotifications();
      if (canExact == false) {
        return AndroidScheduleMode.inexactAllowWhileIdle;
      }
    }
    return AndroidScheduleMode.exactAllowWhileIdle;
  }

  NotificationDetails _detailsFor(NotificationChannelConfig channel) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }
}
