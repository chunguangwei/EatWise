import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/data/food_search_remote.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

final class _SearchAdapter implements HttpClientAdapter {
  _SearchAdapter({this.personal = false, this.gate});
  final bool personal;
  final Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    if (gate != null) await gate!.future;
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'id': 'shared-1',
            'nameZh': '共享丸子',
            'nameEn': 'Shared food',
            'kcalPer100g': 200,
            'proteinPer100g': 10,
            'carbsPer100g': 20,
            'fatPer100g': 5,
            'source': personal ? 'manual' : 'community',
            'isCustom': personal,
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.memory();
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> seed({String? owner, String source = 'manual'}) =>
      db.foodDao.upsertAll([
        FoodsCompanion(
          id: const Value('shared-1'),
          nameZh: const Value('共享丸子'),
          nameEn: const Value('Shared food'),
          kcalPer100g: const Value(200),
          proteinPer100g: const Value(10),
          carbPer100g: const Value(20),
          fatPer100g: const Value(5),
          isCustom: const Value(true),
          ownerUserId: Value(owner),
          source: Value(source),
          contributionStatus: const Value('approved'),
        ),
      ]);
  Future<void> searchAndRecord(String user) async {
    final search = RemoteFoodSearch(
      dio: Dio()..httpClientAdapter = _SearchAdapter(),
      db: db,
      userId: user,
    );
    final hits = await search.search('共享丸子');
    expect(hits, hasLength(1));
    final repo = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.UTC,
      userId: user,
    );
    try {
      final entry = await repo.addEntry(
        RecordDraft(
          foodId: hits.single.id,
          amountG: 100,
          mealUtc: DateTime.utc(2026, 10, 29, 8),
          source: EntrySource.manual,
        ),
      );
      expect(entry.foodId, 'shared-1');
      expect(entry.kcal, 200);
      expect(
        await repo.entriesForDate(DateTime.utc(2026, 10, 29, 8)),
        hasLength(1),
      );
    } finally {
      await repo.dispose();
    }
  }

  test('本人贡献晋升共享后搜索再确认，必须实际写入一条记录', () async {
    await seed(owner: 'user-a');
    await searchAndRecord('user-a');
  });
  test('旧搜索写坏的共享食品owner=null，重新搜索后可入账', () async {
    await seed(source: 'community');
    await searchAndRecord('user-a');
  });
  test('同设备切换账号后，前一账号贡献的共享食品仍可入账', () async {
    await seed(owner: 'user-a', source: 'community');
    await searchAndRecord('user-b');
  });
  test('升级后离线重开旧坏缓存，食品与营养数据保留且可入账', () async {
    await db.close();
    final dir = await Directory.systemTemp.createTemp('eatwise-shared-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/eatwise.db');
    db = AppDatabase(NativeDatabase(file));
    await seed(source: 'community');
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    final repo = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.UTC,
      userId: 'user-a',
    );
    try {
      final entry = await repo.addEntry(
        RecordDraft(
          foodId: 'shared-1',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 10, 29, 8),
          source: EntrySource.manual,
        ),
      );
      expect(entry.kcal, 200);
      expect((await db.foodDao.getById('shared-1'))!.source, 'community');
    } finally {
      await repo.dispose();
    }
  });
  test('恢复共享缓存不得放开其他账号未共享的个人食品', () async {
    await seed(owner: 'user-a');
    final repo = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.UTC,
      userId: 'user-b',
    );
    try {
      await expectLater(
        repo.addEntry(
          RecordDraft(
            foodId: 'shared-1',
            amountG: 100,
            mealUtc: DateTime.utc(2026, 10, 29),
            source: EntrySource.manual,
          ),
        ),
        throwsArgumentError,
      );
    } finally {
      await repo.dispose();
    }
  });
  test('已确认共享食品遗留个人上行标记，不得阻塞记餐上行', () async {
    await seed(owner: 'user-a', source: 'community');
    await db.customStatement(
      "UPDATE foods SET custom_sync_pending = 1 WHERE id = 'shared-1'",
    );
    final remote = FakeRecordRemote();
    final repo = RecordRepository(
      db: db,
      remote: remote,
      location: tz.UTC,
      userId: 'user-a',
    );
    try {
      final entry = await repo.addEntry(
        RecordDraft(
          foodId: 'shared-1',
          amountG: 100,
          mealUtc: DateTime.utc(2026, 10, 29),
          source: EntrySource.manual,
        ),
      );
      await repo.flushEntry(entry.localId);
      expect(remote.pushCount, 1);
      expect(
        (await db.foodEntryDao.getByLocalId(entry.localId))!.syncStatus,
        SyncStatus.synced,
      );
    } finally {
      await repo.dispose();
    }
  });
  test('搜索在途编辑私人食品，旧响应不得覆盖草稿或返回旧快照', () async {
    await seed(owner: 'user-a');
    final gate = Completer<void>();
    final adapter = _SearchAdapter(personal: true, gate: gate);
    final search = RemoteFoodSearch(
      dio: Dio()..httpClientAdapter = adapter,
      db: db,
      userId: 'user-a',
    );
    final searching = search.search('共享丸子');
    await adapter.started.future;
    final row = (await db.foodDao.getById('shared-1'))!;
    await db.foodDao.upsertAll([
      row
          .toCompanion(true)
          .copyWith(
            nameZh: const Value('最新草稿'),
            kcalPer100g: const Value(300),
            customSyncPending: const Value(true),
            customLocalVersion: const Value(3),
          ),
    ]);
    gate.complete();
    final hits = await searching;
    final saved = (await db.foodDao.getById('shared-1'))!;
    expect(saved.nameZh, '最新草稿');
    expect(saved.kcalPer100g, 300);
    expect(saved.customSyncPending, isTrue);
    expect(saved.customLocalVersion, 3);
    expect(hits.single.nameZh, '最新草稿');
  });
  test('首次搜索到其他人的社区食品可入账', () async {
    await searchAndRecord('user-b');
  });
}
