/// Integration walkthroughs write test records and must never target production.
bool isLocalQaApi(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/v1' ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  if (uri.host == 'localhost' || uri.host == '::1') return true;
  final parts = uri.host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 ||
      parts.any((value) => value == null || value < 0 || value > 255)) {
    return false;
  }
  return parts[0] == 127 ||
      parts[0] == 10 ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
}

String requireLocalQaApi() {
  const enabled = bool.fromEnvironment('EATWISE_QA');
  const api = String.fromEnvironment('API_BASE_URL');
  if (!enabled || !isLocalQaApi(api)) {
    throw StateError(
      'This integration test requires EATWISE_QA=true and an explicit local '
      'API_BASE_URL ending in /v1. Use an isolated QA app and memory server.',
    );
  }
  return api;
}
