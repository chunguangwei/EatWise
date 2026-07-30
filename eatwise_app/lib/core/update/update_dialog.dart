import 'dart:io';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/update/update_launcher.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:flutter/material.dart';

/// 更新弹窗（D-15 双语）：标题/版本号/release notes/「立即更新」「以后再说」。
/// 强制更新（[UpdateStatus.forced]）无「以后再说」且不可关闭
/// （barrierDismissible=false + 拦截返回）。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateCheckResult result, {
  UpdateLauncher launcher = const UpdateLauncher(),
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
      platform: resolvedPlatform,
    ),
  );
}

/// 更新弹窗本体（独立 Widget 便于测试）。
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.result,
    this.launcher = const UpdateLauncher(),
    this.platform = 'android',
  });

  final UpdateCheckResult result;
  final UpdateLauncher launcher;
  final String platform;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final forced = result.status == UpdateStatus.forced;
    final info = result.info;
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
        ],
      ),
      actions: <Widget>[
        if (!forced)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.update.later),
          ),
        FilledButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);
            final opened = await launcher.openUpdate(info, platform: platform);
            if (!opened) {
              messenger.showSnackBar(
                SnackBar(content: Text(t.update.downloadFailed)),
              );
              return;
            }
            // 可选更新跳转后关闭弹窗；强制更新保持（未升级前不放行）。
            if (!forced) navigator.pop();
          },
          child: Text(t.update.updateNow),
        ),
      ],
    );
    if (!forced) return dialog;
    // 强制更新：拦截系统返回，弹窗不可关闭。
    return PopScope(canPop: false, child: dialog);
  }
}
