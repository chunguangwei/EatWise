import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 3 题问卷页（M1 功能点 1，D-02：目标/作息/经验，单选，可跳过）。
///
/// 每答一题进度即本地保存，中途退出可续答（PRD M1 异常与边界）。
class QuestionnaireScreen extends ConsumerWidget {
  const QuestionnaireScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final step = state.currentStep;

    final (:title, :options, :selected) = _questionContent(t, state, step);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.onboarding.quiz.progress(
            step: step + 1,
            total: OnboardingController.questionCount,
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('onboarding.quiz.skip'),
            onPressed: () {
              controller.skipQuiz();
              context.go('/onboarding/recommendation');
            },
            child: Text(t.onboarding.quiz.skip),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LinearProgressIndicator(
                value: (step + 1) / OnboardingController.questionCount,
                color: colors.brandPrimary,
                backgroundColor: colors.bgSecondary,
              ),
              const SizedBox(height: AppSpacing.s6),
              Text(
                t.onboarding.quiz.title,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(title, style: textStyles.textXl),
              const SizedBox(height: AppSpacing.s6),
              for (final option in options) ...<Widget>[
                _OptionCard(
                  key: ValueKey<String>(
                    'onboarding.quiz.option.${option.name}',
                  ),
                  label: _optionLabel(t, step, option),
                  selected: option == selected,
                  onTap: () => controller.selectAnswer(option.name),
                ),
                const SizedBox(height: AppSpacing.s3),
              ],
              const Spacer(),
              Row(
                children: <Widget>[
                  if (step > 0)
                    OutlinedButton(
                      key: const ValueKey<String>('onboarding.quiz.back'),
                      onPressed: controller.previousStep,
                      child: Text(t.onboarding.quiz.back),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey<String>('onboarding.quiz.next'),
                    onPressed: !controller.currentAnswered
                        ? null
                        : () {
                            if (step < OnboardingController.questionCount - 1) {
                              controller.nextStep();
                            } else {
                              controller.finishQuiz();
                              context.go('/onboarding/recommendation');
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.brandPrimary,
                    ),
                    child: Text(
                      step < OnboardingController.questionCount - 1
                          ? t.onboarding.quiz.next
                          : t.onboarding.quiz.finish,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({String title, List<Enum> options, Enum? selected}) _questionContent(
    Translations t,
    OnboardingState state,
    int step,
  ) {
    return switch (step) {
      0 => (
        title: t.onboarding.quiz.q1.title,
        options: GoalAnswer.values,
        selected: state.answers.goal,
      ),
      1 => (
        title: t.onboarding.quiz.q2.title,
        options: ScheduleAnswer.values,
        selected: state.answers.schedule,
      ),
      _ => (
        title: t.onboarding.quiz.q3.title,
        options: ExperienceAnswer.values,
        selected: state.answers.experience,
      ),
    };
  }

  String _optionLabel(Translations t, int step, Enum option) {
    return switch ((step, option.name)) {
      (0, 'loseWeight') => t.onboarding.quiz.q1.options.loseWeight,
      (0, 'improveHealth') => t.onboarding.quiz.q1.options.improveHealth,
      (0, 'adjustSchedule') => t.onboarding.quiz.q1.options.adjustSchedule,
      (0, _) => t.onboarding.quiz.q1.options.justTrying,
      (1, 'regular') => t.onboarding.quiz.q2.options.regular,
      (1, 'shiftWork') => t.onboarding.quiz.q2.options.shiftWork,
      (1, _) => t.onboarding.quiz.q2.options.flexible,
      (2, 'beginner') => t.onboarding.quiz.q3.options.beginner,
      (2, 'triedButStopped') => t.onboarding.quiz.q3.options.triedButStopped,
      (_, _) => t.onboarding.quiz.q3.options.experienced,
    };
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Material(
      color: colors.bgSecondary,
      borderRadius: radii.rLg,
      child: InkWell(
        borderRadius: radii.rLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: radii.rLg,
            border: Border.all(
              color: selected ? colors.brandPrimary : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: textStyles.textBase)),
              if (selected)
                Icon(Icons.check_circle, color: colors.brandPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
