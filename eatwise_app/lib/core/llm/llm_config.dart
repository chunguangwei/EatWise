/// 用户自定义 LLM 配置（规格 §3；仅本机存储，D-本-02）。
final class LlmConfig {
  const LlmConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
    this.apiKey,
  });

  /// custom / deepseek / qwen / kimi。
  final String provider;
  final String baseUrl;
  final String model;

  /// 鉴权 key（本地 Ollama 等免鉴权端点可空）。
  final String? apiKey;

  /// 内置供应商 preset（与服务端 PROVIDER_PRESETS 对齐；custom 无 preset）。
  static const Map<String, ({String baseUrl, String model})> presets = {
    'deepseek': (
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
    ),
    'qwen': (
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen-plus',
    ),
    'kimi': (baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k'),
  };

  /// 生效配置：内置供应商留空补 preset；baseUrl 去末尾斜杠。
  LlmConfig effective() {
    final preset = presets[provider];
    return LlmConfig(
      provider: provider,
      baseUrl: (baseUrl.isEmpty ? preset?.baseUrl ?? '' : baseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      ),
      model: model.isEmpty ? preset?.model ?? '' : model,
      apiKey: apiKey,
    );
  }

  /// 可直接用于直连：baseUrl 与 model 均非空。
  bool get isComplete => baseUrl.isNotEmpty && model.isNotEmpty;
}
