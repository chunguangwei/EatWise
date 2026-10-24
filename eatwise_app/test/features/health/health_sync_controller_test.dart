import 'dart:async';

import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/data/health_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 平台通道 fake（HealthGateway 接口即 mock 点，不触真实 MethodChannel）。
final class _FakeHealthGateway implements HealthGateway {
  bool supported = true;
  bool granted = false;

  /// requestAuthorization 的系统应答（用户是否授权）。
  bool grantResult = true;
  bool revokeCalled = false;
  int? steps = 6200;
  double? activeEnergyKcal = 245;
  double? weightKg = 66.5;
  bool throwOnRead = false;
  bool throwOnSupportCheck = false;
  bool throwOnAuthorizationCheck = false;

  int supportedCalls = 0;
  int authorizationChecks = 0;
  int authorizationRequests = 0;
  int stepsReads = 0;
  int energyReads = 0;
  int weightReads = 0;
  Completer<void>? stepsStarted;
  Completer<void>? stepsGate;

  int get dataReads => stepsReads + energyReads + weightReads;

  @override
  Future<bool> isSupported() async {
    supportedCalls++;
    if (throwOnSupportCheck) throw StateError('support check failed');
    return supported;
  }

  @override
  Future<bool> hasAuthorization() async {
    authorizationChecks++;
    if (throwOnAuthorizationCheck) throw StateError('auth check failed');
    return granted;
  }

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequests++;
    granted = grantResult;
    return grantResult;
  }

  @override
  Future<void> revokeAuthorization() async {
    revokeCalled = true;
    granted = false;
  }

  @override
  Future<int?> getTodaySteps(DateTime now) async {
    stepsReads++;
    if (stepsStarted?.isCompleted == false) stepsStarted!.complete();
    if (throwOnRead) throw StateError('read failed');
    final gate = stepsGate;
    if (gate != null) await gate.future;
    return steps;
  }

  @override
  Future<double?> getTodayActiveEnergyKcal(DateTime now) async {
    energyReads++;
    if (throwOnRead) throw StateError('read failed');
    return activeEnergyKcal;
  }

  @override
  Future<double?> getLatestWeightKg(DateTime now) async {
    weightReads++;
    if (throwOnRead) throw StateError('read failed');
    return weightKg;
  }
}

