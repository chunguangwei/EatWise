import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_nutrition_estimator.dart';
import 'package:eatwise/core/llm/user_llm_client.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// 估算实际生效来源（埋点 `record_ai_estimate.source` 维度）。
enum FoodEstimateSource {
  /// 端侧小模型（Gemma4-E2B，本机离线推理）。
  ondevice,

  /// 用户自配 LLM 直连。
  userApi,

  /// 端侧视觉读表（拍营养表 OCR 预填；与 ondevice 同模型，区分场景埋点）。
  photoOcr,
}

/// FoodEstimateSource → 埋点 source 字符串。
String foodEstimateSourceName(FoodEstimateSource source) => switch (source) {
  FoodEstimateSource.ondevice => 'ondevice',
  FoodEstimateSource.userApi => 'user_api',
  FoodEstimateSource.photoOcr => 'photo_ocr',
};

/// 端侧估算窄抽象（测试注入 Fake；与 UserEstimateSource 同法）。
/// 就绪判定内聚在实现里（编排器不直接触碰模型管理器/推理网关）。
abstract interface class OnDeviceEstimateSource {
  /// OOM 后永久禁用（本设备不再尝试端侧）。
  bool get isPermanentlyDisabled;

  /// 模型已就绪（磁盘校验通过；false 时不得调 [estimate] 触发下载）。
  bool get isReady;

  /// 估算每 100g 营养；解析失败返回 null；引擎/模型异常抛
  /// [OnDeviceLlmException]/[OnDeviceModelException] 子类。
  Future<OnDeviceNutritionEstimate?> estimate(String foodName);
}

/// 生产适配：核心层估算器 + 模型管理器快照判定就绪。
final class OnDeviceEstimatorSource implements OnDeviceEstimateSource {
  const OnDeviceEstimatorSource(this._estimator);

  final OnDeviceNutritionEstimator _estimator;

  @override
  bool get isPermanentlyDisabled => _estimator.isPermanentlyDisabled;

  @override
  bool get isReady =>
      _estimator.modelManager.snapshot.status == OnDeviceModelStatus.ready;

  @override
  Future<OnDeviceNutritionEstimate?> estimate(String foodName) =>
      _estimator.estimate(foodName);
}

/// 估算结果 + 实际生效来源。
final class EstimateOutcome {
  const EstimateOutcome({required this.estimate, required this.source});

  /// 估算结果（端侧/用户自配 API 产物）。
  final FoodEstimate estimate;

  /// 实际生效来源（端侧/用户 API）。
  final FoodEstimateSource source;
}

/// 两级估算编排：端侧（开关启用且模型就绪）→ 已配置用户模型直连；
/// 两级都不可用抛 503 ESTIMATE_UNAVAILABLE，由 UI 走「估算暂不可用」
/// 降级分支（无服务端兜底）。
///
/// 端侧层约定：
/// - 开关关闭 / 模型未就绪 / 已被 OOM 永久禁用 → 直接跳过，不触发下载；
/// - 端侧任何失败（解析失败/引擎错误/OOM）→ 静默降级下一级，不阻断；
/// - 端侧 dubious 映射 confidence='low'（UI 据 source=ondevice 改显示
///   「估算存疑，请核对」）。
class FoodEstimateOrchestrator {
  FoodEstimateOrchestrator({
    required this._store,
    required this._userClient,
    this._onDeviceEnabled,
    this._onDeviceSource,
  });

  final LlmConfigStore _store;
  final UserEstimateSource _userClient;

  /// 端侧开关（设置页持久化；null = 未接线，等同关闭）。
  final bool Function()? _onDeviceEnabled;

  /// 端侧估算源惰性获取（避免开关关闭时实例化推理网关）。
  final OnDeviceEstimateSource Function()? _onDeviceSource;

  /// 估算入口：端侧优先（开关开且模型就绪），随后用户模型直连；
  /// 两级都不可用抛 503 ESTIMATE_UNAVAILABLE（UI 提示手动填写）。
  Future<EstimateOutcome> estimate(String name, {String? description}) async {
    final onDevice = await _tryOnDevice(name);
    if (onDevice != null) return onDevice;
    final config = (await _store.read())?.effective();
    if (config == null || !config.isComplete) throw _estimateUnavailable();
    try {
      return EstimateOutcome(
        estimate: await _userClient.estimate(name, description: description),
        source: FoodEstimateSource.userApi,
      );
    } on ApiException {
      rethrow;
    } on Object {
      throw _estimateUnavailable();
    }
  }

  /// 统一的「估算不可用」异常（与 isEstimateUnavailable 判定口径一致）。
  BusinessApiException _estimateUnavailable() => const BusinessApiException(
    httpStatus: 503,
    code: 'ESTIMATE_UNAVAILABLE',
    message: 'estimate unavailable',
  );

  /// 端侧估算（不可用/失败返回 null → 降级下一级）。
  Future<EstimateOutcome?> _tryOnDevice(String name) async {
    final enabled = _onDeviceEnabled;
    final sourceOf = _onDeviceSource;
    if (enabled == null || sourceOf == null || !enabled()) return null;
    final source = sourceOf();
    // 未就绪不调 estimate（会触发 2.41GB 下载）；
    // OOM 永久禁用后本设备不再尝试端侧。
    if (source.isPermanentlyDisabled || !source.isReady) return null;
    try {
      final result = await source.estimate(name);
      if (result == null) return null; // 解析失败 → 降级
      return EstimateOutcome(
        estimate: FoodEstimate(
          per100g: NutritionSnapshot(
            kcal: result.values.kcal,
            proteinG: result.values.proteinG,
            carbG: result.values.carbsG,
            fatG: result.values.fatG,
          ),
          // dubious → low（UI 按 source=ondevice 显示「估算存疑，请核对」）。
          confidence: result.dubious ? 'low' : 'medium',
        ),
        source: FoodEstimateSource.ondevice,
      );
    } on OnDeviceLlmException {
      return null; // 引擎错误/OOM：静默降级（永久禁用由编排器内部处理）
    } on OnDeviceModelException {
      return null; // 模型侧异常（如竞态删除）：静默降级
    }
  }
}
