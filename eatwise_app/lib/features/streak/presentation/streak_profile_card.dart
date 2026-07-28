import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:eatwise/features/streak/presentation/streak_break_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「我的」页 streak 卡片（当前连胜 / 历史最长 / 补签卡库存）。
///
/// 存在窗口内断签日时提供「去补签」入口（§4.1：弹窗关闭后补签入口
/// 仍可达），点击再次进入补签流程。
class StreakProfileCard extends ConsumerWidget {
  const StreakProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final streak = ref.watch(streakControllerProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.local_fire_department,
                color: streak.currentStreak > 0
                    ? colors.brandAccent
                    : colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(t.streak.profile.title, style: textStyles.textXl),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: t.streak.profile.current,
                  value:
                      '${formatStreakCount(streak.currentStreak).isEmpty ? '0' : formatStreakCount(streak.currentStreak)} '
                      '${t.streak.profile.daysUnit}',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: t.streak.profile.longest,
                  value: '${streak.longestStreak} ${t.streak.profile.daysUnit}',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: t.streak.profile.mendCards,
                  value: t.streak.profile.mendCardsValue(
                    n: streak.mendCardBalance,
                  ),
                ),
              ),
            ],
          ),
          if (streak.mendVisualState != MendCardVisualState.unmendable &&
              streak.pendingMendDates.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.s4),
            OutlinedButton.icon(
              onPressed: () => _openMendFlow(context, ref, streak),
              icon: const Icon(Icons.restore),
              label: Text(t.streak.profile.mendEntry),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.brandPrimary,
                side: BorderSide(color: colors.brandPrimary),
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 补签流程入口（「我的-连胜」再次进入，§4.1 频控不限制手动入口）。
  void _openMendFlow(BuildContext context, WidgetRef ref, StreakUiState s) {
    final t = Translations.of(context);
    final controller = ref.read(streakControllerProvider.notifier);
    final missedDate = s.pendingMendDates.first;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StreakBreakDialog(
        visualState: s.mendVisualState,
        cardsLeft: s.mendCardBalance,
        restoreDays: _restorePreview(ref, missedDate),
        onMend: () async {
          Navigator.pop(dialogContext);
          try {
            final result = await controller.useMendCard(missedDate);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    t.streak.kBreak.mendSuccess(days: result.restoredStreak),
                  ),
                ),
              );
            }
          } on Object {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.streak.kBreak.mendFailed)),
              );
            }
          }
        },
        onDismiss: () => Navigator.pop(dialogContext),
      ),
    );
  }

  int _restorePreview(WidgetRef ref, String missedDate) {
    // 补签预览由控制器暴露的引擎推演（见 StreakController.previewMendRestore）。
    return ref
        .read(streakControllerProvider.notifier)
        .previewMendRestore(missedDate);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Column(
      children: <Widget>[
        Text(
          value,
          style: textStyles.textBase.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          label,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