/// 阶段 D consent 状态机：off → connecting → ready/denied/unsupported/error，
/// 关闭撤销授权并清同意记录；平台通道全程 fake。
void main() {
  late _FakeHealthGateway gateway;
  late InMemoryExerciseSyncConsentStore consentStore;

  HealthSyncController build({bool consented = false}) {
    if (consented) consentStore.setConsented(true);
    return HealthSyncController(
      gateway: gateway,
      consentStore: consentStore,
      now: () => DateTime(2026, 9, 17, 12),
    );
  }

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        exerciseSyncConsentStoreProvider.overrideWithValue(consentStore),
        healthGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    gateway = _FakeHealthGateway();
    consentStore = InMemoryExerciseSyncConsentStore();
  });

  test('初始未同意 → off', () {
    expect(build().state.status, HealthSyncStatus.off);
  });

  test('初始已同意（重启恢复）→ connecting 待刷新', () {
    expect(build(consented: true).state.status, HealthSyncStatus.connecting);
  });

  group('provider 冷启动恢复', () {
    test('已同意自动读取一次，并发 refresh 合并在途任务', () async {
      await consentStore.setConsented(true);
      gateway.granted = true;
      final started = Completer<void>();
      final gate = Completer<void>();
      gateway.stepsStarted = started;
      gateway.stepsGate = gate;
      final container = buildContainer();
      final controller = container.read(healthSyncControllerProvider.notifier);
      expect(
        container.read(healthSyncControllerProvider).status,
        HealthSyncStatus.connecting,
      );

      await started.future;
      final first = controller.refresh();
      final second = controller.refresh();
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(gateway.supportedCalls, 1);
      expect(gateway.authorizationChecks, 1);
      expect(gateway.stepsReads, 1);

      gate.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(controller.state.status, HealthSyncStatus.ready);
      expect(controller.state.today?.steps, 6200);
      expect(gateway.stepsReads, 1);
      expect(gateway.energyReads, 1);
      expect(gateway.weightReads, 1);
    });

    test('未同意不自动恢复，主动 refresh 也零通道请求', () async {
      final container = buildContainer();
      final controller = container.read(healthSyncControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();

      expect(controller.state.status, HealthSyncStatus.off);
      expect(gateway.supportedCalls, 0);
      expect(gateway.authorizationChecks, 0);
      expect(gateway.authorizationRequests, 0);
      expect(gateway.dataReads, 0);
    });

    test('系统授权已撤销 → denied，零健康数据读取且不重新申请', () async {
      await consentStore.setConsented(true);
      gateway.granted = false;
      final container = buildContainer();
      final controller = container.read(healthSyncControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, HealthSyncStatus.denied);
      expect(gateway.authorizationRequests, 0);
      expect(gateway.dataReads, 0);
    });

    test('冷启动读取异常进入 error，不停留 connecting', () async {
      await consentStore.setConsented(true);
      gateway.granted = true;
      gateway.throwOnRead = true;
      final container = buildContainer();
      final controller = container.read(healthSyncControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, HealthSyncStatus.error);
      expect(controller.state.today, isNull);
      expect(gateway.stepsReads, 1);
      expect(gateway.energyReads, 0);
      expect(gateway.weightReads, 0);
    });

    test('支持态/授权检查异常进入 error，恢复后可重试', () async {
      await consentStore.setConsented(true);
      gateway.throwOnSupportCheck = true;
      final container = buildContainer();
      final controller = container.read(healthSyncControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, HealthSyncStatus.error);
      expect(gateway.dataReads, 0);

      gateway.throwOnSupportCheck = false;
      gateway.throwOnAuthorizationCheck = true;
      await controller.refresh();
      expect(controller.state.status, HealthSyncStatus.error);
      expect(gateway.dataReads, 0);

      gateway.throwOnAuthorizationCheck = false;
      gateway.granted = true;
      await controller.refresh();
      expect(controller.state.status, HealthSyncStatus.ready);
      expect(gateway.dataReads, 3);
    });
  });

  test('读取中 dispose：完成迟到结果不写状态，也不继续后续读取', () async {
    final controller = build(consented: true);
    gateway.granted = true;
    final started = Completer<void>();
    final gate = Completer<void>();
    gateway.stepsStarted = started;
    gateway.stepsGate = gate;

    final refreshing = controller.refresh();
    await started.future;
    controller.dispose();
    gate.complete();
    await refreshing;

    expect(gateway.stepsReads, 1);
    expect(gateway.energyReads, 0);
    expect(gateway.weightReads, 0);
  });

  test('enable 成功：同意落盘 + 授权 + 读取 → ready 带今日快照', () async {
    final controller = build();
    await controller.enable();

    expect(consentStore.consented, isTrue);
    expect(controller.state.status, HealthSyncStatus.ready);
    final today = controller.state.today!;
    expect(today.steps, 6200);
    expect(today.activeEnergyKcal, 245);
    expect(today.latestWeightKg, 66.5);
  });

  test('enable 设备不支持 → unsupported（同意仍落盘，UI 明示）', () async {
    gateway.supported = false;
    final controller = build();
    await controller.enable();

    expect(controller.state.status, HealthSyncStatus.unsupported);
    expect(consentStore.consented, isTrue);
  });

  test('enable 系统拒绝授权 → denied', () async {
    gateway.grantResult = false;
    final controller = build();
    await controller.enable();

    expect(controller.state.status, HealthSyncStatus.denied);
    expect(controller.state.today, isNull);
  });

  test('enable 读取异常 → error（可重试态）', () async {
    gateway.throwOnRead = true;
    final controller = build();
    await controller.enable();

    expect(controller.state.status, HealthSyncStatus.error);
    expect(controller.state.today, isNull);
  });

  test('refresh 未同意 → 回 off 且不触通道', () async {
    final controller = build(consented: false);
    await controller.refresh();
    expect(controller.state.status, HealthSyncStatus.off);
  });

  test('refresh 已同意但授权被系统侧撤销 → denied', () async {
    final controller = build();
    await controller.enable();
    expect(controller.state.status, HealthSyncStatus.ready);

    gateway.granted = false; // 用户在健康 App 里关了授权
    await controller.refresh();
    expect(controller.state.status, HealthSyncStatus.denied);
  });

  test('disable：撤销授权 + 清同意 + 丢快照 → off', () async {
    final controller = build();
    await controller.enable();
    expect(controller.state.today, isNotNull);

    await controller.disable();
    expect(gateway.revokeCalled, isTrue);
    expect(consentStore.consented, isFalse);
    expect(controller.state.status, HealthSyncStatus.off);
    expect(controller.state.today, isNull);
  });

  test('disable 时撤销抛错不阻断本地关闭', () async {
    final controller = build();
    await controller.enable();
    gateway.supported = false; // 不影响 revoke 路径
    await controller.disable();
    expect(controller.state.status, HealthSyncStatus.off);
  });
}
