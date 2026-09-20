import 'dart:async';
import 'package:app_settings/app_settings.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:eatwise/features/record/recognition/presentation/ai_engine_guide_card.dart';
import 'package:eatwise/features/record/recognition/presentation/ondevice_recording_sheet.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_meal_sheet.dart';
import 'package:eatwise/features/record/recognition/presentation/voice_model_download_sheet.dart';
import 'package:eatwise/features/record/recognition/voice/speech_gateway.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 端侧 ASR 引擎预热（视觉+音频同开）：只在用户明确表现出要用语音的
/// 路径上触发（语音入口端侧分支 / 逃生舱触发时），且模型已下载才执行；
/// 已加载时幂等跳过。失败静默（转写路径会重试并有自己的降级）。
/// 注意内存/电量：不在 App 启动等无明确意图处调用（冷启动预热另有
/// prewarmOnDeviceEngineOnStartup 按开关口径控制）。
void prewarmOnDeviceAsrEngine(WidgetRef ref) {
  final manager = ref.read(onDeviceModelManagerProvider);
  // 就绪判定优先读快照流（语义等价于 manager.snapshot——provider 就是
  // 其 refresh 后的状态流；测试可用 Stream.value 注入，免磁盘 IO）。
  final snapshot = ref.read(onDeviceModelSnapshotProvider).valueOrNull;
  unawaited(
    prewarmOnDeviceEngine(
      modelPath: manager.modelPath,
      isModelReady: () =>
          (snapshot ?? manager.snapshot).status == OnDeviceModelStatus.ready,
      gateway: ref.read(onDeviceLlmGatewayProvider),
      enableAudio: true,
    ),
  );
}

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
  // 设备级记忆：系统 ASR 已确认不可用的设备（无 GMS），跳过系统听写
  // 直达端侧路径——端侧就绪直接进录音面板（不走系统听写、不等 6s），
  // 模型未下载直接弹引擎引导卡（内嵌下载带进度，完成自动回录音面板）。
  if (ref.read(systemAsrBrokenProvider)) {
    if (onDeviceRecognitionActiveFor(
      ref.watch(onDeviceAiEnabledProvider),
      ref.watch(onDeviceModelSnapshotProvider),
    )) {
      await _openOnDeviceRecording(context, ref, s);
    } else if (!ref.read(aiEngineGuideDismissedProvider)) {
      await _showVoiceEngineGuide(context, ref, s);
    }
    return;
  }
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
    transcript = await _openOnDeviceRecording(context, ref, s);
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

/// 打开端侧录音面板（权限首次用时申请 + 预热 + 面板），返回转写结果
///（null = 权限拒绝已弹降级卡 / 用户取消）。两条端侧路径共用：
/// 设备记忆直达 与 系统 ASR 不可用回落。
Future<VoiceTranscript?> _openOnDeviceRecording(
  BuildContext context,
  WidgetRef ref,
  RecordStrings s,
) async {
  final recorder = ref.read(audioRecorderGatewayProvider);
  final permitted = await recorder.ensurePermission();
  if (!context.mounted) return null;
  if (!permitted) {
    await _showVoiceDeniedCard(context, s);
    return null;
  }
  // 预热：面板打开前后台加载引擎（视觉+音频），用户点录音时引擎已热。
  prewarmOnDeviceAsrEngine(ref);
  if (!context.mounted) return null;
  return showModalBottomSheet<VoiceTranscript>(
    context: context,
    isDismissible: false,
    builder: (_) => const OnDeviceRecordingSheet(),
  );
}

