import 'dart:io';

import 'package:health/health.dart';

/// 阶段 D：系统健康数据网关（HealthKit / Health Connect 平台通道抽象）。
///
/// 测试用内存 fake 注入，平台细节（health 包 MethodChannel）不外泄到
/// application 层以上。只读，不写入任何健康数据。
abstract interface class HealthGateway {
  /// 设备/平台是否支持系统健康数据源
  /// （iOS：HealthKit；Android：Health Connect 已安装且 SDK 可用）。
  Future<bool> isSupported();

  /// 当前是否已持有读取授权（null 视为未授权）。
  Future<bool> hasAuthorization();

  /// 向系统申请读取授权（步数/活动能量/体重，均为 READ）。
  Future<bool> requestAuthorization();

  /// 撤销授权（iOS 无撤销 API，health 包为空操作；Android 撤销 Health
  /// Connect 授权）。关闭同步时调用。
  Future<void> revokeAuthorization();

  /// 今日（[now] 当地零点起）累计步数；无数据返回 null。
  Future<int?> getTodaySteps(DateTime now);

  /// 今日活动能量消耗合计（kcal）；无数据返回 null。
  Future<double?> getTodayActiveEnergyKcal(DateTime now);

  /// 最近一次体重（kg，近 30 天内最新一条）；无数据返回 null。
  Future<double?> getLatestWeightKg(DateTime now);
}

/// health 包实现（HealthKit iOS / Health Connect Android）。
final class HealthPackageGateway implements HealthGateway {
  HealthPackageGateway({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  /// 读取范围（合规：最小化，仅步数/活动能量/体重三项，全部 READ）。
  static const List<HealthDataType> _types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
  ];
  static const List<HealthDataAccess> _permissions = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> isSupported() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (Platform.isIOS) return true; // HealthKit（部署目标 iOS 15 已满足）。
    await _ensureConfigured();
    return _health.isHealthConnectAvailable();
  }

  @override
  Future<bool> hasAuthorization() async {
    await _ensureConfigured();
    final granted = await _health.hasPermissions(
      _types,
      permissions: _permissions,
    );
    return granted ?? false;
  }

  @override
  Future<bool> requestAuthorization() async {
    await _ensureConfigured();
    return _health.requestAuthorization(_types, permissions: _permissions);
  }

  @override
  Future<void> revokeAuthorization() async {
    await _ensureConfigured();
    await _health.revokePermissions();
  }

  @override
  Future<int?> getTodaySteps(DateTime now) async {
    final midnight = DateTime(now.year, now.month, now.day);
    return _health.getTotalStepsInInterval(midnight, now);
  }

  @override
  Future<double?> getTodayActiveEnergyKcal(DateTime now) async {
    final midnight = DateTime(now.year, now.month, now.day);
    final points = await _health.getHealthDataFromTypes(
      startTime: midnight,
      endTime: now,
      types: const <HealthDataType>[HealthDataType.ACTIVE_ENERGY_BURNED],
    );
    var total = 0.0;
    var found = false;
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) {
        total += value.numericValue.toDouble();
        found = true;
      }
    }
    return found ? total : null;
  }

  @override
  Future<double?> getLatestWeightKg(DateTime now) async {
    final points = await _health.getHealthDataFromTypes(
      startTime: now.subtract(const Duration(days: 30)),
      endTime: now,
      types: const <HealthDataType>[HealthDataType.WEIGHT],
    );
    HealthDataPoint? latest;
    for (final point in points) {
      if (point.value is! NumericHealthValue) continue;
      if (latest == null || point.dateTo.isAfter(latest.dateTo)) {
        latest = point;
      }
    }
    final value = latest?.value;
    return value is NumericHealthValue ? value.numericValue.toDouble() : null;
  }
}
