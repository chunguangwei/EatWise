import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/presentation/body_profile_form.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 档案采集页（阶段 A：第 3 题之后、推荐页之前；D-18 敏感信息，
/// 整页可跳过、单项可留空——跳过/留空走 §1.6 兜底并在推荐后提示补全）。
class OnboardingProfileScreen extends ConsumerStatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState
    extends ConsumerState<OnboardingProfileScreen> {
  OnboardingProfile _profile = OnboardingProfile.empty;
  bool _valid = true;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final currentYear = DateTime.fromMillisecondsSinceEpoch(
      ref.read(nowUtcProvider) * 1000,
      isUtc: true,
    ).year;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.onboarding.profile.title),
        actions: <Widget>[
          // 整页跳过（D-18）：维持兜底行为，文案明示将使用默认估算。
          TextButton(
            key: const ValueKey<String>('onboarding.profile.skip'),
            onPressed: () => context.go('/onboarding/recommendation'),
            child: Text(t.onboarding.profile.skip),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            Text(
              t.onboarding.profile.subtitle,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s4),
            BodyProfileForm(
              currentYear: currentYear,
              initial: controller.loadProfile() ?? OnboardingProfile.empty,
              onChanged: (profile, valid) {
                _profile = profile;
                if (valid != _valid) setState(() => _valid = valid);
              },
            ),
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              key: const ValueKey<String>('onboarding.profile.save'),
              onPressed: !_valid
                  ? null
                  : () {
                      controller.saveProfile(_profile);
                      context.go('/onboarding/recommendation');
                    },
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(t.onboarding.profile.save),
            ),
          ],
        ),
      ),
    );
  }
}
