import 'package:eatwise/app/l10n/strings.g.dart';

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/widgets/chart_labels.dart';
import 'package:eatwise/core/widgets/glass.dart';
import 'package:eatwise/core/widgets/quiet_tabs.dart';
import 'package:eatwise/features/nutrition/application/nutrition_data_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

/// 近 7 日趋势图（设计稿 §4.2-③：绿描线，区段间距 32）：
/// 热量 / 断食时长双序列切换，随顶部日期切换联动（终点 = 选中日）。
///
/// 自绘 CustomPaint（零新增依赖）；空数据走引导文案（不渲染误导性曲线）。
class TrendChartSection extends ConsumerStatefulWidget {
  const TrendChartSection({super.key});

  @override
  ConsumerState<TrendChartSection> createState() => _TrendChartSectionState();
}

class _TrendChartSectionState extends ConsumerState<TrendChartSection> {
  bool _showFasting = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final trend = t.nutrition.data.trend;

    final end = ref.watch(selectedDateProvider);
    final values = _showFasting
        ? ref.watch(weeklyFastingHoursProvider)
        : ref.watch(weeklyKcalProvider);
    final hasAny = values.any((v) => v != null);
    final latestIndex = values.lastIndexWhere((value) => value != null);
    final latest = latestIndex < 0 ? null : values[latestIndex]!;
    final unit = _showFasting ? trend.hourUnit : t.record.nutrition.kcalUnit;
    final labels = List<String>.generate(7, (i) {
      final date = end.subtract(Duration(days: 6 - i));
      return DateFormat.Md(
        Localizations.localeOf(context).toString(),
      ).format(date);
    });

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: AppSurfaces.card(colors, shadows),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            trend.title,
            style: textStyles.textLg.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          AppQuietTabs<bool>(
            values: const <bool>[false, true],
            selected: _showFasting,
            labelOf: (fasting) => fasting ? trend.fasting : trend.kcal,
            onSelected: (fasting) => setState(() => _showFasting = fasting),
          ),
          if (latest != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      latest.toStringAsFixed(
                        latest == latest.roundToDouble() ? 0 : 1,
                      ),
                      style: textStyles.textDisplay.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s1),
                Text(
                  unit,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.s2),
          Text(
            trend.unitLegend(unit: unit),
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
            maxLines: 1,
          ),
          const SizedBox(height: AppSpacing.s2),
          if (!hasAny)
            _TrendEmpty(message: trend.empty)
          else
            SizedBox(
              height: 184 + MediaQuery.textScalerOf(context).scale(24),
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendLinePainter(
                  values: values,
                  labels: labels,
                  // 双序列分色（2026-09-29 UI 重构）：热量=品牌绿、断食=青蓝
                  // （ringStand，苹果站立环同族色），图表配色走新强调色组。
                  lineColor: _showFasting
                      ? colors.ringStand
                      : colors.ringExercise,
                  labelColor: colors.textSecondary,
                  labelStyle: textStyles.textXs,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendEmpty extends StatelessWidget {
  const _TrendEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return SizedBox(
      height: 184 + MediaQuery.textScalerOf(context).scale(24),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.show_chart, color: colors.textSecondary, size: 32),
          const SizedBox(height: AppSpacing.s2),
          Text(
            message,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          // 空态三件套（薄荷走查 P2）：图标 + 引导文案 + 去记录 CTA。
          FilledButton(
            onPressed: () => context.go('/record'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.actionPrimary,
              foregroundColor: colors.onActionPrimary,
              minimumSize: const Size(0, AppSpacing.s12),
            ),
            child: Text(
              t.nutrition.data.trend.ctaRecord,
              style: textStyles.textBase.copyWith(
                color: colors.onActionPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 趋势图：上方数值带、中央折线、下方日期带，标签按实测宽度避让。
/// 无记录日（null）跳过不连线段。
class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.labelColor,
    required this.labelStyle,
    this.textScaler = TextScaler.noScaling,
  });

  final List<double?> values;
  final List<String> labels;
  final Color lineColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  /// 数值标签格式：整数不带小数位（14 而非 14.0），非整数保留 1 位。
  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    if (present.isEmpty) return;
    final maxV = present.reduce((a, b) => a > b ? a : b);
    // Y 轴零基线（本图只画热量/断食时长，均≥0）：min-max 归一化会把
    // 「16h→14h」的真实小波动渲染成「跌到图底=0」的假象（2026-10-04 wcg
    // 三轮「趋势 0 值」最终根因——数据早已修复，图被误读为仍是 0）。
    const minV = 0.0;
    final span = maxV == 0 ? 1.0 : maxV;
    final labelHeight = textScaler.scale(12) * 1.4;
    final chartBottom = size.height - labelHeight - 16;
    final chartTop = labelHeight + 24;

    Offset pointOf(int i) {
      final x = values.length == 1
          ? size.width / 2
          : 8 + (size.width - 16) * i / (values.length - 1);
      final v = values[i]!;
      final y = chartBottom - (v - minV) / span * (chartBottom - chartTop);
      return Offset(x, y);
    }

    // Quiet reference lines separate the plotting area from both label bands.
    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var row = 0; row <= 2; row++) {
      final y = chartTop + (chartBottom - chartTop) * row / 2;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), gridPaint);
    }
    // 折线（只连接两侧都有值的相邻点）。
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < values.length - 1; i++) {
      if (values[i] != null && values[i + 1] != null) {
        canvas.drawLine(pointOf(i), pointOf(i + 1), linePaint);
      }
    }
    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < values.length; i++) {
      if (values[i] != null) canvas.drawCircle(pointOf(i), 3, dotPaint);
    }
    // Values live in their own band, never on top of the line or target.
    final valueLayout = ChartLabelLayout(
      width: size.width,
      style: labelStyle.copyWith(color: lineColor, fontWeight: FontWeight.w600),
      textScaler: textScaler,
    );
    final lastIndex = values.lastIndexWhere((v) => v != null);
    for (final i in {lastIndex, ...chartLabelPriority(values.length)}) {
      final value = values[i];
      if (value == null || (values.length > 10 && i != lastIndex)) continue;
      valueLayout.paint(canvas, _fmt(value), pointOf(i).dx, 0);
    }
    final dateLayout = ChartLabelLayout(
      width: size.width,
      style: labelStyle.copyWith(color: labelColor),
      textScaler: textScaler,
    );
    for (final i in chartLabelPriority(labels.length)) {
      final label = labels[i];
      final x = values.length == 1
          ? size.width / 2
          : 8 + (size.width - 16) * i / (values.length - 1);
      dateLayout.paint(canvas, label, x, size.height - labelHeight);
    }
  }

  @override
  bool shouldRepaint(_TrendLinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.lineColor != lineColor;
  }
}
