import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/domain/exercise_goals.dart';
import 'package:eatwise/features/health/presentation/health_widgets.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/reports/application/reports_controller.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置页「运动数据」区块（阶段 D，D-19 翻案落地）：
/// 同步开关（首次开启前弹单独同意）+ 授权状态行 + 今日数据预览
/// （步数/活动消耗/最新体重，体重可一键填入体重记录，不自动入账）。
///
/// 薄荷走查 P2：同区块新增每日消耗目标（默认 200 kcal）与每日步数目标
/// （默认 5000 步），本地持久化、变更即时生效（数据页今日消耗卡同读）。
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
                // 薄荷走查 P2：每日消耗/步数目标（本地偏好，即时生效）。
                const _GoalTiles(),
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

/// 每日目标设置行（薄荷走查 P2）：消耗目标（kcal）+ 步数目标（步），
/// 点按弹数字输入对话框，校验落区间后持久化并即时生效。
class _GoalTiles extends ConsumerWidget {
  const _GoalTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final goals = ref.watch(exerciseGoalsProvider);

    return Column(
      children: <Widget>[
        _goalTile(
          context,
          title: t.settings.health.burnGoal,
          trailing: t.settings.health.burnGoalValue(
            kcal: goals.burnGoalKcal.toStringAsFixed(0),
          ),
          colors: colors,
          textStyles: textStyles,
          onTap: () => _editGoal(
            context,
            ref,
            dialogTitle: t.settings.health.burnGoalDialogTitle,
            inputLabel: t.settings.health.burnGoalInputLabel,
            initial: goals.burnGoalKcal.toStringAsFixed(0),
            parse: (raw) {
              final value = double.tryParse(raw);
              return value != null && ExerciseGoals.isValidBurnGoal(value)
                  ? value
                  : null;
            },
            apply: (value) =>
                ref.read(exerciseGoalsProvider.notifier).setBurnGoalKcal(value),
          ),
        ),
        _goalTile(
          context,
          title: t.settings.health.stepsGoal,
          trailing: t.settings.health.stepsGoalValue(
            steps: '${goals.stepsGoal}',
          ),
          colors: colors,
          textStyles: textStyles,
          onTap: () => _editGoal(
            context,
            ref,
            dialogTitle: t.settings.health.stepsGoalDialogTitle,
            inputLabel: t.settings.health.stepsGoalInputLabel,
            initial: '${goals.stepsGoal}',
            parse: (raw) {
              final value = int.tryParse(raw);
              return value != null && ExerciseGoals.isValidStepsGoal(value)
                  ? value
                  : null;
            },
            apply: (value) =>
                ref.read(exerciseGoalsProvider.notifier).setStepsGoal(value),
          ),
        ),
      ],
    );
  }

  Widget _goalTile(
    BuildContext context, {
    required String title,
    required String trailing,
    required AppColors colors,
    required AppTextStyles textStyles,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: textStyles.textBase.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                trailing,
                style: textStyles.textSm.copyWith(color: colors.textSecondary),
              ),
              Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// 数字输入对话框：校验失败行内报错不落盘；确认后持久化即时生效。
  Future<void> _editGoal<T extends num>(
    BuildContext context,
    WidgetRef ref, {
    required String dialogTitle,
    required String inputLabel,
    required String initial,
    required T? Function(String raw) parse,
    required Future<void> Function(T value) apply,
  }) async {
    final value = await showDialog<T>(
      context: context,
      builder: (dialogContext) => _GoalDialog<T>(
        title: dialogTitle,
        inputLabel: inputLabel,
        initial: initial,
        parse: parse,
      ),
    );
    if (value != null) {
      await apply(value);
    }
  }
}

/// 目标值输入对话框（控制器自持生命周期，弹窗动画期不提前 dispose）。
class _GoalDialog<T extends num> extends StatefulWidget {
  const _GoalDialog({
    required this.title,
    required this.inputLabel,
    required this.initial,
    required this.parse,
  });

  final String title;
  final String inputLabel;
  final String initial;
  final T? Function(String raw) parse;

  @override
  State<_GoalDialog<T>> createState() => _GoalDialogState<T>();
}

class _GoalDialogState<T extends num> extends State<_GoalDialog<T>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  /// 校验错误（true 时行内展示 goalInvalid，不落盘不关窗）。
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = widget.parse(_controller.text);
    if (value == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: widget.inputLabel,
          errorText: _invalid ? t.settings.health.goalInvalid : null,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.action.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t.common.action.confirm)),
      ],
    );
  }
}
