import 'package:eatwise/core/network/api_exception.dart';

enum PendingSyncResult {
  success,
  network,
  timeout,
  login,
  server,
  pending,
  rejected,
  failed,
  cancelled,
}

PendingSyncResult _fromCode(String? code) => switch (code) {
  'NETWORK_ERROR' => PendingSyncResult.network,
  'TIMEOUT' => PendingSyncResult.timeout,
  'AUTH_TOKEN_INVALID' ||
  'AUTH_TOKEN_EXPIRED' ||
  'AUTH_REFRESH_INVALID' ||
  'UNAUTHORIZED' ||
  'HTTP_401' => PendingSyncResult.login,
  'INTERNAL_ERROR' ||
  'SERVICE_UNAVAILABLE' ||
  'RATE_LIMITED' => PendingSyncResult.server,
  _ when code != null && RegExp(r'^HTTP_5\d\d$').hasMatch(code) =>
    PendingSyncResult.server,
  _ => PendingSyncResult.pending,
};

/// Sync completion alone is not proof of upload: retryable push failures are
/// persisted, and server rejection can remove a row entirely.
Future<PendingSyncResult> retryPendingRecords({
  required Future<void> Function() sync,
  required Future<List<String?>> Function() readErrors,
  bool Function()? wasRejected,
}) async {
  PendingSyncResult? failure;
  try {
    await sync();
  } on SessionChangedException {
    return PendingSyncResult.cancelled;
  } on ApiException catch (error) {
    failure = error is BusinessApiException && error.httpStatus >= 500
        ? PendingSyncResult.server
        : error is BusinessApiException && error.httpStatus == 401
        ? PendingSyncResult.login
        : _fromCode(error.code);
    if (failure == PendingSyncResult.pending) {
      failure = PendingSyncResult.failed;
    }
  } on Object {
    failure = PendingSyncResult.failed;
  }
  if (wasRejected?.call() == true) return PendingSyncResult.rejected;
  final errors = await readErrors();
  for (final code in errors) {
    final reason = _fromCode(code);
    if (reason != PendingSyncResult.pending) return reason;
  }
  return failure ??
      (errors.isEmpty ? PendingSyncResult.success : PendingSyncResult.pending);
}
