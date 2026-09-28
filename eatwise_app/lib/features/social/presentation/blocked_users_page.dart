import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/social/application/blocked_users_controller.dart';
import 'package:eatwise/features/social/data/social_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 已屏蔽用户管理页（App Store 条例 1.2「屏蔽滥用用户」的设置入口）：
/// 列表 + 解除屏蔽；空态/错误态/加载态四态齐备（四态规范）。
class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final blocked = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.social.blockedUsers.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: blocked.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.social.blockedUsers.loadError,
                  style: textStyles.textBase.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                TextButton(
                  onPressed: () => ref.invalidate(blockedUsersProvider),
                  child: Text(t.common.action.retry),
                ),
              ],
            ),
          ),
          data: (value) => value.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s6),
                    child: Text(
                      t.social.blockedUsers.empty,
                      textAlign: TextAlign.center,
                      style: textStyles.textBase.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  itemCount: value.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s2),
                  itemBuilder: (context, index) =>
                      _BlockedUserTile(user: value[index]),
                ),
        ),
      ),
    );
  }
}

class _BlockedUserTile extends ConsumerWidget {
  const _BlockedUserTile({required this.user});

  final BlockedUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final nickname = user.nickname?.trim().isNotEmpty == true
        ? user.nickname!
        : t.social.blockedUsers.unknownUser;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              nickname,
              style: textStyles.textBase,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _confirmUnblock(context, ref),
            child: Text(t.social.blockedUsers.unblock),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnblock(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t.social.blockedUsers.unblockConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t.social.blockedUsers.unblock),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await unblockUser(ref, user.userId);
      messenger.showSnackBar(
        SnackBar(content: Text(t.social.blockedUsers.unblocked)),
      );
    } on ApiException {
      messenger.showSnackBar(
        SnackBar(content: Text(t.social.blockedUsers.unblockFailed)),
      );
    }
  }
}
