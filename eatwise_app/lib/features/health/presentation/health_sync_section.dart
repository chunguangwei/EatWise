import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/presentation/health_widgets.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置页「运动数据」区块（阶段 D，D-19 翻案落地）：
/// 同步开关（首次开启前弹单独同意）+ 授权状态行 + 今日数据预览
/// （步数/活动消耗/最新体重，体重可一键填入体重记录，不自动入账）。
class HealthSyncSection extends ConsumerWidget {
  const HealthSyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final state = ref.watch(healthSyncControllerProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s1,
              bottom: AppSpacing.s2,
            ),
            child: Text(
              t.settings.health.group,
              style: textStyles.textSm.copyWith(color: colors.textSecondary),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: radii.rLg,
            ),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              t.settings.health.sync,
                              style: textStyles.textBase.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              t.settings.health.syncSubtitle,
                              style: textStyles.textXs.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: state.enabled,
                        onChanged: (value) => _toggle(context, ref, value),
                      ),
                    ],
                  ),
                ),
                // 授权/支持态行（已授权/未授权/设备不支持/读取失败/读取中）。
                if (state.enabled)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.s4,
                      right: AppSpacing.s4,
                      bottom: AppSpacing.s2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _statusText(t, state.status),
                        style: textStyles.textXs.copyWith(
                          color: state.status == HealthSyncStatus.ready
                              ? colors.signalGreen
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                // 今日数据预览 + 一键填入体重记录（不自动入账）。
                if (state.status == HealthSyncStatus.ready &&
                    state.today != null)
                  _TodayPreview(state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _statusText(Translations t, HealthSyncStatus status) {
    return switch (status) {
      HealthSyncStatus.connecting => t.settings.health.statusConnecting,
      HealthSyncStatus.ready => t.settings.health.statusReady,
      HealthSyncStatus.denied => t.settings.health.statusDenied,
      HealthSyncStatus.unsupported => t.settings.health.statusUnsupported,
      HealthSyncStatus.error => t.settings.health.statusError,
      HealthSyncStatus.off => '',
    };
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool value) async {
    final t = Translations.of(context);
    final controller = ref.read(healthSyncControllerProvider.notifier);
    if (value) {
      // GDPR Art.9：单独同意先于系统授权申请。
      final agreed = await showExerciseSyncConsentDialog(context);
      if (!agreed) return;
      await controller.enable();
    } else {
      await controller.disable();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.settings.health.revoked)));
      }
    }
  }
}

/// 今日数据预览（步数/活动消耗/最新体重 + 一键填入体重记录）。
class _TodayPreview extends ConsumerWidget {
  const _TodayPreview({required this.state});

  final HealthSyncState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final today = state.today!;

    final lines = <String>[
      if (today.steps != null) t.settings.health.steps(steps: '${today.steps}'),
      if (today.displayBurnKcal != null)
        t.settings.health.activeEnergy(
          kcal: today.displayBurnKcal!.toStringAsFixed(0),
        ),
      if (today.latestWeightKg != null)
        t.settings.health.latestWeight(
          kg: today.latestWeightKg!.toStringAsFixed(1),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.s4,
        right: AppSpacing.s4,
        bottom: AppSpacing.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (lines.isEmpty)
            Text(
              t.settings.health.noData,
              style: textStyles.textXs.copyWith(color: colors.textSecondary),
            )
          else
            Text(
              lines.join(' · '),
              style: textStyles.textSm.copyWith(color: colors.textPrimary),
            ),
          if (today.latestWeightKg != null) ...<Widget>[
            const SizedBox(height: AppSpacing.s2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _fillWeight(context, ref),
                child: Text(t.settings.health.fillWeight),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 一键填入今日体重记录（覆写同日，走 WeightLogStore pending 同步链路）。
  Future<void> _fillWeight(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final kg = state.today!.latestWeightKg!;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await ref.read(weightLogStoreProvider).save(date, kg);
    // 与记录页体重录入同口径：录入/趋势即刻反映。
    ref.invalidate(todayWeightProvider);
    ref.invalidate(todayWeightEntryProvider);
    ref.invalidate(reportWeightProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.settings.health.weightFilled(kg: kg.toStringAsFixed(1)),
          ),
        ),
      );
    }
  }
}
