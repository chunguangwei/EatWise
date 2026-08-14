import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmConfig.effective', () {
    test('内置供应商留空补 preset', () {
      const cfg = LlmConfig(provider: 'deepseek', baseUrl: '', model: '');
      final eff = cfg.effective();
      expect(eff.baseUrl, 'https://api.deepseek.com/v1');
      expect(eff.model, 'deepseek-chat');
      expect(eff.isComplete, isTrue);
    });

    test('custom 缺 baseUrl/model 则 isComplete=false', () {
      const cfg = LlmConfig(provider: 'custom', baseUrl: '', model: 'qwen3:4b');
      expect(cfg.effective().isComplete, isFalse);
    });

    test('baseUrl 末尾斜杠归一化', () {
      const cfg = LlmConfig(
        provider: 'custom',
        baseUrl: 'http://192.168.1.10:11434/v1/',
        model: 'qwen3:4b',
      );
      expect(cfg.effective().baseUrl, 'http://192.168.1.10:11434/v1');
    });
  });

  group('InMemoryLlmConfigStore', () {
    test('read/save/clear 往返；apiKey 留空保持不变', () async {
      final store = InMemoryLlmConfigStore();
      expect(await store.read(), isNull);
      await store.save(
        const LlmConfig(
          provider: 'custom',
          baseUrl: 'http://x/v1',
          model: 'm',
          apiKey: 'k1',
        ),
      );
      await store.save(
        const LlmConfig(
          provider: 'custom',
          baseUrl: 'http://x/v1',
          model: 'm2',
        ),
      ); // apiKey 空=不变
      final cfg = await store.read();
      expect(cfg?.model, 'm2');
      expect(cfg?.apiKey, 'k1');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}
