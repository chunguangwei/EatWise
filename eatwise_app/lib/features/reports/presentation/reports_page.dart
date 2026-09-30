import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/scroll_depth_tracker.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/reports/presentation/growth_card.dart';
import 'package:eatwise/features/reports/presentation/monthly_report_card.dart';
import 'package:eatwise/features/reports/presentation/trend_section.dart';
import 'package:eatwise/features/reports/presentation/weekly_report_card.dart';
import 'package:eatwise/features/reports/presentation/weekly_summary_card.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M6 数据趋势与深度报告页（/data/reports，数据 Tab 二级页，PRD M6）：
/// 上周小结卡（P1，页顶）→ 趋势图（体重/热量/断食时长 × 7/30 天）→
/// 成长轨迹卡 → 本周报告卡 → 月报卡（轻量版，本地生成）。
/// 空数据各区块独立走引导空态，不渲染空坐标轴。
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  @override
  void initState() {
    super.initState();
    // 进入数据页：本地近 30 天断食历史有缺口时触发一次下行回填（每会话
    // 最多一次，复用 streak 回填通道，幂等只补缺；未登录/离线/未装配静默）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref
            .read(streakControllerProvider.notifier)
            .ensureFastingHistoryBackfilled();
      } on Object {
        // streak 依赖未装配（测试/预览）：跳过回填。
      }
    });
  }

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
        // 报告页滚动深度（§4.2 scroll_depth，page=analytics_reports）。
        child: ScrollDepthTracker(
          page: 'analytics_reports',
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.s4),
            children: const <Widget>[
              WeeklySummaryCard(),
              SizedBox(height: AppSpacing.s6),
              ReportTrendSection(),
              SizedBox(height: AppSpacing.s6),
              GrowthSummaryCard(),
              SizedBox(height: AppSpacing.s6),
              WeeklyReportCard(),
              SizedBox(height: AppSpacing.s6),
              MonthlyReportCard(),
            ],
          ),
        ),
      ),
    );
  }
}
