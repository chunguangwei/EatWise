import 'dart:convert';

import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新手引导本地持久化（M1：进度本地保存可续答 / 方案与营养目标写入）。
///
/// 实现基于 shared_preferences（MVP 单用户本地键值；M7 账号落地后随用户
/// 数据迁移，见 D-20 同步策略）。所有读取为同步（SharedPreferences 内存
/// 缓存），写入为 fire-and-forget（失败不阻断引导主流程〔假设〕）。

/// 问卷进度（可续答）。
final class QuizProgress {
  const QuizProgress({required this.answers, required this.currentStep});

  /// 已作答答案（question.name → option.name）。
  final Map<String, String> answers;

  /// 当前题号下标（0-based）。
  final int currentStep;

  static QuizProgress fromJson(Map<String, dynamic> json) {
    return QuizProgress(
      answers: (json['answers']! as Map<String, dynamic>).cast(),
      currentStep: json['currentStep']! as int,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'answers': answers,
    'currentStep': currentStep,
  };
}

/// 一键启动写入的方案快照（M1 功能点 4 + M2 引擎初始化结果）。
final class ActivePlanSnapshot {
  const ActivePlanSnapshot({
    required this.plan,
    required this.initialState,
    required this.startedAtUtc,
    this.targetUtc,
    this.attributionDate,
  });

  /// 用户选定方案（M2 [FastingPlan]，窗口为本地墙钟表达）。
  final FastingPlan plan;

  /// 启动时刻经 `resolveState` 重算的应用级状态名（如 `fasting`）。
  final String initialState;

  /// 倒计时目标锚点（UTC epoch 秒，见 [FastingSnapshot.targetUtc]）。
  final int? targetUtc;

  /// 归属日预览（ISO 日期，见 [FastingSnapshot.attributionPreview]）。
  final String? attributionDate;

  /// 启动时刻（UTC epoch 秒）。
  final int startedAtUtc;

  static ActivePlanSnapshot fromJson(Map<String, dynamic> json) {
    return ActivePlanSnapshot(
      plan: FastingPlan(
        id: json['planId']! as String,
        eatStartMinutes: json['eatStartMinutes']! as int,
        eatEndMinutes: json['eatEndMinutes']! as int,
      ),
      initialState: json['initialState']! as String,
      targetUtc: json['targetUtc'] as int?,
      attributionDate: json['attributionDate'] as String?,
      startedAtUtc: json['startedAtUtc']! as int,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'planId': plan.id,
    'eatStartMinutes': plan.eatStartMinutes,
    'eatEndMinutes': plan.eatEndMinutes,
    'initialState': initialState,
    'targetUtc': targetUtc,
    'attributionDate': attributionDate,
    'startedAtUtc': startedAtUtc,
  };
}

/// 每日营养目标快照（D-04 计算结果落地）。
final class NutritionGoalSnapshot {
  const NutritionGoalSnapshot({
    required this.targetKcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.usedFallback,
    required this.configVersion,
  });

  final int targetKcal;
  final int proteinG;
  final int carbG;
  final int fatG;

  /// 是否走了 D-04 兜底（驱动「补全资料」引导）。
  final bool usedFallback;
  final String configVersion;

  static NutritionGoalSnapshot fromJson(Map<String, dynamic> json) {
    return NutritionGoalSnapshot(
      targetKcal: json['targetKcal']! as int,
      proteinG: json['proteinG']! as int,
      carbG: json['carbG']! as int,
      fatG: json['fatG']! as int,
      usedFallback: json['usedFallback']! as bool,
      configVersion: json['configVersion']! as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'targetKcal': targetKcal,
    'proteinG': proteinG,
    'carbG': carbG,
    'fatG': fatG,
    'usedFallback': usedFallback,
    'configVersion': configVersion,
  };
}

/// 存储抽象（测试可换内存实现）。
abstract interface class OnboardingStore {
  bool get isOnboardingCompleted;
  void markOnboardingCompleted();

  QuizProgress? loadQuizProgress();
  void saveQuizProgress(QuizProgress progress);
  void clearQuizProgress();

  ActivePlanSnapshot? loadActivePlan();
  void saveActivePlan(ActivePlanSnapshot snapshot);

  /// 待生效方案（T12，D-06：换方案次日 0:00 本地生效）。
  PendingPlan? loadPendingPlan();
  void savePendingPlan(PendingPlan pending);
  void clearPendingPlan();

