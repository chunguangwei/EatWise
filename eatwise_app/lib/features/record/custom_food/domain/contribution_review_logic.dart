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

/// 幽灵贡献行 id（已下架收敛，走查②「服务端删了客户端还在」）：本地行
/// 带贡献审核状态（contributionStatus 非空）但不在服务端「我的贡献」
/// foodId 全集——管理员删除审核内容后候选不再返回，本地贡献物是幽灵。
/// 调用方按 isCustom 分流：自定义行=清记录+删行（同服务端级联口径），
/// 共享行=仅清徽标残留（纠错终态写在共享行上，候选删除后徽标须复位）。
///
/// 行级反查（不依赖 known 表基线）的原因：
/// - 覆盖 pending 起点（管理员删 pending 候选=撤下内容，服务端同口径
///   软删食物行；状态迁移 diff 只认 pending→终态，候选整行消失无迁移可 diff）；
/// - 不依赖基线格式/首轮时序，升级设备与全新安装行为一致。
/// 首轮安全：服务端列表是全量分页拉取，foodId 集合完整；本地行只可能
/// 因「自己提交过贡献」带状态，服务端缺席即已删，无误清窗口。
List<String> findGhostContributionFoodIds({
  required Iterable<({String id, String? contributionStatus})> localRows,
  required Set<String> serverFoodIds,
}) {
  return <String>[
    for (final r in localRows)
      if (r.contributionStatus != null && !serverFoodIds.contains(r.id)) r.id,
  ];
}
