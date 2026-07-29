import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalyticsEvent 事件模型（§1.4）', () {
    AnalyticsEvent buildEvent({
      String name = 'record_flow_success',
      Map<String, Object?> properties = const <String, Object?>{
        'duration_ms': 12400,
      },
    }) {
      return AnalyticsEvent(
        eventId: '3f8a-e21',
        name: name,
        timestamp: 1753600000000,
        clientDate: '2026-07-27',
        common: const <String, Object?>{'platform': 'ios'},
        properties: properties,
      );
    }

    test('JSON 信封结构与字典 §1.4 一致且可往返', () {
      final event = buildEvent();
      final json = event.toJson();
      expect(json['event_id'], '3f8a-e21');
      expect(json['event_name'], 'record_flow_success');
      expect(json['timestamp'], 1753600000000);
      expect(json['client_date'], '2026-07-27');
      expect(json['common'], <String, Object?>{'platform': 'ios'});
      expect(json['properties'], <String, Object?>{'duration_ms': 12400});

      final restored = AnalyticsEvent.fromJson(json);
      expect(restored.eventId, event.eventId);
      expect(restored.name, event.name);
      expect(restored.timestamp, event.timestamp);
      expect(restored.clientDate, event.clientDate);
      expect(restored.properties, event.properties);
    });

    test('非 snake_case 事件名/属性名直接拒绝（§1.1）', () {
      expect(() => buildEvent(name: 'FastingEndConfirm'), throwsArgumentError);
      expect(() => buildEvent(name: 'fasting-end'), throwsArgumentError);
      expect(
        () => buildEvent(properties: <String, Object?>{'BadKey': 1}),
        throwsArgumentError,
      );
    });

    test('属性类型只允许 string/int/double/bool/string[]（§1.4）', () {
      expect(
        () => buildEvent(
          properties: <String, Object?>{
            'nested': <String, int>{'a': 1},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => buildEvent(
          properties: <String, Object?>{
            's': 'v',
            'i': 1,
            'f': 0.83,
            'b': true,
            'list': <String>['a', 'b'],
          },
        ),
        returnsNormally,
      );
    });
  });

  group('AnalyticsContext 公共属性注入（§1.2）', () {
    test('user_id HMAC 匿名化：稳定、去标识、u_ 前缀', () {
      final a = anonymizeUserId('user-123');
      final b = anonymizeUserId('user-123');
      final c = anonymizeUserId('user-456');
      expect(a, b);
      expect(a, isNot(c));
      expect(a, startsWith('u_'));
      expect(a, isNot(contains('user-123')));
    });

    test('commonProps 注入全量公共属性', () {
      final context = AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
        userIdResolver: () => 'user-123',
        localeTag: () => 'zh-CN',
        networkType: () => 'wifi',
        platform: 'ios',
        osVersion: '17.5.1',
        appVersion: '1.0.0',
        buildNumber: '102',
        sessionId: 's_20260727_x1',
      );
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final props = context.commonProps(clientDate: today);
      expect(props['user_id'], anonymizeUserId('user-123'));
      expect(props.containsKey('anonymous_id'), isFalse);
      expect(props['device_id'], startsWith('d_'));
      expect(props['platform'], 'ios');
      expect(props['os_version'], '17.5.1');
      expect(props['app_version'], '1.0.0');
      expect(props['build_number'], '102');
      expect(props['locale'], 'zh-CN');
      expect(props['network'], 'wifi');
      expect(props['session_id'], 's_20260727_x1');
      expect(props['is_first_open_day'], isTrue);
    });

    test('未登录使用 anonymous_id（§1.2 ID-Mapping 前段）', () {
      final context = AnalyticsContext(
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
        userIdResolver: () => null,
      );
      final props = context.commonProps(clientDate: '2026-07-27');
      expect(props.containsKey('user_id'), isFalse);
      expect(props['anonymous_id'], startsWith('a_'));
    });
  });
}
