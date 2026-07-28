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

/// 识别不可用：第三方 API 未接入/超时/无网络/服务端未部署。
/// UI 按 D-16 兜底语义引导手动搜索（不丢已输入内容）。
final class RecognitionUnavailable extends RecognitionOutcome {
  const RecognitionUnavailable(this.reason);

  /// 失败原因码（埋点用：not_integrated / timeout / network / server_error）。
  final String reason;
}
