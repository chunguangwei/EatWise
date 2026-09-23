import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/contributions_controller.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_sheet.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 贡献食物名（按 foodId 解析本地库：审核通过后 id 不变，本地行即原名）。
/// 解析不到（离线未同步等）返回 null，列表行回退展示 foodId。
final FutureProviderFamily<String?, String> contributionFoodNameProvider =
    FutureProvider.family<String?, String>((ref, foodId) async {
      final row = await ref
          .watch(recordRepositoryProvider)
          .db
          .foodDao
          .getById(foodId);
      if (row == null) return null;
      return LocaleSettings.currentLocale == AppLocale.en
          ? row.nameEn
          : row.nameZh;
    });

/// 我的贡献页（众包状态列表）：状态过滤 + 状态标签（颜色+图标+文字三重
/// 编码）+ 拒绝原因 + 提交时间；四态：加载 / 空态 / 错误重试 / 列表。
class MyContributionsPage extends ConsumerStatefulWidget {
  const MyContributionsPage({super.key});

  @override
  ConsumerState<MyContributionsPage> createState() =>
      _MyContributionsPageState();
}

class _MyContributionsPageState extends ConsumerState<MyContributionsPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.position.extentAfter < 200) {
      unawaited(ref.read(contributionsControllerProvider.notifier).loadMore());
    }
  }

  /// 顶栏「+」：弹新建自定义食物流程，返回后刷新列表（成功/离线 pending
  /// 都刷一次；网络失败错误态自带重试入口）。
  Future<void> _openNewContribution() async {
    await startCustomFoodFlow(context, ref);
    if (!mounted) return;
    await ref.read(contributionsControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final c = t.record.customFood.contributions;
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final state = ref.watch(contributionsControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(c.title, style: textStyles.textXl),
        // 顶栏常驻新建入口（真机走查：空态 CTA 只在 0 条时可见，有贡献后
        // 再想新增只能退回记录页绕路）。
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            color: colors.brandPrimary,
            tooltip: c.addAction,
            onPressed: () => unawaited(_openNewContribution()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _FilterBar(
              selected: state.filter,
              onChanged: (value) => unawaited(
                ref
                    .read(contributionsControllerProvider.notifier)
                    .setFilter(value),
              ),
            ),
            Expanded(child: _buildBody(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ContributionsState state) {
    final t = Translations.of(context);
    final c = t.record.customFood.contributions;
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    switch (state.status) {
      case ContributionsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ContributionsStatus.error:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: <Widget>[
            const SizedBox(height: AppSpacing.s16),
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: colors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              c.loadFailed,
              style: textStyles.textLg,
              textAlign: TextAlign.center,
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s2),
              Text(
                state.errorMessage!,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.s6),
            FilledButton(
              onPressed: () => unawaited(
                ref.read(contributionsControllerProvider.notifier).refresh(),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(
                t.common.action.retry,
                style: textStyles.textBase.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      case ContributionsStatus.ready:
        if (state.items.isEmpty) {
          return RefreshIndicator(
            color: colors.brandPrimary,
            onRefresh: () =>
                ref.read(contributionsControllerProvider.notifier).refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.s4),
              children: <Widget>[
                const SizedBox(height: AppSpacing.s16),
                Icon(
                  Icons.inventory_2_outlined,
                  size: 64,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  c.empty,
                  style: textStyles.textLg,
                  textAlign: TextAlign.center,
                ),
                // 空态三件套（薄荷走查 P2）：副文案 + 新建自定义食物 CTA。
                const SizedBox(height: AppSpacing.s2),
                Text(
                  c.emptySubtitle,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s6),
                FilledButton(
                  onPressed: () => unawaited(startCustomFoodFlow(context, ref)),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brandPrimary,
                    minimumSize: const Size.fromHeight(AppSpacing.s12),
                  ),
                  child: Text(
                    c.emptyCta,
                    style: textStyles.textBase.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: colors.brandPrimary,
          onRefresh: () =>
              ref.read(contributionsControllerProvider.notifier).refresh(),
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.s4),
            itemCount: state.items.length + (state.loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= state.items.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.s4),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _ContributionCard(
                key: ValueKey(state.items[index].id),
                item: state.items[index],
              );
            },
          ),
        );
    }
  }
}

/// 状态过滤条（全部 / 审核中 / 已通过 / 已拒绝）。
///
/// 视觉分隔（v1.13.22 走查：列表首项滚到顶部时与 chips 无分隔，读起来像
/// 被 chips 压住/裁掉）：底色 + 底部发线，列表始终从分隔线之下开始。
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final FoodContributionStatus? selected;
  final ValueChanged<FoodContributionStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Translations.of(context).record.customFood.contributions;
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s2,
        ),
        child: Row(
          children: <Widget>[
            _chip(context, c.filterAll, null),
            const SizedBox(width: AppSpacing.s2),
            _chip(context, c.statusPending, FoodContributionStatus.pending),
            const SizedBox(width: AppSpacing.s2),
            _chip(context, c.statusApproved, FoodContributionStatus.approved),
            const SizedBox(width: AppSpacing.s2),
            _chip(context, c.statusRejected, FoodContributionStatus.rejected),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    FoodContributionStatus? value,
  ) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final isSelected = selected == value;
    return ChoiceChip(
      label: Text(label),
      labelStyle: textStyles.textSm.copyWith(
        color: isSelected ? colors.bgPrimary : colors.textPrimary,
      ),
      selected: isSelected,
      selectedColor: colors.brandPrimary,
      backgroundColor: colors.bgSecondary,
      showCheckmark: false,
      onSelected: (_) => onChanged(value),
    );
  }
}

/// 贡献条目卡：食物名 + 状态标签（颜色/图标/文字三重编码）+ 条码徽标
/// （kind=barcode 时展示类型徽标 + 条码号）+ 拒绝原因 + 提交时间。
class _ContributionCard extends ConsumerWidget {
  const _ContributionCard({super.key, required this.item});

  final FoodContribution item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final c = t.record.customFood.contributions;
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final name =
        // 服务端视图带的关联食物名优先（纠错类目标是共享库食物，本地库
        // 未必有该行）；null → 本地库按 foodId 解析；再不行回退 foodId。
        (LocaleSettings.currentLocale == AppLocale.en
            ? (item.nameEn ?? item.nameZh)
            : (item.nameZh ?? item.nameEn)) ??
        ref.watch(contributionFoodNameProvider(item.foodId)).value ??
        item.foodId;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s3),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: textStyles.textBase.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              _StatusBadge(status: item.status),
            ],
          ),
          if (item.kind == FoodContributionKind.barcode &&
              (item.barcode?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Row(
              children: <Widget>[
                _BarcodeKindBadge(label: c.kindBarcode),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    c.barcodeLabel(code: item.barcode!),
                    style: textStyles.textXs.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // 纠错条目（P3「数据有误？」入口）：类型徽标。
          if (item.kind == FoodContributionKind.correction) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            _BarcodeKindBadge(
              label: c.kindCorrection,
              icon: Icons.fact_check_outlined,
            ),
          ],
          if (item.status == FoodContributionStatus.rejected &&
              (item.reason?.isNotEmpty ?? false)) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Text(
              c.reasonLabel(reason: item.reason!),
              style: textStyles.textSm.copyWith(color: colors.signalRed),
            ),
          ],
          const SizedBox(height: AppSpacing.s2),
          Text(
            c.submittedAt(date: _formatLocal(item.createdAt)),
            style: textStyles.textXs.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 提交时间（本地时区 yyyy-MM-dd HH:mm，零填充免双语语序歧义〔假设〕）。
  static String _formatLocal(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 条码补录类型徽标（扫码未命中贡献：条码图标 + 文字，与状态标签同构）；
/// 纠错条目复用同构样式（[icon] 传入 fact_check）。
class _BarcodeKindBadge extends StatelessWidget {
  const _BarcodeKindBadge({required this.label, this.icon = Icons.qr_code_2});

  final String label;

  /// 徽标图标（默认条码；纠错条目传 Icons.fact_check_outlined）。
  final IconData icon;

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
        color: colors.brandPrimary.withValues(alpha: 0.12),
        borderRadius: radii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.brandPrimary),
          const SizedBox(width: AppSpacing.s1),
          Text(
            label,
            style: textStyles.textXs.copyWith(color: colors.brandPrimary),
          ),
        ],
      ),
    );
  }
}

/// 状态标签（无障碍三重编码：颜色 + 图标 + 文字，不单靠色相区分）。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final FoodContributionStatus status;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final c = t.record.customFood.contributions;
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    final (label, icon, color) = switch (status) {
      FoodContributionStatus.approved => (
        c.statusApproved,
        Icons.check_circle_outline,
        colors.signalGreen,
      ),
      FoodContributionStatus.pending => (
        c.statusPending,
        Icons.hourglass_top_outlined,
        colors.signalYellow,
      ),
      FoodContributionStatus.rejected => (
        c.statusRejected,
        Icons.cancel_outlined,
        colors.signalRed,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: radii.rSm,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.s1),
          Text(label, style: textStyles.textXs.copyWith(color: color)),
        ],
      ),
    );
  }
}
