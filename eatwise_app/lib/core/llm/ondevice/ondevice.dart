/// 端侧小模型 AI 估算（Gemma4-E2B .litertlm）公共 API 出口。
///
/// 分层：
/// - ondevice_model_spec：静态规格与选源纯函数；
/// - ondevice_model_manager：下载/续传/校验/状态机；
/// - ondevice_llm_gateway(+flutter_gemma_gateway)：推理引擎网关（接口/实现）；
/// - nutrition_estimate_logic：prompt/解析/sanity-clamp 纯函数；
/// - ondevice_nutrition_estimator：编排（食物库未命中兜底）；
/// - ondevice_providers：riverpod 接线骨架（UI 棒次接入）。
library;

export 'nutrition_estimate_logic.dart';
export 'ondevice_llm_gateway.dart';
export 'ondevice_model_manager.dart';
export 'ondevice_model_spec.dart';
export 'ondevice_nutrition_estimator.dart';
export 'ondevice_providers.dart';
