import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/exposure_tracker.dart';
import 'package:eatwise/core/analytics/scroll_depth_tracker.dart';
import 'package:eatwise/core/notification/notification_types.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/widgets/arc_gauge.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_texts.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_celebration.dart';
import 'package:eatwise/features/fasting/presentation/fasting_ring.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/fasting/presentation/plan_progress_bar.dart';
import 'package:eatwise/features/fasting/presentation/today_budget_row.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/presentation/window_editor_sheet.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:eatwise/features/streak/presentation/milestone_badge.dart';
import 'package:eatwise/features/streak/presentation/streak_banner.dart';
import 'package:eatwise/features/streak/presentation/streak_break_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 断食计时主页（设计稿 §4.2-① / §3.2：顶部问候语+方案标签 → 居中
/// 220px 计时环 → 归属日文案 → 双主按钮 → 底部 mini signal-card，
/// 暖阳橙 FAB 跳记录；四态规范 3.4：本地计算永不等网络，无方案态显示
/// 引导 CTA 卡）。
class FastingHomePage extends ConsumerStatefulWidget {
  const FastingHomePage({super.key});

  @override
  ConsumerState<FastingHomePage> createState() => _FastingHomePageState();
}

class _FastingHomePageState extends ConsumerState<FastingHomePage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 每秒 tick 刷新倒计时（倒计时 = 锚点 − now，小组件同源，《规格-M2》§8）。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(fastingTimerControllerProvider.notifier).tick();
      // M5：前台跨过本地 0 点时对前一日结算（§2.4 本地结算为主）。
      ref.read(streakControllerProvider.notifier).settleIfNeeded();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final timer = ref.watch(fastingTimerControllerProvider);
    final permissionStatus = ref.watch(notificationPermissionStatusProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.fasting.home.title),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 通知权限降级横幅（v1.13.28）：重装/权限被回收后提醒全停且
            // 此前完全静默——探测到未授权即给可见引导，动作走
            // 申请权限→补排／系统设置（controller 单入口）。
            if (permissionStatus != null &&
                permissionStatus != NotificationPermissionStatus.granted)
              _NotificationPermissionBanner(status: permissionStatus),
            Expanded(
              child: timer.plan == null
                  ? const _NoPlanBody()
                  : _TimerBody(timer: timer),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通知权限降级横幅：未授权时固定在首页顶部，点「去开启」申请/跳设置。
class _NotificationPermissionBanner extends ConsumerWidget {
  const _NotificationPermissionBanner({required this.status});

  final NotificationPermissionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Container(
      width: double.infinity,
      color: colors.brandAccent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t.notify.permissionBanner,
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () {
              unawaited(
                ref
                    .read(fastingTimerControllerProvider.notifier)
                    .requestNotificationPermissionAndReschedule(),
              );
            },
            child: Text(t.notify.permissionBannerAction),
          ),
        ],
      ),
    );
  }
}

