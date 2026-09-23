import 'dart:async';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/moderation/application/moderation_controller.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 管理员删除食品结果（404 目标已不在服务端按「已从本地移除」处理，
/// 不当错误抛出——本地缓存可能滞留服务端已删行，见 v1.13.18 走查）。
final class AdminFoodDeleteResult {
  const AdminFoodDeleteResult({this.deletedEntries, this.alreadyGone = false});

  /// 服务端级联清理的记录条数（alreadyGone 时为 null——服务端本无此行）。
  final int? deletedEntries;

  /// 服务端已不存在该行（404 NOT_FOUND）：本地照样直清，提示用友好文案。
  final bool alreadyGone;
}

/// 管理员删除食品（移动端；服务端 DELETE /v1/moderation/foods/:id，
/// 与管理台 adminDeleteFood 同口径：软删任意来源食物行 + 跨用户级联
/// tombstone 饮食记录）。
///
/// 成功后本机直清（与 ModerationController._clearLocalFoodOnDelete 同思路，
/// 但对象为任意食品、不限本人贡献物）：
/// - 引用该 foodId 的本机记录两态删除（未上行物理删 / 已上行 tombstone，
///   由同步轮上行 delete op）+ 按归属日重算聚合缓存；
/// - 本地食物行整行删除（共享行同样删——服务端已软删，本地保留即成幽灵
///   搜索结果；种子库若含该行，仅种子版本升级重灌时回来，与服务端种子
///   治理同步收敛）；
/// - 条目食物缓存 / 搜索缓存失效（常驻流不自刷已删行，v1.13.15 教训）；
/// - 触发一轮同步（下行 tombstone 收敛他端；他端记录由级联 tombstone
///   下行清理）。
///
/// 404 NOT_FOUND（服务端已删，本地幽灵行滞留）：按已删除处理——照样本机
/// 直清并返回 alreadyGone（UI 提示「已从本地移除」）。其余失败上抛
/// （409 FOOD_UNDER_REVIEW 等由调用方提示），本机不做任何清理。
Future<AdminFoodDeleteResult> deleteFoodAsAdmin(
  WidgetRef ref,
  Food food,
) async {
  try {
    final deletedEntries = await ref
        .read(moderationRemoteProvider)
        .deleteFood(food.id);
    await _clearLocalFoodReferences(ref, food);
    return AdminFoodDeleteResult(deletedEntries: deletedEntries);
  } on BusinessApiException catch (e) {
    if (e.code != 'NOT_FOUND') rethrow;
    // 目标已不在服务端（如管理台手工软删过的重复行）：本地直清收敛幽灵。
    await _clearLocalFoodReferences(ref, food);
    return const AdminFoodDeleteResult(alreadyGone: true);
  }
}

/// 本机直清（失败静默：远端已删，后续同步轮 ghost 收敛兜底）。
Future<void> _clearLocalFoodReferences(WidgetRef ref, Food food) async {
  try {
    final repo = ref.read(recordRepositoryProvider);
    final db = repo.db;
    final entries = await db.foodEntryDao.entriesForFood(repo.userId, food.id);
    final dates = <String>{};
    for (final entry in entries) {
      await db.foodEntryDao.deleteEntry(entry.localId);
      dates.add(entry.localDate);
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final date in dates) {
      await db.foodEntryDao.recomputeDailyNutrition(
        repo.userId,
        date,
        updatedAtUtc: nowIso,
      );
    }
    await db.foodDao.deleteById(food.id);
  } on Object {
    // 本机直清失败不影响删除结果（同步轮兜底）。
  }
  ref.invalidate(entryFoodProvider(food.id));
  // 搜索结果缓存行同步失效（常驻流不会自刷已删行）。
  ref.invalidate(recordFoodSearchProvider);
  // 触发一轮同步：本机 tombstone 上行 + 下行级联 tombstone 收敛。
  try {
    unawaited(ref.read(recordSyncEngineProvider).syncNow());
  } on Object {
    // 同步引擎未装配（如测试环境仅注入仓储）时跳过。
  }
}
