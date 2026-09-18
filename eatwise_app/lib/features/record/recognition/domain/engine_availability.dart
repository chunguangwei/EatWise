/// AI 引擎可用性探测（拍照/语音/自由记入口中的估算链三态判定）。
///
/// 三态语义（真机反馈驱动：无引擎时直接「无法识别」是死胡同，应引导
/// 下载模型或配置 API）：
/// - ondeviceReady：端侧开关启用且模型磁盘就绪（字节+魔数校验）；
/// - userApiConfigured：用户自配 LLM 配置完整（估算链有云端路——
///   自定义食物 AI 估算可用，即视为「有 AI 路径」）；
/// - none：两者都无 → 各入口流程应展示引擎引导卡而非「无法识别」。
library;

/// 估算链可用引擎三态。
enum AiEngineAvailability {
  /// 端侧模型已就绪（开关开 + 磁盘校验过）。
  ondeviceReady,

  /// 用户自配云端 API 已配置完整。
  userApiConfigured,

  /// 无任何可用引擎 → 走引导卡（下载本地模型/配置云端 API/先手动搜索）。
  none,
}

/// 三态判定（纯函数，单测直接注入两路布尔）。
AiEngineAvailability aiEngineAvailabilityOf({
  required bool onDeviceReady,
  required bool userApiConfigured,
}) {
  if (onDeviceReady) return AiEngineAvailability.ondeviceReady;
  if (userApiConfigured) return AiEngineAvailability.userApiConfigured;
  return AiEngineAvailability.none;
}

/// 引导卡路由目标（默认实现都深链 /settings/ai-model——端侧模型卡与
/// 自定义 API 配置同页；枚举保留扩展位，便于后续拆分锚点）。
enum AiEngineGuideTarget {
  /// 端侧模型卡（下载/启用本地模型）。
  onDeviceModel,

  /// 自定义云端 API 配置区。
  cloudApi,
}
