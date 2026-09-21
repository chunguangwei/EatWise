import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/exposure_tracker.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart'
    show localDateOf;
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart'
    show mergeProfileWithServer, serverProfileOf;
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart'
    show userMeProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页底部一行三色 mini signal-card（设计稿 §4.2-①：蛋白/碳水/热量，
/// 点按跳数据页；§4.1 信号卡：色+图标+文字三重编码，D-05 阈值判定）。
///
/// 数据流：record 模块当日聚合缓存（本地预估）→ [DailyIntake] →
/// `evaluateDailySignals`（signal_light/daily_nutrition 领域纯函数）→
/// 落区渲染；当日 0 条记录走空态（四态规范 3.4：不出现误导性信号灯）。

/// 每日营养目标（M1 引导写入的快照；缺失/兜底态按最新档案重算，D-04）。
///
/// 走查修复（v1.13.3）「当前按默认目标估算」误提示：快照缺失或本身
/// usedFallback=true（身体档案表单 sex/活动水平可空，保存即落兜底快照）
/// 时，改为按「本地档案 ∪ 服务端下行档案」重算——重装/跨设备登录后
/// 本地未落盘、资料却在服务端的用户不再被误报默认目标。重算仍缺项
/// （isComplete=false）才保留 usedFallback=true 并展示补全提示。
/// 纯读侧重算，不落盘（保存档案仍由 BodyProfileService 写权威快照）。
final nutritionGoalProvider = Provider<NutritionGoal>((ref) {
  final store = ref.watch(onboardingStoreProvider);
  NutritionGoal? snapshotGoal;
  final snapshot = store.loadNutritionGoal();
  if (snapshot != null) {
    snapshotGoal = NutritionGoal(
      bmr: null,
      tdee: null,
      targetKcal: snapshot.targetKcal,
      proteinG: snapshot.proteinG,
      fatG: snapshot.fatG,
      carbG: snapshot.carbG,
      usedFallback: snapshot.usedFallback,
      configVersion: snapshot.configVersion,
    );
    if (!snapshot.usedFallback) return snapshotGoal;
  }
  // 重算素材：本地档案优先、服务端下行补齐（serverProfileOf 逆解析）；
  // 未登录/U1 未加载完时 me=null，等价旧行为（空档案兜底）。
  final me = ref.watch(userMeProvider).valueOrNull;
  final profile = mergeProfileWithServer(
    store.loadProfile() ?? OnboardingProfile.empty,
    me == null ? null : serverProfileOf(me),
  );
  final input = profile.toProfileInput(
    goal: me?.goal == 'fat_loss'
        ? NutritionGoalType.lose
        : NutritionGoalType.maintain,
    currentYear: DateTime.fromMillisecondsSinceEpoch(
      ref.watch(nowUtcProvider) * 1000,
      isUtc: true,
    ).year,
    today: localDateOf(
      ref.watch(nowUtcProvider),
      ref.watch(deviceLocationProvider),
    ),
  );
  if (!input.isComplete) {
    // 资料确实不全：有旧兜底快照则沿用（避免克数口径抖动），否则兜底公式。
    return snapshotGoal ??
        computeNutritionGoal(input, NutritionRuleConfig.defaults);
  }
  return computeNutritionGoal(input, NutritionRuleConfig.defaults);
});

/// 当日营养聚合缓存流（数据源端口）。
///
/// 默认空流：未装配记录仓储的环境（如无 db 的测试）下信号卡走空态——
/// 首页计时为本地计算，绝不因信号卡数据源缺失而破版（四态规范 3.4）。
/// 生产由 main 在 ProviderScope override 为 record 仓储的当日聚合流。
final todayNutritionCacheProvider = StreamProvider<DailyNutritionCache?>((ref) {
  return Stream<DailyNutritionCache?>.value(null);
});

/// 当日累计摄入（聚合缓存 → 领域输入；0 条记录 → null 走空态）。
final todayIntakeProvider = Provider<DailyIntake?>((ref) {
  final cache = ref.watch(todayNutritionCacheProvider).valueOrNull;
  if (cache == null || cache.entryCount == 0) return null;
  return DailyIntake(
    entryCount: cache.entryCount,
    kcal: cache.kcal,
    proteinG: cache.proteinG,
    carbG: cache.carbG,
    fatG: cache.fatG,
  );
});

