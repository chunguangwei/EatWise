import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/exposure_tracker.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 相对时间（打卡卡时间戳；测试经 [socialNowProvider] 固定）。
String relativeTime(
  Translations$social$feed$zh_CN t,
  DateTime createdAtUtc,
  DateTime now,
) {
  final diff = now.toUtc().difference(createdAtUtc);
  if (diff.inMinutes < 1) return t.justNow;
  if (diff.inHours < 1) return t.minutesAgo(n: diff.inMinutes);
  if (diff.inDays < 1) return t.hoursAgo(n: diff.inHours);
  return t.daysAgo(n: diff.inDays);
}

/// 打卡卡（设计稿 §3.2 社区单列卡片：头像/昵称/时间/图文/连续天数徽章/
/// 轻互动点赞/举报入口；四态规范 4.1 正文 3 行截断 + 展开）。
class PostCard extends ConsumerStatefulWidget {
  const PostCard({required this.item, super.key});

  final FeedItem item;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final now = ref.read(socialNowProvider)();
    final item = widget.item;
    final post = item.post;
    final nickname = post.authorNickname?.trim().isNotEmpty == true
        ? post.authorNickname!
        : t.social.feed.anonymous;

    // 打卡流卡片曝光（community_post_expose〔新增事件〕；§4.1 列表类曝光：
    // 逐条按 post_id 去重，重进重计，单卡可视 <500ms 不计）。
    final postIdHash = anonymizedContentId(post.id);
    return ExposureTracker(
      eventName: 'community_post_expose',
      dedupeKey: 'community:post:$postIdHash',
      properties: <String, Object?>{
        'post_id_hash': postIdHash,
        'is_own_post': post.isAuthor,
        'has_image': post.imageUrls.isNotEmpty,
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s3),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: radii.rLg,
        ),
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 头部：头像占位 + 昵称（1 行截断，4.1）+ 相对时间 + 举报入口。
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colors.brandPrimary.withValues(alpha: 0.16),
                  child: Icon(Icons.person_outline, color: colors.brandPrimary),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        nickname,
                        style: textStyles.textBase,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        relativeTime(t.social.feed, post.createdAtUtc, now),
                        style: textStyles.textXs.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!post.isAuthor)
                  IconButton(
                    icon: Icon(
                      Icons.flag_outlined,
                      color: colors.textSecondary,
                    ),
                    tooltip: t.social.feed.report,
                    onPressed: () => _confirmReport(context),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            // 徽章行：连续天数徽章（0/空不显示，四态规范 4.2）+ 审核中标记（D-17）。
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s1,
              children: <Widget>[
                if ((post.streakDaysAtPost ?? 0) > 0)
                  _Badge(
                    icon: Icons.local_fire_department,
                    label: t.social.feed.streakBadge(
                      days: post.streakDaysAtPost!,
                    ),
                    color: colors.brandAccent,
                  ),
                if (item.pendingSync || post.auditStatus == 'pending')
                  _Badge(
                    icon: Icons.hourglass_top,
                    label: t.social.feed.pendingBadge,
                    color: colors.textSecondary,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            // 正文：3 行截断 + 展开（4.1 打卡正文行数上限）。
            _CollapsibleText(
              text: post.text,
              style: textStyles.textBase,
              maxLines: 3,
              expanded: _expanded,
              expandLabel: t.social.feed.expand,
              collapseLabel: t.social.feed.collapse,
              linkColor: colors.brandPrimary,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
            // 图片：服务端回相对路径（/v1/uploads/<id>），渲染前补 origin；
            // 加载失败 → 占位图（§3.2.4）。
            if (post.imageUrls.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.s2),
              ClipRRect(
                borderRadius: radii.rLg,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(
                    ref
                        .read(apiConfigProvider)
                        .resolveUrl(post.imageUrls.first),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: colors.bgPrimary,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colors.textSecondary,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s2),
            // 轻互动：点赞 + 计数（乐观更新；触控区 ≥44px，M8）。
            Row(
              children: <Widget>[
                Semantics(
                  button: true,
                  label: t.social.feed.like,
                  child: InkWell(
                    onTap: item.pendingSync
                        ? null
                        : () => ref
                              .read(feedControllerProvider.notifier)
                              .toggleLike(post.id),
                    borderRadius: radii.rLg,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s2),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            post.likedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 22,
                            color: post.likedByMe
                                ? colors.signalRed
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.s1),
                          Text(
                            '${post.likeCount}',
                            style: textStyles.textSm.copyWith(
                              color: post.likedByMe
                                  ? colors.signalRed
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReport(BuildContext context) async {
    final t = Translations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(t.social.feed.reportConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t.social.feed.report),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(feedControllerProvider.notifier)
        .report(widget.item.post.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? t.social.feed.reported : t.social.feed.reportFailed),
      ),
    );
  }
}

/// 徽章（三重编码思路：图标 + 文字，不只靠颜色）。
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: radii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.s1),
          Text(label, style: textStyles.textXs.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// 可折叠正文：超过 [maxLines] 显示「展开/收起」（4.1：超出显示展开按钮）。
class _CollapsibleText extends StatelessWidget {
  const _CollapsibleText({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.expanded,
    required this.expandLabel,
    required this.collapseLabel,
    required this.linkColor,
    required this.onToggle,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final bool expanded;
  final String expandLabel;
  final String collapseLabel;
  final Color linkColor;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              text,
              style: style,
              maxLines: expanded ? null : maxLines,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
                  child: Text(
                    expanded ? collapseLabel : expandLabel,
                    style: style.copyWith(color: linkColor),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
