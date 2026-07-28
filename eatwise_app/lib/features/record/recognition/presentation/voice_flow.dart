import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/voice/speech_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 语音录入入口流程（PRD M3 / D-16：系统 ASR + 自研轻量解析，
/// 不引入独立 NLP 服务）。
///
/// 首次点击用时申请权限（合规 §3.1：iOS 语音识别+麦克风双权限，
/// Android RECORD_AUDIO）；权限拒绝/设备不支持 → 降级说明卡引导手动
/// 输入，不阻断记录；「取消」丢弃本次听写但不丢已输入内容。
Future<void> startVoiceInput(BuildContext context, WidgetRef ref) async {
  final s = RecordStrings.of(context);
  final gateway = ref.read(speechGatewayProvider);
  final available = await gateway.initialize();
  if (!context.mounted) return;
  if (!available) {
    await _showVoiceDeniedCard(context, s);
    return;
  }
  final localeId = LocaleSettings.currentLocale.languageTag.replaceAll(
    '-',
    '_',
  );
  final transcript = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    builder: (_) => _VoiceListeningSheet(gateway: gateway, localeId: localeId),
  );
  // null = 用户取消听写：静默返回，不动已输入内容。
  if (transcript == null || !context.mounted) return;

  final foods = await ref
      .read(recordRepositoryProvider)
      .searchFoods('', limit: 500);
  if (!context.mounted) return;
  final result = ref.read(voiceTextParserProvider).parse(transcript, foods);
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

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.gateway.start(
        localeId: widget.localeId,
        onText: (text) {
          if (mounted) setState(() => _text = text);
        },
      ),
    );
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
                Icon(Icons.mic, color: colors.brandPrimary),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    _text.isEmpty ? s.voiceListening : _text,
                    style: textStyles.textBase,
                  ),
                ),
              ],
            ),
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
                          Navigator.of(context).pop(_text);
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
