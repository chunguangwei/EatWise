import 'package:eatwise/features/health/domain/exercise_goals.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show sharedPreferencesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 运动目标本地偏好存储（SharedPreferences；只存目标值，非健康数据）。
abstract interface class ExerciseGoalsStore {
  ExerciseGoals load();
  Future<void> save(ExerciseGoals goals);
}

final class SharedPreferencesExerciseGoalsStore implements ExerciseGoalsStore {
  SharedPreferencesExerciseGoalsStore(this._prefs);

  static const String _burnKey = 'health.burnGoalKcal.v1';
  static const String _stepsKey = 'health.stepsGoal.v1';

  final SharedPreferences _prefs;

  @override
  ExerciseGoals load() {
    return ExerciseGoals(
      burnGoalKcal:
          _prefs.getDouble(_burnKey) ?? ExerciseGoals.defaultBurnGoalKcal,
      stepsGoal: _prefs.getInt(_stepsKey) ?? ExerciseGoals.defaultStepsGoal,
    );
  }

  @override
  Future<void> save(ExerciseGoals goals) async {
    await _prefs.setDouble(_burnKey, goals.burnGoalKcal);
    await _prefs.setInt(_stepsKey, goals.stepsGoal);
  }
}

/// 内存兜底（SharedPreferences 未装配的测试/预览场景，进程内有效）。
final class InMemoryExerciseGoalsStore implements ExerciseGoalsStore {
  ExerciseGoals _goals = const ExerciseGoals();

  @override
  ExerciseGoals load() => _goals;

  @override
  Future<void> save(ExerciseGoals goals) async {
    _goals = goals;
  }
}

final exerciseGoalsStoreProvider = Provider<ExerciseGoalsStore>((ref) {
  try {
    return SharedPreferencesExerciseGoalsStore(
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return InMemoryExerciseGoalsStore();
  }
});

/// 运动目标控制器：读取即默认值；修改立即持久化并刷新状态
///（数据页「今日消耗」卡与设置页同 watch 一个 provider，变更即时生效）。
final class ExerciseGoalsController extends StateNotifier<ExerciseGoals> {
  ExerciseGoalsController({required ExerciseGoalsStore store})
    : _store = store,
      super(store.load());

  final ExerciseGoalsStore _store;

  Future<void> setBurnGoalKcal(double kcal) async {
    if (!ExerciseGoals.isValidBurnGoal(kcal)) return;
    final next = state.copyWith(burnGoalKcal: kcal);
    state = next;
    await _store.save(next);
  }

  Future<void> setStepsGoal(int steps) async {
    if (!ExerciseGoals.isValidStepsGoal(steps)) return;
    final next = state.copyWith(stepsGoal: steps);
    state = next;
    await _store.save(next);
  }
}

final exerciseGoalsProvider =
    StateNotifierProvider<ExerciseGoalsController, ExerciseGoals>((ref) {
      return ExerciseGoalsController(
        store: ref.watch(exerciseGoalsStoreProvider),
      );
    });
