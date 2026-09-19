import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:eatwise/features/health/presentation/exercise_screenshot_flow.dart';
import 'package:eatwise/features/health/presentation/exercise_type_names.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 记运动入口（无 GMS 设备手动兜底）：弹层选类型 + 时长 → MET 实时预估
/// kcal（可手改覆盖）→ 保存（乐观更新 + D-11 撤销吐司）。
///
/// 流程埋点与体重录入同口径：保存 → record_flow_success（record_kind=
/// exercise），取消/关闭 → record_flow_abandon；运动明细（类型/时长/热量）
/// 属健康明细不上报（§1.6-3），仅枚举与计数。
Future<void> startExerciseLog(BuildContext context, WidgetRef ref) async {
  final analytics = ref.read(analyticsServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  final flowId = analytics.startRecordFlow();
  final saved = await showModalBottomSheet<ExerciseLog>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ExerciseLogSheet(),
  );
  if (!context.mounted) {
    analytics.endRecordFlow(flowId);
    return;
  }
  if (saved != null) {
    final flow = analytics.endRecordFlow(flowId);
    final confirmedAtMs = DateTime.now().millisecondsSinceEpoch;
    analytics.track(
      'record_flow_success',
      properties: <String, Object?>{
        'flow_id': flowId,
        'duration_ms': flow?.durationMs ?? 0,
        'step_count': 2,
        'entry_type': 'exercise',
        'item_count': 1,
        'record_kind': 'exercise',
        'is_edited': false,
        // 设备级纯本地：不经同步引擎上行。
        'sync_state': 'local',
      },
      flushNow: true,
    );
    // D-11 撤销吐司（与记录页同口径：新吐司顶替旧的，persist 显式 false）。
    final s = RecordStrings.of(context);
    final repo = ref.read(exerciseLogRepositoryProvider);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.toastRecorded),
        duration: repo.undoWindow,
        persist: false,
        action: SnackBarAction(
          label: s.toastUndo,
          onPressed: () => unawaited(
            _undoSaved(
              context,
              analytics,
              repo,
              s,
              saved.localId,
              confirmedAtMs,
            ),
          ),
        ),
      ),
    );
  } else {
    analytics.track(
      'record_flow_abandon',
      properties: <String, Object?>{
        'flow_id': flowId,
        'reason': 'exit',
        'elapsed_ms': analytics.recordFlowElapsedMs(flowId) ?? 0,
      },
    );
    analytics.endRecordFlow(flowId);
  }
}

