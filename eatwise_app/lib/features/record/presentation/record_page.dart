import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M3 记录页（PRD M3：三入口 + 双语搜索 + 份量编辑 + 乐观更新 +
/// D-11 撤销吐司 + D-20「待同步 N 条」入口）。
///
/// 不注册路由，由主代理统一集成到 Tab 结构。
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// 一键确认：乐观更新入账（UI 立即经流展示）+「已记录·撤销」吐司（D-11）。
  Future<void> _confirm(RecordStrings s) async {
    final food = ref.read(recordSelectedFoodProvider);
    if (food == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final amount = double.tryParse(ref.read(recordAmountTextProvider));
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(s.amountInvalid)));
      return;
    }
    final repo = ref.read(recordRepositoryProvider);
    final entry = await repo.addEntry(
      RecordDraft(
        foodId: food.id,
        amountG: amount,
        mealUtc: DateTime.now().toUtc(),
        source: EntrySource.manual,
      ),
    );
    if (!mounted) return;
    ref.read(recordSelectedFoodProvider.notifier).state = null;
    ref.read(recordSearchQueryProvider.notifier).state = '';
    _searchController.clear();
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.toastRecorded),
        duration: repo.undoWindow,
        action: SnackBarAction(
          label: s.toastUndo,
          onPressed: () => unawaited(_undo(repo, entry.localId, s)),
        ),
      ),
    );
  }

  /// D-11 撤销：撤回该条（乐观更新回滚）。
  Future<void> _undo(
    RecordRepository repo,
    String localId,
    RecordStrings s,
  ) async {
    final ok = await repo.undo(localId);
    if (ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.toastUndone)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final pendingCount = ref.watch(recordPendingCountProvider).value ?? 0;
    final today = ref.watch(recordTodayNutritionProvider).value;
    final selected = ref.watch(recordSelectedFoodProvider);
    final results = ref.watch(recordFoodSearchProvider);
    final isEn = LocaleSettings.currentLocale == AppLocale.en;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(s.pageTitle, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 「待同步 N 条」可见入口（§4.1：>0 时展示，点击进同步详情页
            // ——详情页由主代理集成，当前占位提示）。
            if (pendingCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s2,
                  AppSpacing.s4,
                  0,
                ),
                child: Semantics(
                  button: true,
                  label: s.pendingBanner(pendingCount),
                  child: Material(
                    color: colors.bgSecondary,
                    borderRadius: radii.rMd,
                    child: InkWell(
                      borderRadius: radii.rMd,
                      onTap: () => ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(s.comingSoon))),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                          vertical: AppSpacing.s3,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.cloud_upload_outlined,
                              color: colors.brandAccent,
                            ),
                            const SizedBox(width: AppSpacing.s2),
                            Expanded(
                              child: Text(
                                s.pendingBanner(pendingCount),
                                style: textStyles.textSm.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 三入口占位（拍照/语音/常吃，仅 UI，识别能力见 D-16 后续任务）。
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Row(
                children: <Widget>[
                  _EntryCard(
                    icon: Icons.photo_camera_outlined,
                    label: s.entryPhoto,
                    onTap: () => _showComingSoon(s),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  _EntryCard(
                    icon: Icons.mic_none_outlined,
                    label: s.entryVoice,
                    onTap: () => _showComingSoon(s),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  _EntryCard(
                    icon: Icons.favorite_border_outlined,
                    label: s.entryFrequent,
                    onTap: () => _showComingSoon(s),
                  ),
                ],
              ),
            ),
            // 食物搜索（双语匹配，D-15/D-16）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: TextField(
                controller: _searchController,
                style: textStyles.textBase,
                decoration: InputDecoration(
                  hintText: s.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: colors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: radii.rMd,
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) =>
                    ref.read(recordSearchQueryProvider.notifier).state = value,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            // 搜索结果列表。
            Expanded(
              child: results.when(
                data: (foods) {
                  if (foods.isEmpty) {
                    return Center(
                      child: Text(
                        s.searchEmpty,
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
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
                          ref.read(recordSelectedFoodProvider.notifier).state =
                              food;
                          ref.read(recordAmountTextProvider.notifier).state =
                              '100';
                          _amountController.text = '100';
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Text(
                    s.searchEmpty,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            // 今日聚合（本地预估，§2.6 注明待云端校准）。
            if (today != null && today.entryCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s1,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${s.loggedToday(today.entryCount)} · '
                    '${s.todayKcal(today.kcal.round())}',
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            // 可编辑识别结果卡（食物名 + 份量 + 实时营养预览 + 确认）。
            if (selected != null)
              _SelectedFoodCard(
                food: selected,
                isEn: isEn,
                amountController: _amountController,
                onConfirm: () => unawaited(_confirm(s)),
                onClose: () =>
                    ref.read(recordSelectedFoodProvider.notifier).state = null,
                shadows: shadows,
              ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(RecordStrings s) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.comingSoon)));
  }
}

/// 三入口占位卡片（≥44px 触控区，M8 基线）。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: colors.bgSecondary,
          borderRadius: radii.rLg,
          child: InkWell(
            borderRadius: radii.rLg,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              decoration: BoxDecoration(
                borderRadius: radii.rLg,
                boxShadow: shadows.shadowSm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, color: colors.brandPrimary),
                  const SizedBox(height: AppSpacing.s1),
                  Text(label, style: textStyles.textSm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 可编辑结果卡：食物名 + 份量编辑 + 营养实时重算 + 确认按钮。
class _SelectedFoodCard extends ConsumerWidget {
  const _SelectedFoodCard({
    required this.food,
    required this.isEn,
    required this.amountController,
    required this.onConfirm,
    required this.onClose,
    required this.shadows,
  });

  final Food food;
  final bool isEn;
  final TextEditingController amountController;
  final VoidCallback onConfirm;
  final VoidCallback onClose;
  final AppShadows shadows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final nutrition = ref.watch(recordDraftNutritionProvider);

    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isEn ? food.nameEn : food.nameZh,
                  style: textStyles.textLg,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
                tooltip: s.confirm,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: textStyles.textBase,
            decoration: InputDecoration(
              labelText: s.amountLabel,
              filled: true,
              fillColor: colors.bgPrimary,
              border: OutlineInputBorder(
                borderRadius: radii.rMd,
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) =>
                ref.read(recordAmountTextProvider.notifier).state = value,
          ),
          const SizedBox(height: AppSpacing.s2),
          // 份量修改 → 营养换算实时更新（US-3.1）。
          if (nutrition != null)
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s1,
              children: <Widget>[
                _NutritionChip(
                  label: s.nutritionKcal,
                  value: '${nutrition.kcal.round()} ${s.kcalUnit}',
                ),
                _NutritionChip(
                  label: s.nutritionProtein,
                  value:
                      '${nutrition.proteinG.toStringAsFixed(1)} '
                      '${s.gramUnit}',
                ),
                _NutritionChip(
                  label: s.nutritionCarb,
                  value: '${nutrition.carbG.toStringAsFixed(1)} ${s.gramUnit}',
                ),
                _NutritionChip(
                  label: s.nutritionFat,
                  value: '${nutrition.fatG.toStringAsFixed(1)} ${s.gramUnit}',
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.s3),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandPrimary,
              minimumSize: const Size.fromHeight(AppSpacing.s12),
            ),
            child: Text(s.confirm, style: textStyles.textBase),
          ),
        ],
      ),
    );
  }
}

class _NutritionChip extends StatelessWidget {
  const _NutritionChip({required this.label, required this.value});

  final String label;
  final String value;

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
        color: colors.bgPrimary,
        borderRadius: radii.rSm,
      ),
      child: Text(
        '$label $value',
        style: textStyles.textXs.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
