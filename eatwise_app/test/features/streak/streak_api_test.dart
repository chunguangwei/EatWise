import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/features/streak/data/fasting_report_api.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// S1/S2/S3 + F1/F2 接线 mock 测试（dio HttpClientAdapter 桩，不打真实网络）。
void main() {
  final streakViewJson = <String, dynamic>{
    'currentStreak': 5,
    'longestStreak': 9,
    'lastQualifiedDate': '2026-07-27',
    'makeupCards': <String, dynamic>{
      'stock': 1,
      'grantsThisMonth': 2,
      'expiresAt': '2026-07-31',
      'usableWindowDays': 7,
      'status': 'available',
    },
  };

  Dio dioWith(Map<String, dynamic> Function(String path, Object? body) routes) {
    final dio = Dio(BaseOptions(baseUrl: 'http://stub'));
    dio.httpClientAdapter = _StubAdapter(routes);
    return dio;
  }

  group('StreakApi（S1/S2/S3）', () {
    test('S1 解析：streak/最长/补签卡全字段', () async {
      final api = StreakApi(
        dioWith((path, body) {
          expect(path, '/streak');
          return streakViewJson;
        }),
      );
      final view = await api.fetchStreak();
      expect(view.currentStreak, 5);
      expect(view.longestStreak, 9);
      expect(view.lastQualifiedDate, '2026-07-27');
      expect(view.mendCardStock, 1);
      expect(view.mendCardMonth, '2026-07');
      expect(view.usedThisMonth, 1);
    });

    test('S2 补签：请求体携带幂等键与归属日，响应解析', () async {
      Map<String, dynamic>? sentBody;
      final api = StreakApi(
        dioWith((path, body) {
          expect(path, '/streak/makeup');
          sentBody = body as Map<String, dynamic>;
          return streakViewJson;
        }),
      );
      final view = await api.useMendCard(
        clientRequestId: 'req-1',
        date: '2026-07-26',
      );
      expect(sentBody, {'clientRequestId': 'req-1', 'date': '2026-07-26'});
      expect(view.currentStreak, 5);
    });

    test('S3 里程碑列表解析', () async {
      final api = StreakApi(
        dioWith(
          (path, body) => <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'days': 3,
                'achievedAt': '2026-07-28T00:00:00Z',
              },
              <String, dynamic>{
                'days': 7,
                'achievedAt': '2026-07-30T00:00:00Z',
              },
            ],
          },
        ),
      );
      final milestones = await api.fetchMilestones();
      expect(milestones.map((m) => m.days), [3, 7]);
    });
  });

  group('FastingReportApi（F1/F2）', () {
    test('F1 进行中记录解析；无进行中记录返回 null', () async {
      final api = FastingReportApi(
        dioWith(
          (path, body) => <String, dynamic>{
            'state': 'fasting',
            'activeRecord': <String, dynamic>{
              'id': 'rec-1',
              'attributionDate': '2026-07-28',
            },
          },
        ),
      );
      final active = await api.fetchActiveFast();
      expect(active?.id, 'rec-1');
      expect(active?.attributionDate, '2026-07-28');

      final apiEmpty = FastingReportApi(
        dioWith(
          (path, body) => <String, dynamic>{
            'state': 'eating',
            'activeRecord': null,
          },
        ),
      );
      expect(await apiEmpty.fetchActiveFast(), isNull);
    });

    test('F2 结束上报：请求体含幂等键/recordId/endedAt', () async {
      Map<String, dynamic>? sentBody;
      final api = FastingReportApi(
        dioWith((path, body) {
          expect(path, '/fasting/end');
          sentBody = body as Map<String, dynamic>;
          return <String, dynamic>{'id': 'rec-1'};
        }),
      );
      await api.reportEnd(
        clientRequestId: 'req-9',
        recordId: 'rec-1',
        endedAtUtc: DateTime.utc(2026, 7, 28, 12),
      );
      expect(sentBody?['clientRequestId'], 'req-9');
      expect(sentBody?['recordId'], 'rec-1');
      expect(sentBody?['endedAt'], '2026-07-28T12:00:00.000Z');
    });
  });
}

/// 按路径返回桩响应的 HttpClientAdapter。
final class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.routes);

  final Map<String, dynamic> Function(String path, Object? body) routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (options.data != null) {
      body = options.data is String
          ? jsonDecode(options.data as String)
          : options.data;
    }
    final json = routes(options.path, body);
    return ResponseBody.fromString(
      jsonEncode(json),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
