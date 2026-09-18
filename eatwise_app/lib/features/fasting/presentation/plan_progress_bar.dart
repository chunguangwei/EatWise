import 'dart:math' as math;

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart'
    show fastingClockProvider;
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 最新一条体重记录（kg，按归属日取最大日期；无记录为 null）。
final FutureProvider<double?>
latestWeightLogProvider = FutureProvider<double?>((ref) {
  final store = ref.watch(weightLogStoreProvider);
  final entries = store.loadEntries('2000-01-01', localDateKey(DateTime.now()));
  if (entries.isEmpty) return null;
  final latestDate = entries.keys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  return entries[latestDate]!.kg;
});

/// 首页「方案进度」条（薄荷走查 P0）：第 N 周 · 已减 X.X kg / 目标 Y kg
/// + 细进度条，位置在问候语/方案胶囊区。
///
/// 仅当档案设了 targetWeightKg 且能确定起始体重（档案体重优先，缺失回落
/// 最新记录）时渲染；未设目标不渲染保持首页简洁。已减 = 起始体重 − 最新
/// 体重记录（无记录按起始体重计，显示 0）；目标 = 起始体重 − 目标体重。
/// 周数自方案启动日（onboarding 一键启动写入的 startedAtUtc）起算，
/// 不足一周为第 1 周。负向进度（涨称）切换为「距目标还差 X.X kg」，
/// 进度条归零。
class PlanProgressBar extends ConsumerWidget {
  const PlanProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;

    final store = ref.watch(onboardingStoreProvider);
    final profile = store.loadProfile();
    final targetKg = profile?.targetWeightKg;
    if (targetKg == null) return const SizedBox.shrink();

    final latestKg = ref.watch(latestWeightLogProvider).valueOrNull;
    final startKg = profile!.weightKg ?? latestKg;
    if (startKg == null) return const SizedBox.shrink();

    final currentKg = latestKg ?? startKg;
    final lostKg = startKg - currentKg;
    final goalKg = startKg - targetKg;

    // 周数：方案启动日起算；启动日缺失/未来（防御）按第 1 周。
    final startedAtUtc = store.loadActivePlan()?.startedAtUtc;
    final nowUtc = ref.watch(fastingClockProvider)();
    final week = startedAtUtc == null
        ? 1
        : math.max(1, (nowUtc - startedAtUtc) ~/ (7 * 24 * 3600) + 1);

    final progress = goalKg > 0
        ? (lostKg / goalKg).clamp(0.0, 1.0)
        : (lostKg >= 0 ? 1.0 : 0.0);
    final text = lostKg >= 0
        ? t.fasting.home.planProgress(
            week: week,
            lost: lostKg.toStringAsFixed(1),
            goal: goalKg.toStringAsFixed(1),
          )
        : t.fasting.home.planProgressBehind(
            week: week,
            gap: (currentKg - targetKg).toStringAsFixed(1),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            text,
            style: textStyles.textSm.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Semantics(
            label: text,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              borderRadius: radii.rFull,
              backgroundColor: colors.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
