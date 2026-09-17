import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/features/reports/application/weight_log_store.dart';
import 'package:eatwise/features/reports/data/remote_weight_log_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/network/fake_http_adapter.dart';

/// 体重记录推拉同步（阶段 C）：pending 上行 POST /weight-logs（幂等 upsert）
/// 回填 synced；GET /weight-logs 下行 LWW 合并；离线保持 pending 下轮重试。
void main() {
  late FakeHttpAdapter adapter;
  late RemoteWeightLogSync sync;
  late WeightLogStore store;

  setUp(() {
    adapter = FakeHttpAdapter();
    final dio = createApiDio(config: ApiConfig());
    dio.httpClientAdapter = adapter;
    sync = RemoteWeightLogSync(dio: dio);
    store = WeightLogStore.inMemory();
  });

  Map<String, dynamic> postBody(int index) =>
      (adapter.requestBodies[index] as Map<dynamic, dynamic>).cast();

  test('上行：pending 逐条 POST（含体脂率与幂等键），成功转 synced', () async {
    await store.save('2026-09-16', 66.0, bodyFatPct: 18.5);
    await store.save('2026-09-17', 65.5);

    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{'id': 'srv-1'}),
      ),
    );
    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{'id': 'srv-2'}),
      ),
    );

    await sync.pushPending(store);

    expect(adapter.requestsTo('/weight-logs'), 2);
    // 按日期升序上行；幂等键随条目透传。
    expect(postBody(0)['date'], '2026-09-16');
    expect(postBody(0)['weightKg'], 66.0);
    expect(postBody(0)['bodyFatPct'], 18.5);
    expect(postBody(0)['clientRequestId'], isNotEmpty);
    expect(postBody(1)['date'], '2026-09-17');
    expect(store.pendingEntries(), isEmpty);
  });

  test('上行：断网 → 保持 pending 且判离线（下轮重试）', () async {
    await store.save('2026-09-17', 65.5);
    adapter.stub('/weight-logs', StubResponse.networkError('offline'));

    await sync.pushPending(store);

    expect(store.pendingEntries(), hasLength(1));
    expect(sync.isOnline, isFalse);
  });

  test('上行：同日覆写生成新幂等键，仅最新一条待上行', () async {
    await store.save('2026-09-17', 70.0);
    await store.save('2026-09-17', 69.2); // 同日覆写
    final pending = store.pendingEntries();
    expect(pending, hasLength(1));
    expect(pending.single.value.kg, 69.2);
  });

  test('下行：远端新区间合并为 synced；本地 pending 不被覆盖', () async {
    await store.save('2026-09-17', 65.5); // 本地 pending
    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'logs': <Map<String, dynamic>>[
            <String, dynamic>{
              'date': '2026-09-16',
              'weightKg': 66.4,
              'bodyFatPct': null,
              'updatedAt': '2026-09-16T01:00:00.000Z',
            },
            <String, dynamic>{
              'date': '2026-09-17',
              'weightKg': 99.9, // 同日远端旧值：本地 pending 优先，不覆盖
              'bodyFatPct': null,
              'updatedAt': '2026-09-17T00:30:00.000Z',
            },
          ],
        }),
      ),
    );

    await sync.pullDown(store);

    final entries = store.loadEntries('2026-09-16', '2026-09-17');
    expect(entries['2026-09-16']?.kg, 66.4);
    expect(entries['2026-09-16']?.synced, isTrue);
    expect(entries['2026-09-17']?.kg, 65.5); // 本地 pending 保持
    expect(store.pendingEntries(), hasLength(1));
  });

  test('下行：远端较新覆盖本地已同步条目（LWW）', () async {
    await store.save('2026-09-17', 65.5);
    await store.markSynced(
      '2026-09-17',
      store.pendingEntries().single.value.clientRequestId,
    );
    adapter.stub(
      '/weight-logs',
      StubResponse.json(
        200,
        StubResponse.envelope(<String, dynamic>{
          'logs': <Map<String, dynamic>>[
            <String, dynamic>{
              'date': '2026-09-17',
              'weightKg': 64.8,
              'bodyFatPct': 17.9,
              'updatedAt': '2999-09-17T02:00:00.000Z', // 远端更新
            },
          ],
        }),
      ),
    );

    await sync.pullDown(store);

    final entry = store.loadEntries('2026-09-17', '2026-09-17')['2026-09-17'];
    expect(entry?.kg, 64.8);
    expect(entry?.bodyFatPct, 17.9);
    expect(entry?.synced, isTrue);
  });
}
