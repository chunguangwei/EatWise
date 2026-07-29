/// 埋点事件模型（《埋点规范与事件字典》§1.4）。
///
/// 事件体 = 公共属性（`common`，由采集层统一注入，业务代码不得手工拼写）
/// + 事件私有属性（`properties`，以字典第三章为准，禁止字典外属性）。
library;

import 'dart:math';

final RegExp _eventNamePattern = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

/// UUIDv4（`event_id` 幂等键，客户端生成，§1.2）。
String newAnalyticsEventId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// 单条埋点事件。
final class AnalyticsEvent {
  AnalyticsEvent({
    required this.eventId,
    required this.name,
    required this.timestamp,
    required this.clientDate,
    required this.common,
    required this.properties,
  }) {
    if (!_eventNamePattern.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', '事件名必须为小写 snake_case（§1.1）');
    }
    for (final entry in properties.entries) {
      _validateProperty(entry.key, entry.value);
    }
  }

  /// 客户端生成的 UUIDv4，服务端按 `event_id` 幂等去重（防重试重复上报）。
  final String eventId;

  /// 事件名（snake_case，`模块_对象_动作`，§1.1）。
  final String name;

  /// UTC 毫秒时间戳（D-07 全链路 UTC）。
  final int timestamp;

  /// 设备本地自然日（yyyy-MM-dd），留存/有效记录日口径按本地日（§1.2）。
  final String clientDate;

  /// 公共属性（§1.2，采集层注入）。
  final Map<String, Object?> common;

  /// 事件私有属性（字典第三章；类型只允许 string/int/double/bool/string[]）。
  final Map<String, Object?> properties;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'event_id': eventId,
    'event_name': name,
    'timestamp': timestamp,
    'client_date': clientDate,
    'common': common,
    'properties': properties,
  };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    return AnalyticsEvent(
      eventId: json['event_id'] as String,
      name: json['event_name'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      clientDate: json['client_date'] as String,
      common: Map<String, Object?>.from(json['common'] as Map),
      properties: Map<String, Object?>.from(json['properties'] as Map),
    );
  }

  static void _validateProperty(String key, Object? value) {
    if (!_eventNamePattern.hasMatch(key)) {
      throw ArgumentError.value(key, 'properties', '属性名必须为小写 snake_case');
    }
    final ok =
        value == null ||
        value is String ||
        value is int ||
        value is double ||
        value is bool ||
        (value is List && value.every((v) => v is String));
    if (!ok) {
      throw ArgumentError.value(
        value,
        key,
        '属性类型只允许 string/int/double/bool/string[]（§1.4）',
      );
    }
  }
}
