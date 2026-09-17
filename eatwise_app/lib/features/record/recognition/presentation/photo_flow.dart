import 'dart:async';
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_sheet.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 拍照识别整体超时（取图后的 recognize 调用）：低端机首次视觉引擎
/// 重建 + 编码推理可能数十秒，超时按不可用降级（现有 snackbar 兜底），
/// 不让加载对话框无限转圈。
const Duration kPhotoRecognitionTimeout = Duration(seconds: 60);

/// 识别不可用对话框的行动出口（按钮点击结果；null = 直接关闭）。
enum PhotoUnavailableAction {
  /// 重新拍摄（重新走来源选择 → 拍照/相册）。
  retake,

  /// 手动搜索（对焦搜索框；库未收录场景顺带预填识别名）。
  manualSearch,

  /// 以估算值添加（库未收录场景：识别名 + 模型估值预填自定义食物表单）。
  addWithEstimate,
}

/// 拍照识别入口流程（PRD M3 / D-16，≤3 步：选来源 → 拍照 → 确认结果卡）。
///
/// 取图用时申请权限（合规 §3）；识别**异步不阻塞**且进入结果卡前可取消，
/// 取消不丢已输入内容；识别不可用走手动搜索一级兜底；
/// 权限拒绝按《规格-全局 UI 四态》§4.3 弹降级说明卡（不阻断核心闭环）。
Future<void> startPhotoRecognition(BuildContext context, WidgetRef ref) async {
  final s = RecordStrings.of(context);
  final source = await showModalBottomSheet<PhotoSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(s.photoTakePhoto),
            onTap: () => Navigator.of(sheetContext).pop(PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(s.photoFromGallery),
            onTap: () => Navigator.of(sheetContext).pop(PhotoSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  Uint8List bytes;
  try {
    final picked = await ref.read(photoPickerGatewayProvider).pick(source);
    // 用户主动取消取图：静默返回，不动任何已输入内容。
    if (picked == null || !context.mounted) return;
    bytes = picked;
  } on PhotoPermissionDeniedException {
    if (context.mounted) {
      await showPhotoPermissionDeniedCard(context, s);
    }
    return;
  }
  if (!context.mounted) return;

  final outcome = await _recognizeWithCancel(context, ref, bytes);
  // null = 用户在识别中点了取消：不填卡、不清空输入。
  if (outcome == null || !context.mounted) return;
  switch (outcome) {
    case RecognitionSuccess(candidates: final candidates)
        when candidates.isNotEmpty:
      final top = candidates.first;
      ref.read(recordSelectedFoodProvider.notifier).state = top.food;
      ref.read(recordAmountTextProvider.notifier).state = _formatAmount(
        top.defaultAmountG,
      );
      ref.read(recordLowConfidenceProvider.notifier).state =
          top.isLowConfidence;
      ref.read(recordEntrySourceProvider.notifier).state = EntrySource.photo;
    case RecognitionSuccess():
      // 识别成功但候选为空：等同不可用，走手动搜索兜底。
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.photoUnavailable)));
    case RecognitionUnavailable(
          reason: 'no_match',
          detail: final name?,
          estimate: final estimate,
        )
        when name.isNotEmpty:
      // 识别出食物名但库未收录：透出识别名 + 「以估算值添加」出口
      // （模型估值预填自定义食物表单，用户确认后才入库）。
      final action = await showPhotoUnmatchedDialog(
        context,
        s,
        name,
        estimate: estimate,
      );
      if (!context.mounted) return;
      switch (action) {
        case PhotoUnavailableAction.addWithEstimate:
          final prefill = estimate;
          if (prefill != null) {
            // 埋点 record_photo_custom（参照 record_barcode_contribute 风格）。
            ref
                .read(analyticsServiceProvider)
                .track(
                  'record_photo_custom',
                  properties: <String, Object?>{
                    'action': 'add_with_estimate',
                    'low_confidence': prefill.lowConfidence,
                  },
                );
            unawaited(
              startCustomFoodFlow(
                context,
                ref,
                initialEstimate: CustomFoodEstimatePrefill(
                  name: prefill.name,
                  nameEn: prefill.nameEn,
                  per100g: NutritionSnapshot(
                    kcal: prefill.per100g.kcal,
                    proteinG: prefill.per100g.proteinG,
                    carbG: prefill.per100g.carbsG,
                    fatG: prefill.per100g.fatG,
                  ),
                  lowConfidence: prefill.lowConfidence,
                ),
              ),
            );
          }
        case PhotoUnavailableAction.manualSearch:
          // 预填识别名：用户改一两个字往往就能搜到。
          ref.read(recordSearchPrefillProvider.notifier).state = name;
        case PhotoUnavailableAction.retake:
        case null: // 知道了/遮罩关闭：原地不动
      }
    case RecognitionUnavailable(detail: final detail?) when detail.isNotEmpty:
      // 模型原文透出（含「无法识别」）：用户能看到模型实际看到了什么。
      final action = await showPhotoNoFoodDialog(context, s, detail);
      if (!context.mounted) return;
      switch (action) {
        case PhotoUnavailableAction.retake:
          // 重新走完整入口流程（来源选择 → 拍照/相册）。
          unawaited(startPhotoRecognition(context, ref));
        case PhotoUnavailableAction.manualSearch:
          // 仅对焦搜索框（无识别名可预填）。
          ref.read(recordSearchPrefillProvider.notifier).state = '';
        case PhotoUnavailableAction.addWithEstimate: // 此对话框不出该动作
        case null: // 知道了/遮罩关闭：原地不动
      }
    case RecognitionUnavailable():
      // D-16 一级兜底：识别不可用 → 引导手动搜索（搜索框输入保留）。
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.photoUnavailable)));
  }
}

