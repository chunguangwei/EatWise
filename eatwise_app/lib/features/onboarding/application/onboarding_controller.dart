import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// 新手引导状态与动作（M1：问卷流 → 推荐 → 一键启动）。

/// SharedPreferences 实例（main 中 await 获取后 override 注入）。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider 需在 main/测试中 override');
});

/// 引导存储。
final onboardingStoreProvider = Provider<OnboardingStore>((ref) {
  return SharedPreferencesOnboardingStore(ref.watch(sharedPreferencesProvider));
});

/// 引导门禁（与路由共享同一实例；main/测试中 override）。
final onboardingGateProvider = Provider<OnboardingGate>((ref) {
  throw UnimplementedError('onboardingGateProvider 需在 main/测试中 override');
});

/// 当前时刻（UTC epoch 秒；测试可 override 注入固定时钟）。
final nowUtcProvider = Provider<int>((ref) {
  return DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
});

/// 设备时区（D-07：UTC 存储本地渲染）。
///
/// 〔假设〕MVP 上架区域为中国区（D-15），默认 Asia/Shanghai；
/// 时区数据库未初始化（如单元测试未注入）时回退 UTC。
/// 〔待外部确认〕设备 IANA 时区名获取（如 flutter_timezone）属 M2 运行时接线。
final deviceLocationProvider = Provider<tz.Location>((ref) {
  try {
    return tz.getLocation('Asia/Shanghai');
  } on Object {
    return tz.UTC;
  }
});

/// 一键启动结果（驱动兜底提示）。
final class StartPlanResult {
  const StartPlanResult({
    required this.planId,
    required this.targetKcal,
    required this.usedFallback,
  });

  /// 已写入的方案 id。
  final String planId;

  /// 每日热量目标（kcal）。
  final int targetKcal;

  /// 营养目标是否走了 D-04 兜底（true → 提示补全资料）。
  final bool usedFallback;
}

/// 引导流程状态。
final class OnboardingState {
  const OnboardingState({
    required this.answers,
    required this.currentStep,
    this.recommendation,
  });

  /// 当前已作答答案（含续答恢复的部分答案）。
  final OnboardingAnswers answers;

  /// 当前题号下标（0-based，0..2）。
  final int currentStep;

  /// 推荐结果（答完 3 题或跳过后非空）。
  final PlanRecommendation? recommendation;

  OnboardingState copyWith({
    OnboardingAnswers? answers,
    int? currentStep,
    PlanRecommendation? recommendation,
  }) {
    return OnboardingState(
      answers: answers ?? this.answers,
      currentStep: currentStep ?? this.currentStep,
      recommendation: recommendation ?? this.recommendation,
    );
  }
}

/// 引导控制器：答题/续答/跳过/推荐/一键启动。
final class OnboardingController extends Notifier<OnboardingState> {
  static const int questionCount = 3;

  OnboardingStore get _store => ref.read(onboardingStoreProvider);

  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  /// 当前题进入时刻（`onboard_question_answer.duration_ms`，§3.1）。
  int _questionShownAtMs = DateTime.now().millisecondsSinceEpoch;

  @override
  OnboardingState build() {
    // 续答：恢复本地保存的进度（PRD M1 异常与边界）。
    final progress = _store.loadQuizProgress();
    _questionShownAtMs = DateTime.now().millisecondsSinceEpoch;
    return OnboardingState(
      answers: _decodeAnswers(progress?.answers ?? const <String, String>{}),
      currentStep: (progress?.currentStep ?? 0).clamp(0, questionCount - 1),
    );
  }

  /// 选择当前题答案并保存进度。
  void selectAnswer(String optionName) {
    final answers = _encodeAnswers(state.answers)
      ..[_questionKey(state.currentStep)] = optionName;
    _store.saveQuizProgress(
      QuizProgress(answers: answers, currentStep: state.currentStep),
    );
    state = state.copyWith(answers: _decodeAnswers(answers));
  }

  /// 当前题是否已作答（决定「继续」按钮可用性）。
  bool get currentAnswered => switch (state.currentStep) {
    0 => state.answers.goal != null,
    1 => state.answers.schedule != null,
    _ => state.answers.experience != null,
  };

  /// 下一题。
  void nextStep() {
    if (state.currentStep >= questionCount - 1) return;
    _trackQuestionAnswer();
    final step = state.currentStep + 1;
    _store.saveQuizProgress(
      QuizProgress(answers: _encodeAnswers(state.answers), currentStep: step),
    );
    _questionShownAtMs = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(currentStep: step);
  }

  /// 上一题。
  void previousStep() {
    if (state.currentStep <= 0) return;
    _questionShownAtMs = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(currentStep: state.currentStep - 1);
  }

  /// 答完 3 题 → 生成推荐（D-03），清掉续答进度。
  void finishQuiz() {
    _trackQuestionAnswer();
    _store.clearQuizProgress();
    state = state.copyWith(recommendation: recommendPlan(state.answers));
  }

  /// 每题完成埋点（`onboard_question_answer`，§3.1：选中并切至下一题时）。
  void _trackQuestionAnswer() {
    final step = state.currentStep;
    final optionName = _encodeAnswers(state.answers)[_questionKey(step)];
    if (optionName == null) return;
    _analytics.track(
      'onboard_question_answer',
      properties: <String, Object?>{
        'question_index': step + 1,
        'question_key': _questionEventKey(step),
        'option_value': _optionEventValue(step, optionName),
        'duration_ms':
            DateTime.now().millisecondsSinceEpoch - _questionShownAtMs,
      },
    );
  }

