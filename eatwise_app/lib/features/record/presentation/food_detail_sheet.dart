import 'dart:convert';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/domain/food_signal.dart';
import 'package:eatwise/features/record/domain/macro_energy.dart';
import 'package:eatwise/features/record/domain/nrv_reference.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/nutrition_label_ocr_logic.dart'
    show kKjPerKcal;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阶段 E 食物详情底部弹层（薄荷对标合并设计：信息分层——名称头部 →
/// 显著热量 → 三大营养素供能比例三圆环 + 人话注释 → 红绿灯评价徽标 →
/// 其余明细折叠区 → 份量输入直接入账）。
///
/// 薄荷复盘坑位落实：不做字母评级（A~D 反直觉）、不做跨类参照物、
/// 供能圆环带「脂肪供能效率 2.25 倍」注释避免误读为重量比例。
/// 份量双轨（口语化单位）不做——食物库无份量单位数据，遗留。
///
/// [onConfirm]：用户在弹层内点「确认记录」时回调（参数为份量输入原文），
/// 弹层先关闭，由调用方接既有记录确认流程（乐观更新 + D-11 撤销吐司），
/// 不破坏记录页既有入账交互与埋点链路。
Future<void> showFoodDetailSheet({
  required BuildContext context,
  required Food food,
  required ValueChanged<String> onConfirm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => FoodDetailSheet(
      food: food,
      onConfirm: (amountText) {
        Navigator.of(sheetContext).pop();
        onConfirm(amountText);
      },
    ),
  );
}

/// 食物详情弹层内容（直接构造可测）。
class FoodDetailSheet extends ConsumerStatefulWidget {
  const FoodDetailSheet({
    required this.food,
    required this.onConfirm,
    super.key,
  });

  /// 食物库条目。
  final Food food;

  /// 「确认记录」回调（份量输入原文，校验由既有入账流程统一做）。
  final ValueChanged<String> onConfirm;

