import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/auth_interceptor.dart';
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/network/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_adapter.dart';

/// Delays the actual HTTP boundary, leaving the production interceptor intact.
class DelayedSessionAdapter implements HttpClientAdapter {
  DelayedSessionAdapter({
    required this.delayPath,
    required this.delayed,
    this.delayReplayOnly = false,
  });

  final String delayPath;
  final StubResponse delayed;
  final bool delayReplayOnly;
  final started = Completer<void>();
  final release = Completer<void>();
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path == delayPath &&
        !started.isCompleted &&
        (!delayReplayOnly || options.extra['retried'] == true)) {
      started.complete();
      await release.future;
      return delayed.toResponseBody(options);
    }
    if (options.path == '/auth/refresh') {
      return StubResponse.json(
        200,
        StubResponse.envelope({
          'accessToken': 'refreshed-access',
          'refreshToken': 'refreshed-refresh',
        }),
      ).toResponseBody(options);
    }
    if (options.extra['retried'] != true) {
      return StubResponse.json(
        401,
        StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', 'expired'),
      ).toResponseBody(options);
    }
    return StubResponse.json(
      200,
      StubResponse.envelope(true),
    ).toResponseBody(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'disposing a task after refresh was sent still preserves rotated credentials',
    () async {
      final store = InMemoryTokenStore();
      await store.saveTokens(
        accessToken: 'A',
        refreshToken: 'A-r',
        userId: 'A',
      );
      final lease = SessionLease(store);
      final dio = createApiDio(tokenStore: store);
      final adapter = DelayedSessionAdapter(
        delayPath: '/auth/refresh',
        delayed: StubResponse.json(
          200,
          StubResponse.envelope({
            'accessToken': 'A-rotated',
            'refreshToken': 'A-rotated-r',
          }),
        ),
      );
      dio.httpClientAdapter = adapter;
      dio.interceptors
              .whereType<AuthInterceptor>()
              .single
              .refreshDio
              .httpClientAdapter =
          adapter;
      addTearDown(() => dio.close(force: true));
      final result = lease
          .run(() => dio.post<dynamic>('/sync/push'))
          .then<Object?>((r) => r, onError: (Object e) => e);
      await adapter.started.future;
      lease.dispose();
      adapter.release.complete();
      expect(await result, isA<DioException>());
      expect(await store.accessToken, 'A-rotated');
      expect(await store.refreshToken, 'A-rotated-r');
      expect(
        adapter.requests.where((r) => r.path == '/sync/push'),
        hasLength(1),
      );
    },
  );

  for (final changeSession in [true, false]) {
    test(
      'replay completion does not deadlock when ${changeSession ? 'session changes' : 'server fails'}',
      () async {
        final store = InMemoryTokenStore();
        await store.saveTokens(
          accessToken: 'A',
          refreshToken: 'A-r',
          userId: 'A',
        );
        final dio = createApiDio(tokenStore: store);
        final adapter = DelayedSessionAdapter(
          delayPath: '/sync/push',
          delayReplayOnly: true,
          delayed: StubResponse.json(
            changeSession ? 200 : 500,
            changeSession
                ? StubResponse.envelope(true)
                : StubResponse.errorEnvelope('INTERNAL_ERROR', 'failed'),
          ),
        );
        dio.httpClientAdapter = adapter;
        dio.interceptors
                .whereType<AuthInterceptor>()
                .single
                .refreshDio
                .httpClientAdapter =
            adapter;
        addTearDown(() => dio.close(force: true));
        final request = dio
            .post<dynamic>('/sync/push')
            .then<Object?>((r) => r, onError: (Object e) => e);
        await adapter.started.future;
        if (changeSession) {
          await store.clear();
          await store.saveTokens(
            accessToken: 'B',
            refreshToken: 'B-r',
            userId: 'B',
          );
        }
        adapter.release.complete();
        // Only a deadlock watchdog; race ordering is controlled by the barriers.
        expect(
          await request.timeout(const Duration(seconds: 2)),
          isA<DioException>(),
        );
        expect(
          adapter.requests.where((r) => r.path == '/sync/push'),
          hasLength(2),
        );
        expect(await store.userId, changeSession ? 'B' : 'A');
      },
    );
  }

  test('a request queued before auth keeps its original session', () async {
    final store = InMemoryTokenStore();
    await store.saveTokens(
      accessToken: 'A-access',
      refreshToken: 'A-refresh',
      userId: 'A',
    );
    final dio = createApiDio(tokenStore: store);
    final adapter = FakeHttpAdapter(
      fallback: StubResponse.json(200, StubResponse.envelope(true)),
    );
    dio.httpClientAdapter = adapter;
    final started = Completer<void>();
    final release = Completer<void>();
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          started.complete();
          await release.future;
          handler.next(options);
        },
      ),
    );
    final request = dio
        .post<dynamic>('/sync/push', data: {'request': 'A'})
        .then<Object?>((value) => value, onError: (Object error) => error);
    await started.future;
    await store.clear();
    await store.saveTokens(
      accessToken: 'B-access',
      refreshToken: 'B-refresh',
      userId: 'B',
    );
    release.complete();
    expect(await request, isA<DioException>());
    expect(adapter.requests, isEmpty);
    dio.close(force: true);
  });

  test(
    'concurrent 401 responses share one rotation within the same session',
    () async {
      final store = InMemoryTokenStore();
      await store.saveTokens(
        accessToken: 'A-access',
        refreshToken: 'A-refresh',
        userId: 'A',
      );
      final epoch = store.sessionEpoch;
      final dio = createApiDio(tokenStore: store);
      final adapter = DelayedSessionAdapter(
        delayPath: '/auth/refresh',
        delayed: StubResponse.json(
          200,
          StubResponse.envelope({
            'accessToken': 'A-rotated',
            'refreshToken': 'A-refresh-2',
          }),
        ),
      );
      dio.httpClientAdapter = adapter;
      dio.interceptors
              .whereType<AuthInterceptor>()
              .single
              .refreshDio
              .httpClientAdapter =
          adapter;
      final first = dio.post<dynamic>('/a');
      final second = dio.post<dynamic>('/b');
      await adapter.started.future;
      adapter.release.complete();
      await Future.wait([first, second]);
      expect(
        adapter.requests.where((r) => r.path == '/auth/refresh'),
        hasLength(1),
      );
      expect(
        adapter.requests
            .where((r) => r.extra['retried'] == true)
            .every((r) => r.headers['Authorization'] == 'Bearer A-rotated'),
        isTrue,
      );
      expect(store.sessionEpoch, epoch);
      dio.close(force: true);
    },
  );

  for (final delayedRefresh in [false, true]) {
    for (final status in delayedRefresh ? [200, 401] : [401, 200]) {
      test(
        '${delayedRefresh ? 'refresh' : 'request'} late $status cannot cross sessions',
        () async {
          final store = InMemoryTokenStore();
          await store.saveTokens(
            accessToken: 'A-access',
            refreshToken: 'A-refresh',
            userId: 'A',
          );
          var cleared = 0;
          final dio = createApiDio(
            tokenStore: store,
            onSessionCleared: () => cleared++,
          );
          final adapter = DelayedSessionAdapter(
            delayPath: delayedRefresh ? '/auth/refresh' : '/sync/push',
            delayed: StubResponse.json(
              status,
              status == 401
                  ? StubResponse.errorEnvelope('AUTH_TOKEN_EXPIRED', 'expired')
                  : StubResponse.envelope(
                      delayedRefresh
                          ? {
                              'accessToken': 'A-refreshed',
                              'refreshToken': 'A-rotated',
                            }
                          : {'saved': 'A-entry'},
                    ),
            ),
          );
          dio.httpClientAdapter = adapter;
          dio.interceptors
                  .whereType<AuthInterceptor>()
                  .single
                  .refreshDio
                  .httpClientAdapter =
              adapter;
          final result = dio
              .post<dynamic>(
                '/sync/push',
                data: {
                  'ops': [
                    {
                      'clientRequestId': 'A-request',
                      'payload': {'grams': 123},
                    },
                  ],
                },
              )
              .then<Object?>((response) => response, onError: (Object e) => e);
          await adapter.started.future;
          await store.clear();
          await store.saveTokens(
            accessToken: 'B-access',
            refreshToken: 'B-refresh',
            userId: 'B',
          );
          adapter.release.complete();
          expect(await result, isA<DioException>());
          expect(await store.accessToken, 'B-access');
          expect(await store.refreshToken, 'B-refresh');
          expect(await store.userId, 'B');
          expect(cleared, 0);
          expect(
            adapter.requests.where((r) => r.path == '/sync/push'),
            hasLength(1),
          );
          expect(
            adapter.requests.any(
              (r) => r.headers['Authorization'] == 'Bearer B-access',
            ),
            isFalse,
          );
          if (!delayedRefresh) {
            expect(
              adapter.requests.where((r) => r.path == '/auth/refresh'),
              isEmpty,
            );
          }
          dio.close(force: true);
        },
      );
    }
  }
}
