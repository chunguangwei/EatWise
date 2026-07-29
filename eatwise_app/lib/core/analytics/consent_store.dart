import 'package:shared_preferences/shared_preferences.dart';

/// 隐私授权状态存储（D-18 / 《埋点规范》§1.6）。
///
/// 红线：**默认未授权不采集**——`analyticsGranted` 缺省 false；
/// 授权状态变更即时生效（读取同步），撤回后停止一切采集并清空缓存队列。
abstract interface class ConsentStore {
  /// 「数据分析」是否已授权（首次隐私弹窗同意 / 设置内开关打开）。
  bool get analyticsGranted;

  Future<void> setAnalyticsGranted(bool granted);
}

/// SharedPreferences 实现（生产）。
final class SharedPreferencesConsentStore implements ConsentStore {
  SharedPreferencesConsentStore(this._prefs);

  static const String _key = 'analytics.consent.granted';

  final SharedPreferences _prefs;

  @override
  bool get analyticsGranted => _prefs.getBool(_key) ?? false;

  @override
  Future<void> setAnalyticsGranted(bool granted) =>
      _prefs.setBool(_key, granted);
}

/// 内存实现（测试 / 未注入 SharedPreferences 的降级场景）。
final class InMemoryConsentStore implements ConsentStore {
  InMemoryConsentStore({this.analyticsGranted = false});

  @override
  bool analyticsGranted;

  @override
  Future<void> setAnalyticsGranted(bool granted) async {
    analyticsGranted = granted;
  }
}