/// D-11 撤销：物理删除该条（设备级纯本地，无 tombstone），流即时回滚。
Future<void> _undoSaved(
  BuildContext context,
  AnalyticsService analytics,
  ExerciseLogRepository repo,
  RecordStrings s,
  String localId,
  int confirmedAtMs,
) async {
  final ok = await repo.delete(localId);
  if (ok) {
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

/// 记运动弹层：类型 chips 单选 + 时长输入（走路可按步数录入，自动换算
/// 距离与热量）+ 实时预估 kcal（可编辑覆盖）+ 今日运动列表（可删）。
class _ExerciseLogSheet extends ConsumerStatefulWidget {
  const _ExerciseLogSheet();

  @override
  ConsumerState<_ExerciseLogSheet> createState() => _ExerciseLogSheetState();
}

class _ExerciseLogSheetState extends ConsumerState<_ExerciseLogSheet> {
  ExerciseType _type = exerciseTypes.first;
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _stepsController = TextEditingController();
  final TextEditingController _kcalController = TextEditingController();

  /// kcal 被用户手改后为 true（不再随类型/时长联动重算）。
  bool _kcalOverridden = false;

  /// 校验错误文案（null 为无错误）。
  String? _error;

  /// 估算用体重（kg）：档案体重，缺省 60 兜底并标注估算。
  late final double? _profileWeightKg = ref
      .read(onboardingStoreProvider)
      .loadProfile()
      ?.weightKg;

  double get _effectiveWeightKg => _profileWeightKg ?? defaultExerciseWeightKg;

  @override
  void dispose() {
    _durationController.dispose();
    _stepsController.dispose();
    _kcalController.dispose();
    super.dispose();
  }

  /// 类型/时长/步数变化 → 未手改时实时重算预估 kcal。
  /// 走路填了步数 → 按步数口径（体重 × 距离 × 1.036，距离按 0.75m 步幅
  /// 折算，〔待营养背书〕）；否则走 MET × 体重 × 时长。
  void _recomputeEstimate() {
    if (_kcalOverridden) return;
    final steps = int.tryParse(_stepsController.text.trim());
    if (_type.key == 'walk' && steps != null && steps > 0) {
      final estimate = estimateKcalFromStepsWalk(
        steps: steps,
        weightKg: _effectiveWeightKg,
      );
      _kcalController.text = estimate > 0 ? '${estimate.round()}' : '';
      return;
    }
    final minutes = int.tryParse(_durationController.text.trim());
    final estimate = estimateExerciseKcal(
      met: _type.met,
      weightKg: _effectiveWeightKg,
      minutes: minutes ?? 0,
    );
    _kcalController.text = estimate > 0 ? '${estimate.round()}' : '';
  }

  Future<void> _save(Translations t) async {
    final steps = int.tryParse(_stepsController.text.trim());
    final bySteps = _type.key == 'walk' && steps != null && steps > 0;
    // 走路按步数录入时长可留空（无时长口径，落 0）；其余时长必填。
    final minutes = int.tryParse(_durationController.text.trim()) ?? 0;
    if (!bySteps && minutes <= 0) {
      setState(() => _error = t.record.exercise.durationInvalid);
      return;
    }
    final kcal = double.tryParse(_kcalController.text.trim());
    if (kcal == null || kcal <= 0) {
      setState(() => _error = t.record.exercise.kcalInvalid);
      return;
    }
    final saved = await ref
        .read(exerciseLogRepositoryProvider)
        .add(
          typeKey: _type.key,
          durationMin: minutes,
          kcal: kcal,
          steps: bySteps ? steps : null,
        );
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final todayLogs =
        ref.watch(todayExerciseLogsProvider).value ?? const <ExerciseLog>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.s4,
          right: AppSpacing.s4,
          top: AppSpacing.s4,
          bottom: AppSpacing.s4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.record.exercise.title, style: textStyles.textLg),
              const SizedBox(height: AppSpacing.s2),
              // 截图导入入口（华为运动健康「我的数据」/单次运动记录截图 →
              // 端侧视觉识别 → 可编辑确认弹层；复用拍照记选图通道）。
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>('exercise.screenshot.camera'),
                      onPressed: () => unawaited(
                        startExerciseScreenshotImport(
                          context,
                          ref,
                          PhotoSource.camera,
                        ),
                      ),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(
                        t.record.exercise.screenshot.entryCamera,
                        style: textStyles.textSm,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'exercise.screenshot.gallery',
                      ),
                      onPressed: () => unawaited(
                        startExerciseScreenshotImport(
                          context,
                          ref,
                          PhotoSource.gallery,
                        ),
                      ),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(
                        t.record.exercise.screenshot.entryGallery,
                        style: textStyles.textSm,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                t.record.exercise.typeLabel,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.s1),
              // 类型 chips 单选。
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s1,
                children: <Widget>[
                  for (final type in exerciseTypes)
                    ChoiceChip(
                      key: ValueKey<String>('exercise.type.${type.key}'),
                      label: Text(exerciseTypeName(t, type.key)),
                      selected: _type.key == type.key,
                      onSelected: (_) {
                        setState(() {
                          _type = type;
                          _error = null;
                        });
                        _recomputeEstimate();
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              // 时长（分钟）。
              TextField(
                key: const ValueKey<String>('exercise.duration'),
                controller: _durationController,
                keyboardType: TextInputType.number,
                style: textStyles.textBase,
                onChanged: (_) {
                  setState(() => _error = null);
                  _recomputeEstimate();
                },
                decoration: InputDecoration(
                  labelText: t.record.exercise.durationLabel,
                  filled: true,
                  fillColor: colors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: radii.rMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              // 走路专属：步数录入（填了则按步数估算距离与热量，时长可留空）。
              if (_type.key == 'walk') ...<Widget>[
                TextField(
                  key: const ValueKey<String>('exercise.steps'),
                  controller: _stepsController,
                  keyboardType: TextInputType.number,
                  style: textStyles.textBase,
                  onChanged: (_) {
                    setState(() => _error = null);
                    _recomputeEstimate();
                  },
                  decoration: InputDecoration(
                    labelText: t.record.exercise.stepsLabel,
                    helperText: t.record.exercise.stepsEstimateHint,
                    filled: true,
                    fillColor: colors.bgSecondary,
                    border: OutlineInputBorder(
                      borderRadius: radii.rMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
              ],
              // 预估消耗（可编辑覆盖）。
              TextField(
                key: const ValueKey<String>('exercise.kcal'),
                controller: _kcalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: textStyles.textBase,
                onChanged: (_) {
                  _kcalOverridden = true;
                  setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: t.record.exercise.kcalLabel,
                  errorText: _error,
                  filled: true,
                  fillColor: colors.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: radii.rMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              // 档案未填体重 → 按 60kg 估算标注。
              if (_profileWeightKg == null) ...<Widget>[
                const SizedBox(height: AppSpacing.s1),
                Text(
                  t.record.exercise.estimatedWeightHint,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s3),
              FilledButton(
                key: const ValueKey<String>('exercise.save'),
                onPressed: () => unawaited(_save(t)),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(t.record.page.confirm, style: textStyles.textBase),
              ),
              // 今日运动列表（可删）。
              if (todayLogs.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  t.record.exercise.todayList,
                  style: textStyles.textSm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s1),
                for (final log in todayLogs) _TodayExerciseTile(log: log, t: t),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 今日运动列表行：类型 + 时长 + kcal + 删除。
class _TodayExerciseTile extends ConsumerWidget {
  const _TodayExerciseTile({required this.log, required this.t});

  final ExerciseLog log;
  final Translations t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final colors = Theme.of(context).extension<AppColors>()!;
    // 展示项组装：类型名 + 步数（如有）+ 时长（>0 才显示，截图汇总/步数
    // 录入无时长口径，不再出「0 分钟」）+ kcal。
    final parts = <String>[exerciseTypeName(t, log.typeKey)];
    final steps = log.steps;
    if (steps != null && steps > 0) {
      parts.add(t.record.exercise.stepsValue(steps: steps));
    }
    if (log.durationMin > 0) {
      parts.add(t.record.exercise.minutesValue(min: log.durationMin));
    }
    parts.add(t.record.exercise.kcalValue(kcal: log.kcal.round()));
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            parts.join(' · '),
            style: textStyles.textSm.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          key: ValueKey<String>('exercise.delete.${log.localId}'),
          icon: const Icon(Icons.delete_outline),
          tooltip: t.record.exercise.deleteLabel,
          onPressed: () => unawaited(_delete(context, ref)),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await ref
        .read(exerciseLogRepositoryProvider)
        .delete(log.localId);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.record.exercise.deleted)));
    }
  }
}
