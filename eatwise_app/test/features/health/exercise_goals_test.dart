import 'package:eatwise/features/health/application/exercise_goals_controller.dart';
import 'package:eatwise/features/health/domain/exercise_goals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 运动目标（薄荷走查 P2）：进度纯函数 + SharedPreferences 持久化 +
/// 控制器校验与即时生效。
void main() {
  group('exerciseGoalProgress（环进度纯函数）', () {
    test('零值/半值/超目标封顶/非法目标', () {
      expect(exerciseGoalProgress(value: 0, goal: 200), 0);
      expect(exerciseGoalProgress(value: 100, goal: 200), 0.5);
      expect(exerciseGoalProgress(value: 200, goal: 200), 1.0);
      // 超目标：弧长封顶 1.0（文案仍展示真实 X/目标 Y）。
      expect(exerciseGoalProgress(value: 500, goal: 200), 1.0);
      // 防御：目标 ≤0 不出 NaN/负值。
      expect(exerciseGoalProgress(value: 100, goal: 0), 0);
      expect(exerciseGoalProgress(value: -50, goal: 200), 0);
    });
  });

  group('SharedPreferencesExerciseGoalsStore（目标持久化）', () {
    test('默认 200 kcal / 5000 步；保存后重载生效', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesExerciseGoalsStore(prefs);

      final defaults = store.load();
      expect(defaults.burnGoalKcal, ExerciseGoals.defaultBurnGoalKcal);
      expect(defaults.stepsGoal, ExerciseGoals.defaultStepsGoal);

      await store.save(const ExerciseGoals(burnGoalKcal: 350, stepsGoal: 8000));
      // 重开（新实例读同一 prefs）仍生效。
      final reloaded = SharedPreferencesExerciseGoalsStore(prefs).load();
      expect(reloaded.burnGoalKcal, 350);
      expect(reloaded.stepsGoal, 8000);
    });
  });

  group('ExerciseGoalsController（校验 + 即时生效）', () {
    test('合法修改落盘并刷新状态；越界拒绝', () async {
      final store = InMemoryExerciseGoalsStore();
      final controller = ExerciseGoalsController(store: store);
      addTearDown(controller.dispose);

      expect(controller.state.burnGoalKcal, 200);
      expect(controller.state.stepsGoal, 5000);

      await controller.setBurnGoalKcal(300);
      expect(controller.state.burnGoalKcal, 300);
      expect(store.load().burnGoalKcal, 300);

      await controller.setStepsGoal(8000);
      expect(controller.state.stepsGoal, 8000);
      expect(store.load().stepsGoal, 8000);

      // 越界拒绝：状态与落盘均不变。
      await controller.setBurnGoalKcal(10);
      await controller.setStepsGoal(100);
      expect(controller.state.burnGoalKcal, 300);
      expect(controller.state.stepsGoal, 8000);
    });
  });
}
