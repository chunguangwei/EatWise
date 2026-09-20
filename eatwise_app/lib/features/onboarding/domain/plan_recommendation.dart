import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';

/// 方案推荐引擎（M1，D-03 规则表的纯函数实现）。
///
/// 纯函数：无 I/O、无时钟依赖、无副作用；同输入必同输出。
/// 规则表（D-03）：
///
/// | Q3 经验     | 主推荐 | 备选   | 默认进食窗口   |
/// |-------------|--------|--------|----------------|
/// | 零基础      | 14:10  | 16:8   | 10:00–20:00    |
/// | 试过没坚持  | 16:8   | 14:10  | 12:00–20:00    |
/// | 有经验      | 16:8   | 18:6   | 12:00–20:00    |
///
/// 附加规则：
/// - Q1=改善体检指标 且 Q3=有经验 → 主推荐升级 18:6，备选 5:2（仅说明引导）；
/// - Q2=轮班/不规律 → 推荐理由提示「窗口可自由调整」（flexibleWindowHint）；
/// - 跳过/未答完问卷 → 默认 16:8（12:00–20:00）兜底，不阻断进首页。

/// 方案条目（方案库，M1 功能点 2）。
final class PlanOption {
  const PlanOption({
    required this.id,
    required this.eatStartMinutes,
    required this.eatEndMinutes,
    required this.isInfoOnly,
  });

  /// 14:10，进食窗口 10:00–20:00（D-03 零基础主推荐）。
  static const PlanOption p14x10 = PlanOption(
    id: '14:10',
    eatStartMinutes: 10 * 60,
    eatEndMinutes: 20 * 60,
    isInfoOnly: false,
  );

  /// 16:8，进食窗口 12:00–20:00（D-03 兜底/推荐）。
  static const PlanOption p16x8 = PlanOption(
    id: '16:8',
    eatStartMinutes: 12 * 60,
    eatEndMinutes: 20 * 60,
    isInfoOnly: false,
  );

  /// 18:6，进食窗口 12:00–18:00（D-03 有经验升级项）。
  static const PlanOption p18x6 = PlanOption(
    id: '18:6',
    eatStartMinutes: 12 * 60,
    eatEndMinutes: 18 * 60,
    isInfoOnly: false,
  );

  /// 5:2，仅说明引导，MVP 不提供完整计时流（D-03，V1.1 候选）。
  static const PlanOption p5x2 = PlanOption(
    id: '5:2',
    eatStartMinutes: null,
    eatEndMinutes: null,
    isInfoOnly: true,
  );

  /// 方案标识，如 `16:8`。
  final String id;

  /// 进食窗口开始：本地墙钟分钟数；[isInfoOnly] 方案为 null。
  final int? eatStartMinutes;

  /// 进食窗口结束：本地墙钟分钟数；[isInfoOnly] 方案为 null。
  final int? eatEndMinutes;

  /// 是否仅说明引导（5:2：不可一键启动计时）。
  final bool isInfoOnly;

  /// 转为 M2 引擎的 [FastingPlan]；[isInfoOnly] 方案返回 null。
  FastingPlan? toFastingPlan() {
    final start = eatStartMinutes;
    final end = eatEndMinutes;
    if (start == null || end == null) return null;
    return FastingPlan(id: id, eatStartMinutes: start, eatEndMinutes: end);
  }

  @override
  bool operator ==(Object other) =>
      other is PlanOption &&
      other.id == id &&
      other.eatStartMinutes == eatStartMinutes &&
      other.eatEndMinutes == eatEndMinutes &&
      other.isInfoOnly == isInfoOnly;

  @override
  int get hashCode =>
      Object.hash(id, eatStartMinutes, eatEndMinutes, isInfoOnly);

  @override
  String toString() => 'PlanOption($id, infoOnly: $isInfoOnly)';
}

/// 推荐理由模板 key（映射 i18n `onboarding.recommendation.reason.*`）。
enum RecommendationReason {
  beginner,
  triedButStopped,
  experienced,
  healthUpgrade,
  fallback,
}

