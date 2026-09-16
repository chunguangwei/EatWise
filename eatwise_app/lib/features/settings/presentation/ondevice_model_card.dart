import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 卡片动作窄接口（widget 测试注入 Fake；模式同 LlmConnectionTester）。
/// 状态流仍走 [onDeviceModelSnapshotProvider]，本接口只承载「意图」与
/// 估算永久禁用标记（核心层 manager/estimator 为 final class，不可子类化）。
abstract interface class OnDeviceModelActions {
  /// 下载/续传（失败抛 [OnDeviceModelException] 子类，UI 吞掉经状态流呈现）。
  Future<String> ensureModel();

  /// 取消进行中下载（状态转 paused，.part 保留）。
  void cancel();

  /// 删除模型与临时文件。
  Future<void> delete();

  /// 端侧估算已因 OOM 永久禁用（开关置灰 + 文案说明）。
  bool get estimatePermanentlyDisabled;
}

/// 生产实现：委托核心层管理器/估算器。
final class ManagerOnDeviceModelActions implements OnDeviceModelActions {
  const ManagerOnDeviceModelActions(this._ref);

  final Ref _ref;

  @override
  Future<String> ensureModel() =>
      _ref.read(onDeviceModelManagerProvider).ensureModel();

  @override
  void cancel() => _ref.read(onDeviceModelManagerProvider).cancel();

  @override
  Future<void> delete() => _ref.read(onDeviceModelManagerProvider).delete();

  @override
  bool get estimatePermanentlyDisabled =>
      _ref.read(onDeviceNutritionEstimatorProvider).isPermanentlyDisabled;
}

/// 卡片动作出口（测试 override 为 Fake）。
final onDeviceModelActionsProvider = Provider<OnDeviceModelActions>(
  (ref) => ManagerOnDeviceModelActions(ref),
);

/// 端侧小模型卡片（AI 模型配置页顶部）：模型下载/暂停/删除状态机 +
/// 「优先使用端侧估算」开关（就绪后才可操作；OOM 永久禁用置灰并说明）。
///
/// 状态数据源 [onDeviceModelSnapshotProvider]（磁盘实况 refresh 后的
/// 状态流）；开关持久化走 [onDeviceAiEnabledProvider]（SharedPreferences）。
class OnDeviceModelCard extends ConsumerWidget {
  const OnDeviceModelCard({super.key});

