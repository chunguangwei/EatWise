import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/domain/meal_type.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 餐次选择 chips（薄荷走查优化点 2）：确认记录卡 / 食物详情弹层共用。
///
/// 未手动选择时高亮智能预判值（按当前本地小时），点击切换写入
/// [recordMealTypeProvider]（入账或关闭结果卡后由调用方复位 null）。
class MealTypeChips extends ConsumerWidget {
  const MealTypeChips({super.key});

  /// 餐次 → 展示文案（i18n key：record.meal.*）。
  static String labelOf(Translations t, MealType? mealType) =>
      switch (mealType) {
        MealType.breakfast => t.record.meal.breakfast,
        MealType.lunch => t.record.meal.lunch,
        MealType.dinner => t.record.meal.dinner,
        MealType.snack => t.record.meal.snack,
        null => t.record.meal.other,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    // 未手动选择时按当前时间智能预判（与仓储兜底口径同一纯函数）。
    final selected =
        ref.watch(recordMealTypeProvider) ??
        suggestMealType(DateTime.now().toLocal().hour);

    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          t.record.meal.label,
          style: textStyles.textXs.copyWith(color: colors.textSecondary),
        ),
        for (final mealType in MealType.values)
          ChoiceChip(
            label: Text(labelOf(t, mealType)),
            labelStyle: textStyles.textXs.copyWith(
              color: selected == mealType
                  ? colors.bgPrimary
                  : colors.textPrimary,
            ),
            selected: selected == mealType,
            selectedColor: colors.brandPrimary,
            backgroundColor: colors.bgPrimary,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) =>
                ref.read(recordMealTypeProvider.notifier).state = mealType,
          ),
      ],
    );
  }
}
