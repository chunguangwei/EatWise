import 'dart:async';

import 'package:eatwise/core/push/push_providers.dart';
import 'package:eatwise/core/push/push_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// StubPushService 行为测试（推送抽象层默认降级实现，D-17）。
void main() {
  late List<String> logs;
  late StubPushService service;

  setUp(() {
    logs = <String>[];
    service = StubPushService(logger: logs.add);
    addTearDown(service.dispose);
  });

  test('initialize/register/getToken/unregister 全链路打日志不抛异常', () async {
    expect(service.initialized, isFalse);

    await service.initialize();
    expect(service.initialized, isTrue);
    expect(await service.getToken(), isNull);

    await service.register();
    expect(await service.getToken(), 'stub-token');

    await service.unregister();
    expect(await service.getToken(), isNull);

    expect(logs, hasLength(3));
    expect(logs.first, contains('initialize'));
  });

  test('token 刷新/前台消息/点击三流可注入并送达', () async {
    final tokens = <String>[];
    final messages = <PushMessage>[];
    final taps = <PushTap>[];
    final subs = <StreamSubscription<void>>[
      service.onTokenRefresh.listen(tokens.add),
      service.onForegroundMessage.listen(messages.add),
      service.onMessageTap.listen(taps.add),
    ];

    service.emitTokenRefresh('new-token');
    service.emitForegroundMessage(
      const PushMessage(title: 't', body: 'b', data: <String, Object?>{'k': 1}),
    );
    service.emitMessageTap(
      const PushTap(
        message: PushMessage(title: 't', body: 'b'),
        route: '/community',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(tokens, <String>['new-token']);
    expect(messages.single.title, 't');
    expect(messages.single.data, <String, Object?>{'k': 1});
    expect(taps.single.route, '/community');

    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('pushServiceProvider 默认提供 Stub 实现（可 override 真实适配器）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(pushServiceProvider), isA<StubPushService>());
  });
}
