import 'package:eatwise/features/account/domain/weight_unit.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 体重输入单位偏好（公斤/斤，默认公斤；onboarding 档案页、设置页身体
/// 档案与记录页体重弹窗三处共用同一持久化键）。

SharedPreferences? _tryPrefs(Ref ref) {
  try {
    return ref.watch(sharedPreferencesProvider);
  } on Object {
    return null; // 未注入场景（测试/预览）不持久化，仅内存生效。
  }
}

/// 当前体重输入单位（三处输入共用；切换即时生效，异步落盘）。
final weightUnitProvider =
    StateNotifierProvider<WeightUnitController, WeightUnit>(
      (ref) => WeightUnitController(_tryPrefs(ref)),
    );

final class WeightUnitController extends StateNotifier<WeightUnit> {
  WeightUnitController(this._prefs)
    : super(weightUnitFromName(_prefs?.getString(_key)) ?? WeightUnit.kg);

  static const String _key = 'profile.weightUnit';

  final SharedPreferences? _prefs;

  /// 切换即时生效（watch 方重建），异步落盘。
  void setUnit(WeightUnit unit) {
    state = unit;
    _prefs?.setString(_key, unit.name);
  }
}
