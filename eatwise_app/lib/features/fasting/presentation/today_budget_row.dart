import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/widgets/metric_card.dart';
import 'package:eatwise/features/health/application/activity_summary_provider.dart';
import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 首页「今日指标」2 列网格（2026-09-29 UI 重构，替代原一行预算行）：
/// 今日热量 / 运动消耗 / 今日饮水 / 今日步数 四张 [MetricCard]
/// （华为运动健康看板语言：圆形图标徽标 + 大数字 + 迷你进度条 + 说明行）。
///
/// 首页「运动与步数」两列卡（2026-09-30 UI 换代 v2 改）：
/// 断食/热量/饮水三指标已上移至三环仪表 + 三列图例，本区只剩
/// 运动消耗 / 今日步数两卡，避免与仪表重复展示。
///
/// 数据全部复用既有 provider（系统健康数据 系统活动 +
/// 手动运动数据 手动合计 +
/// [exerciseGoalsProvider] 步数目标），不引入新存储；换算口径与数据页
/// 完全一致（activitySummaryProvider，系统优先、手动补充）。
class TodayMetricGrid extends ConsumerWidget {
  const TodayMetricGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;

    final activity = ref.watch(activitySummaryProvider);
    final goals = ref.watch(exerciseGoalsProvider);

    final exerciseKcal = activity.burnKcal;
    final steps = activity.steps;

    void openToday() {
      ref.read(selectedDateProvider.notifier).backToToday();
      context.go('/data');
    }

    final exerciseCard = MetricCard(
      onTap: openToday,
      icon: Icons.local_fire_department_rounded,
      iconColor: colors.ringExercise,
      label: t.fasting.home.metricExercise,
      value: exerciseKcal?.round().toString() ?? '—',
      unit: exerciseKcal != null ? t.record.nutrition.kcalUnit : null,
      caption: exerciseKcal == null
          ? null
          : activity.systemEnergy
          ? t.nutrition.data.burn.systemSource
          : t.nutrition.data.burn.manualSource,
    );
    final stepsCard = MetricCard(
      onTap: openToday,
      icon: Icons.directions_walk_rounded,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final twoColumns = constraints.maxWidth >= 240 * textScale;
        if (twoColumns) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: exerciseCard),
              const SizedBox(width: AppSpacing.s3),
              Expanded(child: stepsCard),
            ],
          );
        }
        return Column(
          children: <Widget>[
            exerciseCard,
            const SizedBox(height: AppSpacing.s3),
            stepsCard,
          ],
        );
      },
    );
  }
}
