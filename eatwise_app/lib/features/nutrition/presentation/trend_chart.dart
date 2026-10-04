import 'package:eatwise/app/l10n/strings.g.dart';

import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
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
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final trend = t.nutrition.data.trend;

    final end = ref.watch(selectedDateProvider);
    final values = _showFasting
        ? ref.watch(weeklyFastingHoursProvider)
        : ref.watch(weeklyKcalProvider);
    final hasAny = values.any((v) => v != null);
    final unit = _showFasting ? trend.hourUnit : t.record.nutrition.kcalUnit;
    final labels = List<String>.generate(7, (i) {
      final date = end.subtract(Duration(days: 6 - i));
      return DateFormat.Md(
        Localizations.localeOf(context).toString(),
      ).format(date);
    });

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
              Expanded(
                child: Text(
                  trend.title,
                  style: textStyles.textLg.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                  ),
                ),
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(
                      trend.kcal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(
                      trend.fasting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: <bool>{_showFasting},
                onSelectionChanged: (selection) =>
                    setState(() => _showFasting = selection.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          if (!hasAny)
            _TrendEmpty(message: trend.empty)
          else
            SizedBox(
              height: 160,
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
                  unitLegend: trend.unitLegend(unit: unit),
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
      height: 160,
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
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size(0, AppSpacing.s12),
            ),
            child: Text(
              t.nutrition.data.trend.ctaRecord,
              style: textStyles.textBase.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// 绿描线趋势图：折线 + 节点圆点 + 数值标签 + 单位图例 + 底部日期标签。
/// 无记录日（null）跳过不连线段。
class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.labelColor,
    required this.labelStyle,
    required this.unitLegend,
  });

  final List<double?> values;
  final List<String> labels;
  final Color lineColor;
  final Color labelColor;
  final TextStyle labelStyle;

  /// 单位图例（「单位：小时」/「Unit: h」/「单位：千卡」），画在图表区
  /// 左上角——单位不再拼接在每个数值后面。
  final String unitLegend;

  static const double _labelHeight = 20;
  static const double _topPadding = 24;

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
    final chartBottom = size.height - _labelHeight;
    final chartTop = _topPadding;

    Offset pointOf(int i) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final v = values[i]!;
      final y = chartBottom - (v - minV) / span * (chartBottom - chartTop);
      return Offset(x, y);
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
    // 节点圆点 + 逐点数值标签（本图固定 7 点，全标不糊）。
    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      canvas.drawCircle(pointOf(i), 3, dotPaint);
      _drawText(
        canvas,
        _fmt(v),
        Offset(pointOf(i).dx, pointOf(i).dy - 16),
        labelStyle.copyWith(color: lineColor),
        center: true,
      );
    }
    // 单位图例（左上角）。
    _drawText(
      canvas,
      unitLegend,
      Offset(0, 2),
      labelStyle.copyWith(color: labelColor),
    );
    // 底部日期标签。
    for (var i = 0; i < labels.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      _drawText(
        canvas,
        labels[i],
        Offset(x, size.height - _labelHeight + 4),
        labelStyle.copyWith(color: labelColor),
        center: true,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    TextStyle style, {
    bool center = false,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 72);
    var dx = position.dx;
    if (center) dx -= painter.width / 2;
    if (alignRight) dx -= painter.width;
    painter.paint(canvas, Offset(dx, position.dy));
  }

  @override
  bool shouldRepaint(_TrendLinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.lineColor != lineColor;
  }
}
