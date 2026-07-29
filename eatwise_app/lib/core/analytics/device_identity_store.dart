import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 设备身份存储（《埋点规范》§1.2：`device_id` 首启生成随机 UUID 并持久化；
/// §1.6-1：未授权前不生成/不上传——仅在授权后首次上报时惰性生成）。
abstract interface class DeviceIdentityStore {
  /// 设备级随机 ID（`d_` 前缀 UUID）；首次调用时生成并持久化。
  String deviceId();

  /// 安装后首个自然日（yyyy-MM-dd，本地），随 `deviceId` 首次生成时冻结。
  String? firstOpenDate();
}

/// SharedPreferences 实现（生产）。
final class SharedPreferencesDeviceIdentityStore
    implements DeviceIdentityStore {
  SharedPreferencesDeviceIdentityStore(this._prefs);

  static const String _deviceKey = 'analytics.device_id';
  static const String _firstOpenKey = 'analytics.first_open_date';

  final SharedPreferences _prefs;

  @override
  String deviceId() {
    final existing = _prefs.getString(_deviceKey);
    if (existing != null) return existing;
    final created = 'd_${_uuidV4()}';
    _prefs.setString(_deviceKey, created);
    _prefs.setString(_firstOpenKey, _localToday());
    return created;
  }

  @override
  String? firstOpenDate() => _prefs.getString(_firstOpenKey);

  static String _localToday() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

/// 内存实现（测试 / 降级场景）。
final class InMemoryDeviceIdentityStore implements DeviceIdentityStore {
  String? _deviceId;
  String? _firstOpenDate;

  @override
  String deviceId() {
    return _deviceId ??= () {
      final id = 'd_${_uuidV4()}';
      _firstOpenDate = DateTime.now().toIso8601String().substring(0, 10);
      return id;
    }();
  }

  @override
  String? firstOpenDate() => _firstOpenDate;
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
