/// 端侧语音转写纯函数层：PCM16 → WAV 封装（LiteRT-LM 音频输入按 WAV
/// bytes 处理）、转写输出清洗（模型可能多输出引号/前缀/多行）、
/// 双语转写 prompt。零 Flutter/插件依赖，可单测。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 端侧录音规格：16kHz 单声道 PCM16（LiteRT-LM 音频编码器输入口径）。
const int kOnDeviceAsrSampleRate = 16000;
const int kOnDeviceAsrNumChannels = 1;

/// PCM16 裸数据 → 标准 44 字节 RIFF/WAVE 头 + 数据的完整 WAV 字节。
///
/// 字段布局（小端）：RIFF/WAVE 容器 + fmt 块（PCM=1）+ data 块；
/// byteRate = sampleRate × channels × 2（16bit），blockAlign = channels × 2。
Uint8List wrapPcm16AsWav(
  Uint8List pcmBytes, {
  int sampleRate = kOnDeviceAsrSampleRate,
  int numChannels = kOnDeviceAsrNumChannels,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final blockAlign = numChannels * (bitsPerSample ~/ 8);
  final dataSize = pcmBytes.length;

  final out = BytesBuilder();
  void writeAscii(String s) => out.add(ascii.encode(s));
  void u32(int v) => out.add(<int>[
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);
  void u16(int v) => out.add(<int>[v & 0xff, (v >> 8) & 0xff]);

  writeAscii('RIFF');
  u32(36 + dataSize);
  writeAscii('WAVE');
  writeAscii('fmt ');
  u32(16); // fmt 块大小（PCM）
  u16(1); // audioFormat = PCM
  u16(numChannels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  writeAscii('data');
  u32(dataSize);
  out.add(pcmBytes);
  return out.takeBytes();
}

/// 转写 prompt（按 App 语言；只输出转写内容，低温采样在调用侧）。
/// 措辞沿用 yiren（Offline Translator）真机调优的「逐字转写机」版本：
/// 显式禁止翻译/改写/回答——Gemma 音频转写的常见失败模式是把问句
/// 当问题回答而不是转写。
const String kTranscribePromptZh =
    '你是一台语音转写机。把这段语音【逐字】转写成简体中文文字：说什么写什么，完全忠实原话。'
    '严禁翻译、严禁改写或润色、严禁总结、严禁回答或接话——即使内容是一个问题也只转写不回答。'
    '保留口语词和重复。只输出转写文字本身，不要任何前后缀。';
const String kTranscribePromptEn =
    'You are a speech-to-text machine. Transcribe this speech VERBATIM in English: '
    'write exactly what is said, fully faithful. Never translate, never paraphrase, '
    'never summarize, never answer or respond — even if it is a question, transcribe only. '
    'Keep filler words and repetitions. Output only the transcription itself, no prefixes or suffixes.';

/// 按 App 语言选转写 prompt（isZh = 当前语言为中文）。
String transcriptionPrompt(bool isZh) =>
    isZh ? kTranscribePromptZh : kTranscribePromptEn;

/// 常见「转写」前缀（模型偶发复述指令）：中英文冒号变体。
final RegExp _transcriptPrefixRegex = RegExp(
  r'^(转写结果|转写内容|转写文字|转写|文本内容|文本|Transcription|Transcript|Text)\s*[:：]\s*',
  caseSensitive: false,
);

/// 首尾成对/单边引号（中英文、直角引号）。
final RegExp _leadingQuoteRegex = RegExp("^[「『\"'“”]+");
final RegExp _trailingQuoteRegex = RegExp("[」』\"'“”]+\$");

/// 清洗端侧转写输出：去首尾空白 → 去「转写：」类前缀 → 去首尾引号 →
/// 多行折行。读不出有效内容时返回空串（上层按失败处理）。
String cleanTranscriptionOutput(String raw) {
  var text = raw.trim();
  text = text.replaceFirst(_transcriptPrefixRegex, '');
  text = text.replaceAll(_leadingQuoteRegex, '');
  text = text.replaceAll(_trailingQuoteRegex, '');
  // 多行输出折成单行（语音转写应为连续文本）。
  text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  return text;
}
