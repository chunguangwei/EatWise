import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter/material.dart';

/// 断签弹窗（《规格-M5》§4，评审硬性三要素缺一不可）：
/// ① 「连胜如何计算」说明；② 补签卡本月剩余次数；③ 补签卡三态之一
/// （可补签 → 主按钮 / 已用尽 → 置灰说明 / 已断签超 7 天 → 仅确认）。
///
/// 无障碍（M8）：图标 + 文字 + 色彩三重编码；按钮 ≥44px；完整语义标签。
class StreakBreakDialog extends StatelessWidget {
  const StreakBreakDialog({
    required this.visualState,
    required this.cardsLeft,
    required this.restoreDays,
    required this.onMend,
    required this.onDismiss,
    super.key,
  });

  /// 补签卡三态（§3.2）。
  final MendCardVisualState visualState;

  /// 本月剩余补签卡。
  final int cardsLeft;

  /// 补签成功可恢复的连胜天数（弹窗 CTA 文案「恢复 {days} 天连胜」）。
  final int restoreDays;

  /// 点按「使用补签卡」（仅 MENDABLE 态可用）。
  final VoidCallback onMend;

  /// 点按「知道了，重新开始」。
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    return AlertDialog(
      backgroundColor: colors.bgPrimary,
      title: Semantics(
        header: true,
        child: Text(t.streak.kBreak.title, style: textStyles.textXl),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 要素①：连胜如何计算（图标 + 文字，非单靠颜色）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, color: colors.brandPrimary, size: 20),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  t.streak.kBreak.howItWorks,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          // 要素②：本月剩余补签卡。
          Text(
            t.streak.kBreak.cardsLeft(n: cardsLeft),
            style: textStyles.textBase.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.s4),
          // 要素③：补签卡三态之一的明确呈现。
          _StateSection(
            visualState: visualState,
            restoreDays: restoreDays,
            onMend: onMend,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: onDismiss,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.s12),
          ),
          child: Text(t.streak.kBreak.dismiss),
        ),
      ],
    );
  }
}

class _StateSection extends StatelessWidget {
  const _StateSection({
    required this.visualState,
    required this.restoreDays,
    required this.onMend,
  });

  final MendCardVisualState visualState;
  final int restoreDays;
  final VoidCallback onMend;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    switch (visualState) {
      case MendCardVisualState.mendable:
        // 可补签：轻盈绿填充主按钮。
        return Semantics(
          button: true,
          label: t.streak.kBreak.mendCta(days: restoreDays),
          child: FilledButton.icon(
            onPressed: onMend,
            icon: const Icon(Icons.restore, color: Colors.white),
            label: Text(
              t.streak.kBreak.mendCta(days: restoreDays),
              style: textStyles.textBase.copyWith(color: Colors.white),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size.fromHeight(AppSpacing.s12),
            ),
          ),
        );
      case MendCardVisualState.exhausted:
        // 已用尽：按钮置灰 + 副文案「下月 1 日将发放 2 张新卡」。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.block),
              label: Text(t.streak.kBreak.mendCta(days: restoreDays)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              t.streak.kBreak.exhausted,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ],
        );
      case MendCardVisualState.unmendable:
        // 已断签超 7 天：不展示补签按钮，仅说明「补签窗口已关闭」。
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.lock_clock, color: colors.textSecondary, size: 20),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                t.streak.kBreak.unmendable,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        );
    }
  }
}
