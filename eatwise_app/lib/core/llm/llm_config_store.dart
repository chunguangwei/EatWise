import 'package:eatwise/core/llm/llm_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LLM 配置本机存储抽象（测试注入内存实现）。
abstract interface class LlmConfigStore {
  /// 未配置返回 null。
  Future<LlmConfig?> read();

  /// 保存；apiKey 为 null/空 = 保持已存 key 不变（控制台密码框语义）。
  Future<void> save(LlmConfig config);

  /// 清除全部配置（回退服务端估算链路）。
  Future<void> clear();
}

/// 本机实现：apiKey → flutter_secure_storage（Keychain/Keystore），
/// 其余 → SharedPreferences（模式同 FoodSeedLoader）。apiKey 禁止写日志。
final class LocalLlmConfigStore implements LlmConfigStore {
  LocalLlmConfigStore({FlutterSecureStorage? secure, required this._prefs})
    : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const String _kProvider = 'llm.provider';
  static const String _kBaseUrl = 'llm.baseUrl';
  static const String _kModel = 'llm.model';
  static const String _kApiKey = 'eatwise.llmApiKey';

  @override
  Future<LlmConfig?> read() async {
    final provider = _prefs.getString(_kProvider);
    if (provider == null) return null;
    return LlmConfig(
      provider: provider,
      baseUrl: _prefs.getString(_kBaseUrl) ?? '',
      model: _prefs.getString(_kModel) ?? '',
      apiKey: await _secure.read(key: _kApiKey),
    );
  }

  @override
  Future<void> save(LlmConfig config) async {
    await _prefs.setString(_kProvider, config.provider);
    await _prefs.setString(_kBaseUrl, config.baseUrl);
    await _prefs.setString(_kModel, config.model);
    if (config.apiKey != null && config.apiKey!.isNotEmpty) {
      await _secure.write(key: _kApiKey, value: config.apiKey);
    }
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_kProvider);
    await _prefs.remove(_kBaseUrl);
    await _prefs.remove(_kModel);
    await _secure.delete(key: _kApiKey);
  }
}

/// 内存实现（widget/单元测试用）。
final class InMemoryLlmConfigStore implements LlmConfigStore {
  LlmConfig? _config;

  @override
  Future<LlmConfig?> read() async => _config;

  @override
  Future<void> save(LlmConfig config) async {
    _config = LlmConfig(
      provider: config.provider,
      baseUrl: config.baseUrl,
      model: config.model,
      apiKey: (config.apiKey == null || config.apiKey!.isEmpty)
          ? _config?.apiKey
          : config.apiKey,
    );
  }

  @override
  Future<void> clear() async => _config = null;
}