/// 「未识别到食物」对话框（detail = 模型原始回复）：引用样式展示 +
/// 引导换角度/手动搜索。出口：重新拍摄/手动搜索（[PhotoUnavailableAction]），
/// 「知道了」或遮罩关闭返回 null（原地不动，不阻断手动搜索）。
Future<PhotoUnavailableAction?> showPhotoNoFoodDialog(
  BuildContext context,
  RecordStrings s,
  String detail,
) {
  return showDialog<PhotoUnavailableAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.photoNoFoodTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.s2),
            ),
            child: Text(
              detail,
              style: Theme.of(dialogContext)
                  .extension<AppTextStyles>()!
                  .textSm
                  .copyWith(fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            s.photoNoFoodHint,
            style: Theme.of(dialogContext).extension<AppTextStyles>()!.textBase,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(s.photoGotIt),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(PhotoUnavailableAction.manualSearch),
          child: Text(s.photoUseManual),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(PhotoUnavailableAction.retake),
          child: Text(s.photoRetake),
        ),
      ],
    ),
  );
}

/// 「识别为 xx 但库未收录」对话框：透出识别名，主行动「以估算值添加」
/// （[estimate] 非空时展示：识别名 + 模型估值预填自定义食物表单），
/// 次行动「手动搜索」（调用方预填识别名并对焦搜索框）。
Future<PhotoUnavailableAction?> showPhotoUnmatchedDialog(
  BuildContext context,
  RecordStrings s,
  String name, {
  RecognizedFoodEstimate? estimate,
}) {
  return showDialog<PhotoUnavailableAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.photoUnmatchedTitle(name)),
      content: Text(s.photoUnmatchedBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(s.photoGotIt),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(PhotoUnavailableAction.manualSearch),
          child: Text(s.photoUseManual),
        ),
        if (estimate != null)
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(PhotoUnavailableAction.addWithEstimate),
            child: Text(s.photoAddWithEstimate),
          ),
      ],
    ),
  );
}

/// 权限拒绝降级说明卡（§4.3：「去开启」/「手动搜索」双按钮）。
Future<void> showPhotoPermissionDeniedCard(
  BuildContext context,
  RecordStrings s,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.photoDeniedTitle),
      content: Text(s.photoDeniedBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(s.photoUseManual),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(AppSettings.openAppSettings());
          },
          child: Text(s.photoOpenSettings),
        ),
      ],
    ),
  );
}

/// 识别中对话框：加载态 + 「取消」（D-16 异步不阻塞；取消不丢输入）。
///
/// 两阶段文案（真机反馈：首拍视觉重建数秒、单一句「识别中…」像卡住）：
/// 端侧实现经 [OnDeviceFoodRecognitionService.onPhaseChanged] 上报阶段，
/// 加载/视觉重建 → 「正在加载视觉模型…」，推理 → 「识别中…」；
/// 非端侧实现（stub/超时降级）恒为识别中文案。
Future<RecognitionOutcome?> _recognizeWithCancel(
  BuildContext context,
  WidgetRef ref,
  Uint8List bytes,
) async {
  final s = RecordStrings.of(context);
  final service = ref.read(foodRecognitionServiceProvider);
  final phase = ValueNotifier<OnDeviceRecognitionPhase>(
    OnDeviceRecognitionPhase.inferring,
  );
  if (service is OnDeviceFoodRecognitionService) {
    service.onPhaseChanged = (next) => phase.value = next;
  }
  // 超时保护：低端机首次视觉引擎重建 + 推理可能很久，超时按
  // RecognitionUnavailable('timeout') 走现有 snackbar 兜底（detail 空）。
  final future = service
      .recognize(bytes)
      .timeout(
        kPhotoRecognitionTimeout,
        onTimeout: () => const RecognitionUnavailable('timeout'),
      );
  var cancelled = false;
  final dialogClosed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // 识别完成时自动关闭加载框（若用户未先取消）。
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
                        loading ? s.photoLoadingModel : s.photoRecognizing,
                        style: Theme.of(
                          context,
                        ).extension<AppTextStyles>()!.textBase,
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      // 预期管理：首次识别要加载视觉引擎，可能等几秒。
                      Text(
                        s.photoRecognizingHint,
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
            // 取消复用 common.action.cancel（D-15 统一动作词）。
            child: Text(s.cancelAction),
          ),
        ],
      );
    },
  );
  try {
    final outcome = await future.then<RecognitionOutcome?>(
      (outcome) => cancelled ? null : outcome,
    );
    // 关键顺序：等加载对话框真正关闭再返回。它的 pop 是延迟落地的
    // （builder 注册 then 回调要等下一帧），快速识别（stub/端侧缓存命中）
    // 时若不等待，这个迟到的 pop 会误关调用方随后打开的对话框。
    await dialogClosed;
    return outcome;
  } finally {
    if (service is OnDeviceFoodRecognitionService) {
      service.onPhaseChanged = null;
    }
    phase.dispose();
  }
}

/// 份量整数化展示（200.0 → "200"，153.5 → "153.5"）。
String _formatAmount(double amountG) {
  return amountG == amountG.roundToDouble()
      ? amountG.round().toString()
      : amountG.toString();
}
