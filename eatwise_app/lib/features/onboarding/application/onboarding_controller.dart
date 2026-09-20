import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/nutrition_goal.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/domain/window_rules.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/application/profile_sync.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_types.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// 新手引导状态与动作（M1：问卷流 → 档案采集（阶段 A，可跳过）→ 推荐 → 一键启动）。

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

/// 方案写入信号量：一键启动/换方案登记时 +1。
///
/// onboardingStoreProvider 是普通 Provider（返回存储句柄），ref.watch 它
/// 不会因 SharedPreferences 键值写入触发重建；FastingTimerController 改为
/// 监听本信号量，在方案写入/登记后重建（修复「启动方案后计时首页不刷新」）。
final planVersionProvider = StateProvider<int>((ref) => 0);

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
    this.pendingEffectiveDate,
  });

  /// 已写入的方案 id。
  final String planId;

  /// 每日热量目标（kcal）。
  final int targetKcal;

  /// 营养目标是否走了 D-04 兜底（true → 提示补全资料）。
  final bool usedFallback;

  /// 换方案登记（T12，D-06）的生效日（本地自然日）；
  /// null = 首次启动立即生效。
  final LocalDate? pendingEffectiveDate;
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
    // 登录态回写服务端 onboardingStatus=skipped（失败静默不阻塞）。
    ref.read(profileSyncServiceProvider).syncOnboardingSkipped();
    state = state.copyWith(
      answers: OnboardingAnswers.empty,
      currentStep: 0,
      recommendation: recommendPlan(OnboardingAnswers.empty),
    );
  }

  /// 档案页保存（阶段 A，D-18：单项可留空；空档案按未采集走兜底）。
  void saveProfile(OnboardingProfile profile) {
    _store.saveProfile(profile);
  }

  /// 已采集档案（档案页/设置页表单初值；未采集为 null）。
  OnboardingProfile? loadProfile() => _store.loadProfile();

  /// 把备选方案升为主推荐。
  void promoteAlternative(PlanOption option) {
    final rec = state.recommendation;
    if (rec == null) return;
    state = state.copyWith(recommendation: rec.promote(option));
  }

  /// 主推荐方案（与 [startPrimaryPlan] 无自定义窗口时同口径）。
  FastingPlan get _primaryPlan =>
      state.recommendation?.primary.toFastingPlan() ?? FastingPlan.plan16x8;

  /// 指定方案 [plan] 相对当前生效方案是否构成换方案（T12，D-06：已有生效
  /// 方案且**进食窗口不同** → 次日 0:00 本地生效）。窗口等价只比起止墙钟
  /// （[sameWindow]），自定义窗口 id 带 `@HH:mm` 后缀但窗口相同者视为
  /// 同方案（直接重写、立即生效）。
  bool isPlanChangeAgainst(FastingPlan plan) {
    final existing = _store.loadActivePlan();
    if (existing == null) return false;
    return !sameWindow(
      existing.plan.eatStartMinutes,
      existing.plan.eatEndMinutes,
      plan.eatStartMinutes,
      plan.eatEndMinutes,
    );
  }

  /// 一键启动是否走换方案链路（主推荐口径；确认弹窗据此先行明示）。
  bool get isPlanChange => isPlanChangeAgainst(_primaryPlan);

  /// 换方案生效日预览（本地次日，确认弹窗展示用）。
  LocalDate get planChangeEffectiveDate => localDateOf(
    ref.read(nowUtcProvider),
    ref.read(deviceLocationProvider),
  ).addDays(1);

  /// 一键启动（M1 功能点 4 / US-1.1；[window] 非空 = 自定义进食窗口，
  /// 方案取草稿构造的 [FastingPlan]，否则用主推荐）：
  /// - 首次启动（或窗口无变化重写）：立即写入用户方案、初始化进食窗口
  ///   （M2 引擎 resolveState 重算落点）；
  /// - 已有生效方案且窗口不同：走换方案链路（T12，D-06），登记
  ///   pendingPlan 次日 0:00 本地生效，当日锚点不动、已记录数据保留
  ///   不回算（生效动作见 FastingTimerController 的 T13 转正）；
  /// 两条路径都初始化每日营养目标（D-04，与断食窗口解耦故即时更新）、
  /// 标记引导完成；方案本地落盘/登记后置脏并尽力上行（PUT
  /// /fasting-plans/current，失败由同步引擎重试）。
  StartPlanResult startPrimaryPlan({FastingWindowDraft? window}) {
    final plan = window?.toFastingPlan() ?? _primaryPlan;
    final nowUtc = ref.read(nowUtcProvider);
    final location = ref.read(deviceLocationProvider);

    // 每日营养目标（D-04）：档案页（阶段 A）填齐有效数据 → 全参精准计算；
    // 缺项/跳过 → 兜底默认值，usedFallback=true 驱动「补全资料」提示。
    final goal = _computeAndSaveNutritionGoal();

    LocalDate? pendingEffectiveDate;
    if (isPlanChangeAgainst(plan)) {
      // 换方案（T12，D-06）：登记 pendingPlan，次日 0:00 本地生效；
      // 确认弹窗「新方案将于次日 0:00 生效」由 UI 层先行明示。
      final pending = schedulePlanChange(plan, nowUtc, location);
      _store.savePendingPlan(pending);
      pendingEffectiveDate = pending.effectiveDate;
    } else {
      // 首次启动：初始化进食窗口，按锚点重算当前落点（《规格-M2》§4.2）。
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
    }
    // 方案上行（进食窗口自选）：置脏 + fire-and-forget 尝试一次；
    // 失败保留脏标记，由 RecordSyncEngine 同步轮重试。
    ref.read(fastingPlanSyncProvider)?.markDirtyAndTryFlush(plan);

    _store.clearQuizProgress();
    _store.markOnboardingCompleted();
    ref.read(onboardingGateProvider).completed = true;
    // 登录态回写服务端（档案 + goal + onboardingStatus=completed；
    // 失败静默不阻塞本地流程）。
    ref
        .read(profileSyncServiceProvider)
        .syncOnboardingCompleted(
          profile: _store.loadProfile(),
          goal: state.answers.goal,
        );
    // 通知计时主控重建（信号量语义见 planVersionProvider 注释）。
    ref.read(planVersionProvider.notifier).state++;

    // 一键启动（核心转化事件，§1.5 立即上报；2.2 引导完成率分子）。
    final rec = state.recommendation;
    _analytics.track(
      'onboard_plan_start',
      properties: <String, Object?>{
        'plan_type': plan.id.replaceAll(':', '_'),
        'eating_window_start': _hhmm(plan.eatStartMinutes),
        'eating_window_end': _hhmm(plan.eatEndMinutes),
        'is_fallback': rec?.usedFallback ?? true,
        // 阶段 A：档案页填齐有效数据后营养目标走精准计算（非兜底）。
        'has_profile': !goal.usedFallback,
      },
      flushNow: true,
    );

    return StartPlanResult(
      planId: plan.id,
      targetKcal: goal.targetKcal,
      usedFallback: goal.usedFallback,
      pendingEffectiveDate: pendingEffectiveDate,
    );
  }

  /// 计算每日营养目标（D-04 + 阶段 B 缺口法；档案齐备走全参计算，
  /// 缺基础信息走兜底）。年龄由出生年按当前 UTC 年折算（与服务端
  /// computeTargets 同口径）；缺口法基准日为设备时区本地日。
  NutritionGoal _computeNutritionGoal() {
    final goalType = state.answers.goal == GoalAnswer.loseWeight
        ? NutritionGoalType.lose
        : NutritionGoalType.maintain;
    final profile = _store.loadProfile();
    final nowUtc = ref.read(nowUtcProvider);
    final currentYear = DateTime.fromMillisecondsSinceEpoch(
      nowUtc * 1000,
      isUtc: true,
    ).year;
    return computeNutritionGoal(
      profile?.toProfileInput(
            goal: goalType,
            currentYear: currentYear,
            today: localDateOf(nowUtc, ref.read(deviceLocationProvider)),
          ) ??
          UserProfileInput(goal: goalType),
      NutritionRuleConfig.defaults,
    );
  }

  /// 推荐页减重预览（阶段 B）：不落盘的试算，驱动「预计每周减 X kg」
  /// 与安全夹取/温和节奏提示。
  NutritionGoal previewNutritionGoal() => _computeNutritionGoal();

  /// 计算并落盘每日营养目标（D-04 + 阶段 B；兜底时驱动「补全资料」提示）。
  NutritionGoalSnapshot _computeAndSaveNutritionGoal() {
    final goal = _computeNutritionGoal();
    final snapshot = NutritionGoalSnapshot(
      targetKcal: goal.targetKcal,
      proteinG: goal.proteinG,
      carbG: goal.carbG,
      fatG: goal.fatG,
      usedFallback: goal.usedFallback,
      configVersion: goal.configVersion,
      weeklyRateKg: goal.weightLoss?.weeklyRateKg,
      weightLossClamped: goal.weightLoss?.clamped ?? false,
      reachDate: goal.weightLoss?.reachDate.toIsoString(),
    );
    _store.saveNutritionGoal(snapshot);
    return snapshot;
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
