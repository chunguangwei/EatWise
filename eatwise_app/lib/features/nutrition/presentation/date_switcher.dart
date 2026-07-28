import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// 顶部日期切换（设计稿 §4.2-③）：前一天 / 日期 / 后一天（不可超今天）
/// + 非今天视图显示「回到今天」。触控区 ≥44px（四态规范 §4）。
class DateSwitcher extends ConsumerWidget {
  const DateSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final selected = ref.watch(selectedDateProvider);
    final canGoNext = ref.watch(canGoNextDayProvider);
    final isToday = ref.watch(isTodaySelectedProvider);
    final locale = Localizations.localeOf(context).toString();
    final dateLabel = DateFormat.MEd(locale).format(selected);
    final ds = t.nutrition.data.dateSwitcher;

    return Row(
      children: <Widget>[
        _ArrowButton(
          icon: Icons.chevron_left,
          tooltip: ds.prevDay,
          onPressed: () => ref.read(selectedDateProvider.notifier).prevDay(),
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                dateLabel,
                style: textStyles.textBase.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (isToday)
                Text(
                  ds.today,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        _ArrowButton(
          icon: Icons.chevron_right,
          tooltip: ds.nextDay,
          onPressed: canGoNext
              ? () => ref.read(selectedDateProvider.notifier).nextDay()
              : null,
        ),
        if (!isToday) ...<Widget>[
          const SizedBox(width: AppSpacing.s2),
          TextButton(
            onPressed: () =>
                ref.read(selectedDateProvider.notifier).backToToday(),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: colors.brandPrimary,
            ),
            child: Text(ds.backToToday),
          ),
        ],
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      color: colors.textPrimary,
      disabledColor: colors.textSecondary.withValues(alpha: 0.4),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
