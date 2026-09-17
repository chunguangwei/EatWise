import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 拍照识别单条明细候选（多行明细协议：组合餐拆分后每种主要食物一条；
/// 单一食物就一条）。
final class RecognizedMealItem {
  const RecognizedMealItem({
    required this.name,
    this.nameEn,
    required this.grams,
    required this.per100g,
    required this.confidence,
    this.food,
  });

  /// 展示名（库命中用库内规范名；未命中用模型识别名）。
  final String name;

  /// 英文通用名（双语识别/库内条目才有）。
  final String? nameEn;

  /// 份量初值（克）：模型按图中实际份量估算，已 clamp 到合理区间
  /// （photo_recognition_logic kPhotoGramsMin/Max）；明细卡克数输入框
  /// 初值，用户可改。
  final double grams;

  /// 每 100g 营养：命中库用**库内精准值**；未命中用模型估值（估值只作
  /// 明细行展示与自动建自定义食物初值，用户确认后才入账，D-16 口径）。
  final NutritionSnapshot per100g;

  /// 置信度 0.0–1.0；低于 [lowConfidenceThreshold] 明细行标「请确认」。
  final double confidence;

  /// 库匹配结果（null = 库未命中；「全部记录」时该条目自动建成自定义
  /// 食物（模型估值 + llmEstimate 口径）再入账）。
  final Food? food;

  /// 低置信度阈值（PRD M3「识别置信度低 → 标记请确认」）。
  static const double lowConfidenceThreshold = 0.7;

  /// 是否低置信度（需用户确认，不直接入账高风险结果）。
  bool get isLowConfidence => confidence < lowConfidenceThreshold;

  /// 是否命中食物库（未命中条目展示模型估值并标低置信）。
  bool get isMatched => food != null;
}

/// 拍照识别结果（D-16：异步不阻塞，识别不可用走手动搜索兜底）。
sealed class RecognitionOutcome {
  const RecognitionOutcome();
}

/// 识别成功：明细条目列表（组合餐多条；单一食物一条）。
final class RecognitionSuccess extends RecognitionOutcome {
  const RecognitionSuccess(this.items);

  /// 明细条目列表（顺序即模型输出顺序）。
  final List<RecognizedMealItem> items;
}

/// 识别不可用：第三方 API 未接入/超时/无网络/服务端未部署，
/// 或端侧视觉识别各环节失败（bad_image / parse_failed / ondevice_error /
/// ondevice_oom / ondevice_disabled）。
/// UI 按 D-16 兜底语义引导手动搜索（不丢已输入内容）。
final class RecognitionUnavailable extends RecognitionOutcome {
  const RecognitionUnavailable(this.reason, {this.detail});

  /// 失败原因码（埋点用：not_integrated / timeout / network / server_error /
  /// bad_image / parse_failed / ondevice_error / ondevice_oom /
  /// ondevice_disabled）。
  final String reason;

  /// 可选详情（端侧识别透出给用户的内容）：
  /// - parse_failed/「无法识别」：模型原始回复（已去换行并截断，见
  ///   cleanRecognitionDetail）；
  /// - 其他原因码恒为 null（无用户可读的模型内容）。
  final String? detail;
}
