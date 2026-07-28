import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter/material.dart';

/// 首页问候区连胜展示（设计稿 §5.1-3：「连续 N 天 🔥」）。
///
/// 显示边界（四态规范）：streak = 0 → 不显示火焰，显示引导文案；
/// streak > 999 → `999+` 截断。三重编码：图标 + 文字 + 色彩（M8）。
class StreakBanner extends StatelessWidget {
  const StreakBanner({required this.currentStreak, super.key});

  final int currentStreak;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    if (currentStreak <= 0) {
      // 无连胜：引导文案，不显示火焰（四态规范 3.4 空态）。
      return Semantics(
        label: t.streak.home.startHint,
        child: Text(
          t.streak.home.startHint,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
      );
    }
    final label = t.streak.home.streakDays(
      days: formatStreakCount(currentStreak),
    );
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: colors.brandAccent.withValues(alpha: 0.12),
          borderRadius: radii.rFull,
        ),
        child: Text(
          label,
          style: textStyles.textSm.copyWith(
            color: colors.brandAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
