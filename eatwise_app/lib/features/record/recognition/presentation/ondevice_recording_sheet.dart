/// 端侧录音转写面板（系统 ASR 不可用设备上的语音路径）：
/// 点击开始/停止录音 → 端侧模型转写 → 文本可编辑确认 → 完成。
/// 与系统听写面板同款的键盘输入切换（纯文本自由记永远可降级）。
library;

import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/domain/ondevice_asr_logic.dart';
import 'package:eatwise/features/record/recognition/presentation/voice_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 面板阶段（idle → recording → transcribing → done/failed）。
enum _Stage { idle, recording, transcribing, done, failed }

/// 端侧录音转写面板（权限已由调用方 [startVoiceInput] 前置申请）。
class OnDeviceRecordingSheet extends ConsumerStatefulWidget {
  const OnDeviceRecordingSheet({super.key});

  @override
  ConsumerState<OnDeviceRecordingSheet> createState() =>
      _OnDeviceRecordingSheetState();
}

class _OnDeviceRecordingSheetState
    extends ConsumerState<OnDeviceRecordingSheet> {
  _Stage _stage = _Stage.idle;
  String _text = '';
  bool _typing = false;
  final TextEditingController _typeController = TextEditingController();

  /// 转写中用户点了取消：在途 future 完成时不再写状态。
  bool _cancelRequested = false;

  @override
  void dispose() {
    _typeController.dispose();
    super.dispose();
  }

  /// 主按钮：idle/failed → 开始录音；recording → 停止并转写。
  Future<void> _onMicTap() async {
    final recorder = ref.read(audioRecorderGatewayProvider);
    switch (_stage) {
      case _Stage.idle:
      case _Stage.failed:
        await recorder.start();
        if (mounted) setState(() => _stage = _Stage.recording);
      case _Stage.recording:
        final pcm = await recorder.stop();
        if (!mounted) return;
        if (pcm == null || pcm.isEmpty) {
          setState(() => _stage = _Stage.failed);
          return;
        }
        setState(() => _stage = _Stage.transcribing);
        final wav = wrapPcm16AsWav(pcm);
        final isZh = LocaleSettings.currentLocale.languageCode == 'zh';
        final service = ref.read(onDeviceAsrServiceProvider);
        final text = service == null
            ? null
            : await service
                  .transcribe(wav, isZh: isZh)
                  .timeout(
                    kFreeTextInferenceTimeout, // 与自由记推理同款 60s 上限
                    onTimeout: () => null,
                  );
        if (!mounted || _cancelRequested) return;
        if (text == null) {
          setState(() => _stage = _Stage.failed);
        } else {
          setState(() {
            _stage = _Stage.done;
            _text = text;
            // 转写完成回填进可编辑文本框（确认前可改，与听写面板键盘态同款）。
            _typing = true;
            _typeController.text = text;
            _typeController.selection = TextSelection.collapsed(
              offset: text.length,
            );
          });
        }
      case _Stage.transcribing:
      case _Stage.done:
        break; // 转写中/已完成：主按钮不响应
    }
  }

  /// 取消：录音中取消本次录音；转写中标记取消；然后关闭面板（不丢已输入）。
  Future<void> _onCancel() async {
    if (_stage == _Stage.recording) {
      await ref.read(audioRecorderGatewayProvider).cancel();
    }
    _cancelRequested = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final recording = _stage == _Stage.recording;
    final busy = _stage == _Stage.transcribing;

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
                      : Text(_statusText(s), style: textStyles.textBase),
                ),
                // 语音/键盘切换（≥48px 触控目标）。
                IconButton(
                  icon: Icon(_typing ? Icons.mic : Icons.keyboard_outlined),
                  tooltip: s.voiceTypeInput,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: busy
                      ? null
                      : () => setState(() {
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
            if (_stage == _Stage.failed) ...<Widget>[
              const SizedBox(height: AppSpacing.s2),
              Text(
                s.voiceTranscribeFailed,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
            ],
            const SizedBox(height: AppSpacing.s4),
            // 主按钮：开始/停止录音（转写中置 loading）。
            OutlinedButton.icon(
              onPressed: busy ? null : () => unawaited(_onMicTap()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSpacing.s12),
                foregroundColor: colors.brandPrimary,
                side: BorderSide(color: colors.brandPrimary),
              ),
              icon: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.brandPrimary,
                      ),
                    )
                  : Icon(recording ? Icons.stop : Icons.mic),
              label: Text(
                busy
                    ? s.voiceTranscribingNow
                    : recording
                    ? s.voiceRecordingNow
                    : s.voiceTapToStart,
                style: textStyles.textBase,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => unawaited(_onCancel()),
                      child: Text(s.cancelAction),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed:
                          (_stage == _Stage.done || _typing) &&
                              _effectiveText().isNotEmpty
                          ? () => Navigator.of(context).pop(
                              VoiceTranscript(_effectiveText(), typed: _typing),
                            )
                          : null,
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

  /// 各阶段状态文案（非键盘态显示在文本区）。
  String _statusText(RecordStrings s) {
    return switch (_stage) {
      _Stage.idle => s.voiceTapToStart,
      _Stage.recording => s.voiceRecordingNow,
      _Stage.transcribing => s.voiceTranscribingNow,
      _Stage.done => _text,
      _Stage.failed => s.voiceTranscribeFailed,
    };
  }

  /// 完成入账文本：键盘态取文本框，否则取转写结果。
  String _effectiveText() => _typing ? _typeController.text.trim() : _text;
}
