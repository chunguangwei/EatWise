import 'package:eatwise/features/social/application/feed_controller.dart'
    show socialApiProvider;
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 已屏蔽用户列表（App Store 条例 1.2「屏蔽滥用用户」管理页数据源）。
/// 屏蔽关系纯服务端（信息流本就在线加载），不做本地离线缓存。
final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((
  ref,
) async {
  return ref.watch(socialApiProvider).fetchBlockedUsers();
});

/// 解除屏蔽（幂等）：成功后失效列表；失败抛 ApiException 由 UI 提示。
Future<void> unblockUser(WidgetRef ref, String userId) async {
  await ref.read(socialApiProvider).unblockUser(userId);
  ref.invalidate(blockedUsersProvider);
}
