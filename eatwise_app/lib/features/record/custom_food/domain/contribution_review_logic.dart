import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';

/// 贡献审核状态迁移（纯逻辑，「我的贡献」下行与本地已知状态 diff）。
///
/// 只关心 pending → approved / pending → rejected 两种迁移：
/// - approved：条目转正（去掉「审核中」标记）；
/// - rejected：清除该食物相关记录并提示用户。
/// 首次见到的候选（本地无记录）按当前状态静默纳入基线——不触发提示
/// （避免首轮同步把历史驳回当成新事件反复打扰）。
final class ContributionTransition {
  const ContributionTransition({
    required this.candidateId,
    required this.foodId,
    required this.to,
    required this.kind,
  });

  /// 候选 id。
  final String candidateId;

  /// 被贡献的食物 id（本地清理/标记按此定位）。
  final String foodId;

  /// 迁移到的终态（仅 approved / rejected）。
  final FoodContributionStatus to;

  /// 贡献类型：rejected 时 correction 只落状态**不清记录**（目标食物仍在
  /// 共享库，服务端同口径）；custom/barcode 才清（走查：纠错驳回误删历史）。
  final FoodContributionKind kind;
}

/// 已知状态表（candidateId → 上次同步时的状态字符串，与
/// [foodContributionStatusName] 同口径）与当前贡献列表 diff。
/// 返回 pending→终态的迁移列表（同一候选重复迁移不重复产出——
/// 已知表落库后下轮 from 已是终态，天然幂等）。
List<ContributionTransition> diffContributionTransitions(
  Map<String, String> known,
  List<FoodContribution> current,
) {
  final transitions = <ContributionTransition>[];
  for (final c in current) {
    if (known[c.id] != 'pending') continue; // 首次见到/非 pending 起点不迁移
    if (c.status == FoodContributionStatus.approved ||
        c.status == FoodContributionStatus.rejected) {
      transitions.add(
        ContributionTransition(
          candidateId: c.id,
          foodId: c.foodId,
          to: c.status,
          kind: c.kind,
        ),
      );
    }
  }
  return transitions;
}

/// 当前贡献列表 → 新已知状态表（全量替换口径：只保留服务端仍返回的候选）。
Map<String, String> knownStatusMapOf(List<FoodContribution> current) {
  return <String, String>{
    for (final c in current) c.id: foodContributionStatusName(c.status),
  };
}
