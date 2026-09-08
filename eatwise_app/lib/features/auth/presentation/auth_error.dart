import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/auth/application/auth_controller.dart';

/// 认证错误码 → 客户端文案（中英双语，i18n key 无硬编码）。
///
/// 契约错误码（AUTH_USERNAME_TAKEN / AUTH_INVALID_CREDENTIALS /
/// AUTH_PASSWORD_TOO_WEAK）映射为固定客户端文案；其余错误码回落
/// 服务端本地化 message（可直接上屏）。无错误时返回 null。
String? authErrorMessage(Translations t, AuthState state) {
  final code = state.errorCode;
  if (code == null && state.errorMessage == null) return null;
  final mapped = switch (code) {
    'AUTH_USERNAME_TAKEN' => t.auth.error.usernameTaken,
    'AUTH_INVALID_CREDENTIALS' => t.auth.error.invalidCredentials,
    'AUTH_PASSWORD_TOO_WEAK' => t.auth.error.passwordTooWeak,
    _ => null,
  };
  return mapped ?? state.errorMessage;
}
