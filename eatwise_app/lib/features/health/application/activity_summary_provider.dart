import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/domain/exercise_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页与数据页共享同一活动汇总，不把步数换算结果或手动记录叠加到系统汇总。
final activitySummaryProvider = Provider((ref) {
  final health = ref.watch(healthSyncControllerProvider);
  final system = health.status == HealthSyncStatus.ready ? health.today : null;
  final manualKcal = ref.watch(todayExerciseKcalProvider).valueOrNull;
  final systemKcal = system?.activeEnergyKcal;
  return (
    burnKcal: mergeBurnKcal(systemKcal: systemKcal, manualKcal: manualKcal),
    steps: mergeSteps(
      systemSteps: system?.steps,
      manualSteps: ref.watch(todayExerciseStepsProvider).valueOrNull,
    ),
    systemEnergy: systemKcal != null && systemKcal.isFinite && systemKcal >= 0,
    manualKcal: manualKcal != null && manualKcal.isFinite && manualKcal > 0
        ? manualKcal
        : null,
  );
});
