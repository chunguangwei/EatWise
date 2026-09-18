import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 权限拒绝降级 UI 测试（《规格-全局 UI 四态》§4.3 + 合规 §3）：
/// 权限拒绝永不阻断核心闭环，只降级对应入口。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
  late FakePhotoPickerGateway photoGateway;
  late FakeFoodRecognitionService recognitionService;
  late FakeSpeechGateway speechGateway;

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
    speechGateway = FakeSpeechGateway();
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
            () async => AiEngineAvailability.ondeviceReady,
          ),
          photoPickerGatewayProvider.overrideWithValue(photoGateway),
          foodRecognitionServiceProvider.overrideWithValue(recognitionService),
          speechGatewayProvider.overrideWithValue(speechGateway),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('相机权限拒绝 → 降级说明卡（去开启/手动搜索），手动搜索仍可用', (tester) async {
    photoGateway.throwDenied = true;
    await pumpPage(tester);

    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // §4.3 首次拒绝：说明卡 + 双按钮。
    expect(find.text('相机未授权'), findsOneWidget);
    expect(find.text('拍不了照也能记，手动搜一样快'), findsOneWidget);
    expect(find.text('去开启'), findsOneWidget);
    expect(find.text('手动搜索'), findsOneWidget);

    // 选「手动搜索」→ 卡片关闭，搜索链路不受影响。
    await tester.tap(find.text('手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('相机未授权'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('白米饭'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('语音不可用/麦克风权限拒绝 → 降级说明卡，不阻断记录', (tester) async {
    speechGateway.available = false;
    await pumpPage(tester);

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('麦克风未授权'), findsOneWidget);
    expect(find.text('去开启'), findsOneWidget);
    expect(find.text('手动搜索'), findsOneWidget);

    await tester.tap(find.text('手动搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('麦克风未授权'), findsNothing);
    // 记录页主体仍在，三入口入口保留。
    expect(find.text('拍照记'), findsOneWidget);
    expect(find.text('语音记'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('语音听写中取消：丢弃本次听写，不丢页面已输入内容', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '鸡蛋');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    speechGateway.onText!('一碗米饭');
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(speechGateway.cancelled, isTrue);
    expect(find.text('确认记录'), findsNothing);
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.controller!.text, '鸡蛋');
    await settleUi(tester);
  });
}