/// 当日信号灯判定结果（D-05 阈值，规则热配置当前用内置默认值）。
final todaySignalsProvider = Provider<DailySignal>((ref) {
  final intake = ref.watch(todayIntakeProvider);
  final goal = ref.watch(nutritionGoalProvider);
  return evaluateDailySignals(
    intake ??
        const DailyIntake(
          entryCount: 0,
          kcal: 0,
          proteinG: 0,
          carbG: 0,
          fatG: 0,
        ),
    goal,
    NutritionRuleConfig.defaults,
  );
});

/// 一行三色 mini signal-card（蛋白/碳水/热量）。
class MiniSignalCards extends ConsumerWidget {
  const MiniSignalCards({required this.onTap, super.key});

  /// 点按任一卡片（设计稿 §4.2-①：跳数据页）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final signal = ref.watch(todaySignalsProvider);
    if (!signal.hasData) {
      return _EmptySignalCard(
        message: t.fasting.home.signalEmpty,
        onTap: onTap,
      );
    }
    return Row(
      children: <Widget>[
        for (final nutrient in <NutrientType>[
          NutrientType.protein,
          NutrientType.carb,
          NutrientType.kcal,
        ]) ...<Widget>[
          if (nutrient != NutrientType.protein)
            const SizedBox(width: AppSpacing.s2),
          // mini signal-card 曝光（§4.1 组件级 ≥50%+500ms；去重键含
          // nutrient+signal_level——落区变化重计）。
          Expanded(
            child: ExposureTracker(
              eventName: 'mini_signal_card_expose',
              dedupeKey:
                  'home:mini_signal:${nutrient.name}:${signal.verdicts[nutrient]!.zone.name}',
              properties: <String, Object?>{
                'nutrient': _nutrientEventValue(nutrient),
                'signal_level': signal.verdicts[nutrient]!.zone.name,
              },
              child: _MiniSignalCard(
                nutrient: nutrient,
                label: _nutrientLabel(t, nutrient),
                verdict: signal.verdicts[nutrient]!,
                onTap: onTap,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 营养素展示名（蛋白/碳水/热量）。
String _nutrientLabel(Translations t, NutrientType nutrient) {
  return switch (nutrient) {
    NutrientType.protein => t.record.nutrition.protein,
    NutrientType.carb => t.record.nutrition.carb,
    NutrientType.kcal => t.record.nutrition.kcal,
    NutrientType.fat => t.record.nutrition.fat,
  };
}

/// NutrientType → 事件字典 nutrient 枚举（§3.4：kcal → calorie）。
String _nutrientEventValue(NutrientType nutrient) {
  return switch (nutrient) {
    NutrientType.kcal => 'calorie',
    NutrientType.protein => 'protein',
    NutrientType.carb => 'carb',
    NutrientType.fat => 'fat',
  };
}

/// 空态卡（四态规范 3.4：当日无记录 → 引导去记录，不出现信号灯）。
class _EmptySignalCard extends StatelessWidget {
  const _EmptySignalCard({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Semantics(
      button: true,
      label: message,
      child: Material(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        child: InkWell(
          borderRadius: radii.rLg,
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.restaurant_outlined,
                  color: colors.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    message,
                    style: textStyles.textSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单张 mini 信号卡：颜色 + 图标 + 文字三重编码（绝不单靠颜色，PRD M8）。
class _MiniSignalCard extends StatelessWidget {
  const _MiniSignalCard({
    required this.nutrient,
    required this.label,
    required this.verdict,
    required this.onTap,
  });

  final NutrientType nutrient;
  final String label;
  final SignalVerdict verdict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final shadows = Theme.of(context).extension<AppShadows>()!;
    final t = Translations.of(context);
    final (color, icon, zoneLabel) = switch (verdict.zone) {
      SignalZone.green => (
        colors.signalGreen,
        Icons.check_circle,
        t.nutrition.signalCard.zone.green,
      ),
      SignalZone.yellow => (
        colors.signalYellow,
        Icons.error,
        t.nutrition.signalCard.zone.yellow,
      ),
      SignalZone.red => (
        colors.signalRed,
        Icons.cancel,
        t.nutrition.signalCard.zone.red,
      ),
    };
    return Semantics(
      button: true,
      label: '$label $zoneLabel',
      child: Material(
        color: colors.bgSecondary,
        borderRadius: radii.rLg,
        child: InkWell(
          borderRadius: radii.rLg,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s2,
            ),
            decoration: BoxDecoration(
              borderRadius: radii.rLg,
              boxShadow: shadows.shadowSm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: color, size: 20),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  label,
                  style: textStyles.textSm.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  zoneLabel,
                  style: textStyles.textXs.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
