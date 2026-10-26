import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A consistent snapshot: token rotation retains epoch; login/logout changes it.
final class TokenSnapshot {
  const TokenSnapshot({
    required this.epoch,
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
  });

  final int epoch;
  final String? accessToken;
  final String? refreshToken;
  final String? userId;
}

/// 令牌存储。所有持久化读写串行；会话代际在登录/登出调用时同步翻转，
/// 迟到 refresh 只能 compare-and-set 原会话，不能覆盖或清掉下一账号。
abstract class TokenStore {
  int _sessionEpoch = 0;
  Future<void>? _pending;

  int get sessionEpoch => _sessionEpoch;

  Future<T> _serial<T>(Future<T> Function() operation) {
    // Start an idle queue in the caller's zone. A Future created with the store
    // can otherwise retain an unpumped parent zone (notably in widget tests).
    final previous = _pending;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    late final Future<void> pending;
    void finish() {
      if (identical(_pending, pending)) _pending = null;
    }

    pending = result.then<void>(
      (_) => finish(),
      onError: (Object _, StackTrace _) => finish(),
    );
    _pending = pending;
    return result;
  }

  Future<String?> get accessToken => _serial(_readAccessToken);
  Future<String?> get refreshToken => _serial(_readRefreshToken);
  Future<String?> get userId => _serial(_readUserId);

  Future<TokenSnapshot> snapshot() {
    final epoch = _sessionEpoch;
    return _serial(() async {
      return TokenSnapshot(
        epoch: epoch,
        accessToken: await _readAccessToken(),
        refreshToken: await _readRefreshToken(),
        userId: await _readUserId(),
      );
    });
  }

  /// 登录/注册建立新会话；不传 uid 时保留原 uid（测试/旧存量兼容）。
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
  }) {
    _sessionEpoch++;
    return _serial(() => _writeTokens(accessToken, refreshToken, userId));
  }

  /// 仅轮换当前会话令牌，不改变 epoch。和登录/登出共享同一存储队列，
  /// 检查与写入之间没有其他写操作可插入。
  Future<bool> rotateIfCurrent({
    required int epoch,
    required String accessToken,
    required String refreshToken,
  }) => _serial(() async {
    if (_sessionEpoch != epoch) return false;
    await _writeTokens(accessToken, refreshToken, null);
    return _sessionEpoch == epoch;
  });

  Future<void> clear() {
    _sessionEpoch++;
    return _serial(_clearTokens);
  }

  Future<bool> clearIfCurrent(int epoch) {
    if (_sessionEpoch != epoch) return Future<bool>.value(false);
    final clearedEpoch = ++_sessionEpoch;
    return _serial(() async {
      await _clearTokens();
      return _sessionEpoch == clearedEpoch;
    });
  }

  Future<String?> _readAccessToken();
  Future<String?> _readRefreshToken();
  Future<String?> _readUserId();
  Future<void> _writeTokens(String access, String refresh, String? userId);
  Future<void> _clearTokens();
}

/// flutter_secure_storage 实现（iOS Keychain / Android Keystore 加密存储）。
final class SecureTokenStore extends TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _accessKey = 'eatwise.accessToken';
  static const String _refreshKey = 'eatwise.refreshToken';
  static const String _userIdKey = 'eatwise.userId';

  @override
  Future<String?> _readAccessToken() => _storage.read(key: _accessKey);
  @override
  Future<String?> _readRefreshToken() => _storage.read(key: _refreshKey);
  @override
  Future<String?> _readUserId() => _storage.read(key: _userIdKey);

  @override
  Future<void> _writeTokens(
    String access,
    String refresh,
    String? userId,
  ) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    if (userId != null) await _storage.write(key: _userIdKey, value: userId);
  }

  @override
  Future<void> _clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
  }
}

/// 内存实现与安全存储共用串行化/CAS 语义。
final class InMemoryTokenStore extends TokenStore {
  String? _accessToken;
  String? _refreshToken;
  String? _userId;

  @override
  Future<String?> _readAccessToken() async => _accessToken;
  @override
  Future<String?> _readRefreshToken() async => _refreshToken;
  @override
  Future<String?> _readUserId() async => _userId;

  @override
  Future<void> _writeTokens(
    String access,
    String refresh,
    String? userId,
  ) async {
    _accessToken = access;
    _refreshToken = refresh;
    if (userId != null) _userId = userId;
  }

  @override
  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
  }
}
