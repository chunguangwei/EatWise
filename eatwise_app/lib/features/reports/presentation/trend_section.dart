import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

/// M6 趋势图区（PRD M6 / 设计稿信息图 ⑦）：
/// 三维切换（体重/热量/断食时长）× 两档时间范围（7/30 天），
/// 自绘折线复用 M4 风格（绿描线、留白、无数据日断点不连线）。
///
/// 空数据走引导空态（四态规范 3.2.2：主文案 + CTA），不渲染空坐标轴。
class ReportTrendSection extends ConsumerWidget {
  const ReportTrendSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final trend = t.reports.trend;

    final dimension = ref.watch(reportDimensionProvider);
    final range = ref.watch(reportRangeProvider);
    final values = ref.watch(trendSeriesProvider);
    final hasAny = values.any((v) => v != null);

    final end = ref.watch(reportsNowProvider);
    final locale = Localizations.localeOf(context).toString();
    final labelEvery = (range.days / 5).ceil();
    final labels = List<String?>.generate(range.days, (i) {
      if (i % labelEvery != 0 && i != range.days - 1) return null;
      final date = end.subtract(Duration(days: range.days - 1 - i));
      return DateFormat.Md(locale).format(date);
    });

    final unit = switch (dimension) {
      ReportDimension.weight => trend.unit.kg,
      ReportDimension.kcal => trend.unit.kcal,
      ReportDimension.fasting => trend.unit.hour,
    };

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
            trend.title,
            style: textStyles.textLg.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s3),
          // 维度切换（三维）。
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ReportDimension>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
              ),
              segments: <ButtonSegment<ReportDimension>>[
                ButtonSegment<ReportDimension>(
                  value: ReportDimension.weight,
                  label: Text(
                    trend.dim.weight,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment<ReportDimension>(
                  value: ReportDimension.kcal,
                  label: Text(
                    trend.dim.kcal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment<ReportDimension>(
                  value: ReportDimension.fasting,
                  label: Text(
                    trend.dim.fasting,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: <ReportDimension>{dimension},
              onSelectionChanged: (selection) => ref
                  .read(reportDimensionProvider.notifier)
                  .select(selection.first),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          // 时间范围切换（7/30 天）。
          SegmentedButton<ReportRange>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            ),
            segments: <ButtonSegment<ReportRange>>[
              ButtonSegment<ReportRange>(
                value: ReportRange.d7,
                label: Text(
                  trend.range.d7,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment<ReportRange>(
                value: ReportRange.d30,
                label: Text(
                  trend.range.d30,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            selected: <ReportRange>{range},
            onSelectionChanged: (selection) =>
                ref.read(reportRangeProvider.notifier).select(selection.first),
          ),
          const SizedBox(height: AppSpacing.s4),
          if (!hasAny)
            _TrendEmpty(dimension: dimension)
          else
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CustomPaint(
                painter: ReportTrendPainter(
                  values: values,
                  labels: labels,
                  lineColor: colors.brandPrimary,
                  labelColor: colors.textSecondary,
                  labelStyle: textStyles.textXs,
                  unit: unit,
                  fractionDigits: dimension == ReportDimension.kcal ? 0 : 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 趋势空态：引导文案 + 按维度给 CTA（不渲染空坐标轴）。
class _TrendEmpty extends StatelessWidget {
  const _TrendEmpty({required this.dimension});

  final ReportDimension dimension;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final trend = t.reports.trend;

    // 体重录入入口〔遗留〕record 模块落地前先跳记录页。
    final (cta, route) = switch (dimension) {
      ReportDimension.weight => (trend.ctaWeight, '/record'),
      ReportDimension.kcal => (trend.ctaRecord, '/record'),
      ReportDimension.fasting => (trend.ctaFast, '/'),
    };

    return SizedBox(
      width: double.infinity,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AppSpacing.s4),
          Icon(Icons.show_chart, color: colors.textSecondary, size: 32),
          const SizedBox(height: AppSpacing.s2),
          Text(
            trend.empty,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          FilledButton(
            onPressed: () => context.go(route),
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size(0, AppSpacing.s12),
            ),
            child: Text(
              cta,
              style: textStyles.textBase.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
      ),
    );
  }
}

/// 绿描线趋势图：折线 + 节点圆点 + 底部稀疏日期标签 + 末点数值标签。
/// 无记录日（null）跳过不连线段（断点处理）。
class ReportTrendPainter extends CustomPainter {
  ReportTrendPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.labelColor,
    required this.labelStyle,
    required this.unit,
    this.fractionDigits = 0,
  });

  final List<double?> values;

  /// 与 values 等长；null 表示该点不画日期标签（30 天档稀疏化）。
  final List<String?> labels;
  final Color lineColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final String unit;
  final int fractionDigits;

  static const double _labelHeight = 20;
  static const double _topPadding = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    if (present.isEmpty) return;
    final maxV = present.reduce((a, b) => a > b ? a : b);
    final minV = present.reduce((a, b) => a < b ? a : b);
    // 全相等时给 10% 的纵向余量，避免除零与贴边。
    final span = (maxV - minV) == 0
        ? (maxV == 0 ? 1.0 : maxV * 0.2)
        : maxV - minV;
    final chartBottom = size.height - _labelHeight;
    final chartTop = _topPadding;

    double xOf(int i) => values.length == 1
        ? size.width / 2
        : size.width * i / (values.length - 1);

    Offset pointOf(int i) {
      final v = values[i]!;
      final y = chartBottom - (v - minV) / span * (chartBottom - chartTop);
      return Offset(xOf(i), y);
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
    // 节点圆点。
    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < values.length; i++) {
      if (values[i] == null) continue;
      canvas.drawCircle(pointOf(i), 3, dotPaint);
    }
    // 末点数值标签。
    final lastIndex = values.lastIndexWhere((v) => v != null);
    if (lastIndex >= 0) {
      _drawText(
        canvas,
        '${values[lastIndex]!.toStringAsFixed(fractionDigits)} $unit',
        Offset(pointOf(lastIndex).dx, chartTop - 12),
        labelStyle.copyWith(color: lineColor),
        alignRight: pointOf(lastIndex).dx > size.width / 2,
      );
    }
    // 底部日期标签（稀疏）。
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      if (label == null) continue;
      _drawText(
        canvas,
        label,
        Offset(xOf(i), size.height - _labelHeight + 4),
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
  bool shouldRepaint(ReportTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.unit != unit;
  }
}
