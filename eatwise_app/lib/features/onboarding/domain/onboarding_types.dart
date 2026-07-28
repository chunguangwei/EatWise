/// 新手问卷类型定义（M1，D-02：3 题单选，可跳过）。
library;

/// 问卷题目（顺序即展示顺序）。
enum QuizQuestion { q1, q2, q3 }

/// Q1 目标（D-02）。
enum GoalAnswer { loseWeight, improveHealth, adjustSchedule, justTrying }

/// Q2 作息（D-02）。
enum ScheduleAnswer { regular, shiftWork, flexible }

/// Q3 经验（D-02）。
enum ExperienceAnswer { beginner, triedButStopped, experienced }

/// 问卷答案集（逐题作答，允许部分完成——进度本地保存可续答，PRD M1 异常与边界）。
final class OnboardingAnswers {
  const OnboardingAnswers({this.goal, this.schedule, this.experience});

  /// 空答案（等价于「跳过问卷」）。
  static const OnboardingAnswers empty = OnboardingAnswers();

  final GoalAnswer? goal;
  final ScheduleAnswer? schedule;
  final ExperienceAnswer? experience;

  /// 3 题全部作答。
  bool get isComplete => goal != null && schedule != null && experience != null;

  OnboardingAnswers copyWith({
    GoalAnswer? goal,
    ScheduleAnswer? schedule,
    ExperienceAnswer? experience,
  }) {
    return OnboardingAnswers(
      goal: goal ?? this.goal,
      schedule: schedule ?? this.schedule,
      experience: experience ?? this.experience,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnboardingAnswers &&
      other.goal == goal &&
      other.schedule == schedule &&
      other.experience == experience;

  @override
  int get hashCode => Object.hash(goal, schedule, experience);

  @override
  String toString() => 'OnboardingAnswers($goal, $schedule, $experience)';
}
