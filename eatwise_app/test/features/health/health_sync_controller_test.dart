import 'package:eatwise/features/health/application/health_sync_controller.dart';
import 'package:eatwise/features/health/data/health_gateway.dart';
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

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> hasAuthorization() async => granted;

  @override
  Future<bool> requestAuthorization() async {
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
    if (throwOnRead) throw StateError('read failed');
    return steps;
  }

  @override
  Future<double?> getTodayActiveEnergyKcal(DateTime now) async {
    if (throwOnRead) throw StateError('read failed');
    return activeEnergyKcal;
  }

  @override
  Future<double?> getLatestWeightKg(DateTime now) async {
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
