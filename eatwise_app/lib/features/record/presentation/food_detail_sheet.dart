import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_error_text.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/core/widgets/app_bottom_sheet.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:eatwise/features/moderation/application/admin_food_delete.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_sheet.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/domain/food_signal.dart';
import 'package:eatwise/features/record/domain/macro_energy.dart';
import 'package:eatwise/features/record/domain/nrv_reference.dart';
import 'package:eatwise/features/record/domain/placeholder_food.dart';
import 'package:eatwise/features/record/presentation/meal_type_chips.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/nutrition_label_ocr_logic.dart'
    show kKjPerKcal;
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阶段 E 食物详情底部弹层（薄荷对标合并设计：信息分层——名称头部 →
/// 显著热量 → 三大营养素供能比例三圆环 + 人话注释 → 红绿灯评价徽标 →
/// 其余明细折叠区 → 份量输入直接入账）。
///
/// 薄荷复盘坑位落实：不做字母评级（A~D 反直觉）、不做跨类参照物、
/// 供能圆环带「脂肪供能效率 2.25 倍」注释避免误读为重量比例。
/// 份量双轨（口语化单位）不做——食物库无份量单位数据，遗留。
///
/// [onConfirm]：用户在弹层内点「确认记录」时回调（参数为份量输入原文），
/// 弹层先关闭，由调用方接既有记录确认流程（乐观更新 + D-11 撤销吐司），
/// 不破坏记录页既有入账交互与埋点链路。
Future<void> showFoodDetailSheet({
  required BuildContext context,
  required Food food,
  required ValueChanged<String> onConfirm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => FoodDetailSheet(
      food: food,
      onConfirm: (amountText) {
        Navigator.of(sheetContext).pop();
        onConfirm(amountText);
      },
    ),
  );
}

/// 食物详情弹层内容（直接构造可测）。
class FoodDetailSheet extends ConsumerStatefulWidget {
  const FoodDetailSheet({
    required this.food,
    required this.onConfirm,
    super.key,
  });

  /// 食物库条目。
  final Food food;

  /// 「确认记录」回调（份量输入原文，校验由既有入账流程统一做）。
  final ValueChanged<String> onConfirm;