/// 语音专属引擎引导（与拍照记同款引导卡文案，但「下载本地模型」不走
/// 设置页——语音流程内嵌下载带进度，完成自动回录音面板，步骤最少）。
Future<void> _showVoiceEngineGuide(
  BuildContext context,
  WidgetRef ref,
  RecordStrings s,
) async {
  final action = await showAiEngineGuideCard(context, s);
  if (!context.mounted) return;
  switch (action) {
    case AiEngineGuideAction.downloadModel:
      final ready = await showModalBottomSheet<bool>(
        context: context,
        builder: (_) => const VoiceModelDownloadSheet(),
      );
      if (!context.mounted) return;
      if (ready == true) {
        // 等下载弹层退出动画完成再开录音面板：连续两个 ModalBottomSheet
        // 时，先弹出弹层的退出动画会被暂停并残留（route isCurrent=false
        // 但 widget 不销毁，Flutter 已知行为）。
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!context.mounted) return;
        // 下载完成：顺畅回到语音——直接进端侧录音面板。
        await _openOnDeviceRecording(context, ref, s);
      }
    case AiEngineGuideAction.configApi:
      ref
          .read(aiEngineGuideNavigatorProvider)
          .call(context, AiEngineGuideTarget.cloudApi);
    case AiEngineGuideAction.manualSearch:
      // 本次会话不再弹（内存态，不持久化）+ 对焦搜索框。
      ref.read(aiEngineGuideDismissedProvider.notifier).state = true;
      ref.read(recordSearchPrefillProvider.notifier).state = '';
    case null: // 遮罩关闭：原地不动
  }
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
  // 词典命中也可能多条（「两个鸡蛋一碗米饭」）：全部条目进同款明细
  // 确认弹层（可改克数/删除/取消），**不再**只取第一条静默预填直接入账
  // （真机走查 bug：多个信息只记了第一个，用户无确认机会）。
  final mealItems = result.items
      .map(
        (p) => RecognizedMealItem(
          name: p.food.nameZh,
          nameEn: p.food.nameEn,
          grams: p.amountG,
          per100g: NutritionSnapshot(
            kcal: p.food.kcalPer100g,
            proteinG: p.food.proteinPer100g,
            carbG: p.food.carbPer100g,
            fatG: p.food.fatPer100g,
          ),
          confidence: 1.0,
          food: p.food,
        ),
      )
      .toList();
  final confirm = await showPhotoMealConfirmSheet(
    context,
    ref,
    mealItems,
    entrySource: EntrySource.voice,
    showRetake: false,
  );
  if (!context.mounted || confirm == null || confirm.loggedCount == 0) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(s.photoLoggedItems(confirm.loggedCount))),
  );
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

  /// 当前是否在听写（错误/停止后为 false → 显示「再说一次」重录入口，
  /// 修复真机走查：没听清后面板只剩错误态，没有语音重录入口）。
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  /// 开始/重新开始听写（清残留错误态 + 重挂静默兜底定时器）。
  void _startListening() {
    setState(() {
      _error = null;
      _noResultHint = false;
      _listening = true;
    });
    unawaited(
      widget.gateway.start(
        localeId: widget.localeId,
        onText: (text) {
          if (mounted) setState(() => _text = text);
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _error = error;
            _listening = false;
          });
          const benign = <String>{'error_no_match', 'error_speech_timeout'};
          if (!benign.contains(error)) {
            // 致命错误：记设备级「系统 ASR 已坏」（下次点语音记直达端侧，
            // 不再走系统听写白等）；同时预热端侧引擎。
            ref.read(systemAsrBrokenProvider.notifier).setBroken(true);
            _prewarmOnce();
          }
        },
      ),
    );
    _noResultTimer?.cancel();
    _noResultTimer = Timer(kNoResultHintDelay, () {
      if (mounted && _text.isEmpty && _error == null && !_typing) {
        setState(() {
          _noResultHint = true;
          _listening = false;
        });
        // 静默 6s 无结果：同样记设备级「系统 ASR 已坏」+ 预热端侧引擎。
        ref.read(systemAsrBrokenProvider.notifier).setBroken(true);
        _prewarmOnce(); // 静默兜底触发 = 用户大概率要点逃生舱，提前热引擎
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

  /// 逃生舱触发后已预热过一次（避免 onError/定时器重复触发预热）。
  bool _prewarmed = false;

  /// 逃生舱触发时后台预热端侧引擎（用户即将点「用离线小模型识别」，意图
  /// 明确；只在端侧就绪时预热，已预热过幂等跳过）。
  void _prewarmOnce() {
    if (_prewarmed || !_onDeviceAsrReady) return;
    _prewarmed = true;
    prewarmOnDeviceAsrEngine(ref);
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
    // 模型未下载/未启用 → 与拍照记入口同款引导卡（下载本地模型带进度
    // /配置云端 API/先手动搜索），修复「没提示下载小模型」：此前按钮
    // 仅在端侧就绪时出现，首次用户（开关默认关）根本看不到它。
    if (!_onDeviceAsrReady) {
      await widget.gateway.cancel();
      if (!mounted) return;
      // 语音专属引导：内嵌下载带进度（不跳设置页），完成自动回录音面板。
      await _showVoiceEngineGuide(context, ref, RecordStrings.of(context));
      if (!mounted) return;
      // 引导结束即关闭听写面板：下载/配置完成，手动搜索已对焦。
      Navigator.of(context).pop();
      return;
    }
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
                          onChanged: (value) => setState(() => _text = value),
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
                      // 切回语音态：不在听写（没听清/出错后）则重新开始听写，
                      // 右上角 mic 钮即语音重录入口。
                      if (!_listening) _startListening();
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
              // 重录入口：没听清/出错/静默后听写已停，点一下重新说
              // （真机走查：此前只能切键盘，语音没有重试入口）。
              if (!_listening) ...<Widget>[
                const SizedBox(height: AppSpacing.s2),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _startListening,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.brandPrimary,
                      side: BorderSide(color: colors.brandPrimary),
                    ),
                    icon: const Icon(Icons.mic),
                    label: Text(s.voiceRetry, style: textStyles.textBase),
                  ),
                ),
              ],
              // 逃生舱：致命错误/静默超时 → 一键切离线模型；模型未就绪
              // 时点击走「下载本地模型」引导卡（与拍照记入口同款 gating），
              // 已选过「先手动搜索」的会话不再打扰（不显示按钮）。
              if (_escapeTriggered &&
                  (_onDeviceAsrReady ||
                      !ref.watch(aiEngineGuideDismissedProvider))) ...<Widget>[
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
