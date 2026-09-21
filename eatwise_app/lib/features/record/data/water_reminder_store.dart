import 'package:shared_preferences/shared_preferences.dart';

/// 喝水提醒开关存储（默认开）。
///
/// 设备级偏好（与主题/语言同级，不随账号同步——通知偏好属设备状态，
/// D-21 口径）。prefs 缺失（测试/预览未注入）时不持久化，仅内存生效。
final class WaterReminderStore {
  WaterReminderStore(this._prefs);

  static const String _key = 'water.reminder.enabled';

  final SharedPreferences? _prefs;

  bool? _memory;

  /// 当前开关（未设置过 = 默认开）。
  bool get isEnabled => _prefs?.getBool(_key) ?? _memory ?? true;

  /// 写入开关。
  void setEnabled(bool value) {
    final prefs = _prefs;
    if (prefs == null) {
      _memory = value;
    } else {
      prefs.setBool(_key, value);
    }
  }
}
