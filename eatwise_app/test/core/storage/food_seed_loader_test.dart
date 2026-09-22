import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/food_seed_loader.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart' show EntrySource;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D-16：FoodSeedLoader 幂等导入 + 导入后 FoodDao 双语搜索有结果。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> sampleDoc(String version) => <String, dynamic>{
    'version': version,
    'sources': <String>['curated'],
    'foods': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'curated-steamed-rice',
        'name_zh': '米饭',
        'name_en': 'Steamed Rice',
        'aliases_zh': <String>['白米饭', '大米饭'],
        'aliases_en': <String>['cooked rice', 'white rice'],
        'kcal': 116.0,
        'protein_g': 2.6,
        'carb_g': 25.9,
        'fat_g': 0.3,
        'source': 'curated',
        'zh_verified': true,
      },
      <String, dynamic>{
        'id': 'curated-chicken-breast',
        'name_zh': '鸡胸肉',
        'name_en': 'Chicken Breast (Cooked)',
        'aliases_zh': <String>['鸡胸'],
        'aliases_en': <String>['grilled chicken breast'],
        'kcal': 133.0,
        'protein_g': 19.4,
        'carb_g': 2.5,
        'fat_g': 5.0,
        'source': 'curated',
        'zh_verified': true,
      },
      <String, dynamic>{
        'id': 'usda-171287',
        'name_zh': null,
        'name_en': 'Apples, raw, with skin',
        'aliases_zh': <String>[],
        'aliases_en': <String>['apples, raw, with skin'],
        'kcal': 52.0,
        'protein_g': 0.3,
        'carb_g': 13.8,
        'fat_g': 0.2,
        'source': 'usda-sr',
        'zh_verified': false,
      },
    ],
  };

  FoodSeedLoader loader(SharedPreferences prefs, String version) {
    return FoodSeedLoader(
      db: db,
      prefs: prefs,
      assetReader: (_) async => jsonEncode(sampleDoc(version)),
    );
  }

  test('首次导入：全部条目写入，双语搜索有结果', () async {
    final prefs = await SharedPreferences.getInstance();
    final result = await loader(prefs, 'test.1').ensureSeeded();

    expect(result.skipped, isFalse);
    expect(result.imported, 3);
    expect(prefs.getString(FoodSeedLoader.versionKey), 'test.1');
    expect(prefs.getStringList(FoodSeedLoader.sourcesKey), <String>['curated']);

    // 中文名搜索
    final zhHits = await db.foodDao.searchFoods('米饭');
    expect(zhHits.map((f) => f.id), contains('curated-steamed-rice'));
    // 英文别名搜索命中中文食物（K2 跨语言）
    final enHits = await db.foodDao.searchFoods('chicken breast');
    expect(enHits.map((f) => f.id), contains('curated-chicken-breast'));
    // 无中文名的 USDA 条目（zh_verified=false）仍可被英文名搜索到
    final usdaHits = await db.foodDao.searchFoods('apples');
    expect(usdaHits.map((f) => f.id), contains('usda-171287'));
  });

  test('幂等：版本一致且表非空则跳过，数据不重复', () async {
    final prefs = await SharedPreferences.getInstance();
    await loader(prefs, 'test.1').ensureSeeded();

    final second = await loader(prefs, 'test.1').ensureSeeded();
    expect(second.skipped, isTrue);
    expect(second.imported, 0);

    final all = await db.foodDao.searchFoods('', limit: 100);
    expect(all.length, 3);
  });

  test('版本升级：重新导入并覆盖更新', () async {
    final prefs = await SharedPreferences.getInstance();
    await loader(prefs, 'test.1').ensureSeeded();

    final upgraded = await loader(prefs, 'test.2').ensureSeeded();
    expect(upgraded.skipped, isFalse);
    expect(upgraded.imported, 3);
    expect(prefs.getString(FoodSeedLoader.versionKey), 'test.2');
    // upsert 语义：重复导入不产生重复行
    final all = await db.foodDao.searchFoods('', limit: 100);
    expect(all.length, 3);
  });
  test('seed 收敛：removedIds 删内置残差，保留自定义/被引用行', () async {
    final prefs = await SharedPreferences.getInstance();
    // 预置残差：内置旧行、自定义同名旧行、被 food_entries 引用的内置旧行。
    await db.foodDao.upsertAll(<FoodsCompanion>[
      const FoodsCompanion(
        id: Value('stale-old'),
        nameZh: Value('旧行'),
        nameEn: Value('Stale old'),
        kcalPer100g: Value(1),
        proteinPer100g: Value(0),
        carbPer100g: Value(0),
        fatPer100g: Value(0),
      ),
      const FoodsCompanion(
        id: Value('stale-custom'),
        nameZh: Value('我的旧自定义'),
        nameEn: Value('My stale custom'),
        kcalPer100g: Value(1),
        proteinPer100g: Value(0),
        carbPer100g: Value(0),
        fatPer100g: Value(0),
        isCustom: Value(true),
      ),
      const FoodsCompanion(
        id: Value('stale-referenced'),
        nameZh: Value('被引用旧行'),
        nameEn: Value('Stale referenced'),
        kcalPer100g: Value(1),
        proteinPer100g: Value(0),
        carbPer100g: Value(0),
        fatPer100g: Value(0),
      ),
    ]);
    await db
        .into(db.foodEntries)
        .insert(
          FoodEntriesCompanion.insert(
            localId: 'e1',
            userId: 'anonymous',
            clientRequestId: 'r1',
            syncStatus: SyncStatus.pending,
            datetimeUtc: DateTime.now().toUtc().toIso8601String(),
            foodId: 'stale-referenced',
            source: EntrySource.manual,
            localDate: '2026-09-22',
            updatedAtUtc: '2026-09-22T00:00:00Z',
            createdAtUtc: '2026-09-22T00:00:00Z',
            amountG: 100,
            kcal: 100,
            proteinG: 1,
            carbG: 1,
            fatG: 1,
          ),
        );

    final doc = sampleDoc('test.2')
      ..['removedIds'] = <String>[
        'stale-old',
        'stale-custom',
        'stale-referenced',
        'curated-steamed-rice', // 本版吸收的策展行
      ];
    final pruned = await FoodSeedLoader(
      db: db,
      prefs: prefs,
      assetReader: (_) async => jsonEncode(doc),
    ).ensureSeeded();
    expect(pruned.skipped, isFalse);

    expect(await db.foodDao.getById('stale-old'), isNull); // 内置残差删除
    expect(
      (await db.foodDao.getById('stale-custom'))!.isCustom,
      isTrue,
    ); // 自定义行不受 seed 管治
    expect(
      await db.foodDao.getById('stale-referenced'),
      isNotNull,
    ); // 被历史记录引用：FK 保护保留
    expect(
      await db.foodDao.getById('curated-steamed-rice'),
      isNull,
    ); // 本版吸收行清残差
    expect(await db.foodDao.getById('curated-chicken-breast'), isNotNull);
    // 重放幂等：版本号已落盘则整体跳过，prune 不重复报错
    final again = await FoodSeedLoader(
      db: db,
      prefs: prefs,
      assetReader: (_) async => jsonEncode(doc),
    ).ensureSeeded();
    expect(again.skipped, isTrue);
  });

  test('真实种子资产：全量导入后中文/英文搜索均有结果', () async {
    final file = File('assets/foods/foods.seed.json');
    expect(file.existsSync(), isTrue, reason: 'pubspec 声明的食物库种子资产');
    final doc = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final expected = (doc['foods']! as List<dynamic>).length;

    final prefs = await SharedPreferences.getInstance();
    final realLoader = FoodSeedLoader(
      db: db,
      prefs: prefs,
      assetReader: (_) => file.readAsString(),
    );
    final result = await realLoader.ensureSeeded();
    expect(result.imported, expected);

    expect((await db.foodDao.searchFoods('米饭')).length, greaterThan(0));
    expect((await db.foodDao.searchFoods('rice')).length, greaterThan(0));
    expect((await db.foodDao.searchFoods('鸡胸肉')).length, greaterThan(0));

    // 重复调用幂等
    final again = await realLoader.ensureSeeded();
    expect(again.skipped, isTrue);
  });
}
