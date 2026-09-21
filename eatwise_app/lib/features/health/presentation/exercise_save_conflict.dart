import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:flutter/material.dart';

/// 保存冲突处理结果：null = 用户取消（留在弹层，不丢输入）。
final class ExerciseConflictOutcome {
  const ExerciseConflictOutcome._({this.saved, this.replaced = const []});

  /// 「再加一条」/当日无冲突直接入账。
  ExerciseConflictOutcome.add(ExerciseLog saved) : this._(saved: saved);

  /// 「替换今天记录」。
  ExerciseConflictOutcome.replace(ExerciseSaveResult result)
    : this._(saved: result.saved, replaced: result.replaced);

  /// 新入账的行；null = 取消。
  final ExerciseLog? saved;

  /// 被替换掉的旧行快照（撤销恢复用）；空 = 纯新增。
  final List<ExerciseLog> replaced;
}

/// 保存前冲突检测 + 选择弹窗（手动记运动 / 截图导入共用同一语义）。
///
/// 背景：华为运动健康等截图是全天汇总，同一天重复导入或再次录入时，旧
/// 逻辑只会追加，当天消耗被重复累计。当日已有记录时让用户二选一：
/// 再加一条 / 替换今天记录（取消 = 留在弹层）。
///
/// 返回 [ExerciseConflictOutcome]（saved 非空 = 已入账）；null = 取消。
Future<ExerciseConflictOutcome?> saveExerciseWithConflict({
  required BuildContext context,
  required Translations t,
  required ExerciseLogRepository repo,
  required String typeKey,
  required int durationMin,
  required double kcal,
  String? source,
  int? steps,
}) async {
  final existing = await repo.todayLogs();
  if (existing.isNotEmpty) {
    if (!context.mounted) return null;
    final totalKcal = existing.fold<double>(0, (sum, log) => sum + log.kcal);
    final mode = await showDialog<ExerciseConflictMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.record.exercise.conflict.title),
        content: Text(
          t.record.exercise.conflict.body(
            count: existing.length,
            kcal: totalKcal.round(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('exercise.conflict.cancel'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.common.action.cancel),
          ),
          TextButton(
            key: const ValueKey<String>('exercise.conflict.add'),
            onPressed: () =>
                Navigator.pop(dialogContext, ExerciseConflictMode.add),
            child: Text(t.record.exercise.conflict.add),
          ),
          TextButton(
            key: const ValueKey<String>('exercise.conflict.replace'),
            onPressed: () =>
                Navigator.pop(dialogContext, ExerciseConflictMode.replace),
            child: Text(t.record.exercise.conflict.replace),
          ),
        ],
      ),
    );
    if (mode == null) return null;
    if (mode == ExerciseConflictMode.replace) {
      final result = await repo.replaceToday(
        typeKey: typeKey,
        durationMin: durationMin,
        kcal: kcal,
        source: source,
        steps: steps,
      );
      return ExerciseConflictOutcome.replace(result);
    }
  }
  final saved = await repo.add(
    typeKey: typeKey,
    durationMin: durationMin,
    kcal: kcal,
    source: source,
    steps: steps,
  );
  return ExerciseConflictOutcome.add(saved);
}

/// 冲突弹窗的用户选择。
enum ExerciseConflictMode { add, replace }
