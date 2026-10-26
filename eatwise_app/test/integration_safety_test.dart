import 'package:flutter_test/flutter_test.dart';

import '../integration_test/qa_environment.dart';

void main() {
  test('QA API accepts only explicit loopback/private IP endpoints', () {
    for (final value in [
      'http://localhost:3011/v1',
      'http://127.0.0.1:3011/v1',
      'http://[::1]:3011/v1',
      'http://192.168.1.2:3011/v1',
      'http://172.23.1.2:3011/v1',
      'http://10.0.0.2:3011/v1',
    ]) {
      expect(isLocalQaApi(value), isTrue, reason: value);
    }
    for (final value in [
      '',
      'https://wcg.polin.tech:8443/v1',
      'https://8.8.8.8/v1',
      'http://172.32.0.1/v1',
      'http://192.168.1.999/v1',
      'http://localhost.evil.test/v1',
      'http://user@localhost/v1',
      'http://localhost/v1?url=https://example.com',
      'http://localhost/',
      'ftp://localhost/v1',
    ]) {
      expect(isLocalQaApi(value), isFalse, reason: value);
    }
  });

  test('walkthrough refuses to run without explicit QA opt-in', () {
    expect(requireLocalQaApi, throwsStateError);
  });
}