  @override
  ConsumerState<FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<FoodDetailSheet> {
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 份量输入驱动营养预览实时重算（US-3.1 同口径）。
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final s = RecordStrings.of(context);
    final cs = CustomFoodStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    final food = widget.food;

    final goal = ref.watch(nutritionGoalProvider);
    final verdict = evaluateFoodSignal(
      kcalPer100g: food.kcalPer100g,
      proteinPer100g: food.proteinPer100g,
      carbPer100g: food.carbPer100g,
      fatPer100g: food.fatPer100g,
      goal: goal,
      config: NutritionRuleConfig.defaults,
    );
    final breakdown = computeMacroEnergyBreakdown(
      proteinG: food.proteinPer100g,
      carbG: food.carbPer100g,
      fatG: food.fatPer100g,
    );

    // 份量预览（按输入份量 × 每 100g 值换算，与记录页结果卡同格式）。
    final amount = double.tryParse(_amountController.text);
    final preview = amount != null && amount > 0 ? amount / 100 : null;
    // 「大约需走 N 步」随选中份量实时联动；未输入份量时按每 100g 展示。
    final walkSteps = stepsFromKcal(food.kcalPer100g * (preview ?? 1));

    return SafeArea(
      child: Padding(
        // 键盘顶起时整体上移（isScrollControlled 下 viewInsets 不被消化）。
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 头部：名称 + 自定义/社区状态标签。
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            isEn ? food.nameEn : food.nameZh,
                            style: textStyles.textXl,
                          ),
                        ),
                        if (cs.badgeFor(food) case final badgeText?)
                          Container(
                            margin: const EdgeInsets.only(left: AppSpacing.s2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s2,
                              vertical: AppSpacing.s1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.brandAccent,
                              borderRadius: radii.rSm,
                            ),
                            child: Text(
                              badgeText,
                              style: textStyles.textXs.copyWith(
                                color: colors.bgPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    // 红绿灯评价徽标（颜色 + 图标 + 文字三重编码，PRD M8/§3.3）。
                    _SignalBadge(verdict: verdict),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      t.record.foodDetail.badgeBasis,
                      style: textStyles.textXs.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    // 显著热量卡（用户最关心，薄荷分层第一位）：千卡/千焦并列。
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      decoration: BoxDecoration(
                        color: colors.bgSecondary,
                        borderRadius: radii.rLg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              Text(
                                '${food.kcalPer100g.round()}',
                                style: textStyles.textTimer.copyWith(
                                  color: colors.brandAccent,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s2),
                              Text(
                                t.record.foodDetail.kcalKj(
                                  kj: (food.kcalPer100g * kKjPerKcal).round(),
                                ),
                                style: textStyles.textSm.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s1),
                          // 「大约需走 N 步」（薄荷口径估算，随份量联动）。
                          Text(
                            t.record.foodDetail.walkSteps(steps: walkSteps),
                            style: textStyles.textXs.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    // 三大营养素供能比例三圆环（供能占比，非重量占比）。
                    Text(
                      t.record.foodDetail.macrosTitle,
                      style: textStyles.textBase,
                    ),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      t.record.foodDetail.energyShareNote,
                      style: textStyles.textXs.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: <Widget>[
                        _MacroRing(
                          label: s.nutritionProtein,
                          energy: breakdown.protein,
                          color: colors.brandPrimary,
                        ),
                        _MacroRing(
                          label: s.nutritionCarb,
                          energy: breakdown.carb,
                          color: colors.brandAccent,
                        ),
                        _MacroRing(
                          label: s.nutritionFat,
                          energy: breakdown.fat,
                          color: colors.brandPrimaryPressed,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    // 份量输入 + 营养预览（与记录页结果卡同格式）。
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: textStyles.textBase,
                      decoration: InputDecoration(
                        labelText: s.amountLabel,
                        filled: true,
                        fillColor: colors.bgSecondary,
                        border: OutlineInputBorder(
                          borderRadius: radii.rMd,
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (preview != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.s2),
                      Wrap(
                        spacing: AppSpacing.s2,
                        runSpacing: AppSpacing.s1,
                        children: <Widget>[
                          _PreviewChip(
                            text:
                                '${s.nutritionKcal} '
                                '${(food.kcalPer100g * preview).round()} '
                                '${s.kcalUnit}',
                          ),
                          _PreviewChip(
                            text:
                                '${s.nutritionProtein} '
                                '${(food.proteinPer100g * preview).toStringAsFixed(1)}'
                                ' ${s.gramUnit}',
                          ),
                          _PreviewChip(
                            text:
                                '${s.nutritionCarb} '
                                '${(food.carbPer100g * preview).toStringAsFixed(1)}'
                                ' ${s.gramUnit}',
                          ),
                          _PreviewChip(
                            text:
                                '${s.nutritionFat} '
                                '${(food.fatPer100g * preview).toStringAsFixed(1)}'
                                ' ${s.gramUnit}',
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s2),
                    // 其余明细折叠区（次级信息，默认收起）。
                    ExpansionTile(
                      title: Text(
                        t.record.foodDetail.moreTitle,
                        style: textStyles.textSm,
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(
                        bottom: AppSpacing.s2,
                      ),
                      children: <Widget>[
                        // NRV% 表（GB 28050 国标 NRV 值；只有库里有的营养素出行）。
                        _NrvTable(
                          rows: computeNrvRows(
                            kcalPer100g: food.kcalPer100g,
                            proteinPer100g: food.proteinPer100g,
                            carbPer100g: food.carbPer100g,
                            fatPer100g: food.fatPer100g,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        for (final row in <(String, MacroEnergy)>[
                          (s.nutritionProtein, breakdown.protein),
                          (s.nutritionCarb, breakdown.carb),
                          (s.nutritionFat, breakdown.fat),
                        ])
                          _DetailRow(
                            text:
                                '${row.$1} '
                                '${row.$2.grams.toStringAsFixed(1)} ${s.gramUnit} · '
                                '${t.record.foodDetail.supplyKcal(kcal: row.$2.kcal.round())}',
                          ),
                        if (_aliasText(food, isEn) case final aliasText?)
                          _DetailRow(
                            text: t.record.foodDetail.aliases(names: aliasText),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 直接入账按钮固定在滚动区外（小屏/键盘下恒可见；接既有记录
            // 确认流程：乐观更新 + D-11 撤销吐司）。
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s2,
                AppSpacing.s4,
                AppSpacing.s4,
              ),
              child: FilledButton(
                onPressed: () =>
                    widget.onConfirm(_amountController.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(s.confirm, style: textStyles.textBase),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 别名展示文本（JSON 字符串数组解码失败视为无别名）。
  static String? _aliasText(Food food, bool isEn) {
    final raw = isEn ? food.aliasesEn : food.aliasesZh;
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      final filtered = list.where((e) => e.trim().isNotEmpty).toList();
      if (filtered.isEmpty) return null;
      return filtered.join(isEn ? ', ' : '、');
    } on Object {
      return null;
    }
  }
}

/// 红绿灯评价徽标：颜色 + 图标 + 文字三重编码（红色仅表警告，§3.3）。
class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.verdict});

  final SignalVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final (color, icon, label) = switch (verdict.zone) {
      SignalZone.green => (
        colors.signalGreen,
        Icons.check_circle,
        t.record.foodDetail.badgeGreen,
      ),
      SignalZone.yellow => (
        colors.signalYellow,
        Icons.error,
        t.record.foodDetail.badgeYellow,
      ),
      SignalZone.red => (
        colors.signalRed,
        Icons.cancel,
        t.record.foodDetail.badgeRed,
      ),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: radii.rSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppSpacing.s1),
            Text(label, style: textStyles.textSm.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 单个供能比例圆环（自绘轻量组件：背景圈 + 占比弧 + 中心百分比）。
class _MacroRing extends StatelessWidget {
  const _MacroRing({
    required this.label,
    required this.energy,
    required this.color,
  });

  final String label;
  final MacroEnergy energy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final colors = Theme.of(context).extension<AppColors>()!;
    final percent = (energy.share * 100).round();
    return Expanded(
      child: Semantics(
        label: '$label $percent%',
        child: Column(
          children: <Widget>[
            SizedBox(
              width: 64,
              height: 64,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: energy.share.clamp(0.0, 1.0),
                  color: color,
                  trackColor: colors.border.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: Text('$percent%', style: textStyles.textBase),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              label,
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 8.0;
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(inset, 0, 2 * 3.141592653589793, false, trackPaint);
    if (fraction <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      inset,
      -3.141592653589793 / 2,
      2 * 3.141592653589793 * fraction,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rSm,
      ),
      child: Text(
        text,
        style: textStyles.textXs.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s1),
        child: Text(
          text,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// NRV% 明细表（薄荷走查 P1：营养素 | 每 100 克 | NRV% 三列；
/// NRV 国标值见 domain/nrv_reference.dart，只有库里有的营养素出行）。
class _NrvTable extends StatelessWidget {
  const _NrvTable({required this.rows});

  final List<NrvRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final headerStyle = textStyles.textXs.copyWith(color: colors.textSecondary);
    final cellStyle = textStyles.textSm.copyWith(color: colors.textSecondary);

    String labelOf(NrvNutrient nutrient) => switch (nutrient) {
      NrvNutrient.energy => t.record.nutrition.kcal,
      NrvNutrient.protein => t.record.nutrition.protein,
      NrvNutrient.carb => t.record.nutrition.carb,
      NrvNutrient.fat => t.record.nutrition.fat,
      NrvNutrient.sodium => t.record.nutrition.sodium,
    };

    String amountOf(NrvRow row) => switch (row.nutrient) {
      NrvNutrient.energy =>
        '${row.amount.round()} ${t.record.nutrition.kjUnit}',
      NrvNutrient.sodium =>
        '${row.amount.round()} ${t.record.nutrition.mgUnit}',
      _ => '${row.amount.toStringAsFixed(1)} ${t.record.nutrition.gramUnit}',
    };

    Widget cell(
      String text,
      TextStyle style, {
      int flex = 1,
      bool end = false,
    }) {
      return Expanded(
        flex: flex,
        child: Text(
          text,
          style: style,
          textAlign: end ? TextAlign.end : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s1),
          child: Row(
            children: <Widget>[
              cell(t.record.foodDetail.nutrientColumn, headerStyle, flex: 3),
              cell(
                t.record.foodDetail.per100g,
                headerStyle,
                flex: 2,
                end: true,
              ),
              cell(t.record.foodDetail.nrvColumn, headerStyle, end: true),
            ],
          ),
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s1),
            child: Row(
              children: <Widget>[
                cell(labelOf(row.nutrient), cellStyle, flex: 3),
                cell(amountOf(row), cellStyle, flex: 2, end: true),
                cell('${row.nrvPercent.round()}%', cellStyle, end: true),
              ],
            ),
          ),
      ],
    );
  }
}
