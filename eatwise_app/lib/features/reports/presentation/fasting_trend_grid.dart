import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/application/report_aggregation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// 断食趋势三态格（v1.14.x：替代折线，连续性一眼可读）：
/// 7 天 = 单行 7 格，30 天 = 7 列日历格压缩。
///
/// 三态诚实区分：达标（ringExercise 绿）/ 未达标（signalRed 珊瑚红）/
/// 无记录（轨道灰，明确不是断签）；今天有进行中周期时加第四态
/// （ringStand 青蓝）。每格内显日期数字，长按 Tooltip 出「日期 · 状态」。
/// 纯展示，状态序列由 fastingDayStatesProvider 对齐（末位 = 今天）。
class FastingTrendGrid extends StatelessWidget {
  const FastingTrendGrid({super.key, required this.states, required this.end});

  /// 与窗口天数等长的日状态序列（末位 = 今天）。
  final List<FastingDayState> states;

  /// 窗口终点（今天）。
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final legend = t.reports.trend.fastingLegend;
    final locale = Localizations.localeOf(context).toString();
    final days = states.length;
    final start = end.subtract(Duration(days: days - 1));

    // 无记录灰 = 轨道暗纹同口径（亮 0.12 / 暗 0.22，对齐 MultiRingProgress）。
    final noRecordColor = colors.textSecondary.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
    );

    Color colorOf(FastingDayState state) => switch (state) {
      FastingDayState.qualified => colors.ringExercise,
      FastingDayState.unqualified => colors.signalRed,
      FastingDayState.inProgress => colors.ringStand,
      FastingDayState.noRecord => noRecordColor,
    };

    String labelOf(FastingDayState state) => switch (state) {
      FastingDayState.qualified => legend.qualified,
      FastingDayState.unqualified => legend.unqualified,
      FastingDayState.inProgress => legend.inProgress,
      FastingDayState.noRecord => legend.noRecord,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: days,
          itemBuilder: (context, i) {
            final date = start.add(Duration(days: i));
            final state = states[i];
            final dateKey = DateFormat('yyyy-MM-dd').format(date);
            return Tooltip(
              message:
                  '${DateFormat.Md(locale).format(date)} · ${labelOf(state)}',
              child: Container(
                key: ValueKey<String>('fasting-day-$dateKey'),
                decoration: BoxDecoration(
                  color: colorOf(state),
                  borderRadius: radii.rSm,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${date.day}',
                  maxLines: 1,
                  style: textStyles.textXs.copyWith(
                    color: state == FastingDayState.noRecord
                        ? colors.textSecondary
                        : Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.s2),
        // 窗口起止日期（30 天档定位用；7 天档同构不特殊化）。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              DateFormat.Md(locale).format(start),
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
            Text(
              DateFormat.Md(locale).format(end),
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        // 三态图例（进行中仅出现时展示）。
        Wrap(
          spacing: AppSpacing.s3,
          runSpacing: AppSpacing.s1,
          children: <Widget>[
            _LegendDot(
              color: colors.ringExercise,
              label: legend.qualified,
              textStyle: textStyles.textXs.copyWith(
                color: colors.textSecondary,
              ),
            ),
            _LegendDot(
              color: colors.signalRed,
              label: legend.unqualified,
              textStyle: textStyles.textXs.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (states.contains(FastingDayState.inProgress))
              _LegendDot(
                color: colors.ringStand,
                label: legend.inProgress,
                textStyle: textStyles.textXs.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            _LegendDot(
              color: noRecordColor,
              label: legend.noRecord,
              textStyle: textStyles.textXs.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 图例项：色点 + 文案。
class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.textStyle,
  });

  final Color color;
  final String label;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.s1),
        Text(label, style: textStyle, maxLines: 1),
      ],
    );
  }
}
