import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart'
    show TrendBucket, TrendPoint;
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/domain/weight_curve_unlock.dart';
import 'package:eatwise/features/reports/presentation/fasting_trend_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

/// M6 趋势图区（PRD M6 / 设计稿信息图 ⑦）：
/// 三维切换（体重/热量/断食）× 四档时间范围（7/30/90/365 天）。
///
/// 2026-09-30 长期趋势改造，解决两个长期存在的展示缺陷：
/// - **断食维度此前只有达标/未达标二元格，没有时长趋势**：`actualSec` 一直
///   有存储，但 14:10 达标与 18:6 达标在格子上完全一样，用户看不出自己的
///   断食时长在变长还是变短。现断食维度拆「时长 / 坚持度」双视图，时长走
///   折线（与体重/热量同一套 painter），坚持度保留三态格。
/// - **窗口上限 30 天**：补 90 天（按周聚合）与 1 年（按自然月聚合）两档，
///   长窗口不再逐日画点（365 个点会糊成噪声），分桶均值可横向比较。
///
/// 空数据走引导空态（四态规范 3.2.2：主文案 + CTA），不渲染空坐标轴。
class ReportTrendSection extends ConsumerStatefulWidget {
  const ReportTrendSection({super.key});

  @override
  ConsumerState<ReportTrendSection> createState() => _ReportTrendSectionState();
}

/// 断食维度的两个视图。
enum _FastingView { duration, consistency }

class _ReportTrendSectionState extends ConsumerState<ReportTrendSection> {
  _FastingView _fastingView = _FastingView.duration;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final trend = t.reports.trend;

    final dimension = ref.watch(reportDimensionProvider);
    final range = ref.watch(reportRangeProvider);
    final points = ref.watch(trendPointsProvider);
    final hasAny = points.any((p) => p.value != null);

    // 断食·坚持度视图：短窗口三态格，长窗口达标率折线。
    final isFastingConsistency =
        dimension == ReportDimension.fasting &&
        _fastingView == _FastingView.consistency;

    // 阶段 C：体重维度叠加目标体重参考线 + 差值文案（未设置目标不画）。
    final targetKg = dimension == ReportDimension.weight
        ? ref.watch(weightTargetProvider)
        : null;
    final lastIdx = points.lastIndexWhere((p) => p.value != null);
    final latestWeight = lastIdx >= 0 ? points[lastIdx].value : null;
    // P3 体重曲线解锁钩子：记录 <3 条时图表盖半透明遮罩引导继续记录。
    final weightUnlockRemaining = dimension == ReportDimension.weight
        ? weightRecordsToUnlock(ref.watch(weightRecordCountProvider))
        : 0;

    final end = ref.watch(reportsNowProvider);
    final locale = Localizations.localeOf(context).toString();

    // 绘制序列：坚持度长窗口取达标率，其余取分桶均值。
    final drawPoints = isFastingConsistency && range.isLongRange
        ? ref.watch(fastingQualifiedRatePointsProvider)
        : points;
    final values = drawPoints.map((p) => p.value).toList(growable: false);
    final labels = _labelsFor(drawPoints, range, locale);

