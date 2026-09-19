import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/health/application/exercise_log_providers.dart';
import 'package:eatwise/features/health/data/exercise_log_repository.dart';
import 'package:eatwise/features/health/data/exercise_screenshot_service.dart';
import 'package:eatwise/features/health/domain/exercise_screenshot_logic.dart';
import 'package:eatwise/features/health/presentation/exercise_log_sheet.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/record/data/water_log_repository.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/domain/engine_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 运动截图导入 widget 测试：记运动弹层入口 → 识别（fake 服务）→
/// 可编辑确认弹层 → 确认落库（source=screenshot）+ D-11 撤销；
/// 引擎缺失 → 引导卡；识别失败 → 透出/兜底。
void main() {
  late AppDatabase db;
  late ExerciseLogRepository repo;
  late SharedPreferences prefs;
  late _FakeScreenshotService service;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.memory();
    repo = ExerciseLogRepository(db: db);
    service = _FakeScreenshotService();
    addTearDown(() async => db.close());
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  String todayKey() => localDateKey(DateTime.now());

  /// 测试收尾（同 exercise_log_sheet_test：隐藏吐司 → 卸载冲刷假时钟区）。
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

  Future<void> pumpApp(
    WidgetTester tester, {
    AiEngineAvailability availability = AiEngineAvailability.ondeviceReady,
    bool withService = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseLogRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          photoPickerGatewayProvider.overrideWithValue(_FakePicker()),
          if (withService)
            exerciseScreenshotServiceProvider.overrideWithValue(service)
          else
            exerciseScreenshotServiceProvider.overrideWithValue(null),
          aiEngineAvailabilityFnProvider.overrideWithValue(
            () async => availability,
          ),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => FilledButton(
                  onPressed: () => startExerciseLog(context, ref),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 打开记运动弹层并点「相册导入」，等识别 fake 返回后确认弹层出现。
  ///（识别中对话框开/关 + 确认弹层滑入各耗一帧动画，需多泵两轮。）
  Future<void> openAndImport(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('相册导入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('汇总截图：步数估算预填 → 改活动热量联动 → 确认落库（source=screenshot）', (
    tester,
  ) async {
    service.outcome = const ExerciseScreenshotSuccess(
      ExerciseScreenshotData(
        kind: ExerciseScreenshotKind.summary,
        steps: 8000,
        floorsClimbedM: 20,
      ),
    );
    await pumpApp(tester);
    await openAndImport(tester);

    // 确认弹层：汇总标题 + 字段预填；kcal 按 60kg × 6km × 1.036 ≈ 373。
    expect(find.text('确认活动数据'), findsOneWidget);
    expect(find.text('爬楼（米，仅展示）'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('screenshot.kcal')),
          )
          .controller!
          .text,
      '373',
    );
    // 记运动弹层在确认弹层之下仍挂载，同款文案两处均在。
    expect(find.text('未填体重，按 60 千克估算'), findsWidgets);

    // 补录活动热量 → 未手改 kcal 时联动直用截图口径。
    await tester.enterText(
      find.byKey(const ValueKey<String>('screenshot.activeKcal')),
      '500',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('screenshot.kcal')),
          )
          .controller!
          .text,
      '500',
    );

    // 确认 → 弹层与记运动弹层都收起，吐司「已记录·撤销」。
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('screenshot.save')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('screenshot.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    final saved = await repo.logsForDate(todayKey());
    expect(saved, hasLength(1));
    expect(saved.single.typeKey, 'summary');
    expect(saved.single.durationMin, 0);
    expect(saved.single.kcal, 500);
    expect(saved.single.source, ExerciseLogRepository.sourceScreenshot);

    // D-11 撤销 → 物理删除。
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await repo.logsForDate(todayKey()), isEmpty);

    await settleUi(tester);
  });

  testWidgets('单次运动截图：类型映射+截图消耗预填，直接确认落库', (tester) async {
    service.outcome = const ExerciseScreenshotSuccess(
      ExerciseScreenshotData(
        kind: ExerciseScreenshotKind.workout,
        exerciseTypeKey: 'run',
        durationMinutes: 32,
        burnKcal: 285,
      ),
    );
    await pumpApp(tester);
    await openAndImport(tester);

    expect(find.text('确认运动记录'), findsOneWidget);
    // 快跑 chip 预选 + 时长/消耗预填（截图值优先，不走 MET）。
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey<String>('screenshot.type.run')),
    );
    expect(chip.selected, isTrue);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('screenshot.duration')),
          )
          .controller!
          .text,
      '32',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('screenshot.kcal')),
          )
          .controller!
          .text,
      '285',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('screenshot.save')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('screenshot.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final saved = (await repo.logsForDate(todayKey())).single;
    expect(saved.typeKey, 'run');
    expect(saved.durationMin, 32);
    expect(saved.kcal, 285);
    expect(saved.source, ExerciseLogRepository.sourceScreenshot);

    await settleUi(tester);
  });

  testWidgets('类型映射不上（other）：须手选类型，MET 估算联动后落库', (tester) async {
    service.outcome = const ExerciseScreenshotSuccess(
      ExerciseScreenshotData(
        kind: ExerciseScreenshotKind.workout,
        exerciseTypeKey: 'other',
        durationMinutes: 45,
      ),
    );
    await pumpApp(tester);
    await openAndImport(tester);

    // other 提示 + 直接保存被拦截（未选类型）。
    expect(find.text('截图里的类型没对上，请手动选择运动类型'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('screenshot.save')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('screenshot.save')));
    await tester.pump();
    expect(await repo.logsForDate(todayKey()), isEmpty);

    // 手选瑜伽 → kcal 按 MET 联动（3.0 × 60 × 0.75 = 135）。
    await tester.tap(
      find.byKey(const ValueKey<String>('screenshot.type.yoga')),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('screenshot.kcal')),
          )
          .controller!
          .text,
      '135',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('screenshot.save')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('screenshot.save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final saved = (await repo.logsForDate(todayKey())).single;
    expect(saved.typeKey, 'yoga');
    expect(saved.kcal, 135);

    await settleUi(tester);
  });

  testWidgets('识别失败透出模型原文；引擎缺失弹引导卡；无服务兜底提示', (tester) async {
    // parse_failed 带 detail → 透出原文（含「无法识别」）。
    service.outcome = const ExerciseScreenshotUnavailable(
      'parse_failed',
      detail: '无法识别',
    );
    await pumpApp(tester);
    await openAndImport(tester);
    expect(find.text('无法识别'), findsOneWidget);
    expect(find.text('确认活动数据'), findsNothing);
    await settleUi(tester);

    // 引擎缺失（未下载未配置）→ 引导卡而非「无法识别」。
    final callsBefore = service.calls;
    await pumpApp(tester, availability: AiEngineAvailability.none);
    await openAndImport(tester);
    expect(find.text('AI 识别需要一个模型'), findsOneWidget);
    expect(service.calls, callsBefore); // 未取图未识别
    await settleUi(tester);

    // 有云端 API 但无视觉链路（服务为 null）→ 不可用 snackbar 兜底。
    await pumpApp(
      tester,
      availability: AiEngineAvailability.userApiConfigured,
      withService: false,
    );
    await openAndImport(tester);
    expect(find.text('没能识别这张图，换张清晰的截图试试'), findsOneWidget);
    await settleUi(tester);
  });
}

final class _FakePicker implements PhotoPickerGateway {
  @override
  Future<Uint8List?> pick(PhotoSource source) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}

final class _FakeScreenshotService implements ExerciseScreenshotService {
  ExerciseScreenshotOutcome outcome = const ExerciseScreenshotUnavailable(
    'parse_failed',
    detail: '无法识别',
  );
  int calls = 0;

  @override
  Future<ExerciseScreenshotOutcome> recognize(Uint8List imageBytes) async {
    calls++;
    return outcome;
  }
}
