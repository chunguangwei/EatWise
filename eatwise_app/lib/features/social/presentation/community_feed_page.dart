import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/presentation/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 社区 Tab：单列打卡流（设计稿 §3.2；四态规范 §3.2.4 社区·打卡流：
/// 骨架 3 卡 / 空态引导发布 / 错误重试 / 成功单列卡片流）。
class CommunityFeedPage extends ConsumerStatefulWidget {
  const CommunityFeedPage({super.key});

  @override
  ConsumerState<CommunityFeedPage> createState() => _CommunityFeedPageState();
}

class _CommunityFeedPageState extends ConsumerState<CommunityFeedPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 200) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final feed = ref.watch(feedControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.social.feed.title, style: textStyles.textXl),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'community-compose',
        backgroundColor: colors.brandAccent,
        tooltip: t.social.compose.title,
        onPressed: () => context.push('/community/compose'),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(child: _buildBody(context, feed)),
    );
  }

  Widget _buildBody(BuildContext context, FeedState feed) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;

    switch (feed.status) {
      case FeedStatus.loading:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: const <Widget>[
            _SkeletonCard(),
            _SkeletonCard(),
            _SkeletonCard(),
          ],
        );
      case FeedStatus.error:
        return _CenteredMessage(
          icon: Icons.cloud_off_outlined,
          title: t.social.feed.errorTitle,
          subtitle: feed.errorMessage,
          ctaLabel: t.common.action.retry,
          onCta: () => ref.read(feedControllerProvider.notifier).refresh(),
        );
      case FeedStatus.ready:
        if (feed.items.isEmpty) {
          return _CenteredMessage(
            icon: Icons.people_outline,
            title: t.social.feed.emptyTitle,
            subtitle: t.social.feed.emptySubtitle,
            ctaLabel: t.social.feed.emptyCta,
            onCta: () => context.push('/community/compose'),
          );
        }
        return RefreshIndicator(
          color: colors.brandPrimary,
          onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.s4),
            itemCount: feed.items.length + (feed.loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= feed.items.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.s4),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return PostCard(
                key: ValueKey(feed.items[index].post.id),
                item: feed.items[index],
              );
            },
          ),
        );
    }
  }
}

/// 骨架卡（四态规范：骨架 = 3 张打卡卡占位，色块 #E4EAE8〔假设〕）。
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    const block = Color(0xFFE4EAE8);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: block,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s3),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).extension<AppColors>()!.bgSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CircleAvatar(radius: 20, backgroundColor: block),
              const SizedBox(width: AppSpacing.s2),
              bar(120, 16),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          bar(double.infinity, 14),
          const SizedBox(height: AppSpacing.s2),
          bar(200, 14),
        ],
      ),
    );
  }
}

/// 空态/错误态统一结构（3.2.2/3.2.3：插画图标 → 主文案 → 副文案 → CTA）。
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.ctaLabel,
    required this.onCta,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s4),
      children: <Widget>[
        const SizedBox(height: AppSpacing.s16),
        Icon(icon, size: 64, color: colors.textSecondary),
        const SizedBox(height: AppSpacing.s4),
        Text(title, style: textStyles.textXl, textAlign: TextAlign.center),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s2),
          Text(
            subtitle!,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.s6),
        FilledButton(
          onPressed: onCta,
          style: FilledButton.styleFrom(
            backgroundColor: colors.brandPrimary,
            minimumSize: const Size.fromHeight(AppSpacing.s12),
          ),
          child: Text(
            ctaLabel,
            style: textStyles.textBase.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
