import 'dart:async';
import 'package:app_settings/app_settings.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:eatwise/features/record/recognition/presentation/ai_engine_guide_card.dart';
import 'package:eatwise/features/record/recognition/presentation/ondevice_recording_sheet.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_meal_sheet.dart';
import 'package:eatwise/features/record/recognition/voice/speech_gateway.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 语音录入入口流程（PRD M3 / D-16：系统 ASR + 端侧文本明细推理优先，
/// 回落自研轻量词典解析，不引入独立 NLP 服务）。
///
/// 「说一句记一笔」：ASR/键盘输入文本 → 端侧文本推理（明细协议文本版，
/// 与拍照识别七段同构）→ 明细确认卡一键入账（EntrySource.voice）；
/// 端侧未启用/推理失败/解析空 → 回落既有词典解析路径（不破坏）。
///
/// 系统 ASR 不可用（无 GMS 等 ROM）时的三路回落：
/// 端侧模型就绪 → 端侧录音转写面板（record 插件录音 + Gemma 音频编码器）；
/// 未就绪 → 引擎引导卡（ai_engine_guide_card 复用；被会话抑制/有引擎时
/// → 现有权限降级卡）。首次点击用时申请权限（合规 §3.1：iOS 语音识别+
/// 麦克风双权限，Android RECORD_AUDIO）；系统 ASR 可用的设备维持原路径。
Future<void> startVoiceInput(BuildContext context, WidgetRef ref) async {
  final s = RecordStrings.of(context);
  final gateway = ref.read(speechGatewayProvider);
  final available = await gateway.initialize();
  if (!context.mounted) return;

  final VoiceTranscript? transcript;
  if (available) {
    final localeId = LocaleSettings.currentLocale.languageTag.replaceAll(
      '-',
      '_',
    );
    transcript = await showModalBottomSheet<VoiceTranscript>(
      context: context,
      isDismissible: false,
      builder: (_) =>
          _VoiceListeningSheet(gateway: gateway, localeId: localeId),
    );
  } else if (onDeviceRecognitionActiveFor(
    ref.watch(onDeviceAiEnabledProvider),
    ref.watch(onDeviceModelSnapshotProvider),
  )) {
    // 端侧模型就绪 → 端侧录音转写（权限首次用时申请，与系统 ASR 路径同口径）。
    final recorder = ref.read(audioRecorderGatewayProvider);
    final permitted = await recorder.ensurePermission();
    if (!context.mounted) return;
    if (!permitted) {
      await _showVoiceDeniedCard(context, s);
      return;
    }
    transcript = await showModalBottomSheet<VoiceTranscript>(
      context: context,
      isDismissible: false,
      builder: (_) => const OnDeviceRecordingSheet(),
    );
    // 面板内取消/转写失败放弃：静默返回（面板已给错误态，不打扰）。
  } else {
    // 模型未就绪 → 引擎引导卡（被会话抑制/有云端 API 时 → 现有降级卡）。
    if (await guideIfNoAiEngine(context, ref, s)) return;
    if (context.mounted) await _showVoiceDeniedCard(context, s);
    return;
  }
  // null = 用户取消听写/录音：静默返回，不动已输入内容。
  if (transcript == null || !context.mounted) return;
  await _handleTranscript(context, ref, s, transcript);
}

/// 转写文本 → 后续管线（系统 ASR 与端侧录音转写共用）：
/// 端侧自由记推理优先（明细确认卡一键入账），失败/解析空回落词典解析。
Future<void> _handleTranscript(
  BuildContext context,
  WidgetRef ref,
  RecordStrings s,
  VoiceTranscript transcript,
) async {
  // 「说一句记一笔」：端侧文本明细推理优先（开关开且模型就绪时），
  // 成功 → 明细确认卡一键入账；失败/解析空/取消 → 回落词典解析。
  final items = await _tryFreeTextInference(
    context,
    ref,
    transcript.text,
    inputKind: transcript.typed ? 'keyboard' : 'voice',
  );
  if (!context.mounted) return;
  if (items != null && items.isNotEmpty) {
    final result = await showPhotoMealConfirmSheet(
      context,
      ref,
      items,
      entrySource: EntrySource.voice,
      showRetake: false, // 文本场景无「重新拍摄」
    );
    if (!context.mounted || result == null || result.loggedCount == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.photoLoggedItems(result.loggedCount))),
    );
    return;
  }

  // 全量食物库构建解析词典（约 7.5k 条内存可行；limit 截断会让尾部
  // 词条永远匹配不到）。
  final foods = await ref.read(recordRepositoryProvider).allFoodsForVoiceDict();
  if (!context.mounted) return;
  final result = ref
      .read(voiceTextParserProvider)
      .parse(transcript.text, foods);
  if (result.isEmpty) {
    // 词典没匹配上：提示换个说法或手动搜索（输入内容保留）。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.voiceNoMatch)));
    return;
  }
  final top = result.items.first;
  ref.read(recordSelectedFoodProvider.notifier).state = top.food;
  ref
      .read(recordAmountTextProvider.notifier)
      .state = top.amountG == top.amountG.roundToDouble()
      ? top.amountG.round().toString()
      : top.amountG.toString();
  // 语音文本已由用户亲口确认，不标「请确认」（该标记留给拍照低置信度）。
  ref.read(recordLowConfidenceProvider.notifier).state = false;
  ref.read(recordEntrySourceProvider.notifier).state = EntrySource.voice;
}

