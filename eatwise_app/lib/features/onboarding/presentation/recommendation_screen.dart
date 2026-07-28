import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
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
            _PlanCard(
              key: const ValueKey<String>('onboarding.recommendation.primary'),
              badge: t.onboarding.recommendation.mainBadge,
              emphasized: true,
              option: rec.primary,
              reasonText: _reasonText(t, rec),
              flexibleHint: rec.flexibleWindowHint
                  ? t.onboarding.recommendation.flexibleHint
                  : null,
            ),
            const SizedBox(height: AppSpacing.s4),
            FilledButton(
              key: const ValueKey<String>('onboarding.recommendation.start'),
              onPressed: () {
                final result = controller.startPrimaryPlan();
                if (result.usedFallback) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        t.onboarding.recommendation.fallbackNotice(
                          kcal: result.targetKcal,
                        ),
                      ),
                    ),
                  );
                }
                context.go('/');
              },
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
            Text(
              t.onboarding.recommendation.altTitle,
              style: textStyles.textXl,
            ),
            const SizedBox(height: AppSpacing.s3),
            for (final alt in rec.alternatives) ...<Widget>[
              _PlanCard(
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
