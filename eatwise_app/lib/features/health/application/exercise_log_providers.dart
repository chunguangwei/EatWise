import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/data/exercise_screenshot_service.dart';
import 'package:eatwise/features/health/data/remote_exercise_log_sync.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart'
    show localDateKey;
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show onDeviceRecognitionActive;
import 'package:eatwise/features/streak/application/streak_controller.dart'
    show currentUserIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 手动记运动仓库（两态 pending/synced，经同步引擎上行云端——仅登录态
/// 生效，匿名本地 pending 保留）。
/// userId 与饮食记录仓储同口径（[currentUserIdProvider]）。
final Provider<ExerciseLogRepository> exerciseLogRepositoryProvider =
    Provider<ExerciseLogRepository>((ref) {
      return ExerciseLogRepository(
        db: ref.watch(appDatabaseProvider),
        userId: ref.watch(currentUserIdProvider),
      );
    });

/// 运动记录上行同步端（两态 pending/synced，挂 recordSyncEngineProvider
/// 触发链，与饮水同口径）。
final Provider<RemoteExerciseLogSync> exerciseLogSyncProvider =
    Provider<RemoteExerciseLogSync>((ref) {
      return RemoteExerciseLogSync(dio: ref.watch(apiDioProvider));
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

/// 今日手动/截图落库步数合计流（数据页「步数」展示 = 系统步数（如有）
/// + 本合计；数据库未装配时降级 0，与 [todayExerciseKcalProvider] 同口径）。
final StreamProvider<int> todayExerciseStepsProvider = StreamProvider<int>((
  ref,
) {
  try {
    return ref
        .watch(exerciseLogRepositoryProvider)
        .watchTotalStepsForDate(localDateKey(DateTime.now()));
  } on Object {
    return Stream<int>.value(0);
  }
});

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

/// 运动截图识别服务（端侧视觉，与拍照识别共用引擎与就绪判定）。
/// 端侧未就绪 → null：入口前置已由 ai_engine_guide_card 引导卡覆盖
/// 「无任何引擎」场景；仅配云端 API（无视觉链路）时同样为 null，UI 走
/// 「识别不可用」snackbar 兜底（与拍照识别 stub 口径一致）。
final Provider<ExerciseScreenshotService?> exerciseScreenshotServiceProvider =
    Provider<ExerciseScreenshotService?>((ref) {
      if (!onDeviceRecognitionActive(ref)) return null;
      final manager = ref.watch(onDeviceModelManagerProvider);
      return OnDeviceExerciseScreenshotService(
        gateway: ref.watch(onDeviceLlmGatewayProvider),
        modelPath: manager.modelPath,
      );
    });
