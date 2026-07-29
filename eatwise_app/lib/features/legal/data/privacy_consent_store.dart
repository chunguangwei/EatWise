import 'package:shared_preferences/shared_preferences.dart';

/// 首启隐私授权状态存储（合规 §4.1：主同意 + 健康数据单独同意，
/// 分离展示、分离勾选、分离记录）。
///
/// 与 `ConsentStore`（埋点授权）独立：主同意是进入 App 的前置门禁；
/// 健康数据同意是 PIPL §29 单独同意，拒绝可继续使用（营养目标走默认值），
/// 可在「设置-隐私」随时撤回（§4.4）。
abstract interface class PrivacyConsentStore {
  /// 当前隐私政策版本号（随政策更新递增以触发重新弹窗，§4.1）。
  static const String currentPolicyVersion = '1.0.0';

  /// 是否已同意当前版本的主隐私政策。
  bool get hasAgreedCurrentPolicy;

  /// 健康数据敏感个人信息单独同意状态（默认未同意）。
  bool get healthDataGranted;

  /// 同意时间戳（UTC epoch 秒，同意日志存证要素，§4.1）。
  int? get agreedAtEpochSec;

  /// 记录同意：主同意 + 健康数据单独同意一并落盘，含时间戳与政策版本号。
  Future<void> agree({required bool healthDataGranted});

  /// 设置页健康数据授权开关（§4.4 撤回路径）。
  Future<void> setHealthDataGranted(bool granted);
}

/// SharedPreferences 实现（生产）。
final class SharedPreferencesPrivacyConsentStore
    implements PrivacyConsentStore {
  SharedPreferencesPrivacyConsentStore(this._prefs);

  static const String _keyVersion = 'privacy.agreedVersion';
  static const String _keyHealthData = 'privacy.healthDataGranted';
  static const String _keyAgreedAt = 'privacy.agreedAtEpochSec';

  final SharedPreferences _prefs;

  @override
  bool get hasAgreedCurrentPolicy =>
      _prefs.getString(_keyVersion) == PrivacyConsentStore.currentPolicyVersion;

  @override
  bool get healthDataGranted => _prefs.getBool(_keyHealthData) ?? false;

  @override
  int? get agreedAtEpochSec => _prefs.getInt(_keyAgreedAt);

  @override
  Future<void> agree({required bool healthDataGranted}) async {
    await _prefs.setString(
      _keyVersion,
      PrivacyConsentStore.currentPolicyVersion,
    );
    await _prefs.setBool(_keyHealthData, healthDataGranted);
    await _prefs.setInt(
      _keyAgreedAt,
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    );
  }

  @override
  Future<void> setHealthDataGranted(bool granted) =>
      _prefs.setBool(_keyHealthData, granted);
}

/// 内存实现（测试 / 未注入 SharedPreferences 的降级场景，缺省未同意）。
final class InMemoryPrivacyConsentStore implements PrivacyConsentStore {
  @override
  bool hasAgreedCurrentPolicy = false;

  @override
  bool healthDataGranted = false;

  @override
  int? agreedAtEpochSec;

  @override
  Future<void> agree({required bool healthDataGranted}) async {
    hasAgreedCurrentPolicy = true;
    this.healthDataGranted = healthDataGranted;
    agreedAtEpochSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  @override
  Future<void> setHealthDataGranted(bool granted) async {
    healthDataGranted = granted;
  }
}
