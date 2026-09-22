/// 识别明细确认弹层（多行明细协议 UI，拍照识别与一句话自由记共用）：
/// 逐条「名称 + 克数输入（可改）+ 该条营养（按克数实时换算）+ 低置信
/// 『请确认』标记 + 删除」，底部「全部记录」一键入账（每条一条 entry，
/// 来源由 [PhotoMealConfirmSheet.entrySource] 定）。
///
/// 库未命中条目：入账时先自动建成自定义食物（模型估值 +
/// CustomFoodSource.llmEstimate 口径）再入账；离线落本地 pending，
/// 联网后由既有 retryPending 上行。
library;

import 'dart:async';

import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/meal_type_chips.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/photo_recognition_logic.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 明细确认弹层结果（关闭时带回）。
final class PhotoMealResult {
  const PhotoMealResult({
    this.loggedCount = 0,
    this.retake = false,
    this.pendingReviewCount = 0,
  });

  /// 已入账条数（0 = 未入账直接关闭/取消）。
  final int loggedCount;

  /// 其中已提交众包审核的条数（库未命中自动新建条目；UI 据此提示
  /// 「M 条待审核」）。
  final int pendingReviewCount;

  /// 用户点了「重新拍摄」（调用方重新走入口流程）。
  final bool retake;
}

/// 打开明细确认弹层（isScrollControlled，键盘弹起不遮挡克数输入）。
Future<PhotoMealResult?> showPhotoMealConfirmSheet(
  BuildContext context,
  WidgetRef ref,
  List<RecognizedMealItem> items, {
  EntrySource entrySource = EntrySource.photo,
  bool showRetake = true,
}) {
  return showModalBottomSheet<PhotoMealResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: PhotoMealConfirmSheet(
        items: items,
        entrySource: entrySource,
        showRetake: showRetake,
      ),
    ),
  );
}

/// 明细确认弹层（ConsumerStateful：克数输入联动 + 删除 + 一键入账）。
class PhotoMealConfirmSheet extends ConsumerStatefulWidget {
  const PhotoMealConfirmSheet({
    super.key,
    required this.items,
    this.entrySource = EntrySource.photo,
    this.showRetake = true,
  });

  /// 识别明细（顺序即模型输出顺序）。
  final List<RecognizedMealItem> items;

  /// 入账来源（拍照识别 photo / 一句话自由记 voice；自由记不显示
  /// 「重新拍摄」入口）。
  final EntrySource entrySource;

  /// 是否显示「重新拍摄」（仅拍照场景；自由记为 false）。
  final bool showRetake;

  @override
  ConsumerState<PhotoMealConfirmSheet> createState() =>
      _PhotoMealConfirmSheetState();
}

/// 明细行状态（条目 + 克数输入控制器）。
final class _MealRow {
  _MealRow(this.item)
    : gramsController = TextEditingController(text: _formatGrams(item.grams));

  /// 当前条目（点选「相似食物」后替换为库内条目，不再走新建/送审）。
  RecognizedMealItem item;
  final TextEditingController gramsController;

  /// 克数整数化初值（200.0 → "200"，153.5 → "153.5"）。
  static String _formatGrams(double grams) {
    return grams == grams.roundToDouble()
        ? grams.round().toString()
        : grams.toString();
  }
}

class _PhotoMealConfirmSheetState extends ConsumerState<PhotoMealConfirmSheet> {
  // 数据通路双保险：空白名称条目不进明细卡（解析层已拒绝空名，
  // 此处兜底上游任何回归——宁可少一行，不渲染空白行）。
  late final List<_MealRow> _rows = [
    for (final item in widget.items)
      if (item.name.trim().isNotEmpty) _MealRow(item),
  ];

  /// 入账在途（防连点）。
  bool _saving = false;

  /// 各未命中行的相似食物候选（本地 drift 模糊搜索；空 = 无相近结果，
  /// 退化为自动新建+送审）。
  final Map<_MealRow, List<Food>> _similar = {};

  @override
  void initState() {
    super.initState();
    // 打开即对未命中行做模糊搜索（本地库，前缀递减查询序列）。
    for (final row in _rows) {
      if (!row.item.isMatched) unawaited(_findSimilar(row));
    }
    // 餐次 chips 共用全局 provider——进弹层先复位，避免残留上次选择。
    ref.read(recordMealTypeProvider.notifier).state = null;
  }

  /// 未命中行模糊搜索：递减前缀逐个查，首个非空结果取前 3 条。
  Future<void> _findSimilar(_MealRow row) async {
    final repo = ref.read(recordRepositoryProvider);
    for (final query in fuzzyQueryCandidates(row.item.name)) {
      final hits = await repo.searchFoods(query, limit: 3);
      if (hits.isNotEmpty) {
        if (mounted) setState(() => _similar[row] = hits);
        return;
      }
    }
    // 全空：_similar 不写入，行维持「自动新建+送审」退化路径。
  }

