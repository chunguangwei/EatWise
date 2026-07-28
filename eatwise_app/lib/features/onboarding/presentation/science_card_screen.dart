import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 原理科普卡占位页（M1 功能点 5：针对「怕伤身」的断食原理可视化占位，
/// 承接设计稿信息图⑥；含「非医疗建议」免责文案，D-18）。
class ScienceCardScreen extends StatelessWidget {
  const ScienceCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    return Scaffold(
      appBar: AppBar(title: Text(t.onboarding.science.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            _InfoCard(
              title: t.onboarding.science.card1Title,
              body: t.onboarding.science.card1Body,
            ),
            const SizedBox(height: AppSpacing.s3),
            _InfoCard(
              title: t.onboarding.science.card2Title,
              body: t.onboarding.science.card2Body,
            ),
            const SizedBox(height: AppSpacing.s6),
            Container(
              key: const ValueKey<String>('onboarding.science.disclaimer'),
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                borderRadius: radii.rLg,
              ),
              child: Text(
                t.onboarding.science.disclaimer,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: textStyles.textLg),
          const SizedBox(height: AppSpacing.s2),
          Text(
            body,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
