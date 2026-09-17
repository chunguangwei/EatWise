import 'package:eatwise/core/llm/ondevice/nutrition_estimate_logic.dart';
import 'package:eatwise/core/storage/database.dart';

/// 拍照识别单个候选食物（PRD M3：候选食物 + 默认份量 + 置信度）。
final class RecognizedCandidate {
  const RecognizedCandidate({
    required this.food,
    required this.defaultAmountG,
    required this.confidence,
  });

  /// 命中的食物库条目（识别结果须映射回自建核心库，D-16）。
  final Food food;

  /// 默认份量（克），用户可在结果卡上修改。
  final double defaultAmountG;

  /// 置信度 0.0–1.0；低于 [lowConfidenceThreshold] 时结果卡标「请确认」。
  final double confidence;

  /// 低置信度阈值（PRD M3「识别置信度低 → 标记请确认」，
  /// 〔假设〕具体阈值随第三方识别 API 实测分布校准）。
  static const double lowConfidenceThreshold = 0.7;

  /// 是否低置信度（需用户确认，不直接入账高风险结果）。
  bool get isLowConfidence => confidence < lowConfidenceThreshold;
}

/// 拍照识别结果（D-16：异步不阻塞，识别不可用走手动搜索兜底）。
sealed class RecognitionOutcome {
  const RecognitionOutcome();
}

/// 识别成功：候选按置信度降序。
final class RecognitionSuccess extends RecognitionOutcome {
  const RecognitionSuccess(this.candidates);

  /// 候选食物列表（Top-N，首个为 Top-1）。
  final List<RecognizedCandidate> candidates;
}

/// 库未收录时透出的模型估值（仅 no_match 场景携带）：
/// 识别名（中/英）+ 每 100g 估算营养 + 低置信标记，供「以估算值添加」
/// 预填自定义食物表单——估值只作表单初值（用户可改），不直接入账。
final class RecognizedFoodEstimate {
  const RecognizedFoodEstimate({
    required this.name,
    this.nameEn,
    required this.per100g,
    required this.lowConfidence,
  });

  /// 识别出的中文食物名（自定义食物表单菜名初值）。
  final String name;

  /// 英文通用名（双语输出时才有；保存时辅助英文名/别名）。
  final String? nameEn;

  /// 模型估算的每 100g 营养（表单四营养初值）。
  final OnDeviceNutritionValues per100g;

  /// 低置信（sanity-clamp  dubious 或类别词 tooGeneric）→ 表单显「估算
  /// 存疑，请核对」（与端侧 AI 估算预填同款提示）。
  final bool lowConfidence;
}

/// 识别不可用：第三方 API 未接入/超时/无网络/服务端未部署，
/// 或端侧视觉识别各环节失败（bad_image / parse_failed / no_match /
/// ondevice_error / ondevice_oom / ondevice_disabled）。
/// UI 按 D-16 兜底语义引导手动搜索（不丢已输入内容）。
final class RecognitionUnavailable extends RecognitionOutcome {
  const RecognitionUnavailable(this.reason, {this.detail, this.estimate});

  /// 失败原因码（埋点用：not_integrated / timeout / network / server_error /
  /// bad_image / parse_failed / no_match / ondevice_error / ondevice_oom /
  /// ondevice_disabled）。
  final String reason;

  /// 可选详情（端侧识别透出给用户的内容）：
  /// - parse_failed/「无法识别」：模型原始回复（已去换行并截断，见
  ///   cleanRecognitionDetail）；
  /// - no_match：识别出的食物名（库未收录，引导换词手动搜索）；
  /// - 其他原因码恒为 null（无用户可读的模型内容）。
  final String? detail;

  /// 库未收录（no_match）时透出的模型估值（识别名 + 每 100g 估算），
  /// 供「以估算值添加」预填自定义食物表单；其他原因码恒为 null。
  final RecognizedFoodEstimate? estimate;
}