  @override
  ConsumerState<FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<FoodDetailSheet> {
  final TextEditingController _amountController = TextEditingController();

  /// 当前展示行：分享/编辑后原地刷新（编辑/删除成功则收起弹层）。
  late Food _food = widget.food;

  @override
  void initState() {
    super.initState();
    // 份量输入驱动营养预览实时重算（US-3.1 同口径）。
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final s = RecordStrings.of(context);
    final cs = CustomFoodStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    final messenger = ScaffoldMessenger.of(context);
    final food = _food;
    // 管理员角色（审批中心同一 role 口径：userMeProvider，不新造）。
    final isAdmin = ref.watch(userMeProvider).value?.role == 'admin';

    final goal = ref.watch(nutritionGoalProvider);
    final verdict = evaluateFoodSignal(
      kcalPer100g: food.kcalPer100g,
      proteinPer100g: food.proteinPer100g,
      carbPer100g: food.carbPer100g,
      fatPer100g: food.fatPer100g,
      goal: goal,
      config: NutritionRuleConfig.defaults,
    );
    final breakdown = computeMacroEnergyBreakdown(
      proteinG: food.proteinPer100g,
      carbG: food.carbPer100g,
      fatG: food.fatPer100g,
    );

    // 份量预览（按输入份量 × 每 100g 值换算，与记录页结果卡同格式）。
    final amount = double.tryParse(_amountController.text);
    final preview = amount != null && amount > 0 ? amount / 100 : null;
    // 「大约需走 N 步」随选中份量实时联动；未输入份量时按每 100g 展示。
    final walkSteps = stepsFromKcal(food.kcalPer100g * (preview ?? 1));
    // 份量必填引导（走查「不知道下一步干嘛」）：空/非法份量 → 确认禁用 +
    // 行内提示，替代「按钮看似可点、点了才报错」的截停链。
    final amountValid = preview != null;

    // 统一弹层骨架（封顶 90% + 内容内滚 + 确认按钮常驻底部，真机走查：
    // 小屏/大字体/键盘下按钮不可被顶出）。
    return AppBottomSheet(
      bottomBar: FilledButton(
        onPressed: amountValid
            ? () => widget.onConfirm(_amountController.text.trim())
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: colors.brandPrimary,
          minimumSize: const Size.fromHeight(AppSpacing.s12),
        ),
        child: Text(s.confirm, style: textStyles.textBase),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 头部：名称 + 自定义/社区状态标签。占位行（名称==id，下行合成）
          // 展示回退「未知食物」+ id 小字可查（回查补名后自动恢复真名）。
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  displayFoodName(t, food, isEn: isEn),
                  style: textStyles.textXl,
                ),
              ),
              if (cs.badgeFor(food) case final badgeText?)
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
                    badgeText,
                    style: textStyles.textXs.copyWith(color: colors.bgPrimary),
                  ),
                ),
            ],
          ),
          // 占位行：id 小字可查（「未知食物」回退下仍可按 id 追溯）。
          if (isPlaceholderFood(food))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s1),
              child: Text(
                food.id,
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpacing.s2),
          // 红绿灯评价徽标（颜色 + 图标 + 文字三重编码，PRD M8/§3.3）。
          _SignalBadge(verdict: verdict),
          const SizedBox(height: AppSpacing.s1),
          Text(
            t.record.foodDetail.badgeBasis,
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s3),
          // 显著热量卡（用户最关心，薄荷分层第一位）：千卡/千焦并列。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s4),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: radii.rLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '${food.kcalPer100g.round()}',
                      style: textStyles.textTimer.copyWith(
                        color: colors.brandAccent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    // 窄屏 + 大字体下千卡/千焦并列行横向溢出（360dp 真机走查
                    // 复现）：Expanded 给足宽度上限，FittedBox 等比缩小不溢出。
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          t.record.foodDetail.kcalKj(
                            kj: (food.kcalPer100g * kKjPerKcal).round(),
                          ),
                          maxLines: 1,
                          style: textStyles.textSm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s1),
                // 「大约需走 N 步」（薄荷口径估算，随份量联动）。
                Text(
                  t.record.foodDetail.walkSteps(steps: walkSteps),
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          // 三大营养素供能比例三圆环（供能占比，非重量占比）。
          Text(t.record.foodDetail.macrosTitle, style: textStyles.textBase),
          const SizedBox(height: AppSpacing.s1),
          Text(
            t.record.foodDetail.energyShareNote,
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              _MacroRing(
                label: s.nutritionProtein,
                energy: breakdown.protein,
                color: colors.brandPrimary,
              ),
              _MacroRing(
                label: s.nutritionCarb,
                energy: breakdown.carb,
                color: colors.brandAccent,
              ),
              _MacroRing(
                label: s.nutritionFat,
                energy: breakdown.fat,
                color: colors.brandPrimaryPressed,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          // 份量输入 + 营养预览（与记录页结果卡同格式）。
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: textStyles.textBase,
            decoration: InputDecoration(
              labelText: s.amountLabel,
              // 份量必填行内引导（空/非法时提示，与确认禁用态联动）。
              helperText: amountValid ? null : s.amountInvalid,
              filled: true,
              fillColor: colors.bgSecondary,
              border: OutlineInputBorder(
                borderRadius: radii.rMd,
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (preview != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s1,
              children: <Widget>[
                _PreviewChip(
                  text:
                      '${s.nutritionKcal} '
                      '${(food.kcalPer100g * preview).round()} '
                      '${s.kcalUnit}',
                ),
                _PreviewChip(
                  text:
                      '${s.nutritionProtein} '
                      '${(food.proteinPer100g * preview).toStringAsFixed(1)}'
                      ' ${s.gramUnit}',
                ),
                _PreviewChip(
                  text:
                      '${s.nutritionCarb} '
                      '${(food.carbPer100g * preview).toStringAsFixed(1)}'
                      ' ${s.gramUnit}',
                ),
                _PreviewChip(
                  text:
                      '${s.nutritionFat} '
                      '${(food.fatPer100g * preview).toStringAsFixed(1)}'
                      ' ${s.gramUnit}',
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.s2),
          // 餐次选择（优化点 2：默认按当前时间智能预判，可点选修改）。
          const MealTypeChips(),
          const SizedBox(height: AppSpacing.s2),
          // 其余明细折叠区（次级信息，默认收起）。
          ExpansionTile(
            title: Text(
              t.record.foodDetail.moreTitle,
              style: textStyles.textSm,
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.s2),
            children: <Widget>[
              // NRV% 表（GB 28050 国标 NRV 值；只有库里有的营养素出行）。
              _NrvTable(
                rows: computeNrvRows(
                  kcalPer100g: food.kcalPer100g,
                  proteinPer100g: food.proteinPer100g,
                  carbPer100g: food.carbPer100g,
                  fatPer100g: food.fatPer100g,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              for (final row in <(String, MacroEnergy)>[
                (s.nutritionProtein, breakdown.protein),
                (s.nutritionCarb, breakdown.carb),
                (s.nutritionFat, breakdown.fat),
              ])
                _DetailRow(
                  text:
                      '${row.$1} '
                      '${row.$2.grams.toStringAsFixed(1)} ${s.gramUnit} · '
                      '${t.record.foodDetail.supplyKcal(kcal: row.$2.kcal.round())}',
                ),
              if (_aliasText(food, isEn) case final aliasText?)
                _DetailRow(text: t.record.foodDetail.aliases(names: aliasText)),
            ],
          ),
          // 「数据有误？」纠错入口（薄荷走查 P3：复用众包审核链路——
          // 建议值入审核池，管理台原值 vs 建议值）。主色 + 铅笔图标
          // 给足可点击感知（走查：曾被 textSecondary+textXs 压成注释
          // 文本没人点）。
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: colors.brandPrimary,
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () =>
                  unawaited(startFoodCorrectionFlow(context, ref, food)),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(
                t.record.foodDetail.reportIssue,
                style: textStyles.textSm,
              ),
            ),
          ),
          // 自定义食物动作行（编辑 / 分享给所有用户 / 删除）；
          // 共享/社区食物无此三能力不渲染。**approved 后也不渲染**：
          // 服务端晋升就地翻 isCustom=false，贡献者失去改删权（本地行
          // 标记不回翻，若放行 PATCH/DELETE 必 404「资源不存在」）；
          // 共享库改动走「数据有误？」纠错入口。审核中不提供分享入口
          // （头部徽标已显示「审核中」），删除仍可用（服务端 409
          // 兜底并提示等待审核）。
          if (food.isCustom &&
              food.contributionStatus != 'approved') ...<Widget>[
            const SizedBox(height: AppSpacing.s1),
            Wrap(
              spacing: AppSpacing.s1,
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('foodDetail.edit'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                    ),
                  ),
                  onPressed: () =>
                      unawaited(_onEdit(messenger, cs, textStyles)),
                  child: Text(cs.editAction, style: textStyles.textSm),
                ),
                if (food.contributionStatus != 'pending')
                  TextButton(
                    key: const ValueKey<String>('foodDetail.share'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s2,
                      ),
                    ),
                    onPressed: () => unawaited(_onShare()),
                    child: Text(cs.shareAction, style: textStyles.textSm),
                  ),
                TextButton(
                  key: const ValueKey<String>('foodDetail.delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.signalRed,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                    ),
                  ),
                  onPressed: () =>
                      unawaited(_onDelete(t, cs, messenger, textStyles)),
                  child: Text(cs.deleteAction, style: textStyles.textSm),
                ),
              ],
            ),
          ]
          // 管理员删除（role==admin 对任意食品可见；自定义食物 owner 删除
          // 入口保留不动、与管理员入口互斥避免双删除钮）——服务端软删 +
          // 跨用户级联 tombstone（共享库重复/存疑行治理，对齐 web 管理台）。
          else if (isAdmin) ...<Widget>[
            const SizedBox(height: AppSpacing.s1),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>('foodDetail.adminDelete'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.signalRed,
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    unawaited(_onAdminDelete(t, cs, messenger, textStyles)),
                icon: const Icon(Icons.delete_forever_outlined, size: 16),
                label: Text(cs.adminDeleteAction, style: textStyles.textSm),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 编辑：叠一层 CustomFoodSheet 编辑态（PATCH）；保存成功刷新搜索
  /// 缓存并收起详情——避免旧份量输入框对着新营养数值。
  Future<void> _onEdit(
    ScaffoldMessengerState messenger,
    CustomFoodStrings cs,
    AppTextStyles textStyles,
  ) async {
    final result = await showModalBottomSheet<CustomFoodSaveResult>(
      context: context,
      isScrollControlled: true,
      // 键盘避让已收进 AppBottomSheet 骨架（外层再垫会双倍扣高）。
      builder: (_) => CustomFoodSheet(editTarget: _food),
    );
    if (result == null) return;
    ref.invalidate(recordFoodSearchProvider);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(cs.savedOnline)));
    Navigator.of(context).pop();
  }

  /// 分享给所有用户：复用事后贡献入口（内部含结果 Toast + 搜索刷新；
  /// rejected 重提交服务端幂等返回原 rejected，按钮维持不显示语义可接受）。
  /// 完成后重读本地行，刷新头部徽标与按钮可见性。
  Future<void> _onShare() async {
    await contributeCustomFood(context, ref, _food.id);
    if (!mounted) return;
    final fresh = await ref
        .read(recordRepositoryProvider)
        .db
        .foodDao
        .getById(_food.id);
    if (!mounted) return;
    setState(() => _food = fresh ?? _food);
  }

  /// 删除：确认对话框明示将级联删除的历史条数 → DELETE 远端成功后本地
  /// 两态级联（tombstone/物理删 + 聚合重算，见 CustomFoodRepository.delete）
  /// 并收起详情；409 FOOD_UNDER_REVIEW / 网络错误本地一切不动，可重试。
  Future<void> _onDelete(
    Translations t,
    CustomFoodStrings cs,
    ScaffoldMessengerState messenger,
    AppTextStyles textStyles,
  ) async {
    final recordRepo = ref.read(recordRepositoryProvider);
    final entries = await recordRepo.db.foodEntryDao.entriesForFood(
      recordRepo.userId,
      _food.id,
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(cs.deleteConfirmTitle),
        content: Text(cs.deleteConfirmBody(entries.length)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(cs.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final n = await ref
          .read(customFoodRepositoryProvider)
          .delete(
            _food,
            recordRepository: recordRepo,
            userId: recordRepo.userId,
          );
      ref.invalidate(recordFoodSearchProvider);
      // 机会性上行 tombstone（失败不影响本地删除结果，下轮 sync 兜底）。
      try {
        unawaited(ref.read(recordSyncEngineProvider).syncNow());
      } on Object {
        // 网络层未装配（测试只注入仓储）时降级纯本地。
      }
      messenger.showSnackBar(SnackBar(content: Text(cs.deleteDone(n))));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (e is FoodApprovedSharedApiException) {
        // 仓储已自愈写 approved；同步内存行让动作行门控立即生效。
        setState(
          () => _food = _food.copyWith(
            contributionStatus: const Value('approved'),
          ),
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is BusinessApiException && e.code == 'FOOD_UNDER_REVIEW'
                ? cs.underReviewDeleteBlocked
                : apiErrorDisplayMessage(t, e),
          ),
        ),
      );
    }
  }

  /// 管理员删除（role==admin，任意食品）：确认弹窗明示级联后果 →
  /// DELETE /v1/moderation/foods/:id（服务端软删 + 跨用户级联 tombstone）→
  /// 本机直清（记录两态删 + 聚合重算 + 本地行删除 + 搜索/条目缓存失效 +
  /// syncNow 收敛他端）→ snackbar 带服务端级联条数 + 收起详情。
  /// 409 FOOD_UNDER_REVIEW（该食物有 pending 审核）提示等待审核。
  Future<void> _onAdminDelete(
    Translations t,
    CustomFoodStrings cs,
    ScaffoldMessengerState messenger,
    AppTextStyles textStyles,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(cs.adminDeleteConfirmTitle),
        content: Text(cs.adminDeleteConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(cs.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await deleteFoodAsAdmin(ref, _food);
      // 404 友好口径：目标已不在服务端 → 本地已移除提示（v1.13.18 走查：
      // 管理台手工软删过的行客户端滞留，点删除曾弹原始「资源不存在」）。
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyGone
                ? cs.adminDeleteAlreadyGone
                : cs.adminDeleteDone(result.deletedEntries ?? 0),
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is BusinessApiException && e.code == 'FOOD_UNDER_REVIEW'
                ? cs.underReviewDeleteBlocked
                : apiErrorDisplayMessage(t, e),
          ),
        ),
      );
    }
  }

  /// 别名展示文本（JSON 字符串数组解码失败视为无别名）。
  static String? _aliasText(Food food, bool isEn) {
    final raw = isEn ? food.aliasesEn : food.aliasesZh;
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      final filtered = list.where((e) => e.trim().isNotEmpty).toList();
      if (filtered.isEmpty) return null;
      return filtered.join(isEn ? ', ' : '、');
    } on Object {
      return null;
    }
  }
}

