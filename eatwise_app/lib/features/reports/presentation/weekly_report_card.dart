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
import 'package:intl/intl.dart' show DateFormat;

/// M6 周期报告〔PRD 假设〕：本周报告卡（自然周，周一起算）——
/// 达标天数 / 记录条数 / 信号灯绿占比 + 一句话鼓励（品牌语气，双语）。
class WeeklyReportCard extends ConsumerWidget {
  const WeeklyReportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final weekly = t.reports.weekly;

    final stats = ref.watch(weeklyReportProvider).valueOrNull;

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
            weekly.title,
            style: textStyles.textLg.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (stats != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s1),
            Text(
              weekly.range(
                start: DateFormat.Md(
                  Localizations.localeOf(context).toString(),
                ).format(stats.weekStart),
                end: DateFormat.Md(
                  Localizations.localeOf(context).toString(),
                ).format(stats.weekEnd),
              ),
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          if (stats == null || !stats.hasData)
            _WeeklyEmpty(message: weekly.empty)
          else
            _WeeklyBody(stats: stats),
        ],
      ),
    );
  }
}

class _WeeklyBody extends StatelessWidget {
  const _WeeklyBody({required this.stats});

  final WeeklyReportStats stats;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final weekly = t.reports.weekly;

    final ratio = stats.greenRatio;
    final lines = <String>[
      weekly.qualified(days: stats.qualifiedDays),
      weekly.entries(count: stats.entryCount),
      if (ratio != null) weekly.greenRatio(percent: (ratio * 100).round()),
    ];

    // 鼓励语气：绿占比高且达标多 → great；几乎没动 → start；其余 mixed。
    final cheer = switch ((
      ratio != null && ratio >= 0.75 && stats.qualifiedDays >= 4,
      stats.entryCount <= 3 && stats.qualifiedDays <= 1,
    )) {
      (true, _) => weekly.cheer.great,
      (_, true) => weekly.cheer.start,
      _ => weekly.cheer.mixed,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: <Widget>[
            for (final line in lines)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s1,
                ),
                decoration: BoxDecoration(
                  color: colors.brandPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  line,
                  style: textStyles.textSm.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        Text(
          cheer,
          style: textStyles.textBase.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

class _WeeklyEmpty extends StatelessWidget {
  const _WeeklyEmpty({required this.message});

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
          Icon(
            Icons.calendar_month_outlined,
            color: colors.textSecondary,
            size: 32,
          ),
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
        ],
      ),
    );
  }
}
