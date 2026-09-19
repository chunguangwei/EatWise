/// flutter_gemma 版端侧推理网关（生产实现；单测不实例化，依赖接口注入 Fake）。
///
/// spike 实测要点落地（端侧推理 spike 报告 §2/§7）：
/// - `FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()])` 注册引擎
///   （core 包无引擎，缺 litertlm 包 createModel 必败）；
/// - installModel 必须显式 `fileType: ModelFileType.litertlm`
///   （默认 task → MediaPipe 路径，加载即败），ModelType 用 gemma4 专用枚举；
/// - 下载由 OnDeviceModelManager 自管，这里只 `fromFile(path)` 安装；
/// - `maxTokens` 是上下文窗口（KV cache，.litertlm 最低 1024），限输出长度
///   用 createChat 的 `maxOutputTokens`，两者别搞混；
/// - CPU 显式指定（iOS Metal 建不了会话，imagepilot 实测）；
/// - 全局串行：引擎单租户，genMutex 式 Future 链串行化。
///
/// XNNPACK cache 注意（spike §7-6）：首次加载引擎会在应用目录生成
/// ~0.75GiB `*_xnnpack_cache`，属正常缓存，清理策略要保留（删了下次冷加载重建）。
library;

import 'dart:async';
import 'dart:io';

import 'package:eatwise/core/llm/ondevice/ondevice_llm_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

final class FlutterGemmaGateway implements OnDeviceLlmGateway {
  bool _initialized = false;
  InferenceModel? _model;

  /// 当前已加载模型的视觉能力（与 getActiveModel 的 supportImage 对应）。
  bool _visionEnabled = false;

  /// 当前已加载模型的音频能力（与 getActiveModel 的 supportAudio 对应）。
  bool _audioEnabled = false;

