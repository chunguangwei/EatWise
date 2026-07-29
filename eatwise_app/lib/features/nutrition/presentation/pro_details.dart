import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 专业数据折叠区（PRD M4 / 设计稿 §4.2-③：默认折叠，展开 affordance 明确
/// ——箭头 + 「查看详情」，评审建议改进项 4）。
///
/// 展开内容：目标值 / 已摄入 / 占比 / RDA 参考。
class ProDetailsSection extends ConsumerStatefulWidget {
  const ProDetailsSection({
    required this.intake,
    required this.goal,
    super.key,
  });

  final DailyIntake intake;
  final NutritionGoal goal;

  @override
  ConsumerState<ProDetailsSection> createState() => _ProDetailsSectionState();
}

class _ProDetailsSectionState extends ConsumerState<ProDetailsSection> {
  bool _expanded = false;

  void _toggle() {
    // 专业数据展开埋点（§3.4 pro_data_expand；仅展开方向上报）。
    if (!_expanded) {
      ref
          .read(analyticsServiceProvider)
          .track(
            'pro_data_expand',
            properties: const <String, Object?>{
              'date_offset': 0,
              'expand_source': 'arrow',
            },
          );
    }
    setState(() => _expanded = !_expanded);
  }

  /// RDA 参考值〔假设〕：成人通用膳食参考（《中国居民膳食营养素参考
  /// 摄入量》口径取整），**待营养专业侧书面背书**；个人目标以用户方案为准。
  static const Map<NutrientType, double> rdaReference = <NutrientType, double>{
    NutrientType.kcal: 2000,
    NutrientType.protein: 60,
    NutrientType.carb: 275,
    NutrientType.fat: 67,
  };

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final pd = t.nutrition.data.proDetails;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowSm,
      ),
      child: Column(
        children: <Widget>[
          // 展开 affordance：图标 + 标题 + 「查看详情/收起」+ 箭头，≥44px。
          InkWell(
            borderRadius: radii.rLg,
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.science_outlined,
                      color: colors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        pd.title,
                        style: textStyles.textBase.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _expanded ? pd.collapse : pd.expand,
                      style: textStyles.textSm.copyWith(
                        color: colors.brandPrimary,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: colors.brandPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                AppSpacing.s4,
              ),
              child: _DetailsTable(
                intake: widget.intake,
                goal: widget.goal,
                rda: rdaReference,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({
    required this.intake,
    required this.goal,
    required this.rda,
  });

  final DailyIntake intake;
  final NutritionGoal goal;
  final Map<NutrientType, double> rda;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final pd = t.nutrition.data.proDetails;

    return Column(
      children: <Widget>[
        _Row(
          cells: <String>['', pd.target, pd.actual, pd.percent, pd.rda],
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
        const Divider(height: AppSpacing.s4),
        for (final n in NutrientType.values) ...<Widget>[
          _nutrientRow(t, n, textStyles, colors),
          if (n != NutrientType.values.last)
            const SizedBox(height: AppSpacing.s2),
        ],
        const SizedBox(height: AppSpacing.s3),
        Text(
          pd.rdaNote,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _nutrientRow(
    Translations t,
    NutrientType n,
    AppTextStyles textStyles,
    AppColors colors,
  ) {
    final name = switch (n) {
      NutrientType.kcal => t.record.nutrition.kcal,
      NutrientType.protein => t.record.nutrition.protein,
      NutrientType.carb => t.record.nutrition.carb,
      NutrientType.fat => t.record.nutrition.fat,
    };
    final unit = n == NutrientType.kcal
        ? t.record.nutrition.kcalUnit
        : t.record.nutrition.gramUnit;
    final (actual, target) = switch (n) {
      NutrientType.kcal => (intake.kcal, goal.targetKcal.toDouble()),
      NutrientType.protein => (intake.proteinG, goal.proteinG.toDouble()),
      NutrientType.carb => (intake.carbG, goal.carbG.toDouble()),
      NutrientType.fat => (intake.fatG, goal.fatG.toDouble()),
    };
    final percent = actual / target * 100;
    return _Row(
      cells: <String>[
        name,
        '${target.toStringAsFixed(0)} $unit',
        '${actual.toStringAsFixed(0)} $unit',
        '${percent.toStringAsFixed(0)}%',
        '${rda[n]!.toStringAsFixed(0)} $unit',
      ],
      style: textStyles.textSm.copyWith(color: colors.textPrimary),
      firstCellStyle: textStyles.textSm.copyWith(color: colors.textPrimary),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, required this.style, this.firstCellStyle});

  final List<String> cells;
  final TextStyle style;
  final TextStyle? firstCellStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: i == 0 ? 3 : 4,
            child: Text(
              cells[i],
              style: i == 0 ? (firstCellStyle ?? style) : style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
            ),
          ),
      ],
    );
  }
}