  NutritionGoalSnapshot? loadNutritionGoal();
  void saveNutritionGoal(NutritionGoalSnapshot snapshot);
}

/// SharedPreferences 实现。
final class SharedPreferencesOnboardingStore implements OnboardingStore {
  SharedPreferencesOnboardingStore(this._prefs);

  static const String _keyCompleted = 'onboarding.completed';
  static const String _keyQuizProgress = 'onboarding.quizProgress';
  static const String _keyActivePlan = 'onboarding.activePlan';
  static const String _keyPendingPlan = 'onboarding.pendingPlan';
  static const String _keyNutritionGoal = 'onboarding.nutritionGoal';

  final SharedPreferences _prefs;

  @override
  bool get isOnboardingCompleted => _prefs.getBool(_keyCompleted) ?? false;

  @override
  void markOnboardingCompleted() {
    _prefs.setBool(_keyCompleted, true);
  }

  @override
  QuizProgress? loadQuizProgress() =>
      _readJson(_keyQuizProgress, QuizProgress.fromJson);

  @override
  void saveQuizProgress(QuizProgress progress) {
    _prefs.setString(_keyQuizProgress, jsonEncode(progress.toJson()));
  }

  @override
  void clearQuizProgress() {
    _prefs.remove(_keyQuizProgress);
  }

  @override
  ActivePlanSnapshot? loadActivePlan() =>
      _readJson(_keyActivePlan, ActivePlanSnapshot.fromJson);

  @override
  void saveActivePlan(ActivePlanSnapshot snapshot) {
    _prefs.setString(_keyActivePlan, jsonEncode(snapshot.toJson()));
  }

  @override
  PendingPlan? loadPendingPlan() =>
      _readJson(_keyPendingPlan, _pendingPlanFromJson);

  @override
  void savePendingPlan(PendingPlan pending) {
    _prefs.setString(
      _keyPendingPlan,
      jsonEncode(<String, dynamic>{
        'planId': pending.plan.id,
        'eatStartMinutes': pending.plan.eatStartMinutes,
        'eatEndMinutes': pending.plan.eatEndMinutes,
        'effectiveDate': pending.effectiveDate.toIsoString(),
        'effectiveUtc': pending.effectiveUtc,
      }),
    );
  }

  @override
  void clearPendingPlan() {
    _prefs.remove(_keyPendingPlan);
  }

  static PendingPlan _pendingPlanFromJson(Map<String, dynamic> json) {
    final parts = (json['effectiveDate']! as String).split('-');
    return PendingPlan(
      plan: FastingPlan(
        id: json['planId']! as String,
        eatStartMinutes: json['eatStartMinutes']! as int,
        eatEndMinutes: json['eatEndMinutes']! as int,
      ),
      effectiveDate: LocalDate(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      ),
      effectiveUtc: json['effectiveUtc']! as int,
    );
  }

  @override
  NutritionGoalSnapshot? loadNutritionGoal() =>
      _readJson(_keyNutritionGoal, NutritionGoalSnapshot.fromJson);

  @override
  void saveNutritionGoal(NutritionGoalSnapshot snapshot) {
    _prefs.setString(_keyNutritionGoal, jsonEncode(snapshot.toJson()));
  }

  T? _readJson<T>(String key, T Function(Map<String, dynamic>) decode) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null; // 本地数据损坏按无进度处理（防御）
    }
  }
}

/// 内存实现（单元/组件测试用）。
final class InMemoryOnboardingStore implements OnboardingStore {
  bool _completed = false;
  QuizProgress? _progress;
  ActivePlanSnapshot? _plan;
  PendingPlan? _pending;
  NutritionGoalSnapshot? _goal;

  @override
  bool get isOnboardingCompleted => _completed;

  @override
  void markOnboardingCompleted() => _completed = true;

  @override
  QuizProgress? loadQuizProgress() => _progress;

  @override
  void saveQuizProgress(QuizProgress progress) => _progress = progress;

  @override
  void clearQuizProgress() => _progress = null;

  @override
  ActivePlanSnapshot? loadActivePlan() => _plan;

  @override
  void saveActivePlan(ActivePlanSnapshot snapshot) => _plan = snapshot;

  @override
  PendingPlan? loadPendingPlan() => _pending;

  @override
  void savePendingPlan(PendingPlan pending) => _pending = pending;

  @override
  void clearPendingPlan() => _pending = null;

  @override
  NutritionGoalSnapshot? loadNutritionGoal() => _goal;

  @override
  void saveNutritionGoal(NutritionGoalSnapshot snapshot) => _goal = snapshot;
}
