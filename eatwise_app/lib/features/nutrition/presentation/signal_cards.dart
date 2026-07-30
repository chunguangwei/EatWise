import 'dart:math' as math;

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/exposure_tracker.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/nutrition/application/advice_text.dart';
import 'package:flutter/material.dart';

/// 信号灯四卡栅格（设计稿 §4.2-③：`grid auto-fit minmax(150px,1fr)`，
/// 蛋白/碳水/脂肪/热量），每卡三重编码（色+图标+文字，M8 硬性）+
/// Inter 大数值（已摄入/目标）+ 一句话建议（§4 规则模板库）。
class SignalCardsGrid extends StatelessWidget {
  const SignalCardsGrid({
    required this.intake,
    required this.signal,
    required this.goal,
    required this.mealSegment,
    this.onCardTap,
    this.exposureDateKey = '',
    super.key,
  });

  /// 当日累计摄入（hasData=true 时非空）。
  final DailyIntake intake;

  /// 当日信号灯判定结果。
  final DailySignal signal;

  /// 每日营养目标（D-04）。
  final NutritionGoal goal;

  /// 当前餐段（建议模板 `{meal_action}` 插值）。
  final MealSegment mealSegment;

  /// 卡片点击回调（M4 埋点 signal_card_click 接线；可空）。
  final void Function(NutrientType nutrient, SignalVerdict verdict)? onCardTap;

  /// 曝光去重日期键（§4.1：attribute_date 变化重计；空串表示不区分日期）。
  final String exposureDateKey;

  /// 栅格最小卡宽（设计稿 minmax(150px,1fr)）。
  static const double minCardWidth = 150;

  @override
  Widget build(BuildContext context) {
    final nutrients = NutrientType.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        // auto-fit：能放几列放几列，卡宽最小 150。
        final cols = math.max(
          1,
          ((constraints.maxWidth + AppSpacing.s4) /
                  (minCardWidth + AppSpacing.s4))
              .floor(),
        );
        final rows = <Widget>[];
        for (var i = 0; i < nutrients.length; i += cols) {
          final chunk = nutrients.sublist(
            i,
            math.min(i + cols, nutrients.length),
          );
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var j = 0; j < chunk.length; j++) ...<Widget>[
                    if (j > 0) const SizedBox(width: AppSpacing.s4),
                    Expanded(
                      // 信号灯卡曝光（§3.4 signal_card_expose；组件级
                      // ≥50%+500ms，§4.1；一句话建议并入本事件不单设）。
                      // 去重键含 nutrient+signal_level+日期——内容变化重计。
                      child: ExposureTracker(
                        eventName: 'signal_card_expose',
                        dedupeKey:
                            'analytics:signal:${chunk[j].name}:${signal.verdicts[chunk[j]]!.zone.name}:$exposureDateKey',
                        properties: <String, Object?>{
                          'nutrient': _nutrientEventValue(chunk[j]),
                          'signal_level': signal.verdicts[chunk[j]]!.zone.name,
                          'advice_template_id': adviceKeyFor(
                            chunk[j],
                            signal.verdicts[chunk[j]]!.subZone,
                            zeroIntake: _actualOf(chunk[j]) == 0,
                          ),
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onCardTap == null
                              ? null
                              : () => onCardTap!(
                                  chunk[j],
                                  signal.verdicts[chunk[j]]!,
                                ),
                          child: SignalCard(
                            nutrient: chunk[j],
                            actual: _actualOf(chunk[j]),
                            target: _targetOf(chunk[j]),
                            verdict: signal.verdicts[chunk[j]]!,
                            mealSegment: mealSegment,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // 末行不足列数时补占位，保持列宽一致。
                  for (var k = chunk.length; k < cols; k++) ...<Widget>[
                    const SizedBox(width: AppSpacing.s4),
                    const Spacer(),
                  ],
                ],
              ),
            ),
          );
          if (i + cols < nutrients.length) {
            rows.add(const SizedBox(height: AppSpacing.s4));
          }
        }
        return Column(children: rows);
      },
    );
  }

  double _actualOf(NutrientType n) => switch (n) {
    NutrientType.kcal => intake.kcal,
    NutrientType.protein => intake.proteinG,
    NutrientType.carb => intake.carbG,
    NutrientType.fat => intake.fatG,
  };

  int _targetOf(NutrientType n) => switch (n) {
    NutrientType.kcal => goal.targetKcal,
    NutrientType.protein => goal.proteinG,
    NutrientType.carb => goal.carbG,
    NutrientType.fat => goal.fatG,
  };

  /// NutrientType → 事件字典 nutrient 枚举（§3.4：kcal → calorie）。
  static String _nutrientEventValue(NutrientType nutrient) {
    return switch (nutrient) {
      NutrientType.kcal => 'calorie',
      NutrientType.protein => 'protein',
      NutrientType.carb => 'carb',
      NutrientType.fat => 'fat',
    };
  }
}

/// 单张信号卡：营养名 + 大数值（已摄入/目标）+ 三重编码落区 + 一句话建议。
class SignalCard extends StatelessWidget {
  const SignalCard({
    required this.nutrient,
    required this.actual,
    required this.target,
    required this.verdict,
    required this.mealSegment,
    super.key,
  });

  final NutrientType nutrient;
  final double actual;
  final int target;
  final SignalVerdict verdict;
  final MealSegment mealSegment;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;

    final name = switch (nutrient) {
      NutrientType.kcal => t.record.nutrition.kcal,
      NutrientType.protein => t.record.nutrition.protein,
      NutrientType.carb => t.record.nutrition.carb,
      NutrientType.fat => t.record.nutrition.fat,
    };
    final unit = nutrient == NutrientType.kcal
        ? t.record.nutrition.kcalUnit
        : t.record.nutrition.gramUnit;
    final (zoneColor, zoneIcon, zoneLabel) = switch (verdict.zone) {
      SignalZone.green => (
        colors.signalGreen,
        Icons.check_circle,
        t.nutrition.signalCard.zone.green,
      ),
      SignalZone.yellow => (
        colors.signalYellow,
        Icons.error,
        t.nutrition.signalCard.zone.yellow,
      ),
      SignalZone.red => (
        colors.signalRed,
        Icons.cancel,
        t.nutrition.signalCard.zone.red,
      ),
    };
    final advice = adviceTextFor(
      t,
      nutrient: nutrient,
      subZone: verdict.subZone,
      zeroIntake: actual == 0,
      mealAction: mealActionTextFor(t, mealSegment),
    );

    return Semantics(
      label: '$name $zoneLabel',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: radii.rLg,
          boxShadow: shadows.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              name,
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s1),
            // Inter 大数值：已摄入（四态规范 4.1：数字按字截断）。
            Text(
              actual.toStringAsFixed(0),
              style: textStyles.text3xl.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '/ ${t.nutrition.data.proDetails.target} $target $unit',
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s2),
            // 三重编码：色 + 图标 + 文字（绝不单靠颜色，PRD M8）。
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              decoration: BoxDecoration(
                color: zoneColor.withValues(alpha: 0.16),
                borderRadius: radii.rFull,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(zoneIcon, color: zoneColor, size: 16),
                  const SizedBox(width: AppSpacing.s1),
                  Flexible(
                    child: Text(
                      zoneLabel,
                      style: textStyles.textXs.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 一句话建议：四态规范 4.1 —— 不允许截断，由文案长度上限约束。
            Text(
              advice,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
