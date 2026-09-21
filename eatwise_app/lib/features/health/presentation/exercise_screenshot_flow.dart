/// 运动截图导入流程（华为运动健康「我的数据」汇总页 / 单次运动记录截图）：
/// 引擎引导（ai_engine_guide_card 复用）→ 取图（拍照记选图通道复用）→
/// 端侧视觉识别（严格 JSON）→ 可编辑确认弹层 → 确认后写入运动记录
/// （来源标记 screenshot，D-11 撤销吐司）。
///
/// 模型未配置/未下载时由 [guideIfNoAiEngine] 前置引导（下载本地模型/
/// 配置云端 API），不落「无法识别」死胡同；仅配云端 API（无视觉链路）
/// 时服务为 null，走「识别不可用」snackbar 兜底（与拍照识别 stub 同口径）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/data/exercise_screenshot_service.dart';
import 'package:eatwise/features/health/domain/exercise_screenshot_logic.dart';
import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:eatwise/features/health/presentation/exercise_save_conflict.dart';
import 'package:eatwise/features/health/presentation/exercise_type_names.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/presentation/ai_engine_guide_card.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 截图识别整体超时（取图后的 recognize 调用；端侧首次视觉重建 + 推理
/// 可能数十秒，超时按不可用降级，不让加载对话框无限转圈）。
const Duration kExerciseScreenshotTimeout = Duration(seconds: 60);

/// 运动截图导入入口（记运动弹层「拍照识别 / 相册导入」）。
Future<void> startExerciseScreenshotImport(
  BuildContext context,
  WidgetRef ref,
  PhotoSource source,
) async {
  final s = RecordStrings.of(context);
  final t = Translations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // 引擎可用性前置探测：无任何引擎 → 引导卡（下载模型/配置 API），
  // 不让用户选完图才发现死胡同。
  if (await guideIfNoAiEngine(context, ref, s)) return;
  if (!context.mounted) return;
  final service = ref.read(exerciseScreenshotServiceProvider);
  if (service == null) {
    // 有云端 API 但无视觉链路（或端侧开关关）：识别不可用兜底。
    messenger.showSnackBar(
      SnackBar(content: Text(t.record.exercise.screenshot.unavailable)),
    );
    return;
  }

  Uint8List bytes;
  try {
    final picked = await ref.read(photoPickerGatewayProvider).pick(source);
    // 用户主动取消取图：静默返回，不动弹层内已输入内容。
    if (picked == null || !context.mounted) return;
    bytes = picked;
  } on PhotoPermissionDeniedException {
    if (context.mounted) {
      await showPhotoPermissionDeniedCard(context, s);
    }
    return;
  }
  if (!context.mounted) return;

  final outcome = await _recognizeWithCancel(context, t, service, bytes);
  // null = 用户在识别中点了取消：原地不动，不丢已输入内容。
  if (outcome == null || !context.mounted) return;
  switch (outcome) {
    case ExerciseScreenshotSuccess(data: final data):
      final result = await showExerciseScreenshotConfirmSheet(
        context,
        ref,
        data,
      );
      if (result == null || !context.mounted) return;
      _trackSaved(ref, result);
      // 确认落库后收起记运动弹层，让「已记录·撤销」吐司可见
      // （SnackBar 在 Scaffold 层，modal sheet 会遮住它）。
      Navigator.of(context).pop();
      _showSavedSnackBar(messenger, ref, s, result);
    case ExerciseScreenshotUnavailable(detail: final detail?)
        when detail.isNotEmpty:
      // 模型原文透出（含「无法识别」）：用户能看到模型实际看到了什么。
      messenger.showSnackBar(SnackBar(content: Text(detail)));
    case ExerciseScreenshotUnavailable():
      messenger.showSnackBar(
        SnackBar(content: Text(t.record.exercise.screenshot.unavailable)),
      );
  }
}

/// 识别成功埋点（record_kind=exercise / entry_type=screenshot；运动明细
/// 属健康明细不上报 §1.6-3；sync_state=pending：本地落库待上行）并触发
/// 一轮同步（pending 队列上行，仅登录态生效）。
void _trackSaved(WidgetRef ref, ExerciseSaveResult result) {
  final analytics = ref.read(analyticsServiceProvider);
  final flowId = analytics.startRecordFlow();
  final flow = analytics.endRecordFlow(flowId);
  try {
    unawaited(ref.read(recordSyncEngineProvider).syncNow());
  } on Object {
    // 防御：同步引擎未装配（如测试环境仅注入仓储）时跳过。
  }
  analytics.track(
    'record_flow_success',
    properties: <String, Object?>{
      'flow_id': flowId,
      'duration_ms': flow?.durationMs ?? 0,
      'step_count': 3,
      'entry_type': 'screenshot',
      'item_count': result.replaced.isEmpty ? 1 : result.replaced.length + 1,
      'record_kind': 'exercise',
      'is_edited': true, // 确认弹层字段全部可编辑，按已确认口径记
      'sync_state': result.replaced.isEmpty ? 'pending' : 'replace',
    },
    flushNow: true,
  );
}