  /// 下载/重试：失败状态经 snapshot 流呈现，这里只吞 typed 异常防未处理。
  void _startDownload(WidgetRef ref) {
    unawaited(
      ref
          .read(onDeviceModelActionsProvider)
          .ensureModel()
          .onError<OnDeviceModelException>((_, _) => ''),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.onDevice.deleteConfirmTitle),
        content: Text(t.settings.onDevice.deleteConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: colors.signalRed),
            child: Text(t.settings.onDevice.deleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(onDeviceModelActionsProvider).delete();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.settings.onDevice.deleted)));
  }

  /// 下载错误 → 友好文案（存储/内存门槛单列，其余统一网络失败）。
  String _errorText(Translations t, OnDeviceModelException? error) {
    final m = t.settings.onDevice;
    return switch (error) {
      OnDeviceInsufficientStorageException() => m.errorStorage,
      OnDeviceInsufficientMemoryException() => m.errorMemory,
      _ => m.errorDownload,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final m = t.settings.onDevice;
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final snapshotAsync = ref.watch(onDeviceModelSnapshotProvider);
    final enabled = ref.watch(onDeviceAiEnabledProvider);
    final actions = ref.watch(onDeviceModelActionsProvider);
    final permanentlyDisabled = actions.estimatePermanentlyDisabled;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(m.title, style: textStyles.textLg),
          const SizedBox(height: AppSpacing.s1),
          Text(
            m.desc,
            style: textStyles.textSm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s3),
          ...switch (snapshotAsync) {
            // 加载态极短（一次磁盘 refresh）：静态占位，不用动画
            //（避免 widget 测试 pumpAndSettle 空转）。
            AsyncLoading() => <Widget>[const SizedBox(height: AppSpacing.s12)],
            AsyncError() => <Widget>[
              Text(
                m.statusFailed,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
            ],
            AsyncData(:final value) => _buildStatus(
              context,
              ref,
              t,
              colors,
              textStyles,
              value,
              enabled: enabled,
              permanentlyDisabled: permanentlyDisabled,
            ),
            _ => <Widget>[
              Text(
                m.statusFailed,
                style: textStyles.textSm.copyWith(color: colors.signalRed),
              ),
            ],
          },
        ],
      ),
    );
  }

  /// 下载进度条（Y4）：轨道浅灰、进度品牌绿——默认轨道取
  /// secondaryContainer（暖阳橙派生）时 0% 整条橙色，误读为已完成。
  /// 透明度叠加与 home_shell 选中指示器同口径（withValues）。
  Widget _progressBar(AppColors colors, double? progress) {
    return LinearProgressIndicator(
      value: progress,
      backgroundColor: colors.textSecondary.withValues(alpha: 0.2),
      color: colors.brandPrimary,
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
    );
  }

  List<Widget> _buildStatus(
    BuildContext context,
    WidgetRef ref,
    Translations t,
    AppColors colors,
    AppTextStyles textStyles,
    OnDeviceModelSnapshot snapshot, {
    required bool enabled,
    required bool permanentlyDisabled,
  }) {
    final m = t.settings.onDevice;
    final percent = ((snapshot.progress ?? 0) * 100).round();
    final actions = ref.read(onDeviceModelActionsProvider);
    return switch (snapshot.status) {
      OnDeviceModelStatus.notDownloaded => <Widget>[
        Text(m.size, style: textStyles.textBase),
        const SizedBox(height: AppSpacing.s1),
        Text(
          m.wifiHint,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s3),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => _startDownload(ref),
          child: Text(m.download),
        ),
      ],
      OnDeviceModelStatus.downloading => <Widget>[
        _progressBar(colors, snapshot.progress),
        const SizedBox(height: AppSpacing.s2),
        Text(m.downloading(percent: percent), style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: actions.cancel,
          child: Text(m.cancel),
        ),
      ],
      OnDeviceModelStatus.paused => <Widget>[
        _progressBar(colors, snapshot.progress),
        const SizedBox(height: AppSpacing.s2),
        Text(m.paused(percent: percent), style: textStyles.textSm),
        const SizedBox(height: AppSpacing.s2),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => _startDownload(ref),
          child: Text(m.resume),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.signalRed,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => unawaited(_confirmDelete(context, ref)),
          child: Text(m.delete),
        ),
      ],
      OnDeviceModelStatus.ready => <Widget>[
        Text(m.ready, style: textStyles.textBase),
        const SizedBox(height: AppSpacing.s1),
        Text(
          m.coldLoadHint,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        if (permanentlyDisabled)
          Text(
            m.oomDisabled,
            style: textStyles.textSm.copyWith(color: colors.signalRed),
          )
        else
          Row(
            children: <Widget>[
              Expanded(child: Text(m.enabled, style: textStyles.textBase)),
              Switch(
                value: enabled,
                onChanged: (value) {
                  ref
                      .read(onDeviceAiEnabledProvider.notifier)
                      .setEnabled(value);
                  if (value) {
                    // 后台预热引擎（只 load 不推理），首拍即热；失败静默。
                    final manager = ref.read(onDeviceModelManagerProvider);
                    unawaited(
                      prewarmOnDeviceEngine(
                        modelPath: manager.modelPath,
                        isModelReady: () =>
                            manager.snapshot.status ==
                            OnDeviceModelStatus.ready,
                        gateway: ref.read(onDeviceLlmGatewayProvider),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.s2),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.signalRed,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => unawaited(_confirmDelete(context, ref)),
          child: Text(m.delete),
        ),
      ],
      OnDeviceModelStatus.error => <Widget>[
        Text(
          _errorText(t, snapshot.error),
          style: textStyles.textSm.copyWith(color: colors.signalRed),
        ),
        const SizedBox(height: AppSpacing.s2),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => _startDownload(ref),
          child: Text(m.retry),
        ),
      ],
    };
  }
}
