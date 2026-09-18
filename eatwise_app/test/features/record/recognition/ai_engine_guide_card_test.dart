import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// AI 引擎引导卡 widget 测试：三态探测、入口引导卡三出口、
/// 「先手动搜索」会话内不再弹、失败归因走引导卡、
/// 「识别不出内容」保持原透出对话框。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FakePhotoPickerGateway photoGateway;
  late FakeFoodRecognitionService recognitionService;

  /// 当前探测结果（测试内可变：模拟失败中途引擎状态翻转）。
  var availability = AiEngineAvailability.none;

  /// 导航目标记录（override 路由出口，不依赖 go_router 装配）。
  late List<AiEngineGuideTarget> navigated;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    repository = RecordRepository(
      db: db,
      remote: FakeRecordRemote(),
      location: tz.getLocation('Asia/Shanghai'),
    );
    photoGateway = FakePhotoPickerGateway();
    recognitionService = FakeFoodRecognitionService();
    availability = AiEngineAvailability.none;
    navigated = <AiEngineGuideTarget>[];
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  Future<void> settleUi(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffolds = find.byType(Scaffold);
    if (scaffolds.evaluate().isNotEmpty) {
      ScaffoldMessenger.of(
        tester.element(scaffolds.first),
      ).hideCurrentSnackBar();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recordRepositoryProvider.overrideWithValue(repository),
          aiEngineAvailabilityFnProvider.overrideWithValue(
            () async => availability,
          ),
          aiEngineGuideNavigatorProvider.overrideWithValue((context, target) {
            navigated.add(target);
          }),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(recognitionService),
          speechGatewayProvider.overrideWithValue(FakeSpeechGateway()),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 打开引导卡（入口路径：点「拍照记」，无可用引擎时先弹卡）。
  Future<void> openGuideCard(WidgetTester tester) async {
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('三态探测（aiEngineAvailabilityOf）', () {
    test('端侧就绪优先于用户 API；两者都无 → none', () {
      expect(
        aiEngineAvailabilityOf(onDeviceReady: true, userApiConfigured: true),
        AiEngineAvailability.ondeviceReady,
      );
      expect(
        aiEngineAvailabilityOf(onDeviceReady: true, userApiConfigured: false),
        AiEngineAvailability.ondeviceReady,
      );
      expect(
        aiEngineAvailabilityOf(onDeviceReady: false, userApiConfigured: true),
        AiEngineAvailability.userApiConfigured,
      );
      expect(
        aiEngineAvailabilityOf(onDeviceReady: false, userApiConfigured: false),
        AiEngineAvailability.none,
      );
    });
  });

  testWidgets('入口引导卡：无引擎 → 点拍照记先弹卡（不开来源面板）', (tester) async {
    await pumpPage(tester);
    await openGuideCard(tester);

    expect(find.text('AI 识别需要一个模型'), findsOneWidget);
    expect(find.textContaining('离线可用'), findsOneWidget);
    expect(find.text('下载本地模型（推荐）'), findsOneWidget);
    expect(find.text('配置云端 API'), findsOneWidget);
    expect(find.text('先手动搜索'), findsOneWidget);
    // 来源选择面板未打开。
    expect(find.text('从相册选择'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('出口「下载本地模型（推荐）」→ 深链端侧模型卡', (tester) async {
    await pumpPage(tester);
    await openGuideCard(tester);

    await tester.tap(find.text('下载本地模型（推荐）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(navigated, <AiEngineGuideTarget>[AiEngineGuideTarget.onDeviceModel]);
    expect(find.text('AI 识别需要一个模型'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('出口「配置云端 API」→ 深链 API 配置区', (tester) async {
    await pumpPage(tester);
    await openGuideCard(tester);

    await tester.tap(find.text('配置云端 API'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(navigated, <AiEngineGuideTarget>[AiEngineGuideTarget.cloudApi]);
    expect(find.text('AI 识别需要一个模型'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('出口「先手动搜索」→ 对焦搜索框且本次会话不再弹卡', (tester) async {
    await pumpPage(tester);
    await openGuideCard(tester);

    await tester.tap(find.text('先手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 识别需要一个模型'), findsNothing);
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.focusNode!.hasFocus, isTrue);
    expect(navigated, isEmpty); // 不发生导航

    // 再次点「拍照记」：抑制生效，不再弹卡，直接走出来源面板。
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI 识别需要一个模型'), findsNothing);
    expect(find.text('从相册选择'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('失败归因：识别中途引擎转不可用 → 引导卡（非 snackbar）', (tester) async {
    // 入口时引擎可用（不出现引导卡），识别中途翻转为 none。
    availability = AiEngineAvailability.ondeviceReady;
    recognitionService.completer = Completer<RecognitionOutcome>();
    await pumpPage(tester);

    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('识别中…'), findsOneWidget);

    // 引擎中途失联（如模型文件被删）→ 失败归因走引导卡。
    availability = AiEngineAvailability.none;
    recognitionService.completer!.complete(
      const RecognitionUnavailable('ondevice_error'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 识别需要一个模型'), findsOneWidget);
    expect(find.text('暂时识别不了，手动搜索一样快'), findsNothing);
    await settleUi(tester);
  });

  testWidgets('有引擎但识别失败（超时/引擎错误）→ 保持 snackbar 兜底', (tester) async {
    availability = AiEngineAvailability.ondeviceReady;
    recognitionService.outcome = const RecognitionUnavailable('ondevice_error');
    await pumpPage(tester);

    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('AI 识别需要一个模型'), findsNothing);
    expect(find.text('暂时识别不了，手动搜索一样快'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('「识别不出内容」→ 保持原透出对话框（不走引导卡）', (tester) async {
    availability = AiEngineAvailability.ondeviceReady;
    recognitionService.outcome = const RecognitionUnavailable(
      'parse_failed',
      detail: '无法识别',
    );
    await pumpPage(tester);

    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // 原失败对话框：透出原文 + 重拍/手动搜索，不是引擎引导卡。
    expect(find.text('未识别到食物'), findsOneWidget);
    expect(find.text('无法识别'), findsOneWidget);
    expect(find.text('AI 识别需要一个模型'), findsNothing);
    await settleUi(tester);
  });
}
