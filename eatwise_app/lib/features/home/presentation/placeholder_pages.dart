import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/streak/presentation/streak_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 社区/我的 占位页（四态规范 3.2.2 空态统一结构：
/// 插画位（线性图标）→ 主文案 → 副文案 → CTA 主按钮，中英双语）。
///
/// 正式页面随 M5 社区 / M7 我的 迭代落地，本文件仅交付
/// 符合四态规范的空态占位，CTA 已接真实出口或「即将上线」提示。
/// M4 数据页已由 nutrition 模块正式页（NutritionDataPage）替换。

/// 社区页占位：空态文案取自四态规范 3.2.2，CTA「发布打卡」为 P1 能力，
/// 当前给「即将上线」提示（不阻断、不误导）。
class CommunityPlaceholderPage extends StatelessWidget {
  const CommunityPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return _PlaceholderScaffold(
      title: t.home.tab.community,
      icon: Icons.people_outline,
      emptyTitle: t.home.community.emptyTitle,
      emptySubtitle: t.home.community.emptySubtitle,
      ctaLabel: t.home.community.cta,
      onCta: () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.home.community.comingSoon))),
    );
  }
}

/// 我的页占位：空态 + 语言设置（D-15：设置内可手动切换，即时生效）。
class ProfilePlaceholderPage extends StatelessWidget {
  const ProfilePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return _PlaceholderScaffold(
      title: t.home.tab.profile,
      icon: Icons.person_outline,
      emptyTitle: t.home.profile.emptyTitle,
      emptySubtitle: t.home.profile.emptySubtitle,
      ctaLabel: null,
      onCta: null,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // M5：连胜卡片（当前/历史最长/补签卡库存 + 补签入口）。
          const StreakProfileCard(),
          const SizedBox(height: AppSpacing.s6),
          Text(t.settings.language.title, style: textStyles.textXl),
          const SizedBox(height: AppSpacing.s2),
          Wrap(
            spacing: AppSpacing.s2,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => LocaleSettings.useDeviceLocale(),
                child: Text(t.settings.language.system),
              ),
              OutlinedButton(
                onPressed: () => LocaleSettings.setLocale(AppLocale.zhCn),
                child: Text(t.settings.language.zhCN),
              ),
              OutlinedButton(
                onPressed: () => LocaleSettings.setLocale(AppLocale.en),
                child: Text(t.settings.language.en),
              ),
            ],
          ),
          // D-13 登出入口（T15：本地未同步数据保留，不随登出清除）。
          const SizedBox(height: AppSpacing.s6),
          Consumer(
            builder: (context, ref, _) {
              final colors = Theme.of(context).extension<AppColors>()!;
              return OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: Text(t.auth.logoutConfirm),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(t.common.action.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(t.auth.logout),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(t.auth.loggedOut)));
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.signalRed,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(t.auth.logout),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 空态占位统一结构（四态规范 3.2.2；触控区 ≥44px）。
class _PlaceholderScaffold extends StatelessWidget {
  const _PlaceholderScaffold({
    required this.title,
    required this.icon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.ctaLabel,
    required this.onCta,
    this.footer,
  });

  final String title;
  final IconData icon;
  final String emptyTitle;
  final String emptySubtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const SizedBox(height: AppSpacing.s16),
            Icon(icon, size: 64, color: colors.textSecondary),
            const SizedBox(height: AppSpacing.s4),
            Text(
              emptyTitle,
              style: textStyles.textXl,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              emptySubtitle,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s6),
              FilledButton(
                onPressed: onCta,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(
                  ctaLabel!,
                  style: textStyles.textBase.copyWith(color: Colors.white),
                ),
              ),
            ],
            if (footer != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
