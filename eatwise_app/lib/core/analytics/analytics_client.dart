import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:eatwise/core/analytics/analytics_event.dart';
import 'package:flutter/foundation.dart';

/// 永久失败（HTTP 4xx）：该批事件按规范丢弃并记 `app_track_error`（§1.5）。
final class AnalyticsPermanentException implements Exception {
  const AnalyticsPermanentException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'AnalyticsPermanentException($statusCode)';
}

/// 上报通道接口（《埋点规范》§1.3 自建通道为主；dev 下 logging 通道并列）。
///
/// 实现方收到的是**同一批**事件（批量信封）；`send` 抛
/// [AnalyticsPermanentException] 表示 4xx 永久失败（调用方丢弃该批），
/// 抛其他异常表示可重试失败（调用方保留队列）。
abstract interface class AnalyticsClient {
  /// 发送一批事件（批量包内按 `timestamp` 升序，由调用方保证）。
  Future<void> send(List<AnalyticsEvent> batch);

  /// 未授权时被抑制的事件标记（合规红线 §1.6-1：未授权不采集、不落缓存）。
  /// 默认 no-op；[LoggingAnalyticsClient] 在 debug 输出供开发核对。
  void logSuppressed(String name, Map<String, Object?> properties) {}
}

/// debug 通道：事件实时打到控制台，开发自测用（验收流程 §5.1-①）。
final class LoggingAnalyticsClient implements AnalyticsClient {
  const LoggingAnalyticsClient();

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    if (!kDebugMode) return;
    for (final event in batch) {
      debugPrint('[analytics] ${jsonEncode(event.toJson())}');
    }
  }

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {
    if (!kDebugMode) return;
    debugPrint('[analytics][suppressed] $name ${jsonEncode(properties)}');
  }
}

/// 自建上报通道（§1.3 主通道）：批量 POST 到采集网关。
///
/// 〔假设〕端点 `/analytics/events`（挂 `/v1` 前缀，服务端采集网关未实现，
/// 本次仅客户端按信封格式发送）：请求体
/// `{data: {events: [...]}, meta: {requestId, clientTime}}`（对齐契约信封）。
/// HTTP 2xx 视为成功；4xx → [AnalyticsPermanentException]；5xx/网络错误重试。
final class RemoteAnalyticsClient implements AnalyticsClient {
  RemoteAnalyticsClient({required this.dio, this.path = '/analytics/events'});

  final Dio dio;
  final String path;

  @override
  void logSuppressed(String name, Map<String, Object?> properties) {
    // 远端通道不输出 suppressed 标记（仅 logging 通道，debug 自测用）。
  }

  @override
  Future<void> send(List<AnalyticsEvent> batch) async {
    try {
      await dio.post<void>(
        path,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'events': batch.map((e) => e.toJson()).toList(),
          },
          'meta': <String, dynamic>{
            'requestId': newAnalyticsEventId(),
            'clientTime': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code >= 400 && code < 500) {
        throw AnalyticsPermanentException(code);
      }
      rethrow;
    }
  }
}
