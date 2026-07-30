import 'dart:async';

import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M3 轻量记录区（PRD M3 功能点 4）：饮水快捷档位一键入账 + 当日累计
/// （目标 2000ml〔假设〕标注）+ D-11 撤销；体重数字录入（kg，同日覆写），
/// 写入 M6 [WeightLogStore] 端口，趋势直接生效。
///
/// 与饮食记录同页的轻量区（三入口之下、搜索框之上），保持记录页布局一致性。
class LightRecordSection extends ConsumerWidget {
  const LightRecordSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: _WaterCard()),
          SizedBox(width: AppSpacing.s2),
          Expanded(flex: 2, child: _WeightCard()),
        ],
      ),
    );
  }
}

/// 饮水卡：当日累计（目标标注）+ 快捷档位一键入账 + 撤销吐司（D-11）。
class _WaterCard extends ConsumerWidget {
  const _WaterCard();

  /// 一键入账（乐观更新：累计经流即时刷新）+「已记录·撤销」吐司。
  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    RecordStrings s,
    int amountMl,
  ) async {
    final repo = ref.read(waterLogRepositoryProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final flowId = analytics.startRecordFlow();
    final log = await repo.add(amountMl);
    // 记录后触发一轮同步（饮水 pending 队列上行，§2.1）。
    try {
      unawaited(ref.read(recordSyncEngineProvider).syncNow());
    } on Object {
      // 防御：同步引擎未装配（如测试环境仅注入仓储）时跳过。
    }
    final flow = analytics.endRecordFlow(flowId);
    final confirmedAtMs = DateTime.now().millisecondsSinceEpoch;
    // 饮水记录成功（§3.3 record_flow_success，record_kind=water；
    // 饮水量数值属健康明细不上报 §1.6-3；sync_state=pending：本地落库待上行）。
    analytics.track(
      'record_flow_success',
      properties: <String, Object?>{
        'flow_id': flowId,
        'duration_ms': flow?.durationMs ?? 0,
        'step_count': 1,
        'entry_type': 'manual',
        'item_count': 1,
        'record_kind': 'water',
        'is_edited': false,
        'meal_period': _mealPeriod(),
        'sync_state': 'pending',
      },
      flushNow: true,
    );
    // 连续入账：新吐司立即顶替旧的，保证「撤销」永远对应最近一次（D-11）。
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.toastRecorded),
        duration: repo.undoWindow,
        action: SnackBarAction(
          label: s.toastUndo,
          onPressed: () => unawaited(
            _undo(context, ref, analytics, repo, s, log.localId, confirmedAtMs),
          ),
        ),
      ),
    );
  }

  /// D-11 撤销：撤回该条（乐观更新回滚）。
  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    AnalyticsService analytics,
    WaterLogRepository repo,
    RecordStrings s,
    String localId,
    int confirmedAtMs,
  ) async {
    final ok = await repo.undo(localId);
    if (ok) {
      // 撤销 tombstone 上行（已上行记录）。
      try {
        unawaited(ref.read(recordSyncEngineProvider).syncNow());
      } on Object {
        // 防御：同步引擎未装配（如测试环境仅注入仓储）时跳过。
      }
      analytics.track(
        'record_undo_click',
        properties: <String, Object?>{
          'record_id_hash': anonymizedContentId(localId),
          'after_ms': DateTime.now().millisecondsSinceEpoch - confirmedAtMs,
        },
      );
    }
    if (ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.toastUndone)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final total = ref.watch(todayWaterTotalProvider).value ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        boxShadow: shadows.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.water_drop_outlined,
                size: 20,
                color: colors.brandPrimary,
              ),
              const SizedBox(width: AppSpacing.s1),
              Expanded(
                child: Text(
                  s.waterTitle,
                  style: textStyles.textSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s1),
          // 当日累计 / 目标（〔假设〕2000ml 标注）。
          Text(
            s.waterProgress(total, WaterLogRepository.dailyGoalMl),
            style: textStyles.textSm.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              for (final ml in WaterLogRepository.quickAmountsMl) ...<Widget>[
                if (ml != WaterLogRepository.quickAmountsMl.first)
                  const SizedBox(width: AppSpacing.s1),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: s.waterQuickAddLabel(ml),
                    child: Material(
                      color: colors.bgPrimary,
                      borderRadius: radii.rMd,
                      child: InkWell(
                        borderRadius: radii.rMd,
                        onTap: () => unawaited(_add(context, ref, s, ml)),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.center,
                          child: Text(
                            '+$ml',
                            style: textStyles.textSm.copyWith(
                              color: colors.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 按本地时间推断餐段（§3.3 meal_period；与记录页同口径〔假设〕）。
  static String _mealPeriod() {
    final hour = DateTime.now().toLocal().hour;
    if (hour >= 5 && hour < 10) return 'breakfast';
    if (hour >= 10 && hour < 15) return 'lunch';
    if (hour >= 17 && hour < 21) return 'dinner';
    return 'snack';
  }
}

/// 体重卡：展示当日体重（未记录提示「记一下」），点按弹数字录入对话框。
class _WeightCard extends ConsumerWidget {
  const _WeightCard();

  /// 打开体重录入对话框；保存成功 → record_flow_success（record_kind=
  /// weight，体重数值不上报 §1.6-3），取消/关闭 → record_flow_abandon。
  Future<void> _openDialog(
    BuildContext context,
    WidgetRef ref,
    double? current,
  ) async {
    final analytics = ref.read(analyticsServiceProvider);
    final flowId = analytics.startRecordFlow();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _WeightDialog(current: current),
    );
    if (saved ?? false) {
      final flow = analytics.endRecordFlow(flowId);
      analytics.track(
        'record_flow_success',
        properties: <String, Object?>{
          'flow_id': flowId,
          'duration_ms': flow?.durationMs ?? 0,
          'step_count': 2,
          'entry_type': 'manual',
          'item_count': 1,
          'record_kind': 'weight',
          'is_edited': current != null,
          'meal_period': _WaterCard._mealPeriod(),
          'sync_state': 'synced',
        },
        flushNow: true,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RecordStrings.of(context).toastRecorded)),
        );
      }
    } else {
      final elapsedMs = analytics.recordFlowElapsedMs(flowId) ?? 0;
      analytics.track(
        'record_flow_abandon',
        properties: <String, Object?>{
          'flow_id': flowId,
          'reason': 'exit',
          'elapsed_ms': elapsedMs,
        },
      );
      analytics.endRecordFlow(flowId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final weight = ref.watch(todayWeightProvider).value;

    return Semantics(
      button: true,
      label: s.weightDialogTitle,
      child: Material(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        child: InkWell(
          borderRadius: radii.rLg,
          onTap: () => unawaited(_openDialog(context, ref, weight)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              borderRadius: radii.rLg,
              boxShadow: shadows.shadowSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.monitor_weight_outlined,
                      size: 20,
                      color: colors.brandPrimary,
                    ),
                    const SizedBox(width: AppSpacing.s1),
                    Expanded(
                      child: Text(s.weightTitle, style: textStyles.textSm),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  weight == null
                      ? s.weightNotLogged
                      : s.weightCurrent(weight.toStringAsFixed(1)),
                  style: textStyles.textBase.copyWith(
                    color: weight == null
                        ? colors.textSecondary
                        : colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 体重录入对话框：48px 数字输入（kg，一位小数）+ 校验 + 同日覆写。
class _WeightDialog extends ConsumerStatefulWidget {
  const _WeightDialog({this.current});

  /// 当日已记录体重（预填，同日重复记取最新）。
  final double? current;

  @override
  ConsumerState<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends ConsumerState<_WeightDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current?.toStringAsFixed(1) ?? '',
  );

  /// 校验错误文案（null 为无错误）。
  String? _error;

  /// 合理体重区间（kg，〔假设〕20–300 防误输）。
  static const double _minKg = 20;
  static const double _maxKg = 300;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 保存：校验 → 写 M6 WeightLogStore（同日覆写）→ 刷新记录页与 M6 趋势。
  Future<void> _save(RecordStrings s) async {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value < _minKg || value > _maxKg) {
      setState(() => _error = s.weightInvalid);
      return;
    }
    // 统一一位小数存储（i18n 规格：存储层统一 kg，展示保留 1 位小数）。
    final kg = (value * 10).round() / 10;
    await ref
        .read(weightLogStoreProvider)
        .save(localDateKey(DateTime.now()), kg);
    ref.invalidate(todayWeightProvider);
    // M6 趋势（reportWeightProvider）即刻反映新体重。
    ref.invalidate(reportWeightProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    return AlertDialog(
      backgroundColor: colors.bgPrimary,
      title: Text(s.weightDialogTitle, style: textStyles.textLg),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: textStyles.textBase,
        onSubmitted: (_) => unawaited(_save(s)),
        decoration: InputDecoration(
          labelText: s.weightInputLabel,
          errorText: _error,
          filled: true,
          fillColor: colors.bgSecondary,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s3,
          ),
          constraints: const BoxConstraints(minHeight: 48),
          border: OutlineInputBorder(
            borderRadius: radii.rMd,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radii.rMd,
            borderSide: BorderSide(color: colors.brandPrimary, width: 2),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.cancelAction, style: textStyles.textBase),
        ),
        FilledButton(
          onPressed: () => unawaited(_save(s)),
          style: FilledButton.styleFrom(
            backgroundColor: colors.brandPrimary,
            minimumSize: const Size(88, 48),
          ),
          child: Text(s.confirm, style: textStyles.textBase),
        ),
      ],
    );
  }
}
