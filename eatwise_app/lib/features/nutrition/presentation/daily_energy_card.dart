import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 摄入目标差值不是代谢结余；运动单独展示，不回加到已有活动系数的目标。
class DailyEnergyCard extends StatelessWidget {
  const DailyEnergyCard({
    super.key,
    required this.intakeKcal,
    required this.targetKcal,
    required this.historical,
  });
  final double? intakeKcal;
  final int targetKcal;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).nutrition.data.energy;
    final colors = Theme.of(context).extension<AppColors>()!;
    final styles = Theme.of(context).extension<AppTextStyles>()!;
    final intake = intakeKcal;
    final difference = intake == null ? null : targetKcal - intake;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: AppSurfaces.card(
        colors,
        Theme.of(context).extension<AppShadows>()!,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title, style: styles.textLg),
          const SizedBox(height: AppSpacing.s3),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s3,
            children: [
              _Value(
                label: t.intake,
                value: intake == null ? '—' : '${intake.round()} kcal',
              ),
              _Value(label: t.target, value: '$targetKcal kcal'),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            difference == null
                ? t.empty
                : difference >= 0
                ? t.remaining(kcal: difference.round().toString())
                : t.over(kcal: (-difference).round().toString()),
            style: styles.textBase,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            historical ? t.historical : t.note,
            style: styles.textXs.copyWith(color: colors.textSecondary),
          ),
          TextButton(
            onPressed: () => context.push('/settings/body-profile'),
            child: Text(t.details),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).extension<AppTextStyles>()!;
    final colors = Theme.of(context).extension<AppColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: styles.textSm.copyWith(color: colors.textSecondary)),
        Text(value, style: styles.textXl),
      ],
    );
  }
}
