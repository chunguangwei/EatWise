import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/widgets/metric_card.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 首页「今日指标」2 列网格（2026-09-29 UI 重构，替代原一行预算行）：
/// 今日热量 / 运动消耗 / 今日饮水 / 今日步数 四张 [MetricCard]
/// （华为运动健康看板语言：圆形图标徽标 + 大数字 + 迷你进度条 + 说明行）。
///
/// 数据全部复用既有 provider（[todayIntakeProvider] 当日聚合 +
/// [nutritionGoalProvider] 目标 + [healthSyncControllerProvider] 系统活动 +
/// [todayExerciseKcalProvider]/[todayExerciseStepsProvider] 手动合计 +
/// [todayWaterTotalProvider] 饮水 + [exerciseGoalsProvider] 步数目标），
/// 不引入新存储；换算口径与原预算行/数据页完全一致（mergeBurnKcal /
/// mergeSteps / 还可吃 = 目标 − 已吃可负）。
class TodayMetricGrid extends ConsumerWidget {
  const TodayMetricGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;

    final goal = ref.watch(nutritionGoalProvider);
    final intake = ref.watch(todayIntakeProvider);
    final health = ref.watch(healthSyncControllerProvider);
    final waterMl = ref.watch(todayWaterTotalProvider).value ?? 0;
    final goals = ref.watch(exerciseGoalsProvider);

    // 运动消耗 = 系统活动能量（如有）+ 今日手动运动 kcal 合计（与原预算行
    // 同口径合并；无 GMS 设备走手动兜底）。
    final systemKcal = health.status == HealthSyncStatus.ready
        ? health.today?.activeEnergyKcal
        : null;
    final exerciseKcal = mergeBurnKcal(
      systemKcal: systemKcal,
      manualKcal: ref.watch(todayExerciseKcalProvider).value,
    );
    // 步数 = 系统步数（如有）+ 手动/截图落库合计（与数据页同口径）。
    final systemSteps = health.status == HealthSyncStatus.ready
        ? health.today?.steps
        : null;
    final steps = mergeSteps(
      systemSteps: systemSteps,
      manualSteps: ref.watch(todayExerciseStepsProvider).value,
    );

    final eaten = intake?.kcal.round() ?? 0;
    final left = goal.targetKcal - eaten;

    final intakeCard = MetricCard(
      icon: Icons.restaurant_outlined,
      iconColor: colors.ringMove,
      label: t.fasting.home.metricIntake,
      value: '$eaten',
      unit: t.record.nutrition.kcalUnit,
      progress: goal.targetKcal > 0 ? eaten / goal.targetKcal : null,
      caption: intake == null
          ? t.fasting.home.budgetEmpty(kcal: goal.targetKcal)
          : left >= 0
          ? t.fasting.home.metricLeft(kcal: left)
          : t.fasting.home.metricOver(kcal: -left),
      onTap: () => context.go('/record'),
    );
    final exerciseCard = MetricCard(
      icon: Icons.local_fire_department_outlined,
      iconColor: colors.ringExercise,
      label: t.fasting.home.metricExercise,
      value: exerciseKcal?.round().toString() ?? '—',
      unit: exerciseKcal != null ? t.record.nutrition.kcalUnit : null,
      caption: t.fasting.home.metricBurnHint,
    );
    final waterCard = MetricCard(
      icon: Icons.water_drop_outlined,
      iconColor: colors.ringStand,
      label: t.fasting.home.metricWater,
      value: '$waterMl',
      unit: 'ml',
      progress: waterMl / WaterLogRepository.dailyGoalMl,
      caption: t.fasting.home.metricWaterGoal(
        ml: WaterLogRepository.dailyGoalMl,
      ),
      onTap: () => context.go('/record'),
    );
    final stepsCard = MetricCard(
      icon: Icons.directions_walk_outlined,
      iconColor: colors.chartPurple,
      label: t.fasting.home.metricSteps,
      value: steps?.toString() ?? '—',
      progress: steps != null ? steps / goals.stepsGoal : null,
      caption: steps != null
          ? t.nutrition.data.burn.stepsGoalProgress(
              steps: '$steps',
              goal: '${goals.stepsGoal}',
            )
          : t.nutrition.data.burn.manualGuide,
    );

    return Column(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: intakeCard),
            const SizedBox(width: AppSpacing.s3),
            Expanded(child: exerciseCard),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: waterCard),
            const SizedBox(width: AppSpacing.s3),
            Expanded(child: stepsCard),
          ],
        ),
      ],
    );
  }
}
