import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/domain/weekly_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

/// 「上周小结」卡（薄荷走查 P1，对标薄荷「上周状态分」）：上一个完整自然周
///（周一～周日）的断食达标/记录天数/平均摄入 vs 目标/体重变化四格统计 +
/// 模板化 2–3 句总结。纯本地数据模板拼接，**不调用任何模型**、不给医疗
/// 建议，结尾固定带「仅供健康生活方式参考」。上周 0 记录走引导文案。
class WeeklySummaryCard extends ConsumerWidget {
  const WeeklySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final summaryT = t.reports.weeklySummary;

    final summary = ref.watch(weeklySummaryProvider).valueOrNull;

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
            summaryT.title,
            style: textStyles.textLg.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (summary != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s1),
            Text(
              t.reports.weekly.range(
                start: DateFormat.Md(
                  Localizations.localeOf(context).toString(),
                ).format(summary.weekStart),
                end: DateFormat.Md(
                  Localizations.localeOf(context).toString(),
                ).format(summary.weekEnd),
              ),
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          if (summary == null || !summary.hasData)
            _SummaryEmpty(message: summaryT.empty)
          else
            _SummaryBody(summary: summary),
        ],
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.summary});

  final WeeklySummary summary;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final summaryT = t.reports.weeklySummary;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;

    final weightDelta = summary.weightDeltaKg;
    final chips = <String>[
      summaryT.chipQualified(days: summary.qualifiedDays),
      summaryT.chipRecorded(days: summary.recordedDays),
      if (summary.avgKcal != null)
        summaryT.chipAvgKcal(
          kcal: summary.avgKcal!.round(),
          target: summary.targetKcal,
        ),
      if (weightDelta != null) summaryT.chipWeight(kg: _signed(weightDelta)),
    ];

    final sentences = <String>[
      for (final sentence in weeklySummarySentences(summary))
        _sentenceText(summaryT, sentence),
    ];
    // 中文用「；」串句并补句号；英文空格串句并补句点。
    final summaryText = isEn
        ? '${sentences.join(' ')}.'
        : '${sentences.join('；')}。';

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
        Text(
          summaryText,
          style: textStyles.textBase.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          summaryT.disclaimer,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  /// 体重变化带符号（+0.4 / −0.6，与月报卡同用 − U+2212）。
  static String _signed(double delta) {
    final abs = delta.abs().toStringAsFixed(1);
    if (delta.abs() < weeklySummaryWeightEpsilon) return '±$abs';
    return delta > 0 ? '+$abs' : '−$abs';
  }

  String _sentenceText(
    Translations$reports$weeklySummary$zh_CN summaryT,
    WeeklySummarySentence sentence,
  ) {
    final days = summary.qualifiedDays;
    final delta = (summary.qualifiedDays - summary.prevQualifiedDays).abs();
    final kcal = summary.avgKcal?.round() ?? 0;
    final percent = weeklySummaryIntakeDeviationPercent(summary);
    final kg = (summary.weightDeltaKg ?? 0).abs().toStringAsFixed(1);
    return switch (sentence) {
      WeeklySummarySentence.fastingPlain => summaryT.fastingPlain(days: days),
      WeeklySummarySentence.fastingMore => summaryT.fastingMore(
        days: days,
        delta: delta,
      ),
      WeeklySummarySentence.fastingLess => summaryT.fastingLess(
        days: days,
        delta: delta,
      ),
      WeeklySummarySentence.fastingSame => summaryT.fastingSame(days: days),
      WeeklySummarySentence.intakeWithin => summaryT.intakeWithin(kcal: kcal),
      WeeklySummarySentence.intakeAbove => summaryT.intakeAbove(
        kcal: kcal,
        percent: percent,
      ),
      WeeklySummarySentence.intakeBelow => summaryT.intakeBelow(
        kcal: kcal,
        percent: percent,
      ),
      WeeklySummarySentence.weightUp => summaryT.weightUp(kg: kg),
      WeeklySummarySentence.weightDown => summaryT.weightDown(kg: kg),
      WeeklySummarySentence.weightSame => summaryT.weightSame,
    };
  }
}

class _SummaryEmpty extends StatelessWidget {
  const _SummaryEmpty({required this.message});

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
          Icon(Icons.auto_awesome, color: colors.textSecondary, size: 32),
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
