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

import '../record_test_helper.dart';
import 'recognition_test_fakes.dart';

/// 没听清后的语音重录入口回归（真机走查：ASR 没听清/报错后，面板只剩
/// 键盘输入一条路，没有重新说话的口）。系统听写面板：错误后出现
/// 「再说一次」，点击重启听写并清除错误态；切回语音态自动重听。
void main() {
  late AppDatabase db;
  late RecordRepository repository;
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
          speechGatewayProvider.overrideWithValue(speechGateway),
          freeTextMealServiceProvider.overrideWithValue(null),
        ],
        child: TranslationProvider(
          child: MaterialApp(theme: AppTheme.light(), home: const RecordPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openListeningSheet(WidgetTester tester) async {
    await tester.tap(find.text('语音记'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('没听清（良性错误）→ 出现「再说一次」，点击恢复听写并可继续出字', (tester) async {
    await pumpPage(tester);
    await openListeningSheet(tester);

    expect(find.text('再说一次'), findsNothing, reason: '正常听写中不显重录钮');

    speechGateway.onError!('error_no_match');
    await tester.pump();
    expect(find.text('再说一次'), findsOneWidget, reason: '没听清必须给语音重录入口');

    await tester.tap(find.text('再说一次'));
    await tester.pump();
    expect(find.text('再说一次'), findsNothing, reason: '重录开始，错误态清除');

    // 重录会话仍能正常回传实时文本。
    speechGateway.onText!('两个鸡蛋');
    await tester.pump();
    expect(find.text('两个鸡蛋'), findsOneWidget);
    await settleUi(tester);
  });

  testWidgets('切键盘再切回语音 → 自动重新开始听写（mic 钮即重录入口）', (tester) async {
    await pumpPage(tester);
    await openListeningSheet(tester);

    speechGateway.onError!('error_network');
    await tester.pump();
    expect(find.text('再说一次'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    expect(find.text('再说一次'), findsNothing, reason: '切回语音态应自动重新开始听写');
    await settleUi(tester);
  });
}
