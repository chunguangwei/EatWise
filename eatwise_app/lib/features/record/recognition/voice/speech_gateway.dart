import 'package:speech_to_text/speech_to_text.dart';

/// 系统 ASR 抽象（D-16：iOS Speech framework / Android SpeechRecognizer，
/// 不引入独立 NLP 服务；便于 widget 测试注入 fake）。
abstract interface class SpeechGateway {
  /// 初始化并按需申请权限（合规 §3：首次点击「语音」入口时申请；
  /// iOS 同时申请语音识别 + 麦克风，Android RECORD_AUDIO）。
  /// 返回 false = 权限被拒或设备不支持（UI 走降级提示，不阻断记录）。
  Future<bool> initialize();

  /// 开始听写；[onText] 回传实时部分结果与最终结果。
  /// [localeId] 如 zh_CN / en_US（D-15 跟随 App 语言）。
  Future<void> start({
    required void Function(String text) onText,
    required String localeId,
  });

  /// 停止听写（保留已识别文本）。
  Future<void> stop();

  /// 取消听写（丢弃本次会话，不丢用户已输入内容）。
  Future<void> cancel();
}

/// speech_to_text 插件实现（生产路径，pub.dev 主流系统 ASR 封装）。
final class SpeechToTextGateway implements SpeechGateway {
  SpeechToTextGateway({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  Future<bool> initialize() async {
    try {
      return await _speech.initialize();
    } on Object {
      // 平台通道缺失（如无 Google 服务的 ROM）→ 视为不可用，走降级。
      return false;
    }
  }

  @override
  Future<void> start({
    required void Function(String text) onText,
    required String localeId,
  }) {
    return _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: localeId,
        // 说完停顿 3 秒自动收尾，控制「≤15 秒 ≤3 步」节奏（PRD M3）。
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