/// 听写面板产出：转写文本 + 输入方式（语音/键盘，埋点 input 维度）。
final class VoiceTranscript {
  const VoiceTranscript(this.text, {required this.typed});

  final String text;

  /// true = 键盘输入（语音转写为 false）。
  final bool typed;
}

/// 自由记推理整体超时（端侧文本推理 + 可能的引擎冷加载）。
const Duration kFreeTextInferenceTimeout = Duration(seconds: 60);

/// 端侧自由记推理（「理解中…」加载框 + 取消；超时/取消/失败返回 null
/// → 调用方回落词典解析）。埋点 record_free_text（input/result 维度）。
Future<List<RecognizedMealItem>?> _tryFreeTextInference(
  BuildContext context,
  WidgetRef ref,
  String text, {
  required String inputKind,
}) async {
  final service = ref.read(freeTextMealServiceProvider);
  if (service == null) return null; // 端侧未启用：直接回落（不埋点）
  final s = RecordStrings.of(context);
  var cancelled = false;
  final future = service
      .parse(text)
      .timeout(kFreeTextInferenceTimeout, onTimeout: () => null);
  final dialogClosed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // 推理完成时自动关闭加载框（若用户未先取消）。
      future.then((items) {
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
              child: Text(
                s.voiceUnderstanding,
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
            child: Text(s.cancelAction),
          ),
        ],
      );
    },
  );
  final items = await future;
  // 与拍照识别同款顺序：等加载框真正关闭再返回（快速完成时防竞态）。
  await dialogClosed;
  ref
      .read(analyticsServiceProvider)
      .track(
        'record_free_text',
        properties: <String, Object?>{
          'input': inputKind,
          'result': items != null && items.isNotEmpty ? 'success' : 'fallback',
        },
      );
  return cancelled ? null : items;
}

/// 语音不可用/权限拒绝降级说明卡（§4.3：「去开启」/「改用文字」）。
Future<void> _showVoiceDeniedCard(BuildContext context, RecordStrings s) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.voiceDeniedTitle),
      content: Text('${s.voiceDeniedBody}\n${s.voiceUnavailable}'),
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

/// 听写面板：实时回显识别文本 + 「完成」（解析预填）/「取消」（丢弃本次）。
/// 触控目标 ≥48px（M8 基线）。
class _VoiceListeningSheet extends ConsumerStatefulWidget {
  const _VoiceListeningSheet({required this.gateway, required this.localeId});

  final SpeechGateway gateway;
  final String localeId;

  @override
  ConsumerState<_VoiceListeningSheet> createState() =>
      _VoiceListeningSheetState();
}

class _VoiceListeningSheetState extends ConsumerState<_VoiceListeningSheet> {
  String _text = '';

  /// 系统 ASR 错误（errorMsg 原值，如 error_no_match / error_network）。
  /// 无 GMS ROM 上 listen 可能不出结果只报错，必须显式呈现。
  String? _error;

  /// 听写开始后长时间无任何回传（静默失败兜底提示）。
  bool _noResultHint = false;
  Timer? _noResultTimer;

  /// 无任何识别结果多久后给出提示（错误回调优先，此为静默失败兜底）。
  static const Duration kNoResultHintDelay = Duration(seconds: 6);

  /// 键盘输入模式（纯文本自由记入口：听写面板内一键切换，最小 UI 改动）。
  bool _typing = false;
  final TextEditingController _typeController = TextEditingController();

