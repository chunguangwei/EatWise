import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_texts.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/presentation/fasting_celebration.dart';
import 'package:eatwise/features/fasting/presentation/fasting_ring.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
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

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(t.fasting.home.title),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: t.record.home.logMeal,
        backgroundColor: colors.brandAccent,
        onPressed: () => context.go('/record'),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: timer.plan == null
            ? const _NoPlanBody()
            : _TimerBody(timer: timer),
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
    final controller = ref.read(fastingTimerControllerProvider.notifier);

    final isFasting =
        timer.state == FastingState.fasting ||
        timer.state == FastingState.fastingExtended;
    final arcColor = isFasting ? colors.brandPrimary : colors.brandAccent;
    final extendedMinutes = timer.cycle?.extendedMinutes ?? 0;
    final extendLimitReached = extendedMinutes >= kExtendMaxMinutes;

    return ListView(
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
                id: plan.id,
                start: _formatMinutes(plan.eatStartMinutes),
                end: _formatMinutes(plan.eatEndMinutes),
              ),
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        // 居中 220px 计时环（断食绿弧 / 进食橙弧；中心 48px 倒计时 + 状态）。
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              FastingRing(
                progress: _progress(timer),
                arcColor: arcColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _formatCountdown(snapshot.countdownSec),
                      style: textStyles.textTimer,
                    ),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      _stateText(t, timer.state),
                      style: textStyles.textBase.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 破壳庆祝（归零/结束断食且达标，§5.1-1；覆盖环区）。
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
        const SizedBox(height: AppSpacing.s3),
        // 归属日文案（D-07 / 评审项 1：环下常驻，双语日期格式）。
        if (snapshot.attributionPreview != null)
          Center(
            child: Text(
              t.fasting.home.attribution(
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
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: isFasting ? controller.endFast : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  disabledBackgroundColor: colors.border.withValues(alpha: 0.3),
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(
                  t.fasting.home.endFast,
                  style: textStyles.textBase.copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: OutlinedButton(
                onPressed: isFasting && !extendLimitReached
                    ? controller.extend
                    : null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.border),
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(t.fasting.home.extend, style: textStyles.textBase),
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
        // 底部一行三色 mini signal-card（蛋白/碳水/热量，点按跳数据页）。
        MiniSignalCards(onTap: () => context.go('/data')),
        const SizedBox(height: AppSpacing.s8),
      ],
    );
  }

  /// 环进度：断食 = 已断食 ÷ 计划（含延长）；进食 = 已进食 ÷ 窗口时长。
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

  static String _formatCountdown(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
