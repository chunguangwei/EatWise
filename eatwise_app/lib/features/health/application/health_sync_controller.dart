import 'dart:async';

import 'package:eatwise/core/time/day_change.dart';
import 'package:eatwise/features/health/data/health_gateway.dart';
import 'package:eatwise/features/health/domain/health_activity.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart'
    show sharedPreferencesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「同步运动数据」单独同意记录（GDPR Art.9 explicit consent / PIPL §29）。
///
/// 只持久化同意布尔位；健康数据本身不落盘（内存态，关闭即清）。
abstract interface class ExerciseSyncConsentStore {
  bool get consented;
  Future<void> setConsented(bool value);
}

final class SharedPreferencesExerciseSyncConsentStore
    implements ExerciseSyncConsentStore {
  SharedPreferencesExerciseSyncConsentStore(this._prefs);

  static const String _key = 'health.exerciseSyncConsent.v1';

  final SharedPreferences _prefs;

  @override
  bool get consented => _prefs.getBool(_key) ?? false;

  @override
  Future<void> setConsented(bool value) => _prefs.setBool(_key, value);
}

/// 内存兜底（SharedPreferences 未装配的测试/预览场景，进程内有效）。
final class InMemoryExerciseSyncConsentStore
    implements ExerciseSyncConsentStore {
  bool _consented = false;

  @override
  bool get consented => _consented;

  @override
  Future<void> setConsented(bool value) async {
    _consented = value;
  }
}

