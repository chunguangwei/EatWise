import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/monthly_report.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

/// M6 月报卡片（轻量版，2026-09-07 拍板范围）：本地生成的自然月统计——
/// 达标天数 / 平均断食时长 / 月均营养 vs 目标 / 体重变化，
/// 月份可左右切换（未来月不可达），空数据走引导空态。
class MonthlyReportCard extends ConsumerWidget {
  const MonthlyReportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final monthly = t.reports.monthly;

    final month = ref.watch(monthlyReportMonthProvider);
    final now = ref.watch(reportsNowProvider);
    final canGoNext =
        month.year < now.year ||
        (month.year == now.year && month.month < now.month);
    final report = ref.watch(monthlyReportProvider).valueOrNull;

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
              IconButton(
                onPressed: () =>
                    ref.read(monthlyReportMonthProvider.notifier).previous(),
                tooltip: monthly.prevMonth,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.chevron_left, color: colors.textPrimary),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(
                    Localizations.localeOf(context).toString(),
                  ).format(month),
                  style: textStyles.textLg.copyWith(color: colors.textPrimary),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: canGoNext
                    ? () => ref.read(monthlyReportMonthProvider.notifier).next()
                    : null,
                tooltip: monthly.nextMonth,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.chevron_right,
                  color: canGoNext ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          if (report == null || !report.hasData)
            _MonthlyEmpty(message: monthly.empty, hint: monthly.emptyHint)
          else
            _MonthlyBody(report: report),
        ],
      ),
    );
  }
}

class _MonthlyBody extends StatelessWidget {
  const _MonthlyBody({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final monthly = t.reports.monthly;

    final chips = <String>[
      monthly.qualified(days: report.qualifiedDays),
      monthly.recordedDays(days: report.daysWithRecords),
    ];
    final fastedMinutes = report.avgFastedMinutes;
    if (fastedMinutes != null) {
      final total = fastedMinutes.round();
      final hours = total ~/ 60;
      final minutes = total % 60;
      chips.add(
        minutes == 0
            ? monthly.avgFastingHours(hours: hours)
            : monthly.avgFastingHoursMinutes(hours: hours, minutes: minutes),
      );
    }

    final kcal = report.avgKcal;
    final weight = report.weightChangeKg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: <Widget>[
            for (final chip in chips)
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
                  chip,
                  style: textStyles.textSm.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s3),
        if (kcal != null)
          Text(
            monthly.kcalAvg(kcal: kcal.round(), target: report.targetKcal),
            style: textStyles.textBase.copyWith(color: colors.textPrimary),
          ),
        if (report.avgProteinG != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s1),
            child: Text(
              monthly.macros(
                protein: report.avgProteinG!.round(),
                carbs: report.avgCarbsG!.round(),
                fat: report.avgFatG!.round(),
              ),
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          monthly.weightChange(
            value: weight == null
                ? t.reports.growth.noValue
                : '${weight >= 0 ? '+' : '−'}${weight.abs().toStringAsFixed(1)} kg',
          ),
          style: textStyles.textBase.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

class _MonthlyEmpty extends StatelessWidget {
  const _MonthlyEmpty({required this.message, required this.hint});

  final String message;
  final String hint;

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
            style: textStyles.textSm.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            hint,
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
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
