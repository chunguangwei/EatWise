import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 令牌存储（契约 §6.2：iOS Keychain / Android Keystore，禁止写日志）。
abstract interface class TokenStore {
  Future<String?> get accessToken;
  Future<String?> get refreshToken;

  /// 登录会话归属用户（随令牌持久化，冷启动恢复登录态时一并恢复，
  /// 否则重启后 currentUserIdProvider 恒 anonymous、历史数据按真实
  /// userId 查询落空）。
  Future<String?> get userId;

  /// 登录/刷新成功后原子写入（refresh 滑动轮换，旧值作废）。
  /// [userId] 仅登录/注册时提供；refresh 轮换不带 userId，保留原值。
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
  });

  /// 登出/refresh 失败清会话。
  Future<void> clear();
}

/// flutter_secure_storage 实现（iOS Keychain / Android Keystore 加密存储）。
final class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _accessKey = 'eatwise.accessToken';
  static const String _refreshKey = 'eatwise.refreshToken';
  static const String _userIdKey = 'eatwise.userId';

  @override
  Future<String?> get accessToken => _storage.read(key: _accessKey);

  @override
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);

  @override
  Future<String?> get userId => _storage.read(key: _userIdKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    if (userId != null) {
      await _storage.write(key: _userIdKey, value: userId);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
  }
}

/// 内存实现（测试与降级用）。
final class InMemoryTokenStore implements TokenStore {
  String? _accessToken;
  String? _refreshToken;
  String? _userId;

  @override
  Future<String?> get accessToken async => _accessToken;

  @override
  Future<String?> get refreshToken async => _refreshToken;

  @override
  Future<String?> get userId async => _userId;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (userId != null) _userId = userId;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
  }
}
