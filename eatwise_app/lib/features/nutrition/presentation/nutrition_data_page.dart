import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:eatwise/features/nutrition/presentation/date_switcher.dart';
import 'package:eatwise/features/nutrition/presentation/pro_details.dart';
import 'package:eatwise/features/nutrition/presentation/signal_cards.dart';
import 'package:eatwise/features/nutrition/presentation/trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// M4 数据页（/data Tab，PRD M4 / 设计稿 §4.2-③）：
/// 顶部日期切换 + 一句话总结（H2 温和语气）→ 信号灯四卡（三重编码 +
/// 一句话建议）→ 专业数据折叠 → 近 7 日趋势图（区段间距 32）。
///
/// 当日无记录 → 空态引导去记录（CTA 跳 /record），不渲染误导性信号灯
/// （D-05 / §3.2）；目标走 D-04 兜底时给出补全资料提示。
class NutritionDataPage extends ConsumerWidget {
  const NutritionDataPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    final intake = ref.watch(dayIntakeProvider);
    final signal = ref.watch(daySignalsProvider);
    final goal = ref.watch(nutritionGoalProvider);
    final tone = ref.watch(daySummaryProvider);
    final mealSegment = ref.watch(mealSegmentProvider);
    final isLocalEstimate =
        ref.watch(dayCacheProvider).valueOrNull?.isLocalEstimate ?? false;

    final summaryText = switch (tone) {
      DaySummaryTone.empty => t.nutrition.data.summary.empty,
      DaySummaryTone.allGreen => t.nutrition.data.summary.allGreen,
      DaySummaryTone.hasYellow => t.nutrition.data.summary.hasYellow,
      DaySummaryTone.hasRed => t.nutrition.data.summary.hasRed,
    };

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.home.tab.data, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const DateSwitcher(),
            const SizedBox(height: AppSpacing.s2),
            // 一句话总结（H2，温和品牌语气）。
            Text(
              summaryText,
              style: textStyles.textXl.copyWith(color: colors.textPrimary),
            ),
            // D-04 兜底目标 → 引导补全资料。
            if (goal.usedFallback) ...<Widget>[
              const SizedBox(height: AppSpacing.s2),
              _HintBanner(
                icon: Icons.info_outline,
                text: t.nutrition.data.summary.fallbackGoal,
              ),
            ],
            // 本地预估角标（§2.6：isLocalEstimate 时注明待云端校准）。
            if (signal.hasData && isLocalEstimate) ...<Widget>[
              const SizedBox(height: AppSpacing.s1),
              Text(
                t.nutrition.data.localEstimate,
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.s6),
            // 信号灯区：无记录走空态，不出现误导性信号灯（D-05）。
            if (signal.hasData && intake != null)
              SignalCardsGrid(
                intake: intake,
                signal: signal,
                goal: goal,
                mealSegment: mealSegment,
              )
            else
              const _EmptyDayState(),
            if (signal.hasData && intake != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s8),
              ProDetailsSection(intake: intake, goal: goal),
            ],
            const SizedBox(height: AppSpacing.s8),
            const TrendChartSection(),
          ],
        ),
      ),
    );
  }
}

/// 兜底/提示横幅（温和语气，非警告）。
class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: colors.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.brandPrimary),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 当日无记录空态（四态规范 3.2.2：主/副文案 + CTA；CTA 跳 /record）。
class _EmptyDayState extends StatelessWidget {
  const _EmptyDayState();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s6),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.restaurant_outlined,
            size: 48,
            color: colors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            t.home.data.emptyTitle,
            style: textStyles.textBase.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            t.home.data.emptySubtitle,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          FilledButton(
            onPressed: () => context.go('/record'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size.fromHeight(AppSpacing.s12),
            ),
            child: Text(
              t.home.data.cta,
              style: textStyles.textBase.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
