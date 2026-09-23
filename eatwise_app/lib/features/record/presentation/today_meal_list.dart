import 'dart:async';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/domain/meal_type.dart';
import 'package:eatwise/features/record/domain/placeholder_food.dart';
import 'package:eatwise/features/record/presentation/meal_type_chips.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「今日记录」餐次分组列表（薄荷走查优化点 2）：
/// 早/午/晚/加餐分组标题 + 组内条目；无餐次的历史数据归入「其他」组。
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
    final groups = groupByMealType(entries, (e) => e.mealType);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      children: <Widget>[
        Text(t.record.today.title, style: textStyles.textBase),
        for (final group in groups) ...<Widget>[
          const SizedBox(height: AppSpacing.s3),
          Text(
            MealTypeChips.labelOf(t, group.mealType),
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s1),
          for (final entry in group.items) _EntryRow(entry: entry),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              name,
              style: textStyles.textBase.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (underReview)
            Container(
              margin: const EdgeInsets.only(left: AppSpacing.s2),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              decoration: BoxDecoration(
                color: colors.brandAccent,
                borderRadius: radii.rSm,
              ),
              child: Text(
                cs.badgePending,
                style: textStyles.textXs.copyWith(color: colors.bgPrimary),
              ),
            ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            '${entry.amountG.round()} ${t.record.nutrition.gramUnit} · '
            '${entry.kcal.round()} ${t.record.nutrition.kcalUnit}',
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          // 删除入口（走查修复）：≥40px 触控目标，确认弹窗防误触。
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            color: colors.textSecondary,
            tooltip: t.record.today.deleteEntry,
            onPressed: () => unawaited(_confirmDelete(context, ref)),
          ),
        ],
      ),
    );
  }
}
