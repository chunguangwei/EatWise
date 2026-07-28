import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/data/record_remote.dart';
import 'package:eatwise/features/record/data/record_repository.dart';
import 'package:eatwise/features/record/presentation/record_page.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'record_test_helper.dart';

/// M3 记录页 widget 测试：主流程（搜索 → 选食物 → 份量实时重算 →
/// 确认乐观更新 → 「已记录·撤销」吐司 → 撤销撤回）+ 三入口占位 + 待同步角标。
void main() {
  late AppDatabase db;
  late FakeRecordRemote remote;
  late RecordRepository repository;

  setUpAll(() async {
    await initRecordTestTimeZones();
  });

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    db = AppDatabase.memory();
    await seedFoods(db);
    remote = FakeRecordRemote();
    repository = RecordRepository(
      db: db,
      remote: remote,
      location: tz.getLocation('Asia/Shanghai'),
    );
    // 在 addTearDown（真实事件区）关闭资源；不要在测试体内 close——
    // drift 流退订时用 `Timer.run` 清理查询缓存，在 widget 测试的假时钟区
    // 里 await close 会等不到 Timer 触发而死锁（挂起 10 分钟超时）。
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  /// 测试收尾：隐藏吐司（取消其时长 Timer）→ 失焦输入框（取消光标
  /// 闪烁 Timer）→ 卸载页面并多次 pump。
  ///
  /// 卸载会退订 drift watch 流：退订回调经微任务完成后，drift 用
  /// `Timer.run` 延迟清理查询缓存（见 stream_queries.dart 注释），该 Timer
  /// 落在假时钟区，必须在其入队后再 pump 一次冲刷，否则 flutter_test 收尾
  /// 判定「Timer 未决」。db.close 留给 addTearDown（真实事件区），在测试体
  /// 内 await close 会等不到假时钟 Timer 触发而死锁挂起。
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
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('主流程：搜索 → 份量重算 → 确认入账 → 撤销撤回', (tester) async {
    await pumpPage(tester);

    // 初始：标题、三入口、无待同步角标。
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('拍照记'), findsOneWidget);
    expect(find.text('语音记'), findsOneWidget);
    expect(find.text('常吃'), findsOneWidget);
    expect(find.text('还有 1 条记录在路上，联网后自动同步'), findsNothing);

    // 双语搜索（中文）。
    await tester.enterText(find.byType(TextField).first, '米饭');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('白米饭'), findsOneWidget);

    // 选中食物 → 结果卡出现，默认 100g 预览。
    await tester.tap(find.text('白米饭'));
    await tester.pump();
    expect(find.text('确认记录'), findsOneWidget);
    expect(find.text('热量 116 千卡'), findsOneWidget);

    // 份量修改 → 营养实时重算（US-3.1）。
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.pump();
    expect(find.text('热量 232 千卡'), findsOneWidget);

    // 确认 → 乐观更新：「已记录·撤销」吐司 + 待同步角标。
    await tester.tap(find.text('确认记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('还有 1 条记录在路上，联网后自动同步'), findsOneWidget);
    expect(find.text('今日已记 1 笔 · 今日约 232 千卡（待云端校准）'), findsOneWidget);

    // 撤销 → 记录撤回，角标消失。
    await tester.tap(find.text('撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已撤销'), findsOneWidget);
    expect(find.text('还有 1 条记录在路上，联网后自动同步'), findsNothing);
    expect(await repository.entriesForDate(DateTime.now().toUtc()), isEmpty);

    // 收尾：隐藏吐司 + 失焦输入框（不卸载页面，见 settleUi 注释）。
    await settleUi(tester);
  });

  testWidgets('三入口为占位：点击提示即将上线', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('拍照记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('即将上线，先用手动搜索记一笔吧'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('搜索无结果 → 空态提示', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '不存在的食物');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('没找到？换个关键词试试'), findsOneWidget);
    await settleUi(tester);
  });
}
