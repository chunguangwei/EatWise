/// 端侧推理引擎网关接口与 typed error。
///
/// 引擎单租户（flutter_gemma 全局串行、KV cache 按会话占内存），
/// 实现侧必须保证 load/infer/inferWithImage/unload 串行（参照 yiren
/// genMutex 模式）。单测不实例化引擎：上层依赖本接口，测试注入 Fake。
library;

import 'dart:typed_data';

/// 端侧推理异常基类（sealed，上层 switch 决策降级策略）。
sealed class OnDeviceLlmException implements Exception {
  const OnDeviceLlmException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// 模型文件缺失/未安装（先去走下载流程）。
final class OnDeviceModelMissingException extends OnDeviceLlmException {
  const OnDeviceModelMissingException(super.message, {super.cause});
}

/// 内存不足（OOM/分配失败）。上层必须**永久禁用端侧估算并降级**
/// （本设备不再重试加载，回退服务端/云端链路），避免反复 OOM 杀进程。
final class OnDeviceLlmMemoryException extends OnDeviceLlmException {
  const OnDeviceLlmMemoryException(super.message, {super.cause});
}

/// 其他引擎错误（加载失败/推理失败/会话异常；可重试）。
final class OnDeviceLlmEngineException extends OnDeviceLlmException {
  const OnDeviceLlmEngineException(super.message, {super.cause});
}

/// 端侧推理网关（窄接口；实现见 flutter_gemma_gateway.dart）。
abstract interface class OnDeviceLlmGateway {
  /// 引擎是否已加载模型。
  bool get isLoaded;

  /// 已加载模型是否带视觉能力（load 时 enableVision: true）。
  bool get visionEnabled;

  /// 加载模型文件（.litertlm 绝对路径）。文件不存在抛
  /// [OnDeviceModelMissingException]；OOM 抛 [OnDeviceLlmMemoryException]。
  ///
  /// [enableVision] 启用多模态视觉编码器（拍照识别用；flutter_gemma 的
  /// supportImage → LiteRT-LM enableVision，视觉编码器固定走 CPU，见
  /// flutter_gemma RuntimeConfig 文档）。已加载且能力一致时幂等复用；
  /// 已加载但视觉能力不一致时引擎侧先关旧模型再按新参数重建（core 单例
  /// 自动处理，调用方无需先 unload）。
  Future<void> load(String modelPath, {bool enableVision = false});

  /// 单次推理，返回模型输出原文（解析由纯函数层负责）。
  /// 每次调用新建会话、结束即关闭（手机端单会话 close+recreate，
  /// 避免多会话叠加 100-500MB 上下文内存，spike §7-7）。
  Future<String> infer(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens,
    double temperature,
    int topK,
    int seed,
  });

  /// 带图推理（拍照识别）：[imageBytes] 为 JPEG/PNG 字节，随用户消息
  /// 一并送入视觉编码器。模型未以视觉能力加载（[visionEnabled] 为 false）
  /// 时抛 [OnDeviceLlmEngineException]——插件在 supportImage=false 时会
  /// 静默丢弃图片按纯文本回答，这里必须显式拦截。
  Future<String> inferWithImage(
    String prompt,
    Uint8List imageBytes, {
    String? systemInstruction,
    int maxOutputTokens,
    double temperature,
    int topK,
    int seed,
  });

  /// 卸载模型释放内存（切低端模式/账号退出时调用）。
  Future<void> unload();
}
