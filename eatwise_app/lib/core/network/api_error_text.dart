import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// ApiException → 用户可读上屏文案（D-15）。
///
/// - 业务错误（[BusinessApiException]）：服务端已按 Accept-Language
///   本地化，message 直接上屏；
/// - 网络/超时（[NetworkApiException]/[TimeoutApiException]）：无服务端
///   文案，走本地 i18n 兜底（`common.error.*`），避免英文界面弹中文提示。
String apiErrorDisplayMessage(Translations t, ApiException e) {
  return switch (e) {
    BusinessApiException() => e.message,
    TimeoutApiException() => t.common.error.timeout,
    NetworkApiException() => t.common.error.network,
  };
}
