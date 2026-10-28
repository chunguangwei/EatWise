import 'dart:async';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/widgets/glass.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/domain/meal_type.dart';
import 'package:eatwise/features/record/domain/placeholder_food.dart';
import 'package:eatwise/features/record/presentation/food_entry_edit_sheet.dart';
import 'package:eatwise/features/record/presentation/meal_type_chips.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「今日记录」餐次分组列表（薄荷走查优化点 2）：
/// 早/午/晚/加餐分组标题 + 组内条目；无餐次的记录按就餐时刻推导
///（跨端下行数据无本地 mealType，见 displayMealType）。
/// 在记录页搜索框为空且有今日记录时，替代搜索空态展示（对标薄荷记录页）。
class TodayMealList extends ConsumerWidget {
  const TodayMealList({required this.entries, super.key});

  /// 今日有效记录（已按就餐时间升序）。
  final List<FoodEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final groups = groupByMealType(
      entries,
      (e) => displayMealType(e.mealType, DateTime.parse(e.datetimeUtc)),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      children: <Widget>[
        Text(
          t.record.today.title,
          style: textStyles.textLg.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final group in groups) ...<Widget>[
          const SizedBox(height: AppSpacing.s3),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  MealTypeChips.labelOf(t, group.mealType),
                  style: textStyles.textBase.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${group.items.fold<double>(0, (sum, entry) => sum + entry.kcal).round()} ${t.record.nutrition.kcalUnit}',
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1),
          Material(
            color: colors.bgSecondary,
            borderRadius: radii.rLg,
            child: Container(
              decoration: AppSurfaces.card(
                colors,
                shadows,
                radius: radii.rLg,
                onMaterial: true,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < group.items.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: AppSpacing.s4,
                        endIndent: AppSpacing.s4,
                        color: colors.divider,
                      ),
                    _EntryRow(entry: group.items[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单条记录行：食物名 + 份量/热量摘要 + 删除（走查修复：入账后无法删除）。
class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry});

  final FoodEntry entry;

  /// 删除确认弹窗（防误触）。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final s = RecordStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.record.today.deleteEntry),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.record.today.deleteConfirmAction),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    await ref.read(recordRepositoryProvider).deleteEntry(entry.localId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.record.today.deleted)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final cs = CustomFoodStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    final food = ref.watch(entryFoodProvider(entry.foodId)).value;
    // 食物行缺失（库下行未覆盖等异常）回退 foodId；占位行（名称==id，
    // 下行合成）回退「未知食物」（id 仍可在详情页查，回查补名后自动恢复）。
    final name = food == null
        ? entry.foodId
        : displayFoodName(t, food, isEn: isEn);
    // 乐观入账（未入库食品先记）：该食物贡献审核中 → 条目带「审核中」标记。
    final underReview =
        food?.isCustom == true && food?.contributionStatus == 'pending';

    Widget description({required bool stacked}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: textStyles.textBase.copyWith(color: colors.textPrimary),
          maxLines: stacked ? null : 1,
          overflow: stacked ? null : TextOverflow.ellipsis,
        ),
        if (underReview)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.s1),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s1,
            ),
            decoration: BoxDecoration(
              color: colors.brandAccent.withValues(alpha: 0.14),
              borderRadius: radii.rSm,
            ),
            child: Text(
              cs.badgePending,
              style: textStyles.textXs.copyWith(color: colors.textPrimary),
            ),
          ),
        Text(
          '${entry.amountG.round()} ${t.record.nutrition.gramUnit}',
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    final energy = Text(
      '${entry.kcal.round()} ${t.record.nutrition.kcalUnit}',
      style: textStyles.textSm.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    final actions = <Widget>[
      if (food != null)
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          iconSize: 20,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          color: colors.textSecondary,
          tooltip: t.record.today.editEntry,
          onPressed: () => unawaited(
            showFoodEntryEditSheet(context, entry).whenComplete(
              () => ref.read(recordMealTypeProvider.notifier).state = null,
            ),
          ),
        ),
      IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        iconSize: 20,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        color: colors.textSecondary,
        tooltip: t.record.today.deleteEntry,
        onPressed: () => unawaited(_confirmDelete(context, ref)),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 480 &&
              MediaQuery.textScalerOf(context).scale(14) > 18;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                description(stacked: true),
                const SizedBox(height: AppSpacing.s1),
                Wrap(
                  spacing: AppSpacing.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [energy, ...actions],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: description(stacked: false)),
              const SizedBox(width: AppSpacing.s2),
              energy,
              ...actions,
            ],
          );
        },
      ),
    );
  }
}
