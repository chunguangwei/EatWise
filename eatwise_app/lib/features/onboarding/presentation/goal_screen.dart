import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/presentation/weight_goal_fields.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 减重目标页（阶段 B：档案页之后、推荐页之前；可跳过）。
///
/// 仅当 Q1 目标=减脂且档案页填了体重时由档案页导航进入（路由本身不设防，
/// 直达时按空目标处理——保存/跳过都落到推荐页，缺口法不生效回落 D-04）。
class OnboardingGoalScreen extends ConsumerStatefulWidget {
  const OnboardingGoalScreen({super.key});

  @override
  ConsumerState<OnboardingGoalScreen> createState() =>
      _OnboardingGoalScreenState();
}

class _OnboardingGoalScreenState extends ConsumerState<OnboardingGoalScreen> {
  double? _targetWeightKg;
  LocalDate? _targetDate;
  bool _valid = true;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final today = localDateOf(
      ref.read(nowUtcProvider),
      ref.read(deviceLocationProvider),
    );
    final stored = controller.loadProfile();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.onboarding.goal.title),
        actions: <Widget>[
          // 整页跳过：不填目标 → 维持 D-04 固定折算。
          TextButton(
            key: const ValueKey<String>('onboarding.goal.skip'),
            onPressed: () => context.go('/onboarding/recommendation'),
            child: Text(t.onboarding.goal.skip),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            Text(
              t.onboarding.goal.subtitle,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s4),
            WeightGoalFields(
              today: today,
              initialWeightKg: stored?.targetWeightKg,
              initialDate: stored?.targetDate,
              onChanged: (weightKg, date, valid) {
                _targetWeightKg = weightKg;
                _targetDate = date;
                if (valid != _valid) setState(() => _valid = valid);
              },
            ),
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              key: const ValueKey<String>('onboarding.goal.save'),
              onPressed: !_valid
                  ? null
                  : () {
                      controller.saveProfile(
                        (stored ?? OnboardingProfile.empty).copyWith(
                          targetWeightKg: () => _targetWeightKg,
                          targetDate: () => _targetDate,
                        ),
                      );
                      context.go('/onboarding/recommendation');
                    },
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(t.onboarding.goal.save),
            ),
          ],
        ),
      ),
    );
  }
}
