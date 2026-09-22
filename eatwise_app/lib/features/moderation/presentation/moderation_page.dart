import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_error_text.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/moderation/application/moderation_controller.dart';
import 'package:eatwise/features/moderation/data/moderation_api.dart';
import 'package:eatwise/features/moderation/presentation/moderation_strings.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 审批中心页（User.role=admin 可见，设置页账号组入口）：
/// pending 候选队列（名称/类型/条码/提交人/营养值/时间）+ 详情展开 +
/// 通过/驳回（确认弹窗，驳回可填原因）+ 操作反馈 snackbar + 游标分页。
class ModerationPage extends ConsumerStatefulWidget {
  const ModerationPage({super.key});

  @override
  ConsumerState<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends ConsumerState<ModerationPage> {
  final ScrollController _scroll = ScrollController();

  /// 详情展开的候选 id 集合。
  final Set<String> _expanded = <String>{};

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
      unawaited(ref.read(moderationControllerProvider.notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ms = ModerationStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final state = ref.watch(moderationControllerProvider);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        title: Text(ms.title, style: textStyles.textXl),
      ),
      body: SafeArea(
        child: switch (state.status) {
          ModerationStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          ModerationStatus.error => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  state.errorMessage ?? ms.loadFailed,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                TextButton(
                  onPressed: () => unawaited(
                    ref.read(moderationControllerProvider.notifier).refresh(),
                  ),
                  child: Text(Translations.of(context).common.action.retry),
                ),
              ],
            ),
          ),
          ModerationStatus.ready => RefreshIndicator(
            onRefresh: () =>
                ref.read(moderationControllerProvider.notifier).refresh(),
            child: state.items.isEmpty
                ? ListView(
                    // 空态可下拉刷新。
                    children: <Widget>[
                      const SizedBox(height: AppSpacing.s12 * 4),
                      Center(
                        child: Text(
                          ms.empty,
                          style: textStyles.textSm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpacing.s4),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.s4),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final candidate = state.items[index];
                      return _CandidateCard(
                        candidate: candidate,
                        expanded: _expanded.contains(candidate.id),
                        acting: state.actingId == candidate.id,
                        onToggle: () => setState(() {
                          if (!_expanded.remove(candidate.id)) {
                            _expanded.add(candidate.id);
                          }
                        }),
                        onApprove: () =>
                            unawaited(_approve(context, candidate)),
                        onReject: () => unawaited(_reject(context, candidate)),
                      );
                    },
                  ),
          ),
        },
      ),
    );
  }

  /// 通过：确认弹窗 → 审核 → 反馈 snackbar。
  Future<void> _approve(
    BuildContext context,
    ModerationCandidate candidate,
  ) async {
    final ms = ModerationStrings.of(context);
    final t = Translations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(ms.approveConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ms.approve),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _doReview(candidate, approve: true);
  }

  /// 驳回：确认弹窗（可填原因）→ 审核 → 反馈 snackbar。
  Future<void> _reject(
    BuildContext context,
    ModerationCandidate candidate,
  ) async {
    final ms = ModerationStrings.of(context);
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ms.rejectConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(ms.rejectConfirmBody),
            const SizedBox(height: AppSpacing.s3),
            TextField(
              controller: reasonController,
              maxLength: 200,
              decoration: InputDecoration(hintText: ms.reasonHint),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: colors.signalRed),
            child: Text(ms.reject),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _doReview(candidate, approve: false, reason: reasonController.text);
  }

  Future<void> _doReview(
    ModerationCandidate candidate, {
    required bool approve,
    String? reason,
  }) async {
    final ms = ModerationStrings.of(context);
    final t = Translations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(moderationControllerProvider.notifier)
          .review(candidate.id, approve: approve, reason: reason?.trim());
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? ms.approved : ms.rejected)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(apiErrorDisplayMessage(t, e))),
      );
      // 失败刷新队列（候选可能已被他人审掉）。
      unawaited(ref.read(moderationControllerProvider.notifier).refresh());
    } on StateError {
      // 审核在途（防连点兜底）：静默。
    }
  }
}

/// 候选卡片：标题行（名称 + 类型徽标）+ 摘要（营养/条码/提交人/时间），
/// 点击展开详情（纠错建议值对照 + 佐证照片链接）+ 通过/驳回按钮。
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.expanded,
    required this.acting,
    required this.onToggle,
    required this.onApprove,
    required this.onReject,
  });

  final ModerationCandidate candidate;
  final bool expanded;

  /// 审核操作在途（按钮 loading 防连点）。
  final bool acting;
  final VoidCallback onToggle;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final ms = ModerationStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final isEn = LocaleSettings.currentLocale == AppLocale.en;
    final name =
        (isEn ? candidate.nameEn : candidate.nameZh) ??
        candidate.nameZh ??
        candidate.foodId;
    final local = candidate.createdAt.toLocal();
    final dateText =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';

    return Card(
      color: colors.bgSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radii.rMd),
      margin: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: InkWell(
        onTap: onToggle,
        borderRadius: radii.rMd,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      name,
                      style: textStyles.textBase.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                      vertical: AppSpacing.s1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.brandAccent,
                      borderRadius: radii.rSm,
                    ),
                    child: Text(
                      ms.kindLabel(candidate.kind),
                      style: textStyles.textXs.copyWith(
                        color: colors.bgPrimary,
                      ),
                    ),
                  ),
                  // 整卡可点展开/收起——chevron 指示（走查：卡面无展开暗示）。
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s1),
              if (candidate.per100g != null)
                Text(
                  _summary(ms, candidate.per100g!),
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              if (candidate.barcode != null)
                Text(
                  ms.barcodeLabel(candidate.barcode!),
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              Text(
                '${ms.submittedAt(dateText)} · '
                '${candidate.submitterUserId.length > 8 ? '${candidate.submitterUserId.substring(0, 8)}…' : candidate.submitterUserId}',
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
              if (expanded) ...<Widget>[
                // 纠错建议值对照（kind=correction）。
                if (candidate.suggestionPer100g != null ||
                    candidate.suggestionNameZh != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    ms.suggestionTitle,
                    style: textStyles.textSm.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (candidate.suggestionNameZh != null)
                    Text(
                      candidate.suggestionNameZh!,
                      style: textStyles.textSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (candidate.suggestionPer100g != null)
                    Text(
                      _summary(ms, candidate.suggestionPer100g!),
                      style: textStyles.textSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
                if (candidate.evidenceImageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s1),
                    child: Text(
                      candidate.evidenceImageUrl!,
                      style: textStyles.textXs.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: AppSpacing.s3),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: acting ? null : onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.signalRed,
                          side: BorderSide(color: colors.signalRed),
                          minimumSize: const Size.fromHeight(AppSpacing.s12),
                        ),
                        child: Text(ms.reject, style: textStyles.textBase),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: FilledButton(
                        onPressed: acting ? null : onApprove,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.brandPrimary,
                          minimumSize: const Size.fromHeight(AppSpacing.s12),
                        ),
                        child: acting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(ms.approve, style: textStyles.textBase),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _summary(ModerationStrings ms, NutritionSnapshot per100g) {
    String num(double v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toString();
    return ms.per100gSummary(
      kcal: num(per100g.kcal),
      protein: num(per100g.proteinG),
      carb: num(per100g.carbG),
      fat: num(per100g.fatG),
    );
  }
}