  /// 点选相似食物：替换为库内条目（营养用库内精准值，克重保留 AI 估算
  /// 可编辑），此后该行与命中条目同口径（直接入账，不走新建/送审）。
  void _useSimilarFood(_MealRow row, Food food) {
    setState(() {
      row.item = RecognizedMealItem(
        name: food.nameZh,
        nameEn: food.nameEn,
        grams: row.item.grams,
        per100g: NutritionSnapshot(
          kcal: food.kcalPer100g,
          proteinG: food.proteinPer100g,
          carbG: food.carbPer100g,
          fatG: food.fatPer100g,
        ),
        confidence: 0.9, // 用户亲选库内条目，高置信
        food: food,
      );
      _similar.remove(row);
    });
  }

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
  /// （模型估值 + llmEstimate 口径）再入账，并**提交众包审核**
  /// （乐观入账带「审核中」标记：approve 转正、reject 级联软删+同步清理，
  /// v1.12.0 既有链路）。离线/贡献失败不阻断入账（食物仍落个人库，
  /// 联网后 retryPending 上行）。
  Future<void> _logAll() async {
    if (_saving || _rows.isEmpty) return;
    setState(() => _saving = true);
    final repo = ref.read(recordRepositoryProvider);
    final customRepo = ref.read(customFoodRepositoryProvider);
    // 阶段 C：断食计时进行中的用餐打「断食期用餐」本地标记（不上行）。
    final duringFast = ref.read(isFastingInProgressProvider);
    // 餐次（走查修）：拍照/自由记流曾完全不传 mealType，仓储一律按当前
    // 小时智能预判；现在与搜索/详情流同款 chips，未点选时传 null 走预判。
    final mealType = ref.read(recordMealTypeProvider);
    var logged = 0;
    var pendingReview = 0;
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
          // 送审（离线/失败静默：不阻断入账，日志留痕）。
          if (saved.uploaded) {
            try {
              await customRepo.contribute(food.id);
              pendingReview++;
            } on Object catch (e) {
              debugPrint('[PhotoMeal] 送审失败（食物已落个人库，不影响入账）：$e');
            }
          }
        }
        await repo.addEntry(
          RecordDraft(
            foodId: food.id,
            amountG: _effectiveGrams(row),
            mealUtc: DateTime.now().toUtc(),
            source: widget.entrySource,
            duringFast: duringFast,
            mealType: mealType,
          ),
        );
        logged++;
      }
      if (mounted) {
        // 提交成功后收起键盘（Y5），避免弹层关闭后键盘滞留。
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(
          PhotoMealResult(
            loggedCount: logged,
            pendingReviewCount: pendingReview,
          ),
        );
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
            // 餐次选择（与搜索确认卡/详情弹层同款；整批条目共用一个餐次）。
            const MealTypeChips(),
            const SizedBox(height: AppSpacing.s2),
            const SizedBox(height: AppSpacing.s1),
            Row(
              children: <Widget>[
                if (widget.showRetake)
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

  /// 明细行：名称行（名称 + 删除，名称永不被挤压——真机反馈窄屏/大字体下
  /// 名称与删除钮被标记挤出不可见，故标记移到独立行）+ 标记行（库未收录/
  /// 请确认）+ 克数输入与实时营养行。
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
          // 第一行只放名称 + 删除：名称是该行第一视觉元素，
          // Expanded 保底宽度（360dp 窄屏也有 ~250px），超长省略不消失。
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  item.name,
                  style: textStyles.textBase,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          // 标记独立成行（Wrap 可换行）：不与名称抢宽度。
          if (!item.isMatched || item.isLowConfidence || item.fromLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s1),
              child: Wrap(
                spacing: AppSpacing.s2,
                children: <Widget>[
                  if (item.fromLabel)
                    Text(
                      s.photoLabelValueTag,
                      style: textStyles.textXs.copyWith(
                        color: colors.brandPrimary,
                      ),
                    ),
                  if (!item.isMatched)
                    Text(
                      s.photoUnmatchedItemTag,
                      style: textStyles.textXs.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (item.isLowConfidence)
                    Text(
                      s.cardPleaseConfirm,
                      style: textStyles.textXs.copyWith(
                        color: colors.signalYellow,
                      ),
                    ),
                ],
              ),
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
          // 相似食物候选区（仅未命中且模糊搜索有结果时）：
          // 点选即用库内条目替换（免新建/送审），否则维持自动新建+送审。
          if (!item.isMatched &&
              (_similar[row]?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Text(
              s.photoSimilarFoodsTitle,
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s1),
            for (final candidate in _similar[row]!)
              InkWell(
                borderRadius: radii.rSm,
                onTap: () => _useSimilarFood(row, candidate),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${candidate.nameZh} · '
                          '${candidate.kcalPer100g.round()} ${s.kcalUnit}/100${s.gramUnit}',
                          style: textStyles.textSm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        s.photoUseThisFood,
                        style: textStyles.textSm.copyWith(
                          color: colors.brandPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
