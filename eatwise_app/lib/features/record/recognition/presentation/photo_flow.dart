import 'dart:async';
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    case RecognitionUnavailable():
      // D-16 一级兜底：识别不可用 → 引导手动搜索（搜索框输入保留）。
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.photoUnavailable)));
  }
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
Future<RecognitionOutcome?> _recognizeWithCancel(
  BuildContext context,
  WidgetRef ref,
  Uint8List bytes,
) {
  final s = RecordStrings.of(context);
  final future = ref.read(foodRecognitionServiceProvider).recognize(bytes);
  var cancelled = false;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // 识别完成时自动关闭加载框（若用户未先取消）。
        future.then((outcome) {
          if (!cancelled && dialogContext.mounted) {
            Navigator.of(dialogContext).pop(outcome);
          }
        });
        return AlertDialog(
          content: Row(
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Text(
                  s.photoRecognizing,
                  style: Theme.of(context).extension<AppTextStyles>()!.textBase,
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
    ),
  );
  return future.then<RecognitionOutcome?>(
    (outcome) => cancelled ? null : outcome,
  );
}

/// 份量整数化展示（200.0 → "200"，153.5 → "153.5"）。
String _formatAmount(double amountG) {
  return amountG == amountG.roundToDouble()
      ? amountG.round().toString()
      : amountG.toString();
}
