/// API 环境配置（契约 §1.1：dev/staging/prod 三环境 Base URL + /v1 前缀）。
///
/// 构建期可用 `--dart-define=API_BASE_URL=...` 覆盖任意环境地址，
/// `--dart-define=API_ENV=staging|prod` 切换环境（默认 dev 本地联调）。
library;

enum ApiEnv { dev, staging, prod }

final class ApiConfig {
  ApiConfig({ApiEnv? env}) : env = env ?? _envFromDefine;

  /// 当前环境。
  final ApiEnv env;

  /// 该环境 Base URL（含 /v1 前缀）；dart-define 覆盖优先。
  String get baseUrl {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    return switch (env) {
      // dev 默认本地 eatwise_server（PORT 见 eatwise_server/.env.example）。
      ApiEnv.dev => 'http://localhost:3000/v1',
      ApiEnv.staging => 'https://api-staging.eatwise.example.com/v1',
      ApiEnv.prod => 'https://api.eatwise.example.com/v1',
    };
  }

  /// 服务端返回的相对路径 → 可直接给 Image.network/dio 用的绝对 URL。
  ///
  /// 上传接口按契约回 `/v1/uploads/<id>`（相对、自带版本前缀），换环境/
  /// 换域名时客户端不用改；这里只补 origin（scheme://host[:port]），
  /// 不拼 [baseUrl]（它已含 /v1，再拼会成 /v1/v1）。已是绝对地址的原样返回。
  String resolveUrl(String url) {
    if (!url.startsWith('/')) return url;
    final base = Uri.parse(baseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: url,
    ).toString();
  }

  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  static ApiEnv get _envFromDefine =>
      switch (const String.fromEnvironment('API_ENV', defaultValue: 'dev')) {
        'staging' => ApiEnv.staging,
        'prod' => ApiEnv.prod,
        _ => ApiEnv.dev,
      };
}
