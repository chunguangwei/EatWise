import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/storage/database.dart';

/// 食物搜索（D-16）：本地优先 + 远端 K1 补充。
///
/// 先查本地 drift 双语库（离线兜底），远端 /foods/search 可用时把结果
/// 合入本地缓存（FoodDao.upsertAll），返回「本地命中在前 + 远端补充」
/// 的并集；远端失败（离线/未登录/5xx）静默降级为纯本地结果。
final class RemoteFoodSearch {
  RemoteFoodSearch({required this.dio, required this.db});

  /// 已装配 dio。
  final Dio dio;

  /// 本地库。
  final AppDatabase db;

  /// 搜索（本地优先，远端补充合入本地缓存）。
  Future<List<Food>> search(String query, {int limit = 20}) async {
    final local = await db.foodDao.searchFoods(query, limit: limit);
    List<Map<String, dynamic>> remoteItems;
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/foods/search',
        queryParameters: <String, dynamic>{'q': query, 'limit': limit},
      );
      final body = response.data ?? const <String, dynamic>{};
      remoteItems = (body['items'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
    } on DioException {
      return local; // 离线/未登录/服务端异常：本地结果兜底
    }
    if (remoteItems.isEmpty) return local;
    // 远端结果合入本地缓存（离线后仍可搜到）。
    await db.foodDao.upsertAll(remoteItems.map(_toCompanion).toList());
    // 本地命中在前，远端新增按服务端相关度序追加（按 id 去重）。
    final localIds = local.map((f) => f.id).toSet();
    final merged = List<Food>.of(local);
    for (final item in remoteItems) {
      final id = item['id'] as String?;
      if (id == null || localIds.contains(id)) continue;
      final food = await db.foodDao.getById(id);
      if (food != null) merged.add(food);
    }
    return merged.take(limit).toList();
  }

  /// K1 item → Foods 行（本地别名表分中英两列；远端 aliases 中英混合，
  /// 统一进中文别名列，LIKE 搜索不受影响）。
  FoodsCompanion _toCompanion(Map<String, dynamic> item) {
    return FoodsCompanion(
      id: Value(item['id']! as String),
      nameZh: Value(item['nameZh']! as String),
      nameEn: Value(item['nameEn']! as String),
      aliasesZh: Value(jsonEncode(item['aliases'] ?? const <dynamic>[])),
      kcalPer100g: Value((item['kcalPer100g'] as num?)?.toDouble() ?? 0),
      proteinPer100g: Value((item['proteinPer100g'] as num?)?.toDouble() ?? 0),
      carbPer100g: Value((item['carbsPer100g'] as num?)?.toDouble() ?? 0),
      fatPer100g: Value((item['fatPer100g'] as num?)?.toDouble() ?? 0),
    );
  }
}
