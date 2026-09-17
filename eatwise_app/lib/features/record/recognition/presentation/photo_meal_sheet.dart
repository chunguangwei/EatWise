/// 拍照识别明细确认弹层（多行明细协议 UI）：逐条「名称 + 克数输入（可改）
/// + 该条营养（按克数实时换算）+ 低置信『请确认』标记 + 删除」，底部
/// 「全部记录」一键入账（每条一条 entry，EntrySource.photo）。
///
/// 库未命中条目：入账时先自动建成自定义食物（模型估值 +
/// CustomFoodSource.llmEstimate 口径）再入账；离线落本地 pending，
/// 联网后由既有 retryPending 上行。
library;

import 'dart:async';

import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 明细确认弹层结果（关闭时带回）。
final class PhotoMealResult {
  const PhotoMealResult({this.loggedCount = 0, this.retake = false});

  /// 已入账条数（0 = 未入账直接关闭/取消）。
  final int loggedCount;

  /// 用户点了「重新拍摄」（调用方重新走入口流程）。
  final bool retake;
}

/// 打开明细确认弹层（isScrollControlled，键盘弹起不遮挡克数输入）。
Future<PhotoMealResult?> showPhotoMealConfirmSheet(
  BuildContext context,
  WidgetRef ref,
  List<RecognizedMealItem> items,
) {
  return showModalBottomSheet<PhotoMealResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: PhotoMealConfirmSheet(items: items),
    ),
  );
}

/// 明细确认弹层（ConsumerStateful：克数输入联动 + 删除 + 一键入账）。
class PhotoMealConfirmSheet extends ConsumerStatefulWidget {
  const PhotoMealConfirmSheet({super.key, required this.items});

  /// 识别明细（顺序即模型输出顺序）。
  final List<RecognizedMealItem> items;

  @override
  ConsumerState<PhotoMealConfirmSheet> createState() =>
      _PhotoMealConfirmSheetState();
}

/// 明细行状态（条目 + 克数输入控制器）。
final class _MealRow {
  _MealRow(this.item)
    : gramsController = TextEditingController(text: _formatGrams(item.grams));

  final RecognizedMealItem item;
  final TextEditingController gramsController;

  /// 克数整数化初值（200.0 → "200"，153.5 → "153.5"）。
  static String _formatGrams(double grams) {
    return grams == grams.roundToDouble()
        ? grams.round().toString()
        : grams.toString();
  }
}

class _PhotoMealConfirmSheetState extends ConsumerState<PhotoMealConfirmSheet> {
  late final List<_MealRow> _rows = [
    for (final item in widget.items) _MealRow(item),
  ];

  /// 入账在途（防连点）。
  bool _saving = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.gramsController.dispose();
    }
    super.dispose();
  }

  /// 行的有效克数（非法输入回退模型估算克数——输入框可清空编辑中，
  /// 不以中间态拦截用户）。
  double _effectiveGrams(_MealRow row) {
    final parsed = double.tryParse(row.gramsController.text.trim());
    return parsed != null && parsed > 0 ? parsed : row.item.grams;
  }

  /// 行营养文本（按当前克数实时换算，US-3.1 口径）。
  String _nutritionText(RecordStrings s, _MealRow row) {
    final ratio = _effectiveGrams(row) / 100;
    final per100g = row.item.per100g;
    final kcal = (per100g.kcal * ratio).round();
    final protein = (per100g.proteinG * ratio).toStringAsFixed(1);
    final carb = (per100g.carbG * ratio).toStringAsFixed(1);
    final fat = (per100g.fatG * ratio).toStringAsFixed(1);
    return '${s.nutritionKcal} $kcal ${s.kcalUnit} · '
        '${s.nutritionProtein} $protein ${s.gramUnit} · '
        '${s.nutritionCarb} $carb ${s.gramUnit} · '
        '${s.nutritionFat} $fat ${s.gramUnit}';
  }

  /// 「全部记录」：逐条入账；库未命中条目先自动建自定义食物
  /// （模型估值 + llmEstimate 口径；离线落本地 pending）再入账。
  Future<void> _logAll() async {
    if (_saving || _rows.isEmpty) return;
    setState(() => _saving = true);
    final repo = ref.read(recordRepositoryProvider);
    final customRepo = ref.read(customFoodRepositoryProvider);
    var logged = 0;
    try {
      for (final row in List<_MealRow>.of(_rows)) {
        var food = row.item.food;
        if (food == null) {
          final saved = await customRepo.save(
            CustomFoodDraft(
              nameZh: row.item.name,
              nameEn: row.item.nameEn,
              aliasesZh: const <String>[],
              per100g: row.item.per100g,
              source: CustomFoodSource.llmEstimate,
            ),
          );
          food = saved.food;
        }
        await repo.addEntry(
          RecordDraft(
            foodId: food.id,
            amountG: _effectiveGrams(row),
            mealUtc: DateTime.now().toUtc(),
            source: EntrySource.photo,
          ),
        );
        logged++;
      }
      if (mounted) {
        // 提交成功后收起键盘（Y5），避免弹层关闭后键盘滞留。
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(PhotoMealResult(loggedCount: logged));
      }
    } on Object {
      // 入账失败（如自定义食物 4xx）：留在弹层内，用户可重试/删条目。
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    return SafeArea(
      // 与自定义食物弹层同款布局：整体可滚（条目多/键盘弹起时不溢出），
      // 明细行少时自然贴合内容高度。
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(s.photoMealConfirmTitle, style: textStyles.textLg),
            const SizedBox(height: AppSpacing.s3),
            for (final row in _rows) ...<Widget>[
              _buildRow(s, colors, textStyles, radii, row),
              const SizedBox(height: AppSpacing.s2),
            ],
            const SizedBox(height: AppSpacing.s1),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(const PhotoMealResult(retake: true)),
                  child: Text(s.photoRetake),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () =>
                            Navigator.of(context).pop(const PhotoMealResult()),
                  child: Text(s.cancelAction),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving || _rows.isEmpty
                      ? null
                      : () => unawaited(_logAll()),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brandPrimary,
                    minimumSize: const Size(0, AppSpacing.s12),
                  ),
                  child: Text(s.photoLogAll, style: textStyles.textBase),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 明细行：名称（+库未收录/请确认标记 + 删除）+ 克数输入 + 实时营养。
  Widget _buildRow(
    RecordStrings s,
    AppColors colors,
    AppTextStyles textStyles,
    AppRadii radii,
    _MealRow row,
  ) {
    final item = row.item;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(item.name, style: textStyles.textBase)),
              if (!item.isMatched)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s2),
                  child: Text(
                    s.photoUnmatchedItemTag,
                    style: textStyles.textXs.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              if (item.isLowConfidence)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s2),
                  child: Text(
                    s.cardPleaseConfirm,
                    style: textStyles.textXs.copyWith(
                      color: colors.signalYellow,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: s.cancelAction,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => setState(() => _rows.remove(row)),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 96,
                child: TextField(
                  controller: row.gramsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                  ],
                  style: textStyles.textBase,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: colors.bgPrimary,
                    border: OutlineInputBorder(
                      borderRadius: radii.rSm,
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setState(() {}), // 营养实时重算
                ),
              ),
              const SizedBox(width: AppSpacing.s1),
              Text(s.gramUnit, style: textStyles.textSm),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  _nutritionText(s, row),
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
