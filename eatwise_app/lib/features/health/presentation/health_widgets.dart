import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/health/domain/health_activity.dart';
import 'package:flutter/material.dart';

/// 运动数据同步单独同意弹窗（GDPR Art.9 / PIPL §29 explicit consent，
/// 合规 §2）：首次开启「同步运动数据」前弹出，明示采集范围（步数/活动
/// 能量/体重）、用途（仅展示热量消耗）、本地处理不出端、可随时关闭。
///
/// 返回 true = 用户同意；false/null = 不同意或 dismiss（均视为未同意）。
Future<bool> showExerciseSyncConsentDialog(BuildContext context) async {
  final t = Translations.of(context);
  final colors = Theme.of(context).extension<AppColors>()!;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.settings.health.consentTitle),
      content: Text(t.settings.health.consentBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(t.settings.health.consentDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: colors.brandPrimary),
          child: Text(t.settings.health.consentAgree),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 数据页「今日消耗」卡（阶段 D）：活动能量 + 步数 + 摄入−消耗结余。
///
/// 仅在同步已开启且读取就绪时由数据页挂载；UI 只做接线，换算与结余
/// 口径见 `features/health/domain/health_activity.dart`。
class TodayBurnCard extends StatelessWidget {
  const TodayBurnCard({
    super.key,
    required this.steps,
    required this.burnKcal,
    required this.estimated,
    this.intakeKcal,
  });

  /// 今日步数（null = 无数据）。
  final int? steps;

  /// 活动消耗（kcal；系统活动能量或步数粗估兜底）。
  final double? burnKcal;

  /// burnKcal 是否来自步数粗估（true 时标注「估算」）。
  final bool estimated;

  /// 当日摄入（kcal；非空且有消耗时展示结余行）。
  final double? intakeKcal;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final burnText = burnKcal == null
        ? '—'
        : estimated
        ? t.nutrition.data.burn.estimatedValue(
            kcal: burnKcal!.toStringAsFixed(0),
          )
        : t.nutrition.data.burn.kcalValue(kcal: burnKcal!.toStringAsFixed(0));
    final balance = (burnKcal != null && intakeKcal != null)
        ? energyBalanceKcal(intakeKcal: intakeKcal!, burnKcal: burnKcal!)
        : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.nutrition.data.burn.title,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  label: t.nutrition.data.burn.activeEnergy,
                  value: burnText,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: t.nutrition.data.burn.steps,
                  value: steps?.toString() ?? '—',
                ),
              ),
            ],
          ),
          if (balance != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Text(
              t.nutrition.data.burn.balance(kcal: _signedKcal(balance)),
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }

  /// 结余带符号（+120 / -80 kcal，正盈余负缺口）。
  static String _signedKcal(double kcal) {
    final rounded = kcal.toStringAsFixed(0);
    return kcal >= 0 ? '+$rounded' : rounded;
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          value,
          style: textStyles.textXl.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}