/// 无方案态（四态规范 3.4 首页·空态：引导启动方案，不显示倒计时）。
class _NoPlanBody extends StatelessWidget {
  const _NoPlanBody();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s6),
          decoration: BoxDecoration(
            color: colors.bgSecondary,
            borderRadius: radii.rLg,
            boxShadow: shadows.shadowSm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.eco_outlined, size: 64, color: colors.brandPrimary),
              const SizedBox(height: AppSpacing.s4),
              Text(
                t.fasting.home.stateNoPlan,
                style: textStyles.textXl,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                t.fasting.home.noPlanSubtitle,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s6),
              FilledButton(
                onPressed: () => context.go('/onboarding'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(
                  t.fasting.home.startPlan,
                  style: textStyles.textBase.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 计时主区（有方案：问候语 + 计时环 + 归属文案 + 双按钮 + 信号卡）。
class _TimerBody extends ConsumerWidget {
  const _TimerBody({required this.timer});

  final FastingTimerState timer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final plan = timer.plan!;
    final snapshot = timer.snapshot!;
    final location = ref.watch(deviceLocationProvider);
    final pending = ref.watch(pendingPlanProvider);
    final controller = ref.read(fastingTimerControllerProvider.notifier);
    final streak = ref.watch(streakControllerProvider);

    // M5：断签弹窗（T3/T4 结算后下次进入前台弹出；每断签日只自动弹 1 次）。
    ref.listen(streakControllerProvider, (previous, next) {
      final popupDate = next.pendingBreakPopupDate;
      if (popupDate != null && popupDate != previous?.pendingBreakPopupDate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          _showBreakDialog(context, ref, popupDate);
        });
      }
      // 服务端判分断签告知（v1.13.27：本地认为达标、服务端判不达标导致
      // streak 下降且本地无断签弹窗时）——SnackBar 带日期补一次原因，
      // 防「连胜莫名归零」（一次性，展示即消费）。
      final notice = next.serverBreakNoticeDate;
      if (notice != null && notice != previous?.serverBreakNoticeDate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final parts = notice.split('-');
          if (parts.length == 3) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  t.streak.kBreak.serverRecalcNotice(
                    month: int.parse(parts[1]),
                    day: int.parse(parts[2]),
                  ),
                ),
              ),
            );
          }
          ref
              .read(streakControllerProvider.notifier)
              .consumeServerBreakNotice();
        });
      }
    });

    // 首页状态环曝光（§3.2 fasting_ring_expose；页面级曝光，去重键含
    // 状态与方案——内容变化重计 §4.1；组件级 ≥50%+500ms 可视判定留 TODO）。
    final streakDays = streak.currentStreak;
    final ringFasting =
        timer.state == FastingState.fasting ||
        timer.state == FastingState.fastingExtended;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ref
          .read(analyticsServiceProvider)
          .trackExpose(
            'fasting_ring_expose',
            dedupeKey: 'home:ring:${timer.state.name}:${plan.id}',
            properties: <String, Object?>{
              'fasting_state': ringFasting ? 'fasting' : 'eating',
              'remain_ms': snapshot.countdownSec * 1000,
              'plan_type': plan.id.replaceAll(':', '_'),
              'streak_days': streakDays,
            },
          );
    });

    final isFasting =
        timer.state == FastingState.fasting ||
        timer.state == FastingState.fastingExtended;
    final extendedMinutes = timer.cycle?.extendedMinutes ?? 0;
    final extendLimitReached = extendedMinutes >= kExtendMaxMinutes;

    // 首页主体滚动区（包进 ScrollDepthTracker 前先成型，避免整棵子树
    // 只因包裹而重缩进）。
    final body = ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      children: <Widget>[
        const SizedBox(height: AppSpacing.s4),
        // 顶部：问候语（按时段，设计稿 §5.3）+ 方案标签。
        Text(
          _greeting(t, toLocal(snapshot.nowUtc, location).hour),
          style: textStyles.textH1,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s1,
            ),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: radii.rFull,
            ),
            child: Text(
              t.fasting.home.planTag(
                fast: plan.fastWindowMinutes ~/ 60,
                start: _formatMinutes(plan.eatStartMinutes),
                end: _formatMinutes(plan.eatEndMinutes),
              ),
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        // 待生效方案横幅（真机走查 Bug1：换方案登记 pendingPlan 后界面无
        // 任何呈现，用户不知道方案存在哪/何时生效/如何取消）。
        if (pending != null)
          Container(
            key: const ValueKey<String>('fasting.pendingPlanBanner'),
            margin: const EdgeInsets.only(bottom: AppSpacing.s2),
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              borderRadius: radii.rMd,
              border: Border.all(
                color: colors.brandPrimary.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: colors.brandPrimary,
                    ),
                    const SizedBox(width: AppSpacing.s1),
                    Expanded(
                      child: Text(
                        '${t.fasting.home.pendingPlanBadge} · ${pending.plan.planTypeId}'
                        ' (${_formatMinutes(pending.plan.eatStartMinutes)}'
                        '–${_formatMinutes(pending.plan.eatEndMinutes)})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.textSm.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(
                    t.fasting.home.pendingPlanEffective(
                      date: formatAttributionDate(
                        pending.effectiveDate,
                        locale: LocaleSettings.currentLocale,
                      ),
                    ),
                    style: textStyles.textXs.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                // 管理操作（真机走查：只能看不能动，用户要求可改/可删/
                // 可立即应用）。
                Padding(
                  padding: const EdgeInsets.only(left: 14, top: AppSpacing.s1),
                  child: Row(
                    children: <Widget>[
                      TextButton(
                        key: const ValueKey<String>('fasting.pendingPlan.edit'),
                        style: _pendingActionStyle(),
                        onPressed: () =>
                            _editPendingPlan(context, ref, pending),
                        child: Text(t.fasting.home.pendingPlanEdit),
                      ),
                      TextButton(
                        key: const ValueKey<String>(
                          'fasting.pendingPlan.apply',
                        ),
                        style: _pendingActionStyle(),
                        onPressed: () {
                          controller.applyPendingPlanNow();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(t.fasting.home.pendingPlanApplied),
                            ),
                          );
                        },
                        child: Text(t.fasting.home.pendingPlanApply),
                      ),
                      TextButton(
                        key: const ValueKey<String>(
                          'fasting.pendingPlan.cancel',
                        ),
                        style: _pendingActionStyle(),
                        onPressed: () => _cancelPendingPlan(context, ref),
                        child: Text(t.common.action.cancel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // M5 问候区连胜展示（streak=0 不显示火焰，显示引导文案；999+ 截断）。
        Align(
          alignment: Alignment.centerLeft,
          child: StreakBanner(currentStreak: streak.currentStreak),
        ),
        // 方案进度条（薄荷走查 P0：设了减重目标才露出，未设目标不渲染）。
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.s2),
          child: PlanProgressBar(),
        ),
        // M5 里程碑徽章滑入（3/7/30 首次解锁；reduced-motion 降级静态淡入）。
        // 徽章触达埋点（§3.5 badge_reach：徽章展示触发；组件级
        // ≥50%+500ms，§4.1；去重键含里程碑档位——新档位重计）。
        if (streak.justUnlockedMilestone != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s3),
            child: ExposureTracker(
              eventName: 'badge_reach',
              dedupeKey: 'home:badge:${streak.justUnlockedMilestone}',
              properties: <String, Object?>{
                'milestone': streak.justUnlockedMilestone,
                'streak_days': streak.currentStreak,
              },
              child: MilestoneBadge(
                days: streak.justUnlockedMilestone!,
                onDismiss: () => ref
                    .read(streakControllerProvider.notifier)
                    .consumeMilestone(),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.s6),
        // 三环仪表 + 三列图例（2026-09-30 UI 换代 v2：开口式多环仪表 +
        // 三列图例，华为运动健康「今日」页语言——断食/热量/饮水三指标并置
        // 同一盘面，图例即三指标读数，不再重复渲染指标卡）。
        _HomeGaugeSection(timer: timer),
        const SizedBox(height: AppSpacing.s3),
        // 归属日文案（D-07 / 评审项 1：环下常驻，双语日期格式）。
        // 进食态无进行中断食，文案改用将来时「下一段断食将计入 X」
        //（走查 B-9：进食窗态沿用「本次断食计入」属旧口径）。
        if (snapshot.attributionPreview != null)
          Center(
            child: Text(
              timer.state == FastingState.eating
                  ? t.fasting.home.attributionEating(
                      date: formatAttributionDate(
                        snapshot.attributionPreview!,
                        locale: LocaleSettings.currentLocale,
                      ),
                    )
                  : t.fasting.home.attribution(
                      date: formatAttributionDate(
                        snapshot.attributionPreview!,
                        locale: LocaleSettings.currentLocale,
                      ),
                    ),
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ),
        if (timer.state == FastingState.fastingExtended) ...<Widget>[
          const SizedBox(height: AppSpacing.s1),
          Center(
            child: Text(
              t.fasting.home.extendedBadge(minutes: extendedMinutes),
              style: textStyles.textXs.copyWith(color: colors.brandPrimary),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s6),
        // 双主按钮（设计稿 §4.2-① 环下横排；进食态置灰，T11）。
        // 2026-10-01 真机走查三轮：按钮仍不明显——加高到 56（s14），
        // 结束断食 FilledButton 加品牌色投影（强转化位视觉重量），
        // 延长由灰描边 OutlinedButton 改品牌绿浅底 tonal FilledButton
        // （描边在暗色/强光下辨识度不足，浅底块面与置灰态一眼可辨）。
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: isFasting
                    ? () => _showEndFastDialog(context, ref)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  disabledBackgroundColor: colors.border.withValues(alpha: 0.3),
                  minimumSize: const Size.fromHeight(AppSpacing.s14),
                  elevation: isFasting ? 3 : 0,
                  shadowColor: colors.brandPrimary.withValues(alpha: 0.45),
                ),
                icon: const Icon(Icons.flag_rounded, size: 20),
                label: Text(
                  t.fasting.home.endFast,
                  style: textStyles.textBase.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: isFasting && !extendLimitReached
                    ? controller.extend
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary.withValues(alpha: 0.14),
                  foregroundColor: colors.brandPrimary,
                  disabledBackgroundColor: colors.border.withValues(
                    alpha: 0.15,
                  ),
                  disabledForegroundColor: colors.textSecondary,
                  minimumSize: const Size.fromHeight(AppSpacing.s14),
                ),
                icon: const Icon(Icons.more_time_rounded, size: 20),
                label: Text(
                  t.fasting.home.extend,
                  style: textStyles.textBase.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        // 延长上限提示（T7，D-10）。
        if (extendLimitReached && isFasting)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Center(
              child: Text(
                t.fasting.home.extendLimit,
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.s6),
        // 运动与步数两列卡（三指标已上移至仪表，此区只留运动/步数）。
        const TodayMetricGrid(),
        const SizedBox(height: AppSpacing.s6),
        // 底部一行三色 mini signal-card（蛋白/碳水/热量，点按跳数据页）。
        MiniSignalCards(onTap: () => context.go('/data')),
        const SizedBox(height: AppSpacing.s8),
      ],
    );

    // 首页滚动深度（§4.2 scroll_depth；25/50/75/100 档位，session 内
    // 同档位只报一次；短内容不足一屏自动按 100 收口）。
    return ScrollDepthTracker(page: 'home', child: body);
  }

  /// 结束断食两步确认弹窗（§3.2：点按钮先报 fasting_end_click，弹窗内
  /// 「确认结束」→ fasting_end_confirm + 执行结束；「继续断食」→
  /// fasting_end_cancel）。D-08 预判不达标时展示警示文案。
  void _showEndFastDialog(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final controller = ref.read(fastingTimerControllerProvider.notifier);
    final cycle = timer.cycle;
    // EATING 下按钮置灰不可达，防御性丢弃（T11）。
    if (cycle == null) return;
    controller.trackEndFastClick();
    final elapsedSec = ref.read(fastingClockProvider)() - cycle.startUtc;
    final plannedSec = cycle.plannedSec;
    final willQualify = controller.wouldEndQualify();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          t.fasting.home.endFastDialog.title,
          style: textStyles.textXl,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.fasting.home.endFastDialog.elapsed(
                hours: elapsedSec ~/ 3600,
                minutes: (elapsedSec % 3600) ~/ 60,
              ),
              style: textStyles.textBase.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              plannedSec % 60 == 0 && (plannedSec ~/ 60) % 60 == 0
                  ? t.fasting.home.endFastDialog.plannedHours(
                      hours: plannedSec ~/ 3600,
                    )
                  : t.fasting.home.endFastDialog.plannedHoursMinutes(
                      hours: plannedSec ~/ 3600,
                      minutes: (plannedSec % 3600) ~/ 60,
                    ),
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            if (!willQualify) ...<Widget>[
              const SizedBox(height: AppSpacing.s3),
              Text(
                t.fasting.home.endFastDialog.earlyWarning,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              controller.trackEndFastCancel();
            },
            child: Text(
              t.fasting.home.endFastDialog.cancel,
              style: textStyles.textBase.copyWith(color: colors.textPrimary),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              controller.endFast();
            },
            style: FilledButton.styleFrom(backgroundColor: colors.brandPrimary),
            child: Text(
              t.fasting.home.endFastDialog.confirm,
              style: textStyles.textBase.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// 断签弹窗（§4 三要素齐全；频控：每断签日只自动弹 1 次）。
  void _showBreakDialog(
    BuildContext context,
    WidgetRef ref,
    String missedDate,
  ) {
    final t = Translations.of(context);
    final notifier = ref.read(streakControllerProvider.notifier);
    final streak = ref.read(streakControllerProvider);
    notifier.markBreakPopupShown(missedDate);
    // 断签弹窗曝光（§3.5 streak_break_dialog_expose；use_card 点击后
    // 在 StreakController.useMendCard 回填）。
    ref
        .read(analyticsServiceProvider)
        .track(
          'streak_break_dialog_expose',
          properties: <String, Object?>{
            // 〔假设〕lost_streak 以补签预览恢复值近似（断签后 currentStreak 已归零）。
            'lost_streak': notifier.previewMendRestore(missedDate),
            'card_state': switch (streak.mendVisualState) {
              MendCardVisualState.mendable => 'available',
              MendCardVisualState.exhausted => 'exhausted',
              MendCardVisualState.unmendable => 'expired',
            },
          },
        );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StreakBreakDialog(
        visualState: streak.mendVisualState,
        cardsLeft: streak.mendCardBalance,
        restoreDays: notifier.previewMendRestore(missedDate),
        onMend: () async {
          Navigator.pop(dialogContext);
          try {
            final result = await notifier.useMendCard(missedDate);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    t.streak.kBreak.mendSuccess(days: result.restoredStreak),
                  ),
                ),
              );
            }
          } on Object {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.streak.kBreak.mendFailed)),
              );
            }
          }
        },
        onDismiss: () => Navigator.pop(dialogContext),
      ),
    );
  }

  /// 紧凑文字按钮样式（横幅三个操作并排，普通 TextButton 内边距会挤爆）。
  static ButtonStyle _pendingActionStyle() => TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    minimumSize: Size.zero,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  /// 修改待生效方案：复用自定义窗口编辑器（预填 pending 方案当前值），
  /// 确认后重新登记 pending（生效日仍是次日 0:00，与登记口径一致）。
  Future<void> _editPendingPlan(
    BuildContext context,
    WidgetRef ref,
    PendingPlan pending,
  ) async {
    final t = Translations.of(context);
    final draft = await WindowEditorSheet.show(
      context,
      initialEatingHours: pending.plan.eatWindowMinutes ~/ 60,
      initialStartMinutes: pending.plan.eatStartMinutes,
    );
    if (draft == null || !context.mounted) return;
    final nowUtc = ref.read(nowUtcProvider);
    final plan = draft.toFastingPlan();
    ref
        .read(onboardingStoreProvider)
        .savePendingPlan(
          schedulePlanChange(plan, nowUtc, ref.read(deviceLocationProvider)),
        );
    // 与登记换方案同口径立即上行（2026-10-01 补齐：此前只落本地 pending，
    // 服务端停留在登记时的旧窗口，要到次日 T13 转正才收敛——期间换机/
    // 他端下行会拿到旧方案）。
    ref.read(fastingPlanSyncProvider)?.markDirtyAndTryFlush(plan);
    ref.read(planVersionProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.fasting.home.pendingPlanRescheduled)),
    );
  }

  /// 取消待生效方案（走查 Bug1）：确认弹窗 → 控制器 `cancelPendingPlan`
  /// （清本地 + 回推当前方案收敛服务端，理由见控制器注释）。
  void _cancelPendingPlan(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(
          t.fasting.home.pendingPlanCancelBody,
          style: textStyles.textBase,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref
                  .read(fastingTimerControllerProvider.notifier)
                  .cancelPendingPlan(timer.plan!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.fasting.home.pendingPlanCancelled)),
              );
            },
            child: Text(t.common.action.confirm),
          ),
        ],
      ),
    );
  }

  static String _greeting(Translations t, int hour) {
    if (hour >= 5 && hour < 11) return t.fasting.home.greeting.morning;
    if (hour >= 11 && hour < 14) return t.fasting.home.greeting.noon;
    if (hour >= 14 && hour < 18) return t.fasting.home.greeting.afternoon;
    if (hour >= 18 && hour < 23) return t.fasting.home.greeting.evening;
    return t.fasting.home.greeting.night;
  }

  static String _stateText(Translations t, FastingState state) {
    return switch (state) {
      FastingState.eating => t.fasting.home.stateEating,
      FastingState.fasting => t.fasting.home.stateFasting,
      FastingState.fastingExtended => t.fasting.home.stateFastingExtended,
      FastingState.noPlan => t.fasting.home.stateNoPlan,
    };
  }

  static String _formatMinutes(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 首页三环仪表区（2026-09-30 UI 换代 v2）：开口式多环仪表 + 中心倒计时 +
/// 三列图例行。整合断食/热量/饮水三指标到同一盘面（华为运动健康今日页语言）。
class _HomeGaugeSection extends ConsumerWidget {
  const _HomeGaugeSection({required this.timer});

  final FastingTimerState timer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final snapshot = timer.snapshot!;
    final controller = ref.read(fastingTimerControllerProvider.notifier);

    final isFasting =
        timer.state == FastingState.fasting ||
        timer.state == FastingState.fastingExtended;
    // 断食环色：断食态用品牌绿（沉静专注），进食窗用琥珀黄（活力进食）。
    final fastArcColor = isFasting ? colors.brandPrimary : colors.gaugeAmber;

    // 断食进度（已断食 ÷ 计划时长；进食窗口同理）。
    final fastProgress = _progress(timer);

    // 热量进度（已吃 ÷ 目标；无目标默认 2000）。
    final goal = ref.watch(nutritionGoalProvider);
    final intake = ref.watch(todayIntakeProvider);
    final kcalProgress = goal.targetKcal > 0
        ? (intake?.kcal ?? 0) / goal.targetKcal
        : 0.0;

    // 饮水进度（已喝 ÷ 目标 2000ml）。
    final waterMl = ref.watch(todayWaterTotalProvider).value ?? 0;
    const waterGoal = 2000.0;
    final waterProgress = waterMl / waterGoal;

    final plan = timer.plan!;
    final fastHours = plan.fastWindowMinutes ~/ 60;
    final gauge = t.fasting.home.gauge;

    return Column(
      children: <Widget>[
        // 三环仪表 + 中心倒计时槽（庆祝动画覆盖整个区域）。
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              FastingRing(
                progress: fastProgress,
                arcColor: fastArcColor,
                secondary: ArcSpec(
                  progress: kcalProgress,
                  color: colors.gaugeRed,
                ),
                tertiary: ArcSpec(
                  progress: waterProgress,
                  color: colors.gaugeBlue,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 进食态：大时钟让位给状态图标（真机走查 2026-09-30：
                    // 进食窗下秒级倒计时占了图标位且非核心信息——图标 +
                    // 无秒倒计时（HH:MM）更适配；断食态保留秒位营造逼近感）。
                    if (!isFasting) ...<Widget>[
                      Icon(
                        Icons.restaurant_rounded,
                        size: 26,
                        color: fastArcColor,
                      ),
                      const SizedBox(height: AppSpacing.s1),
                    ],
                    CountdownText(
                      seconds: snapshot.countdownSec,
                      showSeconds: isFasting,
                    ),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      _TimerBody._stateText(t, timer.state),
                      style: textStyles.textBase.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 破壳庆祝（归零/结束断食且达标，覆盖整个区域）。
              if (timer.celebrating)
                SizedBox(
                  width: 220,
                  height: 220,
                  child: FastingCelebration(
                    onDismiss: controller.dismissCelebration,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        // 三列图例（断食/热量/饮水；短标签 + 大数字 + 目标行）。
        GaugeLegendRow(
          items: <GaugeLegendItem>[
            GaugeLegendItem(
              color: fastArcColor,
              label: gauge.fasting,
              value: fastProgress > 0
                  ? (fastProgress * fastHours).toStringAsFixed(1)
                  : '0',
              goal: gauge.fastingGoal(hours: fastHours),
            ),
            GaugeLegendItem(
              color: colors.gaugeRed,
              label: gauge.kcal,
              value: (intake?.kcal ?? 0).toStringAsFixed(0),
              goal: gauge.kcalGoal(kcal: goal.targetKcal.toStringAsFixed(0)),
            ),
            GaugeLegendItem(
              color: colors.gaugeBlue,
              label: gauge.water,
              value: waterMl.toStringAsFixed(0),
              goal: gauge.waterGoal(ml: waterGoal.toStringAsFixed(0)),
            ),
          ],
        ),
      ],
    );
  }
}

/// 环内倒计时数字（2026-09-30 真机走查二轮）：原 maxWidth 184 超出三环
/// 仪表内环自由直径（220 − 2×(2×(13+5)+13) = 122），秒级倒计时整行压到
/// 环弧上——收窄到 118 并改「HH:MM 大字 + :SS 小字后缀」（断食态），
/// 主数字用指标大数字样式 textDisplay（34pt），秒位降级小字，既有
/// 秒级跳动的逼近感又完全不压环。进食态（showSeconds=false）只渲染
/// HH:MM。FittedBox(scaleDown) 保证 textScaler 放大与超长时间
///（>99h 三位小时）都只缩小不溢出。
class CountdownText extends StatelessWidget {
  const CountdownText({
    required this.seconds,
    this.showSeconds = true,
    super.key,
  });

  /// 倒计时秒数（锚点 − now，HH:MM 主显 + :SS 后缀，小时可超两位）。
  final int seconds;

  /// 是否渲染秒位后缀（进食态传 false：只 HH:MM，配合状态图标更适配）。
  final bool showSeconds;

  /// 可渲染最大宽度（三环内环自由直径 122 − 4 视觉余量）。
  static const double maxWidth = 118;

  @override
  Widget build(BuildContext context) {
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return SizedBox(
      width: maxWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              '$h:$m',
              style: textStyles.textDisplay,
              maxLines: 1,
              softWrap: false,
            ),
            if (showSeconds)
              Text(
                ':$s',
                style: textStyles.textLg.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                softWrap: false,
              ),
          ],
        ),
      ),
    );
  }
}

/// 断食/进食进度 0..1（模块级私有，_HomeGaugeSection 与 _TimerBody 共用）。
double _progress(FastingTimerState timer) {
  final snapshot = timer.snapshot!;
  final cycle = timer.cycle;
  if (cycle != null) {
    final elapsed = snapshot.nowUtc - cycle.startUtc;
    return cycle.plannedSec <= 0 ? 0 : elapsed / cycle.plannedSec;
  }
  final target = snapshot.targetUtc;
  if (target == null) return 0;
  final windowSec = timer.plan!.eatWindowMinutes * 60;
  final elapsed = windowSec - (target - snapshot.nowUtc);
  return windowSec <= 0 ? 0 : elapsed / windowSec;
}
