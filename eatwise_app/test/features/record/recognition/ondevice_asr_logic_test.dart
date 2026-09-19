import 'dart:convert';
import 'dart:typed_data';

import 'package:eatwise/features/record/recognition/domain/ondevice_asr_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 端侧 ASR 纯函数层单测：WAV 头封装、转写输出清洗、双语 prompt。
void main() {
  group('wrapPcm16AsWav', () {
    Uint8List wav(Uint8List pcm) => wrapPcm16AsWav(pcm);

    test('44 字节头 + 数据原样拼接', () {
      final pcm = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
      final out = wav(pcm);
      expect(out.length, 44 + pcm.length);
      expect(out.sublist(44), pcm);
    });

    test('RIFF/WAVE 容器与 fmt 块字段（16kHz 单声道 PCM16）', () {
      final pcm = Uint8List(320); // 10ms @16kHz×2B
      final out = wav(pcm);
      expect(ascii.decode(out.sublist(0, 4)), 'RIFF');
      // chunkSize = 36 + dataSize（小端 LE32）
      final chunkSize = ByteData.sublistView(
        out,
        4,
        8,
      ).getUint32(0, Endian.little);
      expect(chunkSize, 36 + pcm.length);
      expect(ascii.decode(out.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(out.sublist(12, 16)), 'fmt ');
      final view = ByteData.sublistView(out);
      expect(view.getUint32(16, Endian.little), 16); // fmt 块大小
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // 单声道
      expect(view.getUint32(24, Endian.little), 16000); // 采样率
      expect(view.getUint32(28, Endian.little), 32000); // byteRate
      expect(view.getUint16(32, Endian.little), 2); // blockAlign
      expect(view.getUint16(34, Endian.little), 16); // bitDepth
      expect(ascii.decode(out.sublist(36, 40)), 'data');
      expect(view.getUint32(40, Endian.little), pcm.length); // dataSize
    });

    test('空 PCM → 44 字节纯头', () {
      final out = wav(Uint8List(0));
      expect(out.length, 44);
      expect(ByteData.sublistView(out).getUint32(40, Endian.little), 0);
    });
  });

  group('cleanTranscriptionOutput', () {
    test('去首尾空白与引号（中英文/直角引号）', () {
      expect(cleanTranscriptionOutput('  一碗米饭  '), '一碗米饭');
      expect(cleanTranscriptionOutput('「一碗米饭」'), '一碗米饭');
      expect(cleanTranscriptionOutput('"a bowl of rice"'), 'a bowl of rice');
      expect(cleanTranscriptionOutput('“米饭”'), '米饭');
    });

    test('去「转写：」类前缀（中英文冒号）', () {
      expect(cleanTranscriptionOutput('转写：一碗米饭'), '一碗米饭');
      expect(cleanTranscriptionOutput('转写结果: 一碗米饭'), '一碗米饭');
      expect(
        cleanTranscriptionOutput('Transcription: a bowl of rice'),
        'a bowl of rice',
      );
    });

    test('多行折成单行', () {
      expect(cleanTranscriptionOutput('一碗米饭\n加个鸡蛋'), '一碗米饭 加个鸡蛋');
    });

    test('组合杂质：前缀 + 引号 + 换行', () {
      expect(cleanTranscriptionOutput('转写结果：\n「一碗米饭」\n'), '一碗米饭');
    });

    test('纯杂质 → 空串（上层按失败处理）', () {
      expect(cleanTranscriptionOutput('   '), '');
      expect(cleanTranscriptionOutput('「」'), '');
    });
  });

  group('transcriptionPrompt', () {
    test('中文 prompt：只输出转写内容', () {
      expect(transcriptionPrompt(true), contains('转写成文字'));
      expect(transcriptionPrompt(true), contains('不要解释'));
    });

    test('英文 prompt：output only transcription', () {
      expect(transcriptionPrompt(false), contains('Transcribe'));
      expect(transcriptionPrompt(false), contains('no explanation'));
    });
  });
}
