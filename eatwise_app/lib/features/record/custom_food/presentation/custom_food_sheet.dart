import 'dart:async';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自定义食物入口流程（K2：搜索无结果 CTA → 弹层表单 → 保存 → 回填结果卡）。
///
/// 保存成功后自动把该食物填入记录结果卡（份量留空必填，与现行规则一致）；
/// 离线保存提示「已保存到本机，联网后自动同步」。
/// [barcodeAlias]：扫码未收录场景传入条码号，预填进别名输入框〔假设〕。
Future<void> startCustomFoodFlow(
  BuildContext context,
  WidgetRef ref, {
  String? barcodeAlias,
}) async {
  final cs = CustomFoodStrings.of(context);
  // 联网机会窗口：opportunistic 重试离线期间落本地的 pending 自定义食物
  //（〔假设〕sync/push 未支持 foodCustom op，待主代理决定是否挂 syncNow）。
  unawaited(ref.read(customFoodRepositoryProvider).retryPending());
  final result = await showModalBottomSheet<CustomFoodSaveResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: CustomFoodSheet(initialAlias: barcodeAlias),
    ),
  );
  if (result == null || !context.mounted) return;
  ref.read(recordSelectedFoodProvider.notifier).state = result.food;
  // 份量必填：留空由用户输入（与手动搜索选中口径一致）。
  ref.read(recordAmountTextProvider.notifier).state = '';
  ref.read(recordEntrySourceProvider.notifier).state = EntrySource.manual;
  ref.read(recordLowConfidenceProvider.notifier).state = false;
  final messenger = ScaffoldMessenger.of(context);
  if (!result.uploaded) {
    messenger.showSnackBar(SnackBar(content: Text(cs.savedOffline)));
  } else if (result.contributeSubmitted) {
    // 保存时勾选共享且贡献成功。
    messenger.showSnackBar(SnackBar(content: Text(cs.submittedReview)));
  } else if (!result.contributionFailed) {
    // 保存时未勾选共享：Toast 提供「分享给所有用户」二次动作（事后贡献）。
    messenger.showSnackBar(
      SnackBar(
        content: Text(cs.savedOnline),
        action: SnackBarAction(
          label: cs.shareAction,
          onPressed: () =>
              unawaited(contributeCustomFood(context, ref, result.food.id)),
        ),
      ),
    );
  }
  // 拒收/失败原因已在弹层内展示（服务端双语 message），不再弹 Toast。
}