  @override
  void dispose() {
    _noResultTimer?.cancel();
    _typeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.gateway.start(
        localeId: widget.localeId,
        onText: (text) {
          if (mounted) setState(() => _text = text);
        },
        onError: (error) {
          if (mounted) setState(() => _error = error);
        },
      ),
    );
    _noResultTimer = Timer(kNoResultHintDelay, () {
      if (mounted && _text.isEmpty && _error == null && !_typing) {
        setState(() => _noResultHint = true);
      }
    });
  }

  /// 听写状态下的提示文案：ASR 错误优先，其次静默超时兜底。
  /// error_no_match / error_speech_timeout 属「没听清」良性错误，与其余
  /// 「识别不可用」分桶提示；两桶都引导键盘切换（永远可用）。
  String? _statusText(RecordStrings s) {
    final error = _error;
    if (error != null) {
      const benign = <String>{'error_no_match', 'error_speech_timeout'};
      return benign.contains(error) ? s.voiceNoSpeechHint : s.voiceErrorGeneric;
    }
    return _noResultHint ? s.voiceNoSpeechHint : null;
  }

  /// 逃生舱条件：致命 ASR 错误（非 error_no_match/error_speech_timeout
  /// 良性桶）或 6s 静默兜底已触发；良性错误不给按钮（没听清重说即可）。
  bool get _escapeTriggered {
    final error = _error;
    const benign = <String>{'error_no_match', 'error_speech_timeout'};
    return (error != null && !benign.contains(error)) || _noResultHint;
  }

  /// 端侧 ASR 就绪（提供方非空 = 端侧开关开且模型就绪/快照乐观窗口）。
  bool get _onDeviceAsrReady => ref.watch(onDeviceAsrServiceProvider) != null;

  /// 切到端侧录音转写：先取消系统听写（独立于端侧面板状态，cancel 只
  /// 作用于系统 ASR 网关，不吞端侧面板），再把端侧转写结果透传为面板
  /// 返回值——下游管线（_handleTranscript）对两条路径完全同构。
  /// 端侧面板取消 → 整个语音流程静默结束（用户可重新点语音记）。
  Future<void> _switchToOnDevice() async {
    // 端侧录音走 record 插件的麦克风权限（与系统 ASR 初始化时的申请
    // 同口径确认一次；拒绝则静默关闭，键盘输入永远可用）。
    final recorder = ref.read(audioRecorderGatewayProvider);
    await widget.gateway.cancel();
    if (!mounted) return;
    final permitted = await recorder.ensurePermission();
    if (!mounted) return;
    if (!permitted) {
      Navigator.of(context).pop();
      return;
    }
    final transcript = await showModalBottomSheet<VoiceTranscript>(
      context: context,
      isDismissible: false,
      builder: (_) => const OnDeviceRecordingSheet(),
    );
    if (!mounted) return;
    // null（端侧面板取消）也关闭本面板：系统听写已取消，面板留在原地
    // 只剩错误态没有意义。
    Navigator.of(context).pop(transcript);
  }

  /// 提示配色：良性（没听清/超时）弱化，识别不可用用警示红。
  Color _statusColor(AppColors colors) {
    final error = _error;
    final benign =
        error == null ||
        error == 'error_no_match' ||
        error == 'error_speech_timeout';
    return benign ? colors.textSecondary : colors.signalRed;
  }

  @override
  Widget build(BuildContext context) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _typing ? Icons.keyboard_outlined : Icons.mic,
                  color: colors.brandPrimary,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: _typing
                      ? TextField(
                          controller: _typeController,
                          autofocus: true,
                          style: textStyles.textBase,
                          decoration: InputDecoration(
                            hintText: s.voiceTypeHint,
                            isDense: true,
                          ),
                          onChanged: (value) => _text = value,
                        )
                      : Text(
                          _text.isEmpty ? s.voiceListening : _text,
                          style: textStyles.textBase,
                        ),
                ),
                // 语音/键盘切换（≥48px 触控目标）。
                IconButton(
                  icon: Icon(_typing ? Icons.mic : Icons.keyboard_outlined),
                  tooltip: s.voiceTypeInput,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => setState(() {
                    _typing = !_typing;
                    if (_typing) {
                      _typeController.text = _text;
                      _typeController.selection = TextSelection.collapsed(
                        offset: _typeController.text.length,
                      );
                    } else {
                      _text = _typeController.text;
                    }
                  }),
                ),
              ],
            ),
            // 听写异常/静默超时提示（键盘切换入口就在右上角，永远可降级）。
            if (!_typing && _statusText(s) != null) ...<Widget>[
              const SizedBox(height: AppSpacing.s2),
              Text(
                _statusText(s)!,
                style: textStyles.textSm.copyWith(color: _statusColor(colors)),
              ),
              // 逃生舱：致命错误/静默超时 + 端侧 ASR 就绪 → 一键切离线模型
              //（良性「没听清」不给按钮，重说即可；端侧未就绪保持现状）。
              if (_escapeTriggered && _onDeviceAsrReady) ...<Widget>[
                const SizedBox(height: AppSpacing.s2),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_switchToOnDevice()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.brandPrimary,
                      side: BorderSide(color: colors.brandPrimary),
                    ),
                    icon: const Icon(Icons.offline_bolt_outlined),
                    label: Text(
                      s.voiceUseOnDeviceAsr,
                      style: textStyles.textBase,
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () async {
                        await widget.gateway.cancel();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Text(s.cancelAction),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () async {
                        await widget.gateway.stop();
                        if (context.mounted) {
                          Navigator.of(
                            context,
                          ).pop(VoiceTranscript(_text, typed: _typing));
                        }
                      },
                      child: Text(s.voiceFinish),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
