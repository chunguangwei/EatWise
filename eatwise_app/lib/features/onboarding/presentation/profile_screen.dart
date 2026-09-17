import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/account/presentation/body_profile_form.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 档案采集页（阶段 A：第 3 题之后、推荐页之前；D-18 敏感信息，
/// 整页可跳过、单项可留空——跳过/留空走 §1.6 兜底并在推荐后提示补全）。
/// 阶段 B：顶部进食障碍筛查题（是 → 强制温和目标），保存后若 Q1=减脂
/// 且填了体重 → 先进减重目标页，再到推荐页。
class OnboardingProfileScreen extends ConsumerStatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState
    extends ConsumerState<OnboardingProfileScreen> {
  OnboardingProfile _profile = OnboardingProfile.empty;
  EatingDisorderScreening? _screening;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    _screening = ref
        .read(onboardingControllerProvider.notifier)
        .loadProfile()
        ?.eatingDisorderScreening;
  }

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
    final stored = controller.loadProfile();

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
            // 阶段 B：进食障碍筛查（仅存本地不上报；「是」→ 温和目标，
            // 不阻止使用）。
            _ScreeningSection(
              selected: _screening,
              onSelected: (value) => setState(() => _screening = value),
            ),
            const SizedBox(height: AppSpacing.s4),
            BodyProfileForm(
              currentYear: currentYear,
              initial: stored ?? OnboardingProfile.empty,
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
                      final profile = _profile.copyWith(
                        eatingDisorderScreening: () => _screening,
                      );
                      controller.saveProfile(profile);
                      // 阶段 B：仅 Q1=减脂且填了体重才进目标页，否则直达推荐页。
                      final goal = ref
                          .read(onboardingControllerProvider)
                          .answers
                          .goal;
                      if (goal == GoalAnswer.loseWeight &&
                          profile.weightKg != null) {
                        context.go('/onboarding/goal');
                      } else {
                        context.go('/onboarding/recommendation');
                      }
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

/// 进食障碍筛查题（单选，可不作答；再点已选项取消作答）。
class _ScreeningSection extends StatelessWidget {
  const _ScreeningSection({required this.selected, required this.onSelected});

  final EatingDisorderScreening? selected;
  final ValueChanged<EatingDisorderScreening?> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final screening = t.onboarding.profile.screening;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(screening.title, style: textStyles.textBase),
        const SizedBox(height: AppSpacing.s1),
        Text(
          screening.hint,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        SegmentedButton<EatingDisorderScreening>(
          key: const ValueKey<String>('profile.screening'),
          segments: <ButtonSegment<EatingDisorderScreening>>[
            ButtonSegment<EatingDisorderScreening>(
              value: EatingDisorderScreening.yes,
              label: Text(screening.options.yes),
            ),
            ButtonSegment<EatingDisorderScreening>(
              value: EatingDisorderScreening.no,
              label: Text(screening.options.no),
            ),
            ButtonSegment<EatingDisorderScreening>(
              value: EatingDisorderScreening.preferNotToSay,
              label: Text(screening.options.preferNotToSay),
            ),
          ],
          selected: <EatingDisorderScreening>{?selected},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) => onSelected(selection.firstOrNull),
        ),
      ],
    );
  }
}