    final isRate = isFastingConsistency && range.isLongRange;
    final unit = isRate
        ? '%'
        : switch (dimension) {
            ReportDimension.weight => trend.unit.kg,
            ReportDimension.kcal => trend.unit.kcal,
            ReportDimension.fasting => trend.unit.hour,
          };
    // 达标率序列按百分比展示（0..1 → 0..100）。
    final drawValues = isRate
        ? values.map((v) => v == null ? null : v * 100).toList(growable: false)
        : values;

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
          // 时间范围切换（7/30/90/365 天）。四档横排在窄屏会挤，
          // 故整行可横向滚动（英文 "1y"/"90d" 较短，中文「90 天」较长）。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<ReportRange>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
              ),
              segments: <ButtonSegment<ReportRange>>[
                ButtonSegment<ReportRange>(
                  value: ReportRange.d7,
                  label: Text(trend.range.d7, maxLines: 1),
                ),
                ButtonSegment<ReportRange>(
                  value: ReportRange.d30,
                  label: Text(trend.range.d30, maxLines: 1),
                ),
                ButtonSegment<ReportRange>(
                  value: ReportRange.d90,
                  label: Text(trend.range.d90, maxLines: 1),
                ),
                ButtonSegment<ReportRange>(
                  value: ReportRange.d365,
                  label: Text(trend.range.d365, maxLines: 1),
                ),
              ],
              selected: <ReportRange>{range},
              onSelectionChanged: (selection) => ref
                  .read(reportRangeProvider.notifier)
                  .select(selection.first),
            ),
          ),
          // 断食维度：时长 / 坚持度双视图切换（P0：时长趋势此前完全缺失）。
          if (dimension == ReportDimension.fasting) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            SegmentedButton<_FastingView>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
              ),
              segments: <ButtonSegment<_FastingView>>[
                ButtonSegment<_FastingView>(
                  value: _FastingView.duration,
                  label: Text(trend.fastingView.duration, maxLines: 1),
                ),
                ButtonSegment<_FastingView>(
                  value: _FastingView.consistency,
                  label: Text(trend.fastingView.consistency, maxLines: 1),
                ),
              ],
              selected: <_FastingView>{_fastingView},
              onSelectionChanged: (s) => setState(() => _fastingView = s.first),
            ),
          ],
          const SizedBox(height: AppSpacing.s4),
          if (!hasAny)
            _TrendEmpty(dimension: dimension)
          // 断食·坚持度 + 短窗口：三态格（连续性直读，无记录 ≠ 断签）。
          else if (isFastingConsistency && !range.isLongRange)
            FastingTrendGrid(
              states: ref.watch(fastingDayStatesProvider),
              end: end,
            )
          else ...<Widget>[
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CustomPaint(
                    painter: ReportTrendPainter(
                      values: drawValues,
                      labels: labels,
                      lineColor: isRate
                          ? colors.ringExercise
                          : colors.brandPrimary,
                      labelColor: colors.textSecondary,
                      labelStyle: textStyles.textXs,
                      unit: unit,
                      fractionDigits:
                          dimension == ReportDimension.kcal || isRate ? 0 : 1,
                      targetValue: targetKg,
                      targetColor: colors.brandAccent,
                      targetLabel: targetKg == null
                          ? null
                          : trend.targetLine(kg: targetKg.toStringAsFixed(1)),
                    ),
                  ),
                  // 解锁钩子遮罩（半透明，曲线隐约可见但数值不可读）。
                  if (weightUnlockRemaining > 0)
                    Container(
                      decoration: BoxDecoration(
                        color: colors.bgPrimary.withValues(alpha: 0.72),
                        borderRadius: radii.rMd,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      child: Text(
                        trend.weightUnlock(count: weightUnlockRemaining),
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            // 长窗口分桶说明：避免用户把「周均值」误读成「某一天」。
            if (range.isLongRange)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s2),
                child: Text(
                  range.bucket == TrendBucket.month
                      ? trend.bucketNote.month
                      : trend.bucketNote.week,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            // 断食·时长视图：说明补签不计时长（否则用户会觉得数字对不上）。
            if (dimension == ReportDimension.fasting &&
                _fastingView == _FastingView.duration)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s2),
                child: Text(
                  trend.makeupExcluded,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            // 当前体重与目标差值（最新一条记录 vs 目标）。
            if (targetKg != null && latestWeight != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s2),
                child: Text(
                  latestWeight - targetKg > 0.05
                      ? trend.toGoal(
                          kg: (latestWeight - targetKg).toStringAsFixed(1),
                        )
                      : trend.goalReached,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 底部稀疏日期标签：逐日窗口按「每 N 天一个」，分桶窗口每桶一个标签。
  List<String?> _labelsFor(
    List<TrendPoint> points,
    ReportRange range,
    String locale,
  ) {
    if (range.isLongRange) {
      // 分桶：桶数本就不多（90 天≈13 周、365 天≈12 月），隔一个标一个。
      final every = points.length > 8 ? 2 : 1;
      return List<String?>.generate(points.length, (i) {
        if (i % every != 0 && i != points.length - 1) return null;
        return range.bucket == TrendBucket.month
            ? DateFormat.yM(locale).format(points[i].start)
            : DateFormat.Md(locale).format(points[i].start);
      });
    }
    final every = (points.length / 5).ceil();
    return List<String?>.generate(points.length, (i) {
      if (i % every != 0 && i != points.length - 1) return null;
      return DateFormat.Md(locale).format(points[i].start);
    });
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
    this.targetValue,
    this.targetColor,
    this.targetLabel,
  });

  final List<double?> values;

  /// 与 values 等长；null 表示该点不画日期标签（30 天档稀疏化）。
  final List<String?> labels;
  final Color lineColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final String unit;
  final int fractionDigits;

  /// 目标参考线值（阶段 C：体重维度传目标体重；null 不画）。
  final double? targetValue;

  /// 目标参考线颜色。
  final Color? targetColor;

  /// 目标参考线标签（如「目标 55 kg」）。
  final String? targetLabel;

  static const double _labelHeight = 20;
  static const double _topPadding = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    if (present.isEmpty) return;
    var maxV = present.reduce((a, b) => a > b ? a : b);
    var minV = present.reduce((a, b) => a < b ? a : b);
    // 目标线纳入纵向量程，保证参考线可见（不裁剪出图外）。
    final target = targetValue;
    if (target != null) {
      if (target > maxV) maxV = target;
      if (target < minV) minV = target;
    }
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

    // 目标参考虚线（阶段 C：体重目标；先于折线绘制，置于底层）。
    final targetColor = this.targetColor;
    if (target != null && targetColor != null) {
      final targetY =
          chartBottom - (target - minV) / span * (chartBottom - chartTop);
      final dashPaint = Paint()
        ..color = targetColor
        ..strokeWidth = 1;
      const dashWidth = 6.0;
      const dashGap = 4.0;
      for (var x = 0.0; x < size.width; x += dashWidth + dashGap) {
        final end = x + dashWidth;
        canvas.drawLine(
          Offset(x, targetY),
          Offset(end > size.width ? size.width : end, targetY),
          dashPaint,
        );
      }
      final label = targetLabel;
      if (label != null) {
        _drawText(
          canvas,
          label,
          Offset(0, targetY - 14),
          labelStyle.copyWith(color: targetColor),
        );
      }
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
        oldDelegate.unit != unit ||
        oldDelegate.targetValue != targetValue ||
        oldDelegate.targetLabel != targetLabel;
  }
}
