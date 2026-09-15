import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_model_manager.dart';
import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/settings/presentation/ondevice_model_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================== Fake ====================

/// 卡片动作 Fake：记录调用并脚本化状态流推送（widget 测试环境 dart:io
/// 真实 I/O 不前进，不能走真实 manager，故经窄接口替身驱动状态机）。
final class _FakeActions implements OnDeviceModelActions {
  int ensureCalls = 0;
  int cancelCalls = 0;
  int deleteCalls = 0;
  bool permanentlyDisabled = false;

  /// ensureModel 行为脚本（默认无操作，状态由测试推送）。
  Future<String> Function()? onEnsure;

  @override
  Future<String> ensureModel() {
    ensureCalls++;
    return onEnsure?.call() ?? Future<String>.value('/fake/model.litertlm');
  }

  @override
  void cancel() {
    cancelCalls++;
  }

  @override
  Future<void> delete() async {
    deleteCalls++;
  }

  @override
  bool get estimatePermanentlyDisabled => permanentlyDisabled;
}

// ==================== 工具 ====================

OnDeviceModelSnapshot _snap(
  OnDeviceModelStatus status, {
  int downloaded = 0,
  OnDeviceModelException? error,
}) => OnDeviceModelSnapshot(
  status: status,
  downloadedBytes: downloaded,
  totalBytes: 1024,
  error: error,
);

void main() {
  late StreamController<OnDeviceModelSnapshot> snapshots;
  late _FakeActions actions;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    snapshots = StreamController<OnDeviceModelSnapshot>();
    addTearDown(() async => snapshots.close());
    actions = _FakeActions();
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  /// 泵入卡片（首帧状态 [initial] 经 Stream.value 先行下发，后续状态由
  /// Fake 动作脚本推入同一广播流）。
  Future<void> pumpCard(
    WidgetTester tester,
    OnDeviceModelSnapshot initial, {
    SharedPreferences? prefs,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            onDeviceModelSnapshotProvider.overrideWith((ref) async* {
              yield initial;
              yield* snapshots.stream;
            }),
            onDeviceModelActionsProvider.overrideWithValue(actions),
            if (prefs != null)
              sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: OnDeviceModelCard()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('未下载：体积 + Wi-Fi 提示 + 下载按钮；点下载调 ensureModel', (tester) async {
    await pumpCard(tester, _snap(OnDeviceModelStatus.notDownloaded));

    expect(find.text('端侧小模型'), findsOneWidget);
    expect(find.text('模型大小约 2.41GB'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
    expect(find.text('下载模型'), findsOneWidget);

    actions.onEnsure = () async {
      snapshots.add(_snap(OnDeviceModelStatus.downloading, downloaded: 512));
      return '/fake/model.litertlm';
    };
    await tester.tap(find.text('下载模型'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(actions.ensureCalls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('下载中 50%'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('下载中：取消调 cancel；已暂停：继续下载/删除入口', (tester) async {
    await pumpCard(
      tester,
      _snap(OnDeviceModelStatus.downloading, downloaded: 512),
    );

    expect(find.text('下载中 50%'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(actions.cancelCalls, 1);

    // 管理器转 paused（.part 保留）→ 继续/删除。
    snapshots.add(_snap(OnDeviceModelStatus.paused, downloaded: 512));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.text('继续下载'), findsOneWidget);
    expect(find.text('删除模型'), findsOneWidget);

    actions.onEnsure = () async {
      snapshots.add(_snap(OnDeviceModelStatus.ready, downloaded: 1024));
      return '/fake/model.litertlm';
    };
    await tester.tap(find.text('继续下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(actions.ensureCalls, 1);
    expect(find.text('模型已就绪'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.textContaining('首次估算需加载模型'), findsOneWidget);
  });

  testWidgets('已就绪：开关切换持久化到 SharedPreferences', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await pumpCard(
      tester,
      _snap(OnDeviceModelStatus.ready, downloaded: 1024),
      prefs: prefs,
    );

    expect(find.text('模型已就绪'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(prefs.getBool('settings.onDeviceAiEnabled'), isTrue);
  });

  testWidgets('已就绪：删除模型（确认弹窗）→ 调 delete + 提示', (tester) async {
    await pumpCard(tester, _snap(OnDeviceModelStatus.ready, downloaded: 1024));

    await tester.tap(find.text('删除模型'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('删除端侧模型？'), findsOneWidget);

    await tester.tap(find.text('确认删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(actions.deleteCalls, 1);
    expect(find.text('端侧模型已删除'), findsOneWidget); // SnackBar
  });

  testWidgets('错误：下载失败文案 + 重试调 ensureModel', (tester) async {
    await pumpCard(
      tester,
      _snap(
        OnDeviceModelStatus.error,
        error: const OnDeviceDownloadException('下载失败 HTTP 500'),
      ),
    );

    expect(find.text('下载失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(actions.ensureCalls, 1);
  });

  testWidgets('错误：存储/内存门槛拦截 → 对应专项文案', (tester) async {
    await pumpCard(
      tester,
      _snap(
        OnDeviceModelStatus.error,
        error: const OnDeviceInsufficientStorageException(
          requiredBytes: 6470369280,
          freeBytes: 10,
        ),
      ),
    );
    expect(find.textContaining('可用存储不足'), findsOneWidget);

    snapshots.add(
      _snap(
        OnDeviceModelStatus.error,
        error: const OnDeviceInsufficientMemoryException(
          requiredMB: 3800,
          actualMB: 1024,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('设备内存不足，无法使用端侧模型'), findsOneWidget);
  });

  testWidgets('OOM 永久禁用：开关不渲染 + 内存不足说明', (tester) async {
    actions.permanentlyDisabled = true;
    await pumpCard(tester, _snap(OnDeviceModelStatus.ready, downloaded: 1024));

    expect(find.text('模型已就绪'), findsOneWidget);
    expect(find.textContaining('端侧估算已停用'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}