  /// 跳过问卷 → 默认 16:8 兜底（D-03），不阻断进首页。
  void skipQuiz() {
    _analytics.track(
      'onboard_skip_click',
      properties: <String, Object?>{'at_step': state.currentStep + 1},
    );
    _store.clearQuizProgress();
    state = state.copyWith(
      answers: OnboardingAnswers.empty,
      currentStep: 0,
      recommendation: recommendPlan(OnboardingAnswers.empty),
    );
  }

  /// 把备选方案升为主推荐。
  void promoteAlternative(PlanOption option) {
    final rec = state.recommendation;
    if (rec == null) return;
    state = state.copyWith(recommendation: rec.promote(option));
  }

  /// 一键启动（M1 功能点 4 / US-1.1）：
  /// 写入用户方案、初始化进食窗口（M2 引擎 resolveState 重算落点）、
  /// 初始化每日营养目标（D-04，缺基础信息走兜底并提示补全）、标记引导完成。
  StartPlanResult startPrimaryPlan() {
    final plan =
        state.recommendation?.primary.toFastingPlan() ?? FastingPlan.plan16x8;
    final nowUtc = ref.read(nowUtcProvider);
    final location = ref.read(deviceLocationProvider);

    // 初始化进食窗口：按锚点重算当前落点（《规格-M2》§4.2）。
    final snapshot = resolveState(nowUtc, plan, location);
    _store.saveActivePlan(
      ActivePlanSnapshot(
        plan: plan,
        initialState: snapshot.state.name,
        targetUtc: snapshot.targetUtc,
        attributionDate: snapshot.attributionPreview?.toIsoString(),
        startedAtUtc: nowUtc,
      ),
    );

    // 每日营养目标（D-04）：问卷不含身高体重等基础信息 → 兜底默认值，
    // usedFallback=true 驱动「补全资料」提示。
    final goalType = state.answers.goal == GoalAnswer.loseWeight
        ? NutritionGoalType.lose
        : NutritionGoalType.maintain;
    final goal = computeNutritionGoal(
      UserProfileInput(goal: goalType),
      NutritionRuleConfig.defaults,
    );
    _store.saveNutritionGoal(
      NutritionGoalSnapshot(
        targetKcal: goal.targetKcal,
        proteinG: goal.proteinG,
        carbG: goal.carbG,
        fatG: goal.fatG,
        usedFallback: goal.usedFallback,
        configVersion: goal.configVersion,
      ),
    );

    _store.clearQuizProgress();
    _store.markOnboardingCompleted();
    ref.read(onboardingGateProvider).completed = true;

    // 一键启动（核心转化事件，§1.5 立即上报；2.2 引导完成率分子）。
    final rec = state.recommendation;
    _analytics.track(
      'onboard_plan_start',
      properties: <String, Object?>{
        'plan_type': plan.id.replaceAll(':', '_'),
        'eating_window_start': _hhmm(plan.eatStartMinutes),
        'eating_window_end': _hhmm(plan.eatEndMinutes),
        'is_fallback': rec?.usedFallback ?? true,
        // 问卷不含身高体重等基础信息（D-04 走兜底）→ has_profile=false。
        'has_profile': false,
      },
      flushNow: true,
    );

    return StartPlanResult(
      planId: plan.id,
      targetKcal: goal.targetKcal,
      usedFallback: goal.usedFallback,
    );
  }

  static String _questionKey(int step) => switch (step) {
    0 => 'q1',
    1 => 'q2',
    _ => 'q3',
  };

  /// 事件字典 question_key 枚举（§3.1，D-02 三题）。
  static String _questionEventKey(int step) => switch (step) {
    0 => 'goal',
    1 => 'schedule',
    _ => 'experience',
  };

  /// 事件字典 option_value 枚举（附录 A，对齐 D-02 选项表）。
  static String _optionEventValue(int step, String optionName) {
    return switch ((step, optionName)) {
      (0, 'loseWeight') => 'fat_loss',
      (0, 'improveHealth') => 'health_metrics',
      (0, 'adjustSchedule') => 'schedule',
      (0, _) => 'just_try',
      (1, 'shiftWork') => 'shift_work',
      (1, 'flexible') => 'flexible',
      (1, _) => 'regular',
      (2, 'triedButStopped') => 'tried_failed',
      (2, 'experienced') => 'experienced',
      (_, _) => 'beginner',
    };
  }

  static String _hhmm(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  static Map<String, String> _encodeAnswers(OnboardingAnswers answers) {
    return <String, String>{
      if (answers.goal != null) 'q1': answers.goal!.name,
      if (answers.schedule != null) 'q2': answers.schedule!.name,
      if (answers.experience != null) 'q3': answers.experience!.name,
    };
  }

  static OnboardingAnswers _decodeAnswers(Map<String, String> raw) {
    T? find<T extends Enum>(String key, List<T> values) {
      final name = raw[key];
      if (name == null) return null;
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    return OnboardingAnswers(
      goal: find('q1', GoalAnswer.values),
      schedule: find('q2', ScheduleAnswer.values),
      experience: find('q3', ExperienceAnswer.values),
    );
  }
}

/// 引导控制器 Provider。
final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
