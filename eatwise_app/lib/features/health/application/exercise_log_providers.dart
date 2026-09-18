import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 手动记运动仓库（设备级纯本地，不经同步引擎）。
/// userId 与饮食记录仓储同口径（[currentUserIdProvider]）。
final Provider<ExerciseLogRepository> exerciseLogRepositoryProvider =
    Provider<ExerciseLogRepository>((ref) {
      return ExerciseLogRepository(
        db: ref.watch(appDatabaseProvider),
        userId: ref.watch(currentUserIdProvider),
      );
    });

/// 今日手动运动消耗合计流（kcal；首页预算行 / 数据页消耗卡合并数据源）。
///
/// 数据库未装配（测试/预览仅注入其他仓储）时降级 0，与
/// `todayWaterTotalProvider` 的兜底口径一致。
final StreamProvider<double> todayExerciseKcalProvider = StreamProvider<double>(
  (ref) {
    try {
      return ref
          .watch(exerciseLogRepositoryProvider)
          .watchTotalKcalForDate(localDateKey(DateTime.now()));
    } on Object {
      return Stream<double>.value(0);
    }
  },
);

/// 今日手动运动记录流（记运动弹层今日列表 / 数据页展示用）。
final StreamProvider<List<ExerciseLog>> todayExerciseLogsProvider =
    StreamProvider<List<ExerciseLog>>((ref) {
      try {
        return ref
            .watch(exerciseLogRepositoryProvider)
            .watchLogsForDate(localDateKey(DateTime.now()));
      } on Object {
        return Stream<List<ExerciseLog>>.value(const <ExerciseLog>[]);
      }
    });