/// 入账成功吐司（已记录 + D-11 撤销；与记运动手动保存同口径）。
void _showSavedSnackBar(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  RecordStrings s,
  ExerciseSaveResult result,
) {
  final saved = result.saved;
  final analytics = ref.read(analyticsServiceProvider);
  final repo = ref.read(exerciseLogRepositoryProvider);
  final confirmedAtMs = DateTime.now().millisecondsSinceEpoch;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(s.toastRecorded),
      duration: repo.undoWindow,
      persist: false,
      action: SnackBarAction(
        label: s.toastUndo,
        onPressed: () => unawaited(() async {
          final ok = result.replaced.isEmpty
              ? await repo.delete(saved.localId)
              : await repo
                    .undoReplace(
                      savedLocalId: saved.localId,
                      replaced: result.replaced,
                    )
                    .then((_) => true);
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
                'record_id_hash': anonymizedContentId(saved.localId),
                'after_ms':
                    DateTime.now().millisecondsSinceEpoch - confirmedAtMs,
              },
            );
            messenger.showSnackBar(SnackBar(content: Text(s.toastUndone)));
          }
        }()),
      ),
    ),
  );
}

/// 识别中对话框：加载态 + 「取消」（D-16 异步不阻塞；取消不丢输入）。
/// 两阶段文案与拍照识别一致（加载模型 vs 识别中）；60s 超时兜底。
Future<ExerciseScreenshotOutcome?> _recognizeWithCancel(
  BuildContext context,
  Translations t,
  ExerciseScreenshotService service,
  Uint8List bytes,
) async {
  final phase = ValueNotifier<OnDeviceRecognitionPhase>(
    OnDeviceRecognitionPhase.inferring,
  );
  if (service is OnDeviceExerciseScreenshotService) {
    service.onPhaseChanged = (next) => phase.value = next;
  }
  final future = service
      .recognize(bytes)
      .timeout(
        kExerciseScreenshotTimeout,
        onTimeout: () => const ExerciseScreenshotUnavailable('timeout'),
      );
  var cancelled = false;
  final dialogClosed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      future.then((outcome) {
        if (!cancelled && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
      });
      return AlertDialog(
        content: Row(
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: ValueListenableBuilder<OnDeviceRecognitionPhase>(
                valueListenable: phase,
                builder: (context, current, _) {
                  final loading =
                      current == OnDeviceRecognitionPhase.loadingModel;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        loading
                            ? t.record.exercise.screenshot.loadingModel
                            : t.record.exercise.screenshot.recognizing,
                        style: Theme.of(
                          context,
                        ).extension<AppTextStyles>()!.textBase,
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        t.record.exercise.screenshot.recognizingHint,
                        style: Theme.of(
                          context,
                        ).extension<AppTextStyles>()!.textSm,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(dialogContext).pop();
            },
            child: Text(t.common.action.cancel),
          ),
        ],
      );
    },
  );
  try {
    final outcome = await future.then<ExerciseScreenshotOutcome?>(
      (outcome) => cancelled ? null : outcome,
    );
    // 等加载对话框真正关闭再返回（迟到的 pop 会误关随后打开的确认弹层，
    // 与拍照识别同坑同修法）。
    await dialogClosed;
    return outcome;
  } finally {
    if (service is OnDeviceExerciseScreenshotService) {
      service.onPhaseChanged = null;
    }
    phase.dispose();
  }
}

/// 打开截图数据确认弹层（isScrollControlled，键盘弹起不遮挡输入）。
/// 返回已落库结果 [ExerciseSaveResult]（null = 取消/关闭）。
Future<ExerciseSaveResult?> showExerciseScreenshotConfirmSheet(
  BuildContext context,
  WidgetRef ref,
  ExerciseScreenshotData data,
) {
  return showModalBottomSheet<ExerciseSaveResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: ExerciseScreenshotConfirmSheet(data: data),
    ),
  );
}

