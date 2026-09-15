import 'package:eatwise/core/llm/ondevice/ondevice_model_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('prefersChinaModelSource（对齐 imagepilot modelRegion 口径）', () {
    for (final (locale, expected) in [
      ('zh-CN', true),
      ('zh_CN', true),
      ('zh-Hans-CN', true),
      ('zh_hans_sg', true),
      ('zh', true),
      ('zh-TW', false), // 港台繁体视为海外（GitHub 更稳）
      ('zh-HK', false),
      ('zh-Hant-TW', false),
      ('en-US', false),
      ('ja-JP', false),
      ('', false), // 取不到 → 海外源（全球可达作安全默认）
    ]) {
      test('$locale → $expected', () {
        expect(prefersChinaModelSource(locale), expected);
      });
    }
  });

  group('onDeviceModelUrlCandidates', () {
    test('国内：ModelScope 优先，GitHub 兜底', () {
      final urls = onDeviceModelUrlCandidates(preferChina: true);
      expect(urls, [
        OnDeviceModelSpec.modelScopeUrl,
        OnDeviceModelSpec.gitHubUrl,
      ]);
    });

    test('海外：GitHub 优先，ModelScope 兜底', () {
      final urls = onDeviceModelUrlCandidates(preferChina: false);
      expect(urls, [
        OnDeviceModelSpec.gitHubUrl,
        OnDeviceModelSpec.modelScopeUrl,
      ]);
    });
  });

  group('静态规格锚点（与 spike/imagepilot 一致）', () {
    test('字节数 / 魔数 / 文件名', () {
      expect(OnDeviceModelSpec.expectedBytes, 2588147712);
      expect(String.fromCharCodes(OnDeviceModelSpec.magicBytes), 'LITERTLM');
      expect(OnDeviceModelSpec.fileName, 'gemma-4-E2B-it.litertlm');
    });

    test('内存门槛：iOS 3000 / Android 3800', () {
      expect(minDeviceMemMBForPlatform('ios'), 3000);
      expect(minDeviceMemMBForPlatform('android'), 3800);
      expect(minDeviceMemMBForPlatform('macos'), 3800); // 非 iOS 一律就高
    });

    test('存储预留 ≈ 2.5 倍模型体积（模型+cache+下载峰值 ≈6GiB）', () {
      expect(
        OnDeviceModelSpec.requiredFreeStorageBytes,
        (OnDeviceModelSpec.expectedBytes * 2.5).ceil(),
      );
    });
  });
}
