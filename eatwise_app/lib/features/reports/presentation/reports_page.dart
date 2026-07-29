import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/presentation/growth_card.dart';
import 'package:eatwise/features/reports/presentation/trend_section.dart';
import 'package:eatwise/features/reports/presentation/weekly_report_card.dart';
import 'package:flutter/material.dart';

/// M6 数据趋势与深度报告页（/data/reports，数据 Tab 二级页，PRD M6）：
/// 趋势图（体重/热量/断食时长 × 7/30 天）→ 成长轨迹卡 → 本周报告卡 →
/// 月报占位（V1.2）。空数据各区块独立走引导空态，不渲染空坐标轴。
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.reports.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: const <Widget>[
            ReportTrendSection(),
            SizedBox(height: AppSpacing.s6),
            GrowthSummaryCard(),
            SizedBox(height: AppSpacing.s6),
            WeeklyReportCard(),
            SizedBox(height: AppSpacing.s6),
            MonthlyReportPlaceholderCard(),
          ],
        ),
      ),
    );
  }
}
