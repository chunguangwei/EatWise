import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';

/// 营养快照（按份量换算后随 FoodEntry 落库，PRD 第五章「营养快照」；
/// §3.2 不仲裁——由 foodId + amount 重新换算生成）。
final class NutritionSnapshot {
  const NutritionSnapshot({
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
  });

  /// 热量（kcal）。
  final double kcal;

  /// 蛋白质（g）。
  final double proteinG;

  /// 碳水（g）。
  final double carbG;

  /// 脂肪（g）。
  final double fatG;

  /// 按食物每 100g 营养 × 份量换算（份量修改实时重算，US-3.1）。
  factory NutritionSnapshot.forAmount(Food food, double amountG) {
    final ratio = amountG / 100;
    return NutritionSnapshot(
      kcal: food.kcalPer100g * ratio,
      proteinG: food.proteinPer100g * ratio,
      carbG: food.carbPer100g * ratio,
      fatG: food.fatPer100g * ratio,
    );
  }
}

/// 记一笔的输入草稿（记录页确认时提交）。
final class RecordDraft {
  const RecordDraft({
    required this.foodId,
    required this.amountG,
    required this.mealUtc,
    required this.source,
    this.note,
  });

  /// 食物库条目 ID。
  final String foodId;

  /// 份量（克），必须 > 0（对齐服务端防腐 §5：amount > 0）。
  final double amountG;

  /// 就餐时间（UTC）。
  final DateTime mealUtc;

  /// 录入方式（拍照/语音/常吃/手动）。
  final EntrySource source;

  /// 备注。
  final String? note;
}

/// 上行结果（对齐《规格-数据同步与四态持久化》§2.3 逐条 ack/nack）。
sealed class PushOutcome {
  const PushOutcome();
}

/// 2xx 成功：回填服务端主键/版本/时间戳（T4）。
final class PushAck extends PushOutcome {
  const PushAck({
    required this.serverId,
    required this.serverVersion,
    required this.serverUpdatedAtUtc,
  });

  /// 服务端分配主键。
  final String serverId;

  /// 服务端版本号（etag 语义）。
  final int serverVersion;

  /// 服务端时间戳（UTC ISO8601，LWW 仲裁依据）。
  final String serverUpdatedAtUtc;
}

/// 可重试失败：网络错误 / 5xx / 429 → 转 pending 保数据（T5，§1.4）。
final class PushRetryable extends PushOutcome {
  const PushRetryable(this.code);

  /// 失败原因码。
  final String code;
}

/// 不可重试失败：4xx（非 409）校验拒绝 → 回滚乐观更新（T7）。
final class PushReject extends PushOutcome {
  const PushReject(this.code);

  /// 校验错误码（如 422 逐字段错误码）。
  final String code;
}

/// 版本冲突：409，自动合并未覆盖 → 转 conflicted 入冲突队列（T6/T11）。
final class PushConflict extends PushOutcome {
  const PushConflict({
    required this.serverVersion,
    required this.serverUpdatedAtUtc,
  });

  /// 服务端当前版本号。
  final int serverVersion;

  /// 服务端当前时间戳（UTC ISO8601）。
  final String serverUpdatedAtUtc;
}
