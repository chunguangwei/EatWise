import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/notification/notification_service.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理员「待审批」提醒（2026-10-04 用户拍板：需要审批时也要通知管理员）。
///
/// 推送通道是 stub（无 APNs/FCM，鸿蒙无 GMS）——可行口径 = **同步轮轮询 +
/// 本地即时通知**：RecordSyncEngine 每轮 syncNow（启动/登录/前台回切）
/// 调一次 [syncNow] 拉 pending-count，与上次基线（prefs 每用户命名空间）
/// 比较：
/// - 首轮：静默建基线（装机/升级后不轰炸存量队列）；
/// - 计数上升：showNow 本地通知「有 N 条食物贡献等待审批」并抬基线；
/// - 计数下降/不变：仅收敛基线（他端/管理台已处理的队列不提醒）。
///
/// 仅 role=admin 的登录用户启用（普通用户/匿名跳过，不浪费请求）。
/// 设置页「审批中心」行角标共用同一计数端点（adminPendingCountProvider）。
final class AdminPendingAlertSync {
  AdminPendingAlertSync({
    required this.remote,
    required this.prefs,
    required this.userId,
    required this.isAdmin,
    required this.notifications,
    required this.channel,
    required this.title,
    required this.bodyFor,
    this.onCountChanged,
  });

  /// 审批中心远程端。
  final ModerationRemote remote;

  /// 基线持久化。
  final SharedPreferences prefs;

  /// 当前用户 id（未登录 'anonymous'）。
  final String Function() userId;

  /// 当前用户是否 admin（userMe.role；未加载/异常按 false 跳过）。
  final bool Function() isAdmin;

  /// 本地通知服务（showNow 即时通知）。
  final NotificationService notifications;

  /// 提醒渠道（main 已注册）。
  final NotificationChannelConfig channel;

  /// 通知标题（i18n，装配时按当前语言解析）。
  final String title;

  /// 通知正文（带计数插值）。
  final String Function(int n) bodyFor;

  /// 计数变化后的回调（失效设置页角标 provider；可空）。
  final void Function()? onCountChanged;

  /// 通知 id（固定，避开断食/喝水排程 id 空间 (sec~/60)*10+kind）。
  static const int notificationId = 500000001;

  static const String _lastSeenPrefix = 'moderation.lastSeenPendingCount_';

  /// 提醒渠道 id（稳定，不随语言变化）。
  static const String channelId = 'moderation_alerts';

  /// 一轮检查：拉计数 → 比基线 → 必要时通知 → 收敛基线。
  /// 拉取失败上抛（引擎吞掉，基线不动，下轮重试）。
  Future<void> syncNow() async {
    final uid = userId();
    if (uid == 'anonymous' || !isAdmin()) return;
    final count = await remote.fetchPendingCount();
    final key = '$_lastSeenPrefix$uid';
    final last = prefs.getInt(key);
    if (last == null) {
      // 首轮静默建基线：存量队列不轰炸。
      await prefs.setInt(key, count);
      onCountChanged?.call();
      return;
    }
    if (count > last) {
      await notifications.showNow(
        id: notificationId,
        title: title,
        body: bodyFor(count),
        channel: channel,
      );
    }
    if (count != last) {
      await prefs.setInt(key, count);
      onCountChanged?.call();
    }
  }
}

/// 管理员提醒通知渠道（Android 系统设置页可见；名称/描述走 i18n，D-15）。
NotificationChannelConfig moderationAlertChannel(Translations t) {
  return NotificationChannelConfig(
    id: AdminPendingAlertSync.channelId,
    name: t.moderation.notify.channelName,
    description: t.moderation.notify.channelDesc,
  );
}
