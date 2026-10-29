import 'package:eatwise/features/health/data/health_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

class _PermissionHealth extends Health {
  _PermissionHealth(this.permission);

  final bool? permission;

  @override
  Future<void> configure() async {}

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    expect(permissions, everyElement(HealthDataAccess.READ));
    return permission;
  }
}

void main() {
  test('保留 iOS 只读授权的未知状态，不误判为拒绝', () async {
    final gateway = HealthPackageGateway(health: _PermissionHealth(null));

    expect(await gateway.hasAuthorization(), isNull);
  });

  test('保留平台明确返回的授权与拒绝结果', () async {
    for (final permission in [true, false]) {
      final gateway = HealthPackageGateway(
        health: _PermissionHealth(permission),
      );

      expect(await gateway.hasAuthorization(), permission);
    }
  });
}
