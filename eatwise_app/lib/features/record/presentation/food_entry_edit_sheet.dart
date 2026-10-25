import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/widgets/app_bottom_sheet.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/meal_type.dart';
import 'package:eatwise/features/record/domain/placeholder_food.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/meal_type_chips.dart';
import 'package:eatwise/features/record/presentation/portion_input.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 今日记录「编辑」弹层（记录纠错）：份量 + 餐次原地纠正，保存走
/// [RecordRepository.updateEntry]（synced→换新幂等键转 submitting 上行，
/// pending 原位改；mealType 纯本地不上行）。
///
/// 复用 AppBottomSheet 骨架（按钮常驻/键盘避让）+ portionInputDecoration
/// （可见描边+克单位）+ MealTypeChips（全局 [recordMealTypeProvider]，
/// 打开时以记录现值播种、关闭复位 null——与记录页结果卡同一复位纪律）。
Future<void> showFoodEntryEditSheet(BuildContext context, FoodEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FoodEntryEditSheet(entry: entry),
  );
}

class FoodEntryEditSheet extends ConsumerStatefulWidget {
  const FoodEntryEditSheet({required this.entry, super.key});

  final FoodEntry entry;

  @override
  ConsumerState<FoodEntryEditSheet> createState() => _FoodEntryEditSheetState();
}

class _FoodEntryEditSheetState extends ConsumerState<FoodEntryEditSheet> {
  final TextEditingController _amountController = TextEditingController();
  bool _saving = false;
  // initState 捕获控制器：播种经 postFrameCallback 写值（dispose 期禁改 provider）。
  late final StateController<MealType?> _mealType;

  @override
  void initState() {
    super.initState();
    final amount = widget.entry.amountG;
    _amountController.text = amount == amount.truncateToDouble()
        ? amount.toInt().toString()
        : amount.toString();
    _mealType = ref.read(recordMealTypeProvider.notifier);
    // 餐次 chips 走全局 provider：以记录现值播种；无显式餐次按**入账时刻**
    // 推导（与展示层 displayMealType 同口径）——chips 高亮即实际分组，
    // 用户不动直接保存=餐次不变（用当前小时会把早晨记录静默改成晚餐）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mealType.state =
            widget.entry.mealType ??
            suggestMealType(
              DateTime.parse(widget.entry.datetimeUtc).toLocal().hour,
            );
      }
    });
  }

  @override
  void dispose() {
    // 餐次 provider 复位由调用方在弹层关闭后执行（today_meal_list 的
    // whenComplete）——riverpod 禁止在 dispose 生命周期改 provider。
    _amountController.dispose();
    super.dispose();
  }

  double? get _amountG => parseFoodAmount(_amountController.text.trim());

  bool get _amountValid => (_amountG ?? 0) > 0;

  Future<void> _save() async {
    final amountG = _amountG;
    if (!_amountValid || _saving) return;
    setState(() => _saving = true);
    final t = Translations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final localId = widget.entry.localId;
    try {
      await ref
          .read(recordRepositoryProvider)
          .updateEntry(
            localId,
            amountG: amountG!,
            mealType: ref.read(recordMealTypeProvider),
          );
      // 用户可在写库期间下滑/返回关闭弹层；退场动画中 mounted 仍为 true，
      // 必须同时检查路由，避免再次 pop 掉底下的页面。
      if (!mounted || route?.isCurrent == false) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.record.today.edited)));
    } on Object {
      // 食物行缺失（StateError）等异常 → 弹层不关，用户可改回后重试。
      if (!mounted || route?.isCurrent == false) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(t.record.today.editSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    final food = ref.watch(entryFoodProvider(widget.entry.foodId)).value;
    final name = food == null
        ? widget.entry.foodId
        : displayFoodName(t, food, isEn: isEn);
    // 份量改动实时预览新热量（与入账同口径纯函数；食物行缺失不显示）。
    final previewKcal = _amountValid && food != null
        ? NutritionSnapshot.forAmount(food, _amountG!).kcal.round()
        : null;

    return AppBottomSheet(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.record.today.editTitle,
            style: textStyles.textXl.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            name,
            style: textStyles.textBase.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s3),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: false,
            onChanged: (_) => setState(() {}),
            decoration: portionInputDecoration(
              t: t,
              colors: colors,
              radii: radii,
              fillColor: colors.bgPrimary,
              helperText: _amountValid ? null : t.record.amount.invalid,
            ),
          ),
          if (previewKcal != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              '$previewKcal ${t.record.nutrition.kcalUnit}',
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          const MealTypeChips(),
        ],
      ),
      bottomBar: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _amountValid && !_saving ? _save : null,
          child: Text(t.common.action.save),
        ),
      ),
    );
  }
}
