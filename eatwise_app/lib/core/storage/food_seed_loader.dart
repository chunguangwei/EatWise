// ignore_for_file: prefer_initializing_formals — 私有字段无法用作命名初始化形参
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// 食物库种子导入结果。
class FoodSeedResult {
  const FoodSeedResult({
    required this.version,
    required this.imported,
    required this.skipped,
  });

  /// seed 文件版本号（由 eatwise_data 管线按内容升级）。
  final String version;

  /// 本次实际写入条数（[skipped] 为 true 时恒为 0）。
  final int imported;

  /// 是否命中幂等跳过。
  final bool skipped;
}

/// D-16：首次启动把 `assets/foods/foods.seed.json` 灌入 drift Foods 表。
///
/// 幂等策略（按 source + 版本号）：seed 版本号与来源清单随导入落盘到
/// SharedPreferences；版本一致且 Foods 表非空则跳过，版本升级（管线重跑）
/// 才重新导入。upsert 语义保证重复执行不产生脏数据。
class FoodSeedLoader {
  FoodSeedLoader({
    required AppDatabase db,
    required SharedPreferences prefs,
    Future<String> Function(String assetPath)? assetReader,
  }) : _db = db,
       _prefs = prefs,
       _assetReader = assetReader ?? rootBundle.loadString;

  /// 种子资产路径（pubspec 已声明）。
  static const String assetPath = 'assets/foods/foods.seed.json';

  /// SharedPreferences 键：已导入的 seed 版本号 / 来源清单。
  static const String versionKey = 'food_seed_imported_version';
  static const String sourcesKey = 'food_seed_imported_sources';

  /// 单批 upsert 条数，避免单事务过大阻塞首启。
  static const int batchSize = 500;

  final AppDatabase _db;
  final SharedPreferences _prefs;
  final Future<String> Function(String assetPath) _assetReader;

  /// 幂等导入。任何资产缺失/解析异常由调用方兜底（main() 中 try-catch 降级）。
  Future<FoodSeedResult> ensureSeeded() async {
    final raw = await _assetReader(assetPath);
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    final version = doc['version']! as String;
    final sources = (doc['sources']! as List<dynamic>).cast<String>();

    final importedVersion = _prefs.getString(versionKey);
    if (importedVersion == version && await _foodCount() > 0) {
      return FoodSeedResult(version: version, imported: 0, skipped: true);
    }

    final foods = (doc['foods']! as List<dynamic>).cast<Map<String, dynamic>>();
    var imported = 0;
    while (imported < foods.length) {
      final end = imported + batchSize > foods.length
          ? foods.length
          : imported + batchSize;
      await _db.foodDao.upsertAll(
        foods.sublist(imported, end).map(_toCompanion).toList(),
      );
      imported = end;
    }

    // seed 版本收敛：清掉历史版本导入、本版已删除的行（同名对账吸收/裁剪）。
    // 幂等可重放——prune 先于版本号落盘，中断后重跑再执行一次无副作用。
    final removedIds =
        (doc['removedIds'] as List<dynamic>? ?? const <dynamic>[])
            .cast<String>();
    await _db.foodDao.deleteBuiltInByIds(removedIds);

    await _prefs.setString(versionKey, version);
    await _prefs.setStringList(sourcesKey, sources);
    return FoodSeedResult(version: version, imported: imported, skipped: false);
  }

  Future<int> _foodCount() {
    return _db
        .customSelect('SELECT COUNT(*) AS c FROM foods', readsFrom: {_db.foods})
        .map((row) => row.read<int>('c'))
        .getSingle();
  }

  FoodsCompanion _toCompanion(Map<String, dynamic> f) {
    // 双语条目 name_zh 必有值；USDA 未翻译条目（zh_verified=false）回退空串，
    // 搜索由双语别名兜底（规格-i18n §四：缺译条目有回退而非空白）。
    return FoodsCompanion(
      id: Value(f['id']! as String),
      nameZh: Value((f['name_zh'] as String?) ?? ''),
      nameEn: Value(f['name_en']! as String),
      aliasesZh: Value(
        jsonEncode(f['aliases_zh'] as List<dynamic>? ?? const <String>[]),
      ),
      aliasesEn: Value(
        jsonEncode(f['aliases_en'] as List<dynamic>? ?? const <String>[]),
      ),
      kcalPer100g: Value((f['kcal']! as num).toDouble()),
      proteinPer100g: Value((f['protein_g']! as num).toDouble()),
      carbPer100g: Value((f['carb_g']! as num).toDouble()),
      fatPer100g: Value((f['fat_g']! as num).toDouble()),
    );
  }
}