final exerciseSyncConsentStoreProvider = Provider<ExerciseSyncConsentStore>((
  ref,
) {
  try {
    return SharedPreferencesExerciseSyncConsentStore(
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return InMemoryExerciseSyncConsentStore();
  }
});

/// 平台通道装配（生产唯一实现；测试 override 为 fake）。
final healthGatewayProvider = Provider<HealthGateway>((ref) {
  return HealthPackageGateway();
});

/// 运动数据同步状态机（阶段 D）。
///
/// - off：未开启（或无单独同意）；
/// - connecting：已同意，正在检查支持态/授权/读取；
/// - unsupported：设备不支持（Android 未装 Health Connect 等）；
/// - denied：系统授权被拒（iOS 健康 App 内被关也落此态）；
/// - ready：已授权且读取成功（[HealthSyncState.today] 为最新快照）；
/// - error：支持态/授权检查或读取失败（可重试）。
enum HealthSyncStatus { off, connecting, unsupported, denied, ready, error }

final class HealthSyncState {
  const HealthSyncState({required this.status, this.today});

  final HealthSyncStatus status;

  /// 今日活动快照（仅 ready 时非空；内存态不落盘）。
  final HealthTodaySummary? today;

  bool get enabled => status != HealthSyncStatus.off;
}

/// 同步控制器：单独同意落盘 → 系统授权 → 读取今日数据；关闭即撤销授权
/// 并丢弃内存快照（健康数据不出端、不落盘，合规 §2 单独同意规格）。
final class HealthSyncController extends StateNotifier<HealthSyncState> {
  HealthSyncController({
    required HealthGateway gateway,
    required ExerciseSyncConsentStore consentStore,
    DateTime Function()? now,
    // super 初始态依赖 consentStore 实参，不能改初始化形参。
    // ignore: prefer_initializing_formals
  }) : _gateway = gateway,
       // ignore: prefer_initializing_formals
       _consentStore = consentStore,
       // ignore: prefer_initializing_formals
       _now = now ?? DateTime.now,
       super(
         consentStore.consented
             ? const HealthSyncState(status: HealthSyncStatus.connecting)
             : const HealthSyncState(status: HealthSyncStatus.off),
       );

  final HealthGateway _gateway;
  final ExerciseSyncConsentStore _consentStore;
  final DateTime Function() _now;

  int _operation = 0;
  Future<void>? _refreshFuture;

  bool _isCurrent(int operation) {
    return mounted && operation == _operation && _consentStore.consented;
  }

  void _setState(HealthSyncState next, int operation) {
    if (_isCurrent(operation)) state = next;
  }

  /// 开启同步（调用方须先完成单独同意弹窗并得到用户同意）。
  Future<void> enable() async {
    final operation = ++_operation;
    await _consentStore.setConsented(true);
    _setState(
      const HealthSyncState(status: HealthSyncStatus.connecting),
      operation,
    );
    if (!_isCurrent(operation)) return;
    try {
      if (!await _guardSupported(operation) || !_isCurrent(operation)) return;
      final granted = await _gateway.requestAuthorization();
      if (!_isCurrent(operation)) return;
      if (!granted) {
        _setState(
          const HealthSyncState(status: HealthSyncStatus.denied),
          operation,
        );
        return;
      }
      await _loadToday(operation);
    } on Object {
      _setState(
        const HealthSyncState(status: HealthSyncStatus.error),
        operation,
      );
    }
  }

  /// 关闭同步：撤销系统授权 + 清同意记录 + 丢弃内存数据。
  Future<void> disable() async {
    final operation = ++_operation;
    try {
      await _gateway.revokeAuthorization();
    } on Object {
      // 撤销失败不阻断本地关闭（iOS 本就无撤销 API）。
    }
    await _consentStore.setConsented(false);
    if (mounted && operation == _operation) {
      state = const HealthSyncState(status: HealthSyncStatus.off);
    }
  }

  /// 重新读取（冷启动恢复/页面曝光/下拉刷新；未同意时静默返回）。
  Future<void> refresh() {
    if (!mounted) return Future<void>.value();
    if (!_consentStore.consented) {
      state = const HealthSyncState(status: HealthSyncStatus.off);
      return Future<void>.value();
    }
    final active = _refreshFuture;
    if (active != null) return active;

    final operation = _operation;
    late final Future<void> future;
    future = _refreshConsented(operation).whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshConsented(int operation) async {
    try {
      if (!await _guardSupported(operation) || !_isCurrent(operation)) return;
      final granted = await _gateway.hasAuthorization();
      if (!_isCurrent(operation)) return;
      if (!granted) {
        _setState(
          const HealthSyncState(status: HealthSyncStatus.denied),
          operation,
        );
        return;
      }
      await _loadToday(operation);
    } on Object {
      _setState(
        const HealthSyncState(status: HealthSyncStatus.error),
        operation,
      );
    }
  }

  Future<bool> _guardSupported(int operation) async {
    final supported = await _gateway.isSupported();
    if (!supported) {
      _setState(
        const HealthSyncState(status: HealthSyncStatus.unsupported),
        operation,
      );
    }
    return supported;
  }

  Future<void> _loadToday(int operation) async {
    if (!_isCurrent(operation)) return;
    final now = _now();
    final steps = await _gateway.getTodaySteps(now);
    if (!_isCurrent(operation)) return;
    final activeEnergyKcal = await _gateway.getTodayActiveEnergyKcal(now);
    if (!_isCurrent(operation)) return;
    final latestWeightKg = await _gateway.getLatestWeightKg(now);
    if (!_isCurrent(operation)) return;
    _setState(
      HealthSyncState(
        status: HealthSyncStatus.ready,
        today: HealthTodaySummary(
          steps: steps,
          activeEnergyKcal: activeEnergyKcal,
          latestWeightKg: latestWeightKg,
        ),
      ),
      operation,
    );
  }
}

final healthSyncControllerProvider =
    StateNotifierProvider<HealthSyncController, HealthSyncState>((ref) {
      ref.watch(localDayProvider);
      final consentStore = ref.watch(exerciseSyncConsentStoreProvider);
      final controller = HealthSyncController(
        gateway: ref.watch(healthGatewayProvider),
        consentStore: consentStore,
        now: ref.watch(localDayClockProvider),
      );
      if (consentStore.consented) {
        unawaited(Future<void>.microtask(controller.refresh));
      }
      return controller;
    });
