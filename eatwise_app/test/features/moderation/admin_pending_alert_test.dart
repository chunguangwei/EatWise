import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/moderation/data/admin_pending_alert.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AdminPendingAlertSync 单测（2026-10-04 拍板：需要审批时也通知管理员）。
void main() {
  late SharedPreferences prefs;
  late FakeModerationRemote remote;
  late _RecordingNotifications notifications;
  bool admin = true;
  String uid = 'admin-1';

  const channel = NotificationChannelConfig(
    id: AdminPendingAlertSync.channelId,
    name: '审批提醒',
    description: 'desc',
  );

  AdminPendingAlertSync build() => AdminPendingAlertSync(
    remote: remote,
    prefs: prefs,
    userId: () => uid,
    isAdmin: () => admin,
    notifications: notifications,
    channel: channel,
    title: '新的待审批贡献',
    bodyFor: (n) => '有 $n 条食物贡献等待审批',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    remote = FakeModerationRemote();
    notifications = _RecordingNotifications();
    admin = true;
    uid = 'admin-1';
  });

  test('首轮静默建基线：不通知，基线落盘', () async {
    remote.pendingCount = 5;
    await build().syncNow();

    expect(notifications.shown, isEmpty);
    expect(prefs.getInt('moderation.lastSeenPendingCount_admin-1'), 5);
  });

  test('计数上升 → 通知一次并抬基线；同数不再重复通知', () async {
    remote.pendingCount = 2;
    await build().syncNow(); // 建基线
    remote.pendingCount = 5;
    await build().syncNow();

    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single.title, '新的待审批贡献');
    expect(notifications.shown.single.body, '有 5 条食物贡献等待审批');
    expect(notifications.shown.single.id, AdminPendingAlertSync.notificationId);
    expect(prefs.getInt('moderation.lastSeenPendingCount_admin-1'), 5);

    await build().syncNow(); // 同数
    expect(notifications.shown, hasLength(1));
  });

  test('计数下降（他端已审批）→ 不通知，基线收敛', () async {
    remote.pendingCount = 6;
    await build().syncNow();
    remote.pendingCount = 1;
    await build().syncNow();

    expect(notifications.shown, isEmpty);
    expect(prefs.getInt('moderation.lastSeenPendingCount_admin-1'), 1);
  });

  test('计数变化后触发 onCountChanged（角标失效）', () async {
    var invalidations = 0;
    remote.pendingCount = 3;
    final sync = AdminPendingAlertSync(
      remote: remote,
      prefs: prefs,
      userId: () => uid,
      isAdmin: () => admin,
      notifications: notifications,
      channel: channel,
      title: 't',
      bodyFor: (n) => '$n',
      onCountChanged: () => invalidations++,
    );
    await sync.syncNow(); // 首轮也刷一次（角标首填）
    expect(invalidations, 1);
    remote.pendingCount = 4;
    await sync.syncNow();
    expect(invalidations, 2);
  });

  test('非 admin / 匿名：跳过（无请求、无基线、无通知）', () async {
    remote.pendingCount = 9;
    admin = false;
    await build().syncNow();
    expect(prefs.getInt('moderation.lastSeenPendingCount_admin-1'), isNull);

    admin = true;
    uid = 'anonymous';
    await build().syncNow();
    expect(prefs.getInt('moderation.lastSeenPendingCount_anonymous'), isNull);
    expect(notifications.shown, isEmpty);
  });

  test('拉取失败：基线不动（上抛由引擎吞掉，下轮重试）', () async {
    remote.pendingCount = 2;
    await build().syncNow();
    remote
      ..pendingCount = 8
      ..countError = StateError('offline');
    await expectLater(build().syncNow(), throwsStateError);

    expect(prefs.getInt('moderation.lastSeenPendingCount_admin-1'), 2);
    expect(notifications.shown, isEmpty);
  });
}

/// 记录 showNow 的通知服务假实现。
final class _RecordingNotifications implements NotificationService {
  final List<({int id, String title, String body})> shown =
      <({int id, String title, String body})>[];

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    NotificationChannelConfig? channel,
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body));
  }

  @override
  Future<void> initialize({
    NotificationChannelConfig? channel,
    List<NotificationChannelConfig> extraChannels =
        const <NotificationChannelConfig>[],
  }) async {}

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<void> scheduleZoned(ScheduledNotification notification) async {}

  @override
  Future<void> cancelAll() async {}
}
