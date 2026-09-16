import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/llm_config.dart';
import 'package:eatwise/core/llm/llm_config_store.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/settings/presentation/ai_model_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「估算生效链路」卡：两级优先级状态展示 + 当前生效行高亮。
///
/// 覆盖：开关开+模型就绪 → 高亮端侧（已启用）；开关关+已配 API →
/// 高亮自定义 API（已配置）；两级都不可用 → 无高亮（估算走「暂不可用」提示）。
void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  OnDeviceModelSnapshot snap(OnDeviceModelStatus status) =>
      OnDeviceModelSnapshot(status: status);

  Future<void> pumpPage(
    WidgetTester tester, {
    required OnDeviceModelStatus modelStatus,
    required bool onDeviceEnabled,
    required bool userApiConfigured,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.onDeviceAiEnabled': onDeviceEnabled,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = InMemoryLlmConfigStore();
    if (userApiConfigured) {
      await store.save(
        const LlmConfig(
          provider: 'custom',
          baseUrl: 'http://x/v1',
          model: 'm',
          apiKey: 'sk',
        ),
      );
    }
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            llmConfigStoreProvider.overrideWithValue(store),
            sharedPreferencesProvider.overrideWithValue(prefs),
            onDeviceModelSnapshotProvider.overrideWith(
              (ref) => Stream<OnDeviceModelSnapshot>.value(snap(modelStatus)),
            ),
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

  /// 名称所在链路由（行文本为「序号 名称 — 状态」单串，用包含匹配）。
  Finder chainRow(String name) => find.ancestor(
    of: find.textContaining('$name —'),
    matching: find.byType(Row),
  );

  /// 断言：仅 [active] 行带「当前生效」标记，其余行没有。
  void expectActiveRow(String active, List<String> inactive) {
    expect(find.text('当前生效'), findsOneWidget);
    expect(
      find.descendant(of: chainRow(active), matching: find.text('当前生效')),
      findsOneWidget,
    );
    for (final name in inactive) {
      expect(
        find.descendant(of: chainRow(name), matching: find.text('当前生效')),
        findsNothing,
      );
    }
  }

  testWidgets('开关开 + 模型就绪 → 高亮端侧（已启用）', (tester) async {
    await pumpPage(
      tester,
      modelStatus: OnDeviceModelStatus.ready,
      onDeviceEnabled: true,
      userApiConfigured: true, // 即使 API 已配，端侧优先
    );

    expect(find.text('估算生效链路'), findsOneWidget);
    expectActiveRow('端侧小模型', <String>['自定义 API']);
    expect(find.textContaining('端侧小模型 — 已启用'), findsOneWidget);
    expect(find.textContaining('自定义 API — 已配置'), findsOneWidget);
  });

  testWidgets('开关关（模型就绪）+ 已配 API → 高亮自定义 API', (tester) async {
    await pumpPage(
      tester,
      modelStatus: OnDeviceModelStatus.ready,
      onDeviceEnabled: false,
      userApiConfigured: true,
    );

    expectActiveRow('自定义 API', <String>['端侧小模型']);
    expect(find.textContaining('端侧小模型 — 未启用'), findsOneWidget);
  });

  testWidgets('端侧未下载 + API 未配置 → 两级都不可用，无高亮', (tester) async {
    await pumpPage(
      tester,
      modelStatus: OnDeviceModelStatus.notDownloaded,
      onDeviceEnabled: false,
      userApiConfigured: false,
    );

    expect(find.text('当前生效'), findsNothing);
    expect(find.textContaining('端侧小模型 — 未下载'), findsOneWidget);
    expect(find.textContaining('自定义 API — 未配置'), findsOneWidget);
  });

  testWidgets('开关开但模型未就绪（已暂停）→ 端侧不算可用，高亮自定义 API', (tester) async {
    await pumpPage(
      tester,
      modelStatus: OnDeviceModelStatus.paused,
      onDeviceEnabled: true,
      userApiConfigured: true,
    );

    expectActiveRow('自定义 API', <String>['端侧小模型']);
    expect(find.textContaining('端侧小模型 — 已暂停'), findsOneWidget);
  });
}