/// 事后贡献入口（保存成功 Toast 的「分享给所有用户」动作）：
/// 成功显示「已提交审核」并刷新搜索结果状态标签；拒收显示服务端双语原因。
Future<void> contributeCustomFood(
  BuildContext context,
  WidgetRef ref,
  String foodId,
) async {
  final cs = CustomFoodStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(customFoodRepositoryProvider).contribute(foodId);
    // 状态标签数据源已落本地，刷新搜索结果让「审核中」立即可见。
    ref.invalidate(recordFoodSearchProvider);
    messenger.showSnackBar(SnackBar(content: Text(cs.submittedReview)));
  } on ApiException catch (e) {
    ref.invalidate(recordFoodSearchProvider); // 拒收落 rejected 同样需刷新
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// 自定义食物弹层：菜名（必填）+ 别名（可选）+ AI 估算 + 四营养输入。
///
/// AI 估算成功预填四营养并显示「AI 估算，请确认」徽标（low 置信度额外
/// 提示核对）；估算不可用（503/超时/网络）降级手动填写，不阻断。
/// [initialAlias]：扫码未收录承接场景预填的别名（条码号〔假设〕）。
class CustomFoodSheet extends ConsumerStatefulWidget {
  const CustomFoodSheet({super.key, this.initialAlias});

  /// 预填别名（可选，扫码未收录时传入条码号）。
  final String? initialAlias;

  @override
  ConsumerState<CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends ConsumerState<CustomFoodSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  late final TextEditingController _aliasController = TextEditingController(
    text: widget.initialAlias,
  );
  final TextEditingController _kcalController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();

  /// 估算请求在途（按钮转 loading，防连点）。
  bool _estimating = false;

  /// 估算值仍在表单中（显示「AI 估算，请确认」徽标；用户改值即清除，
  /// 改后按 manual 保存——估算标记只覆盖未改动的估算值）。
  bool _estimateApplied = false;

  /// 最近一次估算置信度 low（额外提示核对）。
  bool _estimateLow = false;

  /// 估算不可用提示（503/超时/网络；降级手动填写，不阻断）。
  bool _estimateUnavailable = false;

  /// 保存在途（防连点重复提交）。
  bool _saving = false;

  /// 勾选「分享给所有用户」（默认不勾；保存成功后调 /contribute 提交审核）。
  bool _shareToAll = false;

  @override
  void dispose() {
    _nameController.dispose();
    _aliasController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  /// 点「AI 估算」：调 /foods/estimate，成功预填四营养。
  Future<void> _onEstimate() async {
    final cs = CustomFoodStrings.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _formKey.currentState?.validate(); // 触发菜名必填错误
      return;
    }
    setState(() {
      _estimating = true;
      _estimateUnavailable = false;
    });
    try {
      final estimate = await ref.read(customFoodRemoteProvider).estimate(name);
      if (!mounted) return;
      setState(() {
        _kcalController.text = _formatNumber(estimate.per100g.kcal);
        _proteinController.text = _formatNumber(estimate.per100g.proteinG);
        _carbController.text = _formatNumber(estimate.per100g.carbG);
        _fatController.text = _formatNumber(estimate.per100g.fatG);
        _estimateApplied = true;
        _estimateLow = estimate.isLowConfidence;
      });
    } on Object catch (e) {
      if (!mounted) return;
      if (isEstimateUnavailable(e)) {
        // 503/超时/网络：提示降级手动填写，不阻断（字段本就可编辑）。
        setState(() => _estimateUnavailable = true);
      } else {
        final message = e is ApiException ? e.message : cs.estimateUnavailable;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  /// 保存：校验 → 远端 /foods/custom（离线仅落本地 pending）→ 关弹层回填。
  Future<void> _onSave() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _saving = true;
    try {
      final name = _nameController.text.trim();
      final draft = CustomFoodDraft(
        nameZh: name,
        // 单输入框不区分中英：英文字母开头的名字同步进英文名（D-15 双语搜索）。
        nameEn: _looksEnglish(name) ? name : null,
        aliasesZh: _parseAliases(_aliasController.text),
        per100g: NutritionSnapshot(
          kcal: double.parse(_kcalController.text.trim()),
          proteinG: double.parse(_proteinController.text.trim()),
          carbG: double.parse(_carbController.text.trim()),
          fatG: double.parse(_fatController.text.trim()),
        ),
        // 估算值被用户改动后按 manual 保存（估算标记只覆盖未改动的估算值）。
        source: _estimateApplied
            ? CustomFoodSource.llmEstimate
            : CustomFoodSource.manual,
      );
      var result = await ref.read(customFoodRepositoryProvider).save(draft);
      // 勾选共享且已上行：立即贡献（幂等）；拒收展示服务端双语原因，
      // 保存本身不受影响（食物仍落本地可搜可记）。
      if (_shareToAll && result.uploaded) {
        try {
          await ref
              .read(customFoodRepositoryProvider)
              .contribute(result.food.id);
          result = CustomFoodSaveResult(
            food: result.food,
            uploaded: result.uploaded,
            contributeSubmitted: true,
          );
          // 状态落库后刷新搜索结果，「审核中」标签立即可见。
          ref.invalidate(recordFoodSearchProvider);
        } on ApiException catch (e) {
          result = CustomFoodSaveResult(
            food: result.food,
            uploaded: result.uploaded,
            contributionFailed: true,
          );
          ref.invalidate(recordFoodSearchProvider);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
      }
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      _saving = false;
    }
  }

  /// 别名解析：中英文逗号/顿号分隔，trim 去空去重。
  static List<String> _parseAliases(String raw) {
    final seen = <String>{};
    for (final part in raw.split(RegExp('[,，、;；]'))) {
      final alias = part.trim();
      if (alias.isNotEmpty) seen.add(alias);
    }
    return seen.toList();
  }

  /// 是否纯英文名（粗略：不含 CJK 字符）。
  static bool _looksEnglish(String name) => !RegExp(r'[一-鿿]').hasMatch(name);

  /// 数字展示（116.0 → "116"，13.3 → "13.3"）。
  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }

  /// 营养字段校验：必填 >0；热量 ≤900，宏量 ≤100。
  FormFieldValidator<String> _nutritionValidator(
    CustomFoodStrings cs,
    double max,
    String rangeMsg,
  ) {
    return (value) {
      final parsed = double.tryParse((value ?? '').trim());
      if (parsed == null || parsed <= 0) return cs.nutritionRequired;
      if (parsed > max) return rangeMsg;
      return null;
    };
  }

  /// 估算值被手动改动：清除估算徽标（保存时按 manual 上报）。
  void _onNutritionEdited(String _) {
    if (_estimateApplied || _estimateLow) {
      setState(() {
        _estimateApplied = false;
        _estimateLow = false;
      });
    }
  }

  InputDecoration _fieldDecoration(
    AppColors colors,
    AppRadii radii,
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.bgSecondary,
      constraints: const BoxConstraints(minHeight: AppSpacing.s12),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: radii.rMd,
        borderSide: BorderSide.none,
      ),
      // 表单规范：focus 品牌绿描边。
      focusedBorder: OutlineInputBorder(
        borderRadius: radii.rMd,
        borderSide: BorderSide(color: colors.brandPrimary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = CustomFoodStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final numberKeyboard = const TextInputType.numberWithOptions(decimal: true);
    final numberFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(cs.title, style: textStyles.textLg),
              const SizedBox(height: AppSpacing.s4),
              TextFormField(
                controller: _nameController,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.nameLabel),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? cs.nameRequired : null,
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _aliasController,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.aliasLabel),
              ),
              const SizedBox(height: AppSpacing.s3),
              // AI 估算按钮（≥44px；在途转 loading 防连点）。
              OutlinedButton.icon(
                onPressed: _estimating ? null : () => unawaited(_onEstimate()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                  foregroundColor: colors.brandPrimary,
                  side: BorderSide(color: colors.brandPrimary),
                ),
                icon: _estimating
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.brandPrimary,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  _estimating ? cs.estimating : cs.estimate,
                  style: textStyles.textBase,
                ),
              ),
              // 估算不可用降级提示（双语，不阻断手动填写）。
              if (_estimateUnavailable)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s2),
                  child: Text(
                    cs.estimateUnavailable,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              // 「AI 估算，请确认」徽标（low 置信度额外提示核对）。
              if (_estimateApplied)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.brandAccent,
                      borderRadius: radii.rSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          cs.estimateBadge,
                          style: textStyles.textSm.copyWith(
                            color: colors.bgSecondary,
                          ),
                        ),
                        if (_estimateLow)
                          Text(
                            cs.estimateLow,
                            style: textStyles.textXs.copyWith(
                              color: colors.bgSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.s3),
              // 四营养输入（每 100g；全部必填 >0，热量 ≤900 / 宏量 ≤100）。
              TextFormField(
                controller: _kcalController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.kcalLabel),
                validator: _nutritionValidator(cs, 900, cs.kcalRange),
                onChanged: _onNutritionEdited,
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _proteinController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.proteinLabel),
                validator: _nutritionValidator(cs, 100, cs.macroRange),
                onChanged: _onNutritionEdited,
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _carbController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.carbLabel),
                validator: _nutritionValidator(cs, 100, cs.macroRange),
                onChanged: _onNutritionEdited,
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _fatController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.fatLabel),
                validator: _nutritionValidator(cs, 100, cs.macroRange),
                onChanged: _onNutritionEdited,
              ),
              const SizedBox(height: AppSpacing.s3),
              // 贡献开关（默认不勾）：保存成功后提交共享候选审核。
              CheckboxListTile(
                value: _shareToAll,
                onChanged: (value) =>
                    setState(() => _shareToAll = value ?? false),
                title: Text(cs.shareOptIn, style: textStyles.textSm),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.s4),
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_onSave()),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(cs.saveAction, style: textStyles.textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
