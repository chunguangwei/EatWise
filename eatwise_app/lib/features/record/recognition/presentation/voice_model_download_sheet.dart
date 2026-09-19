/// 语音兜底内嵌模型下载弹层（不跳设置页）：
/// 「下载本地模型」点完就地开始下载（Range 断点续传，管理器既有能力），
/// 进度条实时显示；完成自动关闭并回 true（调用方直接进端侧录音面板）；
/// 失败显示错误可重试；取消中断下载（.part 保留可续传）。
library;

import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/settings/presentation/ondevice_model_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 语音流程内嵌模型下载弹层：返回 true = 模型已就绪（调用方直接进录音
/// 面板）；false/null = 用户取消或失败未重试（语音流程结束，可重进）。
class VoiceModelDownloadSheet extends ConsumerStatefulWidget {
  const VoiceModelDownloadSheet({super.key});

  @override
  ConsumerState<VoiceModelDownloadSheet> createState() =>
      _VoiceModelDownloadSheetState();
}

class _VoiceModelDownloadSheetState
    extends ConsumerState<VoiceModelDownloadSheet> {
  /// 下载/重试在途（防连点）。
  bool _starting = false;

  /// 最近一次失败原因（可重试；取消不算失败）。
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// 启动/重试下载（管理器内部并发共享同一下载；Range 断点续传）。
  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await ref.read(onDeviceModelActionsProvider).ensureModel();
    } on OnDeviceDownloadCancelledException {
      // 用户取消：状态转 paused（.part 保留可续传），留在弹层可重试。
    } on OnDeviceModelException catch (e) {
      if (mounted) setState(() => _error = e);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final m = t.settings.onDevice;
    final s = RecordStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final snapshot =
        ref.watch(onDeviceModelSnapshotProvider).valueOrNull ??
        const OnDeviceModelSnapshot(status: OnDeviceModelStatus.notDownloaded);

    // 模型就绪：下一帧自动关闭并回 true（调用方直接进录音面板）。
    if (snapshot.status == OnDeviceModelStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
    final progress = snapshot.progress;
    final percent = progress == null ? null : (progress * 100).round();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(s.voiceDownloadTitle, style: textStyles.textLg),
            const SizedBox(height: AppSpacing.s2),
            Text(
              m.size,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s4),
            if (_error == null) ...<Widget>[
              LinearProgressIndicator(
                value: snapshot.status == OnDeviceModelStatus.downloading
                    ? progress
                    : null,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                percent == null
                    ? m.downloading(percent: 0)
                    : m.downloading(percent: percent),
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
            ] else ...<Widget>[
              Text(
                m.errorDownload,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
              const SizedBox(height: AppSpacing.s2),
              OutlinedButton(
                onPressed: _starting ? null : () => unawaited(_start()),
                child: Text(m.retry),
              ),
            ],
            const SizedBox(height: AppSpacing.s3),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  ref.read(onDeviceModelActionsProvider).cancel();
                  Navigator.of(context).pop(false);
                },
                child: Text(s.cancelAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
