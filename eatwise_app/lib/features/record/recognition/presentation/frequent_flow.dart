import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 常吃复用入口（PRD M3：历史高频食物 Top N，点选即填充结果卡）。
Future<void> startFrequentPick(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _FrequentFoodsSheet(),
  );
}

class _FrequentFoodsSheet extends ConsumerWidget {
  const _FrequentFoodsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    final frequent = ref.watch(recordFrequentFoodsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.frequentTitle, style: textStyles.textLg),
            const SizedBox(height: AppSpacing.s2),
            Flexible(
              child: frequent.when(
                data: (foods) {
                  if (foods.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s4,
                      ),
                      child: Text(
                        s.frequentEmpty,
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: foods.length,
                    itemBuilder: (context, index) {
                      final food = foods[index];
                      return ListTile(
                        title: Text(
                          isEn ? food.nameEn : food.nameZh,
                          style: textStyles.textBase,
                        ),
                        subtitle: Text(
                          '${food.kcalPer100g.round()} '
                          '${s.kcalUnit}/100${s.gramUnit}',
                          style: textStyles.textSm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        onTap: () {
                          // 点选即填充结果卡（默认 100g，与手动选择一致）。
                          ref.read(recordSelectedFoodProvider.notifier).state =
                              food;
                          ref.read(recordAmountTextProvider.notifier).state =
                              '100';
                          ref.read(recordLowConfidenceProvider.notifier).state =
                              false;
                          ref.read(recordEntrySourceProvider.notifier).state =
                              EntrySource.frequent;
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.s4),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => Text(
                  s.frequentEmpty,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