/// 推荐结果（M1 功能点 3：1 个主方案 + ≥1 个备选）。
final class PlanRecommendation {
  const PlanRecommendation({
    required this.primary,
    required this.alternatives,
    required this.reason,
    required this.usedFallback,
    required this.flexibleWindowHint,
  });

  /// 主推荐方案。
  final PlanOption primary;

  /// 备选方案（≥1 个；5:2 仅说明引导，见 [PlanOption.isInfoOnly]）。
  final List<PlanOption> alternatives;

  /// 推荐理由模板 key。
  final RecommendationReason reason;

  /// 是否走了「跳过问卷」兜底（D-03：默认 16:8）。
  final bool usedFallback;

  /// Q2=轮班/不规律 → 推荐理由中提示「窗口可自由调整」（D-03）。
  final bool flexibleWindowHint;

  /// 用备选 [option] 替换主推荐（原主推荐降为备选）。
  PlanRecommendation promote(PlanOption option) {
    if (option.isInfoOnly || option == primary) return this;
    return PlanRecommendation(
      primary: option,
      alternatives: <PlanOption>[
        primary,
        for (final alt in alternatives)
          if (alt != option) alt,
      ],
      reason: reason,
      usedFallback: usedFallback,
      flexibleWindowHint: flexibleWindowHint,
    );
  }

  @override
  String toString() =>
      'PlanRecommendation(primary: $primary, alts: $alternatives, '
      'reason: $reason, fallback: $usedFallback, flex: $flexibleWindowHint)';
}

/// 推荐规则（D-03）。
///
/// [answers] 未答完（含跳过）→ 默认 16:8（12:00–20:00）兜底。
PlanRecommendation recommendPlan(OnboardingAnswers answers) {
  final flexible =
      answers.schedule == ScheduleAnswer.shiftWork ||
      answers.schedule == ScheduleAnswer.flexible;

  if (!answers.isComplete) {
    return PlanRecommendation(
      primary: PlanOption.p16x8,
      alternatives: const <PlanOption>[PlanOption.p14x10],
      reason: RecommendationReason.fallback,
      usedFallback: true,
      flexibleWindowHint: flexible,
    );
  }

  switch (answers.experience!) {
    case ExperienceAnswer.beginner:
      return PlanRecommendation(
        primary: PlanOption.p14x10,
        alternatives: const <PlanOption>[PlanOption.p16x8],
        reason: RecommendationReason.beginner,
        usedFallback: false,
        flexibleWindowHint: flexible,
      );
    case ExperienceAnswer.triedButStopped:
      return PlanRecommendation(
        primary: PlanOption.p16x8,
        alternatives: const <PlanOption>[PlanOption.p14x10],
        reason: RecommendationReason.triedButStopped,
        usedFallback: false,
        flexibleWindowHint: flexible,
      );
    case ExperienceAnswer.experienced:
      // D-03 附加规则：改善体检指标 + 有经验 → 升级 18:6，备选 5:2（仅说明）。
      if (answers.goal == GoalAnswer.improveHealth) {
        return PlanRecommendation(
          primary: PlanOption.p18x6,
          alternatives: const <PlanOption>[PlanOption.p5x2],
          reason: RecommendationReason.healthUpgrade,
          usedFallback: false,
          flexibleWindowHint: flexible,
        );
      }
      return PlanRecommendation(
        primary: PlanOption.p16x8,
        alternatives: const <PlanOption>[PlanOption.p18x6],
        reason: RecommendationReason.experienced,
        usedFallback: false,
        flexibleWindowHint: flexible,
      );
  }
}

/// 各进食时长的推荐窗口起点（本地墙钟分钟数，D-03 默认窗口表）：
/// 10h→10:00（14:10 零基础默认窗口）、8h→12:00、6h→12:00（16:8/18:6
/// 默认窗口）。自定义窗口编辑器「重置为推荐窗口」预填用。
/// [eatingHours] 非 6/8/10 抛 [ArgumentError]。
int recommendedStartMinutes(int eatingHours) {
  return switch (eatingHours) {
    10 => 10 * 60,
    8 => 12 * 60,
    6 => 12 * 60,
    _ => throw ArgumentError.value(
      eatingHours,
      'eatingHours',
      '进食时长只支持 6/8/10 小时',
    ),
  };
}
