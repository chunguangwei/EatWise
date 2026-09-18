import 'package:eatwise/features/account/application/weight_unit_controller.dart';
import 'package:eatwise/features/account/domain/weight_unit.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 体重单位（公斤/斤）换算与偏好持久化（真机走查防呆：按斤填体重）。
void main() {
  group('换算与格式化（存储一律 kg）', () {
    test('斤 ↔ kg：1 斤 = 0.5 kg', () {
      expect(jinToKg(170), 85);
      expect(jinToKg(131), 65.5);
      expect(kgToJin(85), 170);
      expect(kgToJin(65.5), 131);
    });

    test('展示格式化：整数不带小数，否则 1 位小数', () {
      expect(formatWeightForUnit(85, WeightUnit.jin), '170');
      expect(formatWeightForUnit(65.5, WeightUnit.jin), '131');
      expect(formatWeightForUnit(65.55, WeightUnit.jin), '131.1');
      expect(formatWeightForUnit(70, WeightUnit.kg), '70');
      expect(formatWeightForUnit(65.5, WeightUnit.kg), '65.5');
    });
  });

  group('偏好持久化（profile.weightUnit，默认 kg）', () {
    test('缺省/非法值 → 公斤；切换斤 → 落盘且新实例恢复', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      // 默认公斤。
      expect(container.read(weightUnitProvider), WeightUnit.kg);

      // 切斤 → 状态即时生效 + 落盘。
      container.read(weightUnitProvider.notifier).setUnit(WeightUnit.jin);
      expect(container.read(weightUnitProvider), WeightUnit.jin);
      expect(prefs.getString('profile.weightUnit'), 'jin');

      // 新控制器实例（模拟冷启动）从持久化恢复。
      expect(WeightUnitController(prefs).state, WeightUnit.jin);

      // 非法存量值回落公斤。
      await prefs.setString('profile.weightUnit', 'lb');
      expect(WeightUnitController(prefs).state, WeightUnit.kg);
    });
  });
}