/// 截图数据确认弹层（仿拍照明细确认交互）：识别字段全部列出且可编辑，
/// 用户改完点确认才落库（来源标记 screenshot）。
///
/// 落库规则（domain 纯函数，见 exercise_screenshot_logic.dart）：
/// - 汇总：活动热量 >0 直接入账；只有步数 → 体重 × 距离 × 1.036 估算
///   （距离缺失按步数 × 0.75m 步幅估距离）；爬楼仅展示不入账；
/// - 单次运动：消耗优先用截图值，没有再走 MET 表（类型映射不上 other
///   时须手选类型）。
class ExerciseScreenshotConfirmSheet extends ConsumerStatefulWidget {
  const ExerciseScreenshotConfirmSheet({super.key, required this.data});

  final ExerciseScreenshotData data;

  @override
  ConsumerState<ExerciseScreenshotConfirmSheet> createState() =>
      _ExerciseScreenshotConfirmSheetState();
}

class _ExerciseScreenshotConfirmSheetState
    extends ConsumerState<ExerciseScreenshotConfirmSheet> {
  late final bool _isSummary =
      widget.data.kind == ExerciseScreenshotKind.summary;

  // 汇总字段。
  late final TextEditingController _stepsController = TextEditingController(
    text: widget.data.steps?.toString() ?? '',
  );
  late final TextEditingController _distanceController = TextEditingController(
    text: _fmt(widget.data.distanceKm),
  );
  late final TextEditingController _floorsController = TextEditingController(
    text: _fmt(widget.data.floorsClimbedM),
  );
  late final TextEditingController _activeKcalController =
      TextEditingController(text: _fmt(widget.data.activeCaloriesKcal));

  // 单次运动字段。
  late final TextEditingController _durationController = TextEditingController(
    text: widget.data.durationMinutes?.toString() ?? '',
  );
  late ExerciseType? _selectedType = exerciseTypeByKey(
    widget.data.exerciseTypeKey ?? '',
  );

  // 共用：计入消耗 kcal。
  late final TextEditingController _kcalController;
  bool _kcalOverridden = false;
  String? _error;
  bool _saving = false;

  /// 估算用体重（kg）：档案体重，缺省 60 兜底并标注估算。
  late final double? _profileWeightKg = ref
      .read(onboardingStoreProvider)
      .loadProfile()
      ?.weightKg;

  double get _weightKg => _profileWeightKg ?? defaultExerciseWeightKg;

  static String _fmt(double? value) => value == null
      ? ''
      : (value == value.roundToDouble() ? '${value.round()}' : '$value');

  @override
  void initState() {
    super.initState();
    final draft = _isSummary
        ? draftFromSummaryScreenshot(widget.data, weightKg: _weightKg)
        : draftFromWorkoutScreenshot(widget.data, weightKg: _weightKg);
    _kcalController = TextEditingController(
      text: _fmt(draft?.kcal?.roundToDouble()),
    );
  }

  @override
  void dispose() {
    _stepsController.dispose();
    _distanceController.dispose();
    _floorsController.dispose();
    _activeKcalController.dispose();
    _durationController.dispose();
    _kcalController.dispose();
    super.dispose();
  }

  /// 字段编辑 → 未手改 kcal 时按当前字段实时重算计入消耗。
  void _recomputeKcal() {
    if (_kcalOverridden) return;
    double? next;
    if (_isSummary) {
      next = draftFromSummaryScreenshot(
        ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.summary,
          steps: int.tryParse(_stepsController.text.trim()),
          distanceKm: double.tryParse(_distanceController.text.trim()),
          activeCaloriesKcal: double.tryParse(
            _activeKcalController.text.trim(),
          ),
        ),
        weightKg: _weightKg,
      )?.kcal;
    } else {
      next = draftFromWorkoutScreenshot(
        ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.workout,
          exerciseTypeKey: _selectedType?.key,
          durationMinutes: int.tryParse(_durationController.text.trim()),
        ),
        weightKg: _weightKg,
      ).kcal;
    }
    _kcalController.text = _fmt(next?.roundToDouble());
  }

  Future<void> _save(Translations t) async {
    if (_saving) return;
    final kcal = double.tryParse(_kcalController.text.trim());
    if (kcal == null || kcal <= 0) {
      setState(() => _error = t.record.exercise.kcalInvalid);
      return;
    }
    final String typeKey;
    final int durationMin;
    final int? steps;
    if (_isSummary) {
      typeKey = 'summary';
      durationMin = 0;
      // 步数随记录落库（步数持久化：数据页展示 = 系统步数 + 当日合计）。
      final parsedSteps = int.tryParse(_stepsController.text.trim());
      steps = (parsedSteps != null && parsedSteps > 0) ? parsedSteps : null;
    } else {
      final type = _selectedType;
      if (type == null) {
        setState(() => _error = t.record.exercise.screenshot.pickTypeHint);
        return;
      }
      final minutes = int.tryParse(_durationController.text.trim());
      if (minutes == null || minutes <= 0) {
        setState(() => _error = t.record.exercise.durationInvalid);
        return;
      }
      typeKey = type.key;
      durationMin = minutes;
      steps = null;
    }
    _saving = true;
    try {
      // 当日已有记录 → 「再加一条 / 替换今天记录」选择（全天汇总截图
      // 重复导入防重复累计）；取消则留在确认弹层。
      final outcome = await saveExerciseWithConflict(
        context: context,
        t: t,
        repo: ref.read(exerciseLogRepositoryProvider),
        typeKey: typeKey,
        durationMin: durationMin,
        kcal: kcal,
        source: ExerciseLogRepository.sourceScreenshot,
        steps: steps,
      );
      if (outcome == null) return;
      if (mounted) {
        Navigator.of(context).pop(
          ExerciseSaveResult(saved: outcome.saved!, replaced: outcome.replaced),
        );
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.bgSecondary,
      border: OutlineInputBorder(
        borderRadius: radii.rMd,
        borderSide: BorderSide.none,
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _isSummary
                  ? t.record.exercise.screenshot.confirmTitleSummary
                  : t.record.exercise.screenshot.confirmTitleWorkout,
              style: textStyles.textLg,
            ),
            const SizedBox(height: AppSpacing.s3),
            if (_isSummary) ...<Widget>[
              // 汇总页字段：步数/距离/爬楼/活动热量（全部可编辑；爬楼仅展示）。
              TextField(
                key: const ValueKey<String>('screenshot.steps'),
                controller: _stepsController,
                keyboardType: TextInputType.number,
                style: textStyles.textBase,
                decoration: deco(t.record.exercise.screenshot.stepsLabel),
                onChanged: (_) => _recomputeKcal(),
              ),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                key: const ValueKey<String>('screenshot.distance'),
                controller: _distanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: textStyles.textBase,
                decoration: deco(t.record.exercise.screenshot.distanceLabel),
                onChanged: (_) => _recomputeKcal(),
              ),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                key: const ValueKey<String>('screenshot.floors'),
                controller: _floorsController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: textStyles.textBase,
                decoration: deco(t.record.exercise.screenshot.floorsLabel),
              ),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                key: const ValueKey<String>('screenshot.activeKcal'),
                controller: _activeKcalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: textStyles.textBase,
                decoration: deco(t.record.exercise.screenshot.activeKcalLabel),
                onChanged: (_) => _recomputeKcal(),
              ),
            ] else ...<Widget>[
              // 单次运动字段：类型 chips（other 未选中须手选）+ 时长。
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s1,
                children: <Widget>[
                  for (final type in exerciseTypes)
                    ChoiceChip(
                      key: ValueKey<String>('screenshot.type.${type.key}'),
                      label: Text(exerciseTypeName(t, type.key)),
                      selected: _selectedType?.key == type.key,
                      onSelected: (_) {
                        setState(() {
                          _selectedType = type;
                          _error = null;
                        });
                        _recomputeKcal();
                      },
                    ),
                ],
              ),
              if (widget.data.exerciseTypeKey == 'other') ...<Widget>[
                const SizedBox(height: AppSpacing.s1),
                Text(
                  t.record.exercise.screenshot.pickTypeHint,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s2),
              TextField(
                key: const ValueKey<String>('screenshot.duration'),
                controller: _durationController,
                keyboardType: TextInputType.number,
                style: textStyles.textBase,
                decoration: deco(t.record.exercise.durationLabel),
                onChanged: (_) => _recomputeKcal(),
              ),
            ],
            const SizedBox(height: AppSpacing.s2),
            // 计入消耗（可编辑覆盖；未手改时随上方字段联动）。
            TextField(
              key: const ValueKey<String>('screenshot.kcal'),
              controller: _kcalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: textStyles.textBase,
              decoration: deco(
                t.record.exercise.screenshot.burnLabel,
              ).copyWith(errorText: _error),
              onChanged: (_) {
                _kcalOverridden = true;
                setState(() => _error = null);
              },
            ),
            // 估算标注（60kg 兜底 / MET / 步数口径）。
            if (_profileWeightKg == null) ...<Widget>[
              const SizedBox(height: AppSpacing.s1),
              Text(
                t.record.exercise.estimatedWeightHint,
                style: textStyles.textXs.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.s3),
            FilledButton(
              key: const ValueKey<String>('screenshot.save'),
              onPressed: () => unawaited(_save(t)),
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.s12),
              ),
              child: Text(t.record.page.confirm, style: textStyles.textBase),
            ),
          ],
        ),
      ),
    );
  }
}
