import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/widgets/metric_card.dart';
import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页「今日指标」2 列网格（2026-09-29 UI 重构，替代原一行预算行）：
/// 今日热量 / 运动消耗 / 今日饮水 / 今日步数 四张 [MetricCard]
/// （华为运动健康看板语言：圆形图标徽标 + 大数字 + 迷你进度条 + 说明行）。
///
/// 首页「运动与步数」两列卡（2026-09-30 UI 换代 v2 改）：
/// 断食/热量/饮水三指标已上移至三环仪表 + 三列图例，本区只剩
/// 运动消耗 / 今日步数两卡，避免与仪表重复展示。
///
/// 数据全部复用既有 provider（[healthSyncControllerProvider] 系统活动 +
/// [todayExerciseKcalProvider]/[todayExerciseStepsProvider] 手动合计 +
/// [exerciseGoalsProvider] 步数目标），不引入新存储；换算口径与数据页
/// 完全一致（mergeBurnKcal / mergeSteps）。
class TodayMetricGrid extends ConsumerWidget {
  const TodayMetricGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;

    final health = ref.watch(healthSyncControllerProvider);
    final goals = ref.watch(exerciseGoalsProvider);

    // 运动消耗 = 系统活动能量（如有）+ 今日手动运动 kcal 合计（与数据页
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

    final exerciseCard = MetricCard(
      icon: Icons.local_fire_department_outlined,
      iconColor: colors.ringExercise,
      label: t.fasting.home.metricExercise,
      value: exerciseKcal?.round().toString() ?? '—',
      unit: exerciseKcal != null ? t.record.nutrition.kcalUnit : null,
      caption: t.fasting.home.metricBurnHint,
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: exerciseCard),
        const SizedBox(width: AppSpacing.s3),
        Expanded(child: stepsCard),
      ],
    );
  }
}
