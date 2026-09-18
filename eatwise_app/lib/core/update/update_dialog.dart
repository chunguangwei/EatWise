import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/update/update_downloader.dart';
import 'package:eatwise/core/update/update_launcher.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:flutter/material.dart';

/// 更新弹窗（D-15 双语）：标题/版本号/release notes/「立即更新」「以后再说」。
/// 强制更新（[UpdateStatus.forced]）无「以后再说」且不可关闭
/// （barrierDismissible=false + 拦截返回）。
///
/// 「立即更新」行为分平台：Android 走 App 内下载（[UpdateDownloader]，自托管
/// 自签名证书不经浏览器、可显示进度），完成自动调起系统安装器，失败给重试；
/// iOS 走 [UpdateLauncher] 打开 App Store 占位（当前 iOS 平台门不弹窗，
/// 该路径仅平台中立性兜底）。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateCheckResult result, {
  UpdateLauncher launcher = const UpdateLauncher(),
  UpdateDownloader? downloader,
  String? platform,
}) {
  final forced = result.status == UpdateStatus.forced;
  final resolvedPlatform = platform ?? (Platform.isIOS ? 'ios' : 'android');
  return showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (dialogContext) => UpdateDialog(
      result: result,
      launcher: launcher,
      downloader: downloader,
      platform: resolvedPlatform,
    ),
  );
}

/// 更新弹窗的下载阶段。
enum _UpdatePhase {
  /// 初始（展示版本信息，等待点击「立即更新」）。
  idle,

  /// 下载中（展示进度，隐藏操作按钮避免中途关窗）。
  downloading,

  /// 下载/调起安装失败（展示错误与「重试」）。
  failed,
}

/// 更新弹窗本体（独立 Widget 便于测试）。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.result,
    this.launcher = const UpdateLauncher(),
    this.downloader,
    this.platform = 'android',
  });

  final UpdateCheckResult result;
  final UpdateLauncher launcher;

  /// APK 下载器；为空时用无证书锁定的兜底实例（生产经 provider 注入）。
  final UpdateDownloader? downloader;
  final String platform;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  double? _progress;

  late final UpdateDownloader _downloader =
      widget.downloader ?? UpdateDownloader(dio: Dio());

  bool get _forced => widget.result.status == UpdateStatus.forced;

  Future<void> _startUpdate() async {
    final info = widget.result.info;
    // iOS：维持原跳转（App Store 占位）；当前平台门下实际不可达。
    if (widget.platform == 'ios') {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final opened = await widget.launcher.openUpdate(
        info,
        platform: widget.platform,
      );
      if (!mounted) return;
      if (!opened) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(Translations.of(context).update.downloadFailed),
          ),
        );
        return;
      }
      if (!_forced) navigator.pop();
      return;
    }
    final apkUrl = info.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() => _phase = _UpdatePhase.failed);
      return;
    }
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = null;
    });
    final ok = await _downloader.downloadAndInstall(
      apkUrl,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _progress = total > 0 ? received / total : null;
        });
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _UpdatePhase.failed);
      return;
    }
    // 可选更新调起安装器后关闭弹窗；强制更新保持（未升级前不放行）。
    if (!_forced) Navigator.of(context).pop();
  }

  /// 下载进度条（与 ondevice_model_card 同款：轨道浅灰、进度品牌绿）。
  Widget _progressBar(AppColors colors) {
    return LinearProgressIndicator(
      value: _progress,
      backgroundColor: colors.textSecondary.withValues(alpha: 0.2),
      color: colors.brandPrimary,
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final info = widget.result.info;
    final notes = info.releaseNotesFor(
      LocaleSettings.currentLocale.languageTag,
    );
    final dialog = AlertDialog(
      title: Text(t.update.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(t.update.newVersion(version: info.latestVersion)),
          if (notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(notes),
          ],
          if (_phase == _UpdatePhase.downloading) ...<Widget>[
            const SizedBox(height: AppSpacing.s3),
            _progressBar(colors),
            const SizedBox(height: AppSpacing.s2),
            Text(
              _progress == null
                  ? t.update.downloadingNoProgress
                  : t.update.downloading(percent: (_progress! * 100).round()),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_phase == _UpdatePhase.failed) ...<Widget>[
            const SizedBox(height: AppSpacing.s3),
            Text(
              t.update.downloadFailed,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.signalRed),
            ),
          ],
        ],
      ),
      actions: switch (_phase) {
        _UpdatePhase.downloading => const <Widget>[],
        _UpdatePhase.idle => <Widget>[
          if (!_forced)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.update.later),
            ),
          FilledButton(
            onPressed: _startUpdate,
            child: Text(t.update.updateNow),
          ),
        ],
        _UpdatePhase.failed => <Widget>[
          if (!_forced)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.update.later),
            ),
          FilledButton(onPressed: _startUpdate, child: Text(t.update.retry)),
        ],
      },
    );
    if (!_forced) return dialog;
    // 强制更新：拦截系统返回，弹窗不可关闭。
    return PopScope(canPop: false, child: dialog);
  }
}
