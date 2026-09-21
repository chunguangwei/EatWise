import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页「今日预算」行（薄荷走查 P0）：已吃 / 还可吃 / 运动消耗一行情要，
/// 位置在双主按钮与 mini signal-card 之间。
///
/// 数据全部复用既有 provider（[todayIntakeProvider] 当日聚合 +
/// [nutritionGoalProvider] 目标 + [healthSyncControllerProvider] 活动能量 +
/// [todayExerciseKcalProvider] 手动运动合计），不引入新存储。还可吃 =
/// 目标 − 已吃，可为负（负值转「已超 Z」红色）；运动消耗（系统活动能量 +
/// 手动运动合计）>0 时追加「 · 运动 +Z」（展示口径，不抵减
/// 还可吃——预算口径与信号卡一致，只按目标对比）。无记录走引导态一行。
class TodayBudgetRow extends ConsumerWidget {
  const TodayBudgetRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    final goal = ref.watch(nutritionGoalProvider);
    final intake = ref.watch(todayIntakeProvider);
    final health = ref.watch(healthSyncControllerProvider);
    // 「运动 +Z」= 系统活动能量（如有）+ 今日手动运动 kcal 合计（合并口径，
    // 有系统数据时正常叠加；无 GMS 设备走手动兜底）。
    final systemKcal = health.status == HealthSyncStatus.ready
        ? health.today?.activeEnergyKcal
        : null;
    final manualKcal = ref.watch(todayExerciseKcalProvider).value;
    final exerciseKcal = mergeBurnKcal(
      systemKcal: systemKcal,
      manualKcal: manualKcal,
    );

    final String text;
    final Color textColor;
    final IconData icon;
    if (intake == null) {
      // 引导态：当日 0 条记录（与 mini signal-card 空态同口径）。
      text = t.fasting.home.budgetEmpty(kcal: goal.targetKcal);
      textColor = colors.textSecondary;
      icon = Icons.restaurant_outlined;
    } else {
      final eaten = intake.kcal.round();
      final left = goal.targetKcal - eaten;
      final base = left >= 0
          ? t.fasting.home.budgetNormal(eaten: eaten, left: left)
          : t.fasting.home.budgetOver(eaten: eaten, over: -left);
      final exercise = exerciseKcal != null && exerciseKcal > 0
          ? t.fasting.home.budgetExercise(kcal: exerciseKcal.round())
          : '';
      text = '$base$exercise';
      textColor = left >= 0 ? colors.textPrimary : colors.signalRed;
      icon = left >= 0
          ? Icons.local_fire_department_outlined
          : Icons.warning_amber_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            // 窄屏三段齐（已吃/还可吃/运动）一行放不下——曾 ellipsis 截成
            // 「运…」（真机走查）；放开两行自然换行，信息完整优先。
            child: Text(
              text,
              style: textStyles.textSm.copyWith(color: textColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
