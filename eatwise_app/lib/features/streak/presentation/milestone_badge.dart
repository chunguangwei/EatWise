import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 里程碑徽章滑入（《规格-M5》§5.1/§5.2：3/7/30 天首次解锁，
/// 「N 天连胜 🔥」徽章自底部滑入；可点按出分享图卡占位——分享本身留 TODO）。
///
/// reduced-motion 降级（M8 硬性）：系统「减弱动态效果」开启时
/// （`MediaQuery.disableAnimations`）取消滑入位移，改为静态徽章淡入
/// （opacity ≤200ms）。
class MilestoneBadge extends StatefulWidget {
  const MilestoneBadge({
    required this.days,
    required this.onDismiss,
    super.key,
  });

  /// 里程碑档位（3/7/30）。
  final int days;

  /// 动画播完或用户关闭后回调。
  final VoidCallback onDismiss;

  @override
  State<MilestoneBadge> createState() => _MilestoneBadgeState();
}

class _MilestoneBadgeState extends State<MilestoneBadge> {
  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final badge = _MilestoneBadgeCard(
      days: widget.days,
      onDismiss: widget.onDismiss,
    );
    if (reduceMotion) {
      // 降级：静态淡入（无位移/粒子）。
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: badge,
      );
    }
    // 默认：自下方滑入 + 淡入（克制，≤1.5s）。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: child,
        ),
      ),
      child: badge,
    );
  }
}

class _MilestoneBadgeCard extends StatelessWidget {
  const _MilestoneBadgeCard({required this.days, required this.onDismiss});

  final int days;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Semantics(
      label: t.streak.milestone.title(days: '$days'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: radii.rLg,
          border: Border.all(color: colors.brandAccent, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              t.streak.milestone.title(days: '$days'),
              style: textStyles.textBase.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () {
                    // TODO(M5 分享)：生成分享图卡（里程碑图卡 + 渠道分享），
                    // 埋点 milestone_shared；当前为占位提示。
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t.streak.milestone.shareComingSoon),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.border),
                    foregroundColor: colors.textPrimary,
                    minimumSize: const Size(0, AppSpacing.s12),
                  ),
                  child: Text(t.streak.milestone.share),
                ),
                const SizedBox(width: AppSpacing.s3),
                FilledButton(
                  onPressed: onDismiss,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brandPrimary,
                    minimumSize: const Size(0, AppSpacing.s12),
                  ),
                  child: Text(
                    t.streak.milestone.accept,
                    style: textStyles.textBase.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
