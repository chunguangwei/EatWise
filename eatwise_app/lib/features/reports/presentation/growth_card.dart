import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// M6 成长轨迹卡（设计稿信息图 ⑦「7天/30天成长轨迹」）：
/// 达标天数 / 记录天数 / 平均断食时长 / 体重变化 Δ 四格摘要，
/// 随趋势区时间范围（7/30 天）联动；全无数据走引导空态。
class GrowthSummaryCard extends ConsumerWidget {
  const GrowthSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final growth = t.reports.growth;

    final range = ref.watch(reportRangeProvider);
    final summary = ref.watch(growthSummaryProvider);

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
          Text(
            growth.title(days: range.days),
            style: textStyles.textLg.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s3),
          if (!summary.hasData)
            _GrowthEmpty(message: growth.empty)
          else
            _StatGrid(summary: summary),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.summary});

  final GrowthSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final growth = t.reports.growth;

    final delta = summary.weightDeltaKg;
    final deltaText = delta == null
        ? growth.noValue
        : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} ${growth.kgUnit}';

    final cells = <(String, String, IconData)>[
      (
        growth.qualifiedDays,
        '${summary.qualifiedDays} ${growth.daysUnit}',
        Icons.local_fire_department_outlined,
      ),
      (
        growth.recordedDays,
        '${summary.recordedDays} ${growth.daysUnit}',
        Icons.edit_note,
      ),
      (
        growth.avgFasting,
        summary.avgFastingHours == null
            ? growth.noValue
            : '${summary.avgFastingHours!.toStringAsFixed(1)} ${growth.hourUnit}',
        Icons.timer_outlined,
      ),
      (growth.weightDelta, deltaText, Icons.monitor_weight_outlined),
    ];

    return Row(
      children: <Widget>[
        for (var i = 0; i < cells.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _StatCell(
              label: cells[i].$1,
              value: cells[i].$2,
              icon: cells[i].$3,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s3,
        horizontal: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: colors.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 20, color: colors.brandPrimary),
          const SizedBox(height: AppSpacing.s1),
          Text(
            value,
            style: textStyles.textBase.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s1),
          // 标签允许两行换行（走查：英文长标签如 "Fasting goals hit"
          // 单行省略截断后读不出含义；两行内仍放不下才省略）。
          Text(
            label,
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 成长轨迹空态（鼓励语气 + 去记录 CTA）。
class _GrowthEmpty extends StatelessWidget {
  const _GrowthEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AppSpacing.s2),
          Icon(Icons.eco_outlined, color: colors.textSecondary, size: 32),
          const SizedBox(height: AppSpacing.s2),
          Text(
            message,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          FilledButton(
            onPressed: () => context.go('/record'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size(0, AppSpacing.s12),
            ),
            child: Text(
              t.reports.trend.ctaRecord,
              style: textStyles.textBase.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
        ],
      ),
    );
  }
}
