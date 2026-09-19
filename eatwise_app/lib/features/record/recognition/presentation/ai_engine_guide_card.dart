/// AI 引擎引导卡（真机反馈：首次使用拍照记/语音记/自由记时端侧未下载
/// 且未配云端 API，直接「无法识别」是死胡同）——友好说明「AI 识别需要
/// 一个模型」+ 三出口：下载本地模型（推荐）/ 配置云端 API / 先手动搜索。
///
/// 触发口径：
/// - 进入拍照识别流程时（取图前）：无可用引擎且本会话未点过「先手动搜索」；
/// - 识别中途失败归因（RecognitionUnavailable 无 detail）：再次探测，
///   引擎缺失/未就绪（区别于「识别不出内容」）时展示；
/// - 「识别不出内容」（parse_failed 带 detail）保持原有透出对话框不变；
/// - 语音/自由记有词典解析降级兜底，不被引导卡阻断（见 voice_flow）。
library;

import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 引导卡按钮动作（null = 遮罩关闭/返回键，等同「先手动搜索」但不抑制）。
enum AiEngineGuideAction {
  /// 下载本地模型（推荐）。
  downloadModel,

  /// 配置云端 API。
  configApi,

  /// 先手动搜索（本次会话不再弹引导卡）。
  manualSearch,
}

/// 展示引擎引导卡（返回用户选择的动作；遮罩关闭返回 null）。
Future<AiEngineGuideAction?> showAiEngineGuideCard(
  BuildContext context,
  RecordStrings s,
) {
  return showDialog<AiEngineGuideAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.engineGuideTitle),
      content: Text(s.engineGuideBody),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(AiEngineGuideAction.manualSearch),
          child: Text(s.engineGuideManual),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(AiEngineGuideAction.configApi),
          child: Text(s.engineGuideConfigApi),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(AiEngineGuideAction.downloadModel),
          child: Text(s.engineGuideDownload),
        ),
      ],
    ),
  );
}

/// 无可用引擎时展示引导卡；返回 true = 已展示（调用方直接结束当前流程）。
///
/// 动作处理：
/// - 下载/配置 → 经 [aiEngineGuideNavigatorProvider] 深链设置页（用户
///   进入对应流程后自然继续；不抑制后续引导）；
/// - 先手动搜索 → 置会话抑制位（内存态，不持久化）+ 对焦搜索框。
Future<bool> guideIfNoAiEngine(
  BuildContext context,
  WidgetRef ref,
  RecordStrings s,
) async {
  if (ref.read(aiEngineGuideDismissedProvider)) return false;
  final availability = await ref.read(aiEngineAvailabilityFnProvider)();
  if (availability != AiEngineAvailability.none || !context.mounted) {
    return false;
  }
  await showAiEngineGuideWithActions(context, ref, s);
  return true;
}

/// 无条件展示引导卡并处理出口（探测/抑制由调用方负责——语音逃生舱
/// 「用离线小模型识别」按钮语义：无论云端 API 是否已配，端侧模型才是
/// ASR 唯一路径，未就绪时必须给「下载本地模型（推荐）」出口）。
Future<void> showAiEngineGuideWithActions(
  BuildContext context,
  WidgetRef ref,
  RecordStrings s,
) async {
  final action = await showAiEngineGuideCard(context, s);
  if (!context.mounted) return;
  switch (action) {
    case AiEngineGuideAction.downloadModel:
      ref
          .read(aiEngineGuideNavigatorProvider)
          .call(context, AiEngineGuideTarget.onDeviceModel);
    case AiEngineGuideAction.configApi:
      ref
          .read(aiEngineGuideNavigatorProvider)
          .call(context, AiEngineGuideTarget.cloudApi);
    case AiEngineGuideAction.manualSearch:
      // 本次会话不再弹（内存态即可，不持久化）。
      ref.read(aiEngineGuideDismissedProvider.notifier).state = true;
      // 对焦搜索框（复用识别降级对话框的 prefill 通道；空串仅对焦）。
      ref.read(recordSearchPrefillProvider.notifier).state = '';
    case null: // 遮罩关闭：原地不动（不抑制，下次入口再引导）
  }
}
