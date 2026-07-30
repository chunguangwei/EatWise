import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/update/update_checker.dart';
import 'package:eatwise/core/update/update_launcher.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_throttle.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 当前 App 版本（package_info_plus；测试注入固定值）。
final currentAppVersionProvider = Provider<Future<String> Function()>((ref) {
  return () async => (await PackageInfo.fromPlatform()).version;
});

/// 更新检查器（dio 走全局装配：请求头/信封解包/错误映射）。
final updateCheckerProvider = Provider<UpdateChecker>((ref) {
  return UpdateChecker(
    dio: ref.watch(apiDioProvider),
    currentVersion: ref.watch(currentAppVersionProvider),
  );
});

/// 更新跳转器（测试注入假 launch）。
final updateLauncherProvider = Provider<UpdateLauncher>((ref) {
  return const UpdateLauncher();
});

/// 启动检查节流（SharedPreferences，间隔 ≥24h〔假设〕）。
final updateThrottleProvider = Provider<UpdateCheckThrottle>((ref) {
  return UpdateCheckThrottle(ref.watch(sharedPreferencesProvider));
});

/// 更新检查协调器：启动静默检查（节流 + 异常静默）与手动检查（不节流）。
final updateCoordinatorProvider = Provider<UpdateCheckCoordinator>((ref) {
  return UpdateCheckCoordinator(
    checker: ref.watch(updateCheckerProvider),
    throttle: ref.watch(updateThrottleProvider),
  );
});

final class UpdateCheckCoordinator {
  UpdateCheckCoordinator({required this.checker, required this.throttle});

  final UpdateChecker checker;
  final UpdateCheckThrottle throttle;

  /// 启动静默检查：节流窗口内跳过（返回 null）；网络/解析异常静默
  /// （返回 null，不阻断启动）；仅在有更新（可选/强制）时返回结果。
  Future<UpdateCheckResult?> checkOnStartup() async {
    if (!throttle.shouldCheck()) return null;
    await throttle.markChecked();
    try {
      final result = await checker.check();
      return result.status == UpdateStatus.upToDate ? null : result;
    } on Object {
      return null;
    }
  }

  /// 设置页手动检查：不节流，异常向上抛由 UI 提示。
  Future<UpdateCheckResult> checkManually() => checker.check();
}