  /// genMutex：全局操作串行化（引擎单租户）。
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    // 失败不阻塞后续排队操作
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
    _initialized = true;
  }

  @override
  bool get isLoaded => _model != null;

  @override
  bool get visionEnabled => _model != null && _visionEnabled;

  @override
  bool get audioEnabled => _model != null && _audioEnabled;

  @override
  Future<void> load(
    String modelPath, {
    bool enableVision = false,
    bool enableAudio = false,
  }) {
    return _serialized(() async {
      // 幂等：已加载且能力组合一致直接复用；任一能力不一致时交给
      // getActiveModel —— core 单例检测到 supportImage/supportAudio 变化会
      // 自动关旧模型重建（ActiveModelParams.firstDifference），无需手动
      // unload。
      if (_model != null &&
          _visionEnabled == enableVision &&
          _audioEnabled == enableAudio) {
        return;
      }
      if (!await File(modelPath).exists()) {
        throw OnDeviceModelMissingException('模型文件不存在：$modelPath');
      }
      try {
        await _ensureInitialized();
        if (_model == null) {
          await FlutterGemma.installModel(
            modelType: ModelType.gemma4, // Gemma4 专用枚举，别用 gemmaIt
            fileType: ModelFileType.litertlm, // 必须显式！默认 task 必败
          ).fromFile(modelPath).install();
        }
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 2048, // 上下文窗口（KV cache），非输出长度
          preferredBackend: PreferredBackend.cpu,
          // 视觉编码器开关（Gemma4-E2B 多模态）；编码器后端缺省即 CPU
          // （Metal 备不了 STABLEHLO_COMPOSITE，LiteRT-LM#2461）。
          supportImage: enableVision,
          maxNumImages: enableVision ? 1 : null,
          // 音频编码器开关（端侧 ASR；supportAudio → LiteRT-LM
          // enableAudio，litertlm FFI 全链路支持）。⚠️ E2B 是否含音频塔
          // 未实证：不含则此处加载失败，UI 回落降级（AGENTS.md 已记录）。
          supportAudio: enableAudio,
        );
        _visionEnabled = enableVision;
        _audioEnabled = enableAudio;
      } on OnDeviceLlmException {
        rethrow;
      } on Object catch (e) {
        _model = null;
        _visionEnabled = false;
        _audioEnabled = false;
        throw _classifyLoadError(e);
      }
    });
  }

  @override
  Future<String> infer(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) {
    return _runChat(
      Message.text(text: prompt, isUser: true),
      requiresVision: false,
      systemInstruction: systemInstruction,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topK: topK,
      seed: seed,
    );
  }

  @override
  Future<String> inferWithImage(
    String prompt,
    Uint8List imageBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) {
    return _runChat(
      Message.withImage(text: prompt, imageBytes: imageBytes, isUser: true),
      requiresVision: true,
      systemInstruction: systemInstruction,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topK: topK,
      seed: seed,
    );
  }

  @override
  Future<String> inferWithAudio(
    String prompt,
    Uint8List wavBytes, {
    String? systemInstruction,
    int maxOutputTokens = 96,
    double temperature = 0.15,
    int topK = 1,
    int seed = 42,
  }) {
    return _runChat(
      Message.withAudio(text: prompt, audioBytes: wavBytes, isUser: true),
      requiresAudio: true,
      systemInstruction: systemInstruction,
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topK: topK,
      seed: seed,
    );
  }

  /// 单会话 close+recreate 执行一次推理（spike 定稿采样参数为默认值）。
  Future<String> _runChat(
    Message message, {
    bool requiresVision = false,
    bool requiresAudio = false,
    String? systemInstruction,
    required int maxOutputTokens,
    required double temperature,
    required int topK,
    required int seed,
  }) {
    return _serialized(() async {
      final model = _model;
      if (model == null) {
        throw const OnDeviceLlmEngineException('引擎未加载模型，请先 load()');
      }
      if (requiresVision && !_visionEnabled) {
        // 插件在 supportImage=false 时静默丢图按纯文本回答，必须显式拦截。
        throw const OnDeviceLlmEngineException(
          '当前模型未启用视觉能力，请 load(enableVision: true)',
        );
      }
      if (requiresAudio && !_audioEnabled) {
        // 插件在 supportAudio=false 时静默拒音频消息，必须显式拦截
        //（与视觉拦截同口径）。
        throw const OnDeviceLlmEngineException(
          '当前模型未启用音频能力，请 load(enableAudio: true)',
        );
      }
      InferenceChat? chat;
      try {
        chat = await model.createChat(
          temperature: temperature,
          topK: topK,
          randomSeed: seed,
          systemInstruction: systemInstruction ?? '',
          maxOutputTokens: maxOutputTokens,
        );
        await chat.addQueryChunk(message);
        final response = await chat.generateChatResponse();
        return switch (response) {
          TextResponse(:final token) => token,
          _ => response.toString(),
        };
      } on OnDeviceLlmException {
        rethrow;
      } on Object catch (e) {
        throw _classifyInferError(e);
      } finally {
        try {
          await chat?.session.close();
        } on Object {
          // 会话关闭失败不影响结果返回
        }
      }
    });
  }

  @override
  Future<void> unload() {
    return _serialized(() async {
      final model = _model;
      _model = null;
      _visionEnabled = false;
      _audioEnabled = false;
      if (model != null) {
        try {
          await model.close();
        } on Object {
          // 卸载失败静默（进程内引用已清，原生侧随引擎析构回收）
        }
      }
    });
  }

  /// OOM 关键字识别（iOS jetsam/Android LMK 前引擎抛出的分配失败）。
  static bool _looksLikeOom(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('out of memory') ||
        s.contains('outofmemory') ||
        s.contains('oom') ||
        s.contains('cannot allocate memory') ||
        s.contains('failed to allocate') ||
        s.contains('memory pressure');
  }

  static OnDeviceLlmException _classifyLoadError(Object e) {
    final s = e.toString();
    if (_looksLikeOom(e)) {
      return OnDeviceLlmMemoryException('引擎加载内存不足', cause: e);
    }
    if (s.contains('No active inference model') ||
        s.contains('not found') && s.contains('.litertlm')) {
      return OnDeviceModelMissingException('模型未安装或文件缺失', cause: e);
    }
    return OnDeviceLlmEngineException('引擎加载失败', cause: e);
  }

  static OnDeviceLlmException _classifyInferError(Object e) {
    if (_looksLikeOom(e)) {
      return OnDeviceLlmMemoryException('推理过程内存不足', cause: e);
    }
    return OnDeviceLlmEngineException('推理失败', cause: e);
  }
}
