import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/session_lease.dart';
import 'package:eatwise/core/storage/database.dart';

/// 食物搜索（D-16）：本地优先 + 远端 K1 补充。
///
/// 先查本地 drift 双语库（离线兜底），远端 /foods/search 可用时把结果
/// 合入本地缓存（FoodDao.upsertAll），返回「本地命中在前 + 远端补充」
/// 的并集；远端失败（离线/未登录/5xx）静默降级为纯本地结果。
final class RemoteFoodSearch {
  RemoteFoodSearch({required this.dio, required this.db, required this.userId});

  /// 已装配 dio。
  final Dio dio;

  /// 本地库。
  final AppDatabase db;

  /// 当前账号；共享食物对所有账号可见，个人食物仅归属账号可见。
  final String userId;

  /// 搜索（本地优先，远端补充合入本地缓存）。
  Future<List<Food>> search(String query, {int limit = 20}) =>
      withApiSession(dio, () => _search(query, limit: limit), userId: userId);

  Future<List<Food>> _search(String query, {required int limit}) async {
    final local = await db.foodDao.searchFoods(
      query,
      limit: limit,
      ownerUserId: userId,
    );
    checkActiveSession();
    List<Map<String, dynamic>> remoteItems;
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/foods/search',
        queryParameters: <String, dynamic>{'q': query, 'limit': limit},
      );
      checkActiveSession();
      final body = response.data ?? const <String, dynamic>{};
      remoteItems = (body['items'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
    } on DioException {
      checkActiveSession();
      return local; // 离线/未登录/服务端异常：本地结果兜底
    }
    if (remoteItems.isEmpty) return local;
    // 远端结果合入本地缓存（离线后仍可搜到）。社区共享食物（source==
    // 'community'）下行标记 contributionStatus=approved；若该食物是本人
    // 贡献的自定义食物（本地 isCustom=true 且已贡献），保留 isCustom，
    // 搜索行标签显示「已共享」而非「社区」（审核晋升 id 不变，服务端
    // approve 后 isCustom 转 false，仅本地标记可区分）。
    await db.transaction(() async {
      checkActiveSession();
      for (final item in remoteItems) {
        var companion = _toCompanion(item);
        final existing = await db.foodDao.getById(companion.id.value);
        checkActiveSession();
        // Search can finish after a newer local edit. Read and cache in one
        // transaction so the old response cannot overwrite that dirty draft.
        if (existing != null &&
            existing.isCustom &&
            existing.ownerUserId == userId &&
            existing.customSyncPending) {
          continue;
        }
        if (item['source'] == 'community' &&
            item['isCustom'] != true &&
            existing != null &&
            existing.isCustom &&
            existing.ownerUserId == userId &&
            existing.contributionStatus != null) {
          // An author-only marker must retain its owner; another account's
          // shared result must use the server's globally visible identity.
          companion = companion.copyWith(
            isCustom: const Value(true),
            ownerUserId: Value(userId),
          );
        }
        await db.foodDao.upsertAll([companion]);
        checkActiveSession();
      }
    });
    checkActiveSession();
    // Keep ranking but return the current visible rows, not the snapshots read
    // before the network await (which can precede an edit or promotion).
    final ids = <String>{
      ...local.map((food) => food.id),
      ...remoteItems.map((item) => item['id']! as String),
    };
    final merged = <Food>[];
    for (final id in ids) {
      final food = await db.foodDao.getById(id, ownerUserId: userId);
      checkActiveSession();
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
      // K1 搜索结果标注 isCustom（个人库排内置后）；缓存保留标记供「自定义」标签。
      isCustom: Value(item['isCustom'] == true),
      ownerUserId: Value(item['isCustom'] == true ? userId : null),
      source: Value(item['source'] as String? ?? 'manual'),
      // 社区共享食物下行标记 approved（「社区」标签）；非社区项不动本地
      // 贡献状态（保存/贡献时写入的 pending/rejected 不被下行覆盖）〔假设：
      // 服务端无按 id 批量查候选状态端点，以本地写入 + 本处下行标记为准〕。
      contributionStatus: item['source'] == 'community'
          ? const Value('approved')
          : const Value.absent(),
    );
  }
}