/// 红绿灯评价徽标：颜色 + 图标 + 文字三重编码（红色仅表警告，§3.3）。
class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.verdict});

  final SignalVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final (color, icon, label) = switch (verdict.zone) {
      SignalZone.green => (
        colors.signalGreen,
        Icons.check_circle,
        t.record.foodDetail.badgeGreen,
      ),
      SignalZone.yellow => (
        colors.signalYellow,
        Icons.error,
        t.record.foodDetail.badgeYellow,
      ),
      SignalZone.red => (
        colors.signalRed,
        Icons.cancel,
        t.record.foodDetail.badgeRed,
      ),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: radii.rSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppSpacing.s1),
            Text(label, style: textStyles.textSm.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 单个供能比例圆环（自绘轻量组件：背景圈 + 占比弧 + 中心百分比）。
class _MacroRing extends StatelessWidget {
  const _MacroRing({
    required this.label,
    required this.energy,
    required this.color,
  });

  final String label;
  final MacroEnergy energy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final colors = Theme.of(context).extension<AppColors>()!;
    final percent = (energy.share * 100).round();
    return Expanded(
      child: Semantics(
        label: '$label $percent%',
        child: Column(
          children: <Widget>[
            SizedBox(
              width: 64,
              height: 64,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: energy.share.clamp(0.0, 1.0),
                  color: color,
                  trackColor: colors.border.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: Text('$percent%', style: textStyles.textBase),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              label,
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 8.0;
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(inset, 0, 2 * 3.141592653589793, false, trackPaint);
    if (fraction <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      inset,
      -3.141592653589793 / 2,
      2 * 3.141592653589793 * fraction,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rSm,
      ),
      child: Text(
        text,
        style: textStyles.textXs.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s1),
        child: Text(
          text,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// NRV% 明细表（薄荷走查 P1：营养素 | 每 100 克 | NRV% 三列；
/// NRV 国标值见 domain/nrv_reference.dart，只有库里有的营养素出行）。
class _NrvTable extends StatelessWidget {
  const _NrvTable({required this.rows});

  final List<NrvRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final headerStyle = textStyles.textXs.copyWith(color: colors.textSecondary);
    final cellStyle = textStyles.textSm.copyWith(color: colors.textSecondary);

    String labelOf(NrvNutrient nutrient) => switch (nutrient) {
      NrvNutrient.energy => t.record.nutrition.kcal,
      NrvNutrient.protein => t.record.nutrition.protein,
      NrvNutrient.carb => t.record.nutrition.carb,
      NrvNutrient.fat => t.record.nutrition.fat,
      NrvNutrient.sodium => t.record.nutrition.sodium,
    };

    String amountOf(NrvRow row) => switch (row.nutrient) {
      NrvNutrient.energy =>
        '${row.amount.round()} ${t.record.nutrition.kjUnit}',
      NrvNutrient.sodium =>
        '${row.amount.round()} ${t.record.nutrition.mgUnit}',
      _ => '${row.amount.toStringAsFixed(1)} ${t.record.nutrition.gramUnit}',
    };

    Widget cell(
      String text,
      TextStyle style, {
      int flex = 1,
      bool end = false,
    }) {
      return Expanded(
        flex: flex,
        child: Text(
          text,
          style: style,
          textAlign: end ? TextAlign.end : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s1),
          child: Row(
            children: <Widget>[
              cell(t.record.foodDetail.nutrientColumn, headerStyle, flex: 3),
              cell(
                t.record.foodDetail.per100g,
                headerStyle,
                flex: 2,
                end: true,
              ),
              cell(t.record.foodDetail.nrvColumn, headerStyle, end: true),
            ],
          ),
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s1),
            child: Row(
              children: <Widget>[
                cell(labelOf(row.nutrient), cellStyle, flex: 3),
                cell(amountOf(row), cellStyle, flex: 2, end: true),
                cell('${row.nrvPercent.round()}%', cellStyle, end: true),
              ],
            ),
          ),
      ],
    );
  }
}
