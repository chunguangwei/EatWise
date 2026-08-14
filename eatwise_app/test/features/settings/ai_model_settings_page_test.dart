import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/settings/presentation/ai_model_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI 模型配置页：初始回填、保存写 store（apiKey 留空保持不变）、
/// 清除配置（确认弹窗）、测试连接禁用态/loading 态与成功/失败提示。
void main() {
  late InMemoryLlmConfigStore store;
  late _FakeConnectionTester tester2;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    store = InMemoryLlmConfigStore();
    tester2 = _FakeConnectionTester();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            llmConfigStoreProvider.overrideWithValue(store),
            llmConnectionTesterProvider.overrideWithValue(tester2),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AiModelSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('初始回填：已存配置填入供应商/baseUrl/model/apiKey', (tester) async {
    await store.save(
      const LlmConfig(
        provider: 'deepseek',
        baseUrl: 'https://proxy.example.com/v1',
        model: 'deepseek-reasoner',
        apiKey: 'sk-saved',
      ),
    );
    await pumpPage(tester);

    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );
    // 供应商下拉回显 DeepSeek。
    expect(find.text(t.settings.aiModel.providers.deepseek), findsOneWidget);
    // baseUrl / model / apiKey 文本框回填。
    expect(
      find.widgetWithText(TextField, 'https://proxy.example.com/v1'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'deepseek-reasoner'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'sk-saved'), findsOneWidget);
  });

  testWidgets('保存写 store：表单内容持久化并提示', (tester) async {
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    // 选 custom 供应商。
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.aiModel.providers.custom).last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, t.settings.aiModel.baseUrl),
      'http://localhost:11434/v1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, t.settings.aiModel.model),
      'qwen2.5:7b',
    );
    await tester.enterText(
      find.widgetWithText(TextField, t.settings.aiModel.apiKey),
      'sk-local',
    );
    await scrollTo(tester, find.text(t.settings.aiModel.save));
    await tester.tap(find.text(t.settings.aiModel.save));
    await tester.pumpAndSettle();

    final saved = await store.read();
    expect(saved, isNotNull);
    expect(saved!.provider, 'custom');
    expect(saved.baseUrl, 'http://localhost:11434/v1');
    expect(saved.model, 'qwen2.5:7b');
    expect(saved.apiKey, 'sk-local');
    expect(find.text(t.settings.aiModel.saved), findsOneWidget);
  });

  testWidgets('保存：apiKey 留空保持已存 key 不变', (tester) async {
    await store.save(
      const LlmConfig(
        provider: 'kimi',
        baseUrl: '',
        model: '',
        apiKey: 'sk-keep',
      ),
    );
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    // 清空 apiKey 输入框后保存（其余字段不动）。
    await tester.enterText(
      find.widgetWithText(TextField, t.settings.aiModel.apiKey),
      '',
    );
    await scrollTo(tester, find.text(t.settings.aiModel.save));
    await tester.tap(find.text(t.settings.aiModel.save));
    await tester.pumpAndSettle();

    final saved = await store.read();
    expect(saved, isNotNull);
    expect(saved!.apiKey, 'sk-keep');
  });

  testWidgets('保存校验：custom 供应商 baseUrl/model 必填', (tester) async {
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    // 默认 custom 且字段为空，直接保存 → 校验错误且不写 store。
    await scrollTo(tester, find.text(t.settings.aiModel.save));
    await tester.tap(find.text(t.settings.aiModel.save));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.aiModel.baseUrlRequired), findsOneWidget);
    expect(find.text(t.settings.aiModel.modelRequired), findsOneWidget);
    expect(await store.read(), isNull);
  });

  testWidgets('清除配置：确认弹窗 → store 清空并提示', (tester) async {
    await store.save(
      const LlmConfig(provider: 'qwen', baseUrl: '', model: '', apiKey: 'sk-x'),
    );
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    await scrollTo(tester, find.text(t.settings.aiModel.clear));
    await tester.tap(find.text(t.settings.aiModel.clear));
    await tester.pumpAndSettle();
    // 确认弹窗。
    expect(find.text(t.settings.aiModel.clearConfirmTitle), findsOneWidget);
    await tester.tap(find.text(t.settings.aiModel.clearConfirmAction));
    await tester.pumpAndSettle();

    expect(await store.read(), isNull);
    expect(find.text(t.settings.aiModel.cleared), findsOneWidget);
  });

  testWidgets('测试连接：config 不完整时按钮禁用', (tester) async {
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    // custom 且 baseUrl/model 为空 → 测试按钮禁用。
    await scrollTo(tester, find.text(t.settings.aiModel.test));
    final FilledButton button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, t.settings.aiModel.test),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('测试连接：进行中 loading 防连点，成功提示 testOk', (tester) async {
    await store.save(
      const LlmConfig(
        provider: 'deepseek',
        baseUrl: '',
        model: '',
        apiKey: 'sk-saved',
      ),
    );
    tester2.completer = Completer<String?>();
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    await scrollTo(tester, find.text(t.settings.aiModel.test));
    await tester.tap(find.text(t.settings.aiModel.test));
    await tester.pump();

    // loading 态：按钮禁用 + 进度指示；已用表单 effective preset 发起请求。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester2.calls, hasLength(1));
    expect(tester2.calls.single.baseUrl, 'https://api.deepseek.com/v1');
    expect(tester2.calls.single.model, 'deepseek-chat');
    expect(tester2.calls.single.apiKey, 'sk-saved');

    tester2.completer!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text(t.settings.aiModel.testOk), findsOneWidget);
  });

  testWidgets('测试连接：失败显示 testFail 与原因', (tester) async {
    await store.save(
      const LlmConfig(provider: 'kimi', baseUrl: '', model: '', apiKey: 'sk'),
    );
    tester2.result = 'HTTP 401';
    await pumpPage(tester);
    final Translations t = Translations.of(
      tester.element(find.byType(AiModelSettingsPage)),
    );

    await scrollTo(tester, find.text(t.settings.aiModel.test));
    await tester.tap(find.text(t.settings.aiModel.test));
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.aiModel.testFail(reason: 'HTTP 401')),
      findsOneWidget,
    );
  });
}

/// 测试连接窄接口的 Fake（模式同 FakeCustomFoodRemote）：
/// 记录调用配置；result/completer 控制返回（null = 成功）。
final class _FakeConnectionTester implements LlmConnectionTester {
  /// 固定返回（completer 为空时生效）；null 表示连接成功。
  String? result;

  /// 挂起中的测试（loading 态用）。
  Completer<String?>? completer;

  final List<LlmConfig> calls = <LlmConfig>[];

  @override
  Future<String?> test(LlmConfig config) {
    calls.add(config);
    final pending = completer;
    if (pending != null) return pending.future;
    return Future<String?>.value(result);
  }
}
