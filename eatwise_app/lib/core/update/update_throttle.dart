import 'package:shared_preferences/shared_preferences.dart';

/// 启动静默检查节流：SharedPreferences 记录上次检查时间，
/// 间隔 ≥[interval]（默认 24h〔假设〕，待产品校准）才再次检查。
/// 设置页手动检查不经此节流。
final class UpdateCheckThrottle {
  UpdateCheckThrottle(
    this._prefs, {
    this.interval = const Duration(hours: 24),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const String lastCheckKey = 'update.lastCheckAtMs';

  final SharedPreferences _prefs;
  final Duration interval;
  final DateTime Function() _now;

  /// 距上次检查是否已超过节流间隔（从未检查过视为应检查）。
  bool shouldCheck() {
    final lastMs = _prefs.getInt(lastCheckKey);
    if (lastMs == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return _now().difference(last) >= interval;
  }

  /// 记录本次检查时间（无论结果如何，防频繁打服务端）。
  Future<void> markChecked() =>
      _prefs.setInt(lastCheckKey, _now().millisecondsSinceEpoch);
}
