import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/exposure_tracker.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/presentation/weight_goal_fields.dart';
import 'package:eatwise/features/fasting/domain/window_rules.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
import 'package:eatwise/features/onboarding/presentation/window_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 推荐结果页（M1 功能点 3/4：主方案卡 + ≥1 备选卡 + 一键启动）。
class RecommendationScreen extends ConsumerWidget {
  const RecommendationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    // 直达本页（无答题状态）时按 D-03 兜底展示 16:8。
    final rec = state.recommendation ?? recommendPlan(OnboardingAnswers.empty);

    return Scaffold(
      appBar: AppBar(title: Text(t.onboarding.recommendation.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            // 方案推荐曝光（§3.1 onboard_plan_recommend_expose；升级为组件级
            // ≥50%+500ms，§4.1；内容键 = 主方案 ID——重算推荐重计）。
            ExposureTracker(
              eventName: 'onboard_plan_recommend_expose',
              dedupeKey: 'onboarding:recommend:${rec.primary.id}',
              properties: <String, Object?>{
                'main_plan': rec.primary.id.replaceAll(':', '_'),
                'alt_plan': rec.alternatives.first.id.replaceAll(':', '_'),
                'is_fallback': rec.usedFallback,
                // 〔假设〕rule_id 用推荐理由模板 key 占位（D-03 规则行 ID 未定）。
                'rule_id': 'r_${rec.reason.name}',
              },
              child: _PlanCard(
                key: const ValueKey<String>(
                  'onboarding.recommendation.primary',
                ),
                badge: t.onboarding.recommendation.mainBadge,
                emphasized: true,
                option: rec.primary,
                reasonText: _reasonText(t, rec),
                flexibleHint: rec.flexibleWindowHint
                    ? t.onboarding.recommendation.flexibleHint
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            // 阶段 B：减重目标预览（缺口法生效时展示周速率/预计达成日/热量
            // 目标；安全夹取与筛查温和化提示；筛查「是」强化免责提示）。
            _WeightLossPreview(controller: controller),
            FilledButton(
              key: const ValueKey<String>('onboarding.recommendation.start'),
              onPressed: () => _onStartPressed(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                t.onboarding.recommendation.startNow,
                style: textStyles.textBase,
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            // 自定义进食窗口（进食窗口自选：编辑器弹层；确认后走既有
            // 启动/换方案路径，T12 弹窗与 D-06 次日生效文案复用）。
            OutlinedButton.icon(
              key: const ValueKey<String>(
                'onboarding.recommendation.customWindow',
              ),
              onPressed: () => _onCustomWindowPressed(context, ref),
              icon: const Icon(Icons.schedule),
              label: Text(t.fasting.window.entry),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              t.onboarding.recommendation.altTitle,
              style: textStyles.textXl,
            ),
            const SizedBox(height: AppSpacing.s3),
            for (final alt in rec.alternatives) ...<Widget>[
              // 备选方案卡曝光（onboard_plan_card_expose〔新增事件〕：
              // 组件级 ≥50%+500ms，内容键 = 方案 ID）。
              ExposureTracker(
                eventName: 'onboard_plan_card_expose',
                dedupeKey: 'onboarding:recommend:alt:${alt.id}',
                properties: <String, Object?>{
                  'plan_id': alt.id.replaceAll(':', '_'),
                  'slot': 'alt',
                },
                child: _PlanCard(
                  key: ValueKey<String>(
                    'onboarding.recommendation.alt.${alt.id}',
                  ),
                  option: alt,
                  action: alt.isInfoOnly
                      ? null
                      : () => controller.promoteAlternative(alt),
                  actionLabel: alt.isInfoOnly
                      ? t.onboarding.recommendation.comingSoon
                      : t.onboarding.recommendation.select,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
            ],
            const SizedBox(height: AppSpacing.s3),
            TextButton(
              key: const ValueKey<String>('onboarding.recommendation.science'),
              onPressed: () => context.push('/onboarding/science'),
              child: Text(t.onboarding.recommendation.scienceLink),
            ),
          ],
        ),
      ),
    );
  }

  /// 「一键启动」与「自定义窗口确认」共用入口：已有生效方案且目标窗口
  /// 不同时先弹 T12 确认（「新方案将于次日 0:00 生效」，D-06），确认后
  /// 写入；首次启动立即生效。[window] 非空 = 自定义进食窗口草稿。
  Future<void> _startWith(
    BuildContext context,
    WidgetRef ref, {
    FastingWindowDraft? window,
  }) async {
    final t = Translations.of(context);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final plan = window?.toFastingPlan();
    final planChanged = plan == null
        ? controller.isPlanChange
        : controller.isPlanChangeAgainst(plan);
    if (planChanged) {
      final date = controller.planChangeEffectiveDate.toIsoString();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.onboarding.recommendation.planChangeTitle),
          content: Text(
            t.onboarding.recommendation.planChangeConfirm(date: date),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t.common.action.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t.common.action.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final result = controller.startPrimaryPlan(window: window);
    if (result.usedFallback && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.onboarding.recommendation.fallbackNotice(kcal: result.targetKcal),
          ),
        ),
      );
    }
    if (context.mounted) {
      context.go('/');
    }
  }

  /// 一键启动（主推荐口径）。
  Future<void> _onStartPressed(BuildContext context, WidgetRef ref) =>
      _startWith(context, ref);

  /// 自定义进食窗口：弹编辑器（初始值 = 当前主推荐窗口）；确认后走
  /// [_startWith]（T12 弹窗与生效时序与一键启动同路径）。
  Future<void> _onCustomWindowPressed(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final rec =
        ref.read(onboardingControllerProvider).recommendation ??
        recommendPlan(OnboardingAnswers.empty);
    final draft = await WindowEditorSheet.show(
      context,
      initialEatingHours:
          (rec.primary.toFastingPlan()?.eatWindowMinutes ?? 8 * 60) ~/ 60,
      initialStartMinutes: rec.primary.eatStartMinutes ?? 12 * 60,
    );
    if (draft == null || !context.mounted) return;
    await _startWith(context, ref, window: draft);
  }

  String _reasonText(Translations t, PlanRecommendation rec) {
    final reasons = t.onboarding.recommendation.reason;
    return switch (rec.reason) {
      RecommendationReason.beginner => reasons.beginner,
      RecommendationReason.triedButStopped => reasons.triedButStopped,
      RecommendationReason.experienced => reasons.experienced,
      RecommendationReason.healthUpgrade => reasons.healthUpgrade,
      RecommendationReason.fallback => reasons.fallback,
    };
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    super.key,
    required this.option,
    this.badge,
    this.reasonText,
    this.flexibleHint,
    this.emphasized = false,
    this.action,
    this.actionLabel,
  });

  final PlanOption option;
  final String? badge;
  final String? reasonText;
  final String? flexibleHint;
  final bool emphasized;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final (:name, :desc) = _planText(t, option.id);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: emphasized ? shadows.shadowSm : null,
        border: emphasized
            ? Border.all(color: colors.brandPrimary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(name, style: textStyles.textXl)),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.brandPrimary,
                    borderRadius: radii.rSm,
                  ),
                  child: Text(
                    badge!,
                    style: textStyles.textXs.copyWith(color: Colors.white),
                  ),
                ),
            ],
          ),
          if (option.eatStartMinutes != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s1),
            Text(
              t.onboarding.recommendation.window(
                start: _hhmm(option.eatStartMinutes!),
                end: _hhmm(option.eatEndMinutes!),
              ),
              style: textStyles.textSm.copyWith(
                color: colors.brandPrimaryPressed,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s2),
          Text(
            desc,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          if (reasonText != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Text(reasonText!, style: textStyles.textBase),
          ],
          if (flexibleHint != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Text(
              flexibleHint!,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ],
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s3),
            Align(
              alignment: Alignment.centerRight,
              child: action == null
                  ? Text(
                      actionLabel!,
                      style: textStyles.textSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    )
                  : OutlinedButton(
                      key: ValueKey<String>(
                        'onboarding.recommendation.select.${option.id}',
                      ),
                      onPressed: action,
                      child: Text(actionLabel!),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  static ({String name, String desc}) _planText(Translations t, String id) {
    final plans = t.onboarding.plans;
    return switch (id) {
      '14:10' => (name: plans.p14x10.name, desc: plans.p14x10.desc),
      '18:6' => (name: plans.p18x6.name, desc: plans.p18x6.desc),
      '5:2' => (name: plans.p5x2.name, desc: plans.p5x2.desc),
      _ => (name: plans.p16x8.name, desc: plans.p16x8.desc),
    };
  }

  static String _hhmm(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 减重目标预览卡（阶段 B）：缺口法生效时展示「预计每周减 X kg · 约 Y 达成」
/// + 日热量目标；速率被安全夹取时提示；进食障碍筛查「是」展示强化免责提示。
class _WeightLossPreview extends StatelessWidget {
  const _WeightLossPreview({required this.controller});

  final OnboardingController controller;

  /// 速率展示：保留至多 2 位小数并去尾零（0.50 → 0.5）。
  static String _formatRate(double rate) {
    final fixed = rate.toStringAsFixed(2);
    return fixed.contains('.')
        ? fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')
        : fixed;
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    final profile = controller.loadProfile();
    final screeningYes =
        profile?.eatingDisorderScreening == EatingDisorderScreening.yes;
    final preview = controller.previewNutritionGoal();
    final plan = preview.weightLoss;
    if (plan == null && !screeningYes) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (plan != null)
            Container(
              key: const ValueKey<String>(
                'onboarding.recommendation.weightLoss',
              ),
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                borderRadius: radii.rLg,
                border: Border.all(color: colors.brandPrimary),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.onboarding.recommendation.weightLossPlan(
                      rate: _formatRate(plan.weeklyRateKg),
                      date: formatLocalDate(context, plan.reachDate),
                    ),
                    style: textStyles.textBase,
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  Text(
                    t.onboarding.recommendation.dailyKcalTarget(
                      kcal: preview.targetKcal,
                    ),
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (plan.clamped) ...<Widget>[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      // 温和节奏（筛查「是」）下安全上限为 0.5 kg/周，文案区分。
                      screeningYes
                          ? t.onboarding.recommendation.gentleNotice
                          : t.onboarding.recommendation.clampedNotice,
                      style: textStyles.textSm.copyWith(
                        color: colors.brandPrimaryPressed,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (screeningYes) ...<Widget>[
            if (plan != null) const SizedBox(height: AppSpacing.s3),
            Container(
              key: const ValueKey<String>('onboarding.recommendation.edNotice'),
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: colors.brandPrimary.withValues(alpha: 0.08),
                borderRadius: radii.rLg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.favorite_border,
                    size: 18,
                    color: colors.brandPrimary,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      t.onboarding.recommendation.edNotice,
                      style: textStyles.textSm.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
