import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../fasting/presentation/fasting_presentation_test_helper.dart';
import '../fasting/tz_test_helper.dart';
import '../social/social_test_fakes.dart';

/// 5 Tab 骨架 widget 测试：底栏五个分支渲染与切换、占位页四态空态文案、
/// 分支状态保留（IndexedStack）。
void main() {
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    prefs = await seedActivePlanPrefs(startedAtUtc: bjtUtc(27, 12));
    db = AppDatabase.memory();
    addTearDown(() async {
      await db.close();
    });
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            onboardingGateProvider.overrideWithValue(
              OnboardingGate(completed: true),
            ),
            appDatabaseProvider.overrideWithValue(db),
            localNotificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            // M5：社区 Tab 已接真实打卡流，注入内存桩避免真实网络。
            socialApiProvider.overrideWithValue(FakeSocialApi()),
            fastingClockProvider.overrideWithValue(() => bjtUtc(28, 0)),
            deviceLocationProvider.overrideWithValue(bjt),
          ],
          child: EatWiseApp(gate: OnboardingGate(completed: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 收尾：失焦输入框 → 卸载并多次 pump（冲刷 drift 退订的 Timer.run，
  /// 见 record_page_test 同名约定）；db.close 留给 addTearDown 真实事件区。
  Future<void> unmount(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('5 Tab 底栏渲染与切换：占位页四态空态文案齐备', (tester) async {
    await pumpApp(tester);

    // 底栏五个 Tab（首页默认选中，显示断食计时主页）
    for (final label in <String>['首页', '记录', '数据', '社区', '我的']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('断食中'), findsOneWidget);

    // 数据 Tab：空态（插画位 + 主/副文案 + CTA）
    await tester.tap(find.text('数据'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('数据曲线正在热身，多记几天它就跑起来啦。'), findsOneWidget);
    // 当日空态 CTA + 趋势空态 CTA（薄荷走查 P2 补齐）各一个。
    expect(find.text('去记录'), findsNWidgets(2));

    // 社区 Tab：真实打卡流（M5）——空流 → 空态 + CTA「发布打卡」进发布页
    await tester.tap(find.text('社区'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('这里在等今天第一口美食登场。'), findsOneWidget);
    await tester.tap(find.text('发布打卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('0/500'), findsOneWidget); // 发布页字数计数

    // 我的 Tab：M7 设置页（账号/隐私/偏好/提醒/关于分组，D-18）
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('隐私'), findsOneWidget);
    // 账号组扩充后偏好组在首屏外：滚动至可见再断言（ListView 懒构建）
    await tester.scrollUntilVisible(
      find.text('语言'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);

    // 记录 Tab：挂现有 RecordPage
    await tester.tap(find.text('记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('拍照记'), findsOneWidget);

    // 回首页：分支状态保留（IndexedStack），计时主页仍在
    await tester.tap(find.text('首页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('断食中'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('数据页 CTA「去记录」跳记录 Tab', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('数据'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 两个「去记录」CTA（当日空态 + 趋势空态）同跳记录 Tab，点第一个。
    await tester.tap(find.text('去记录').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('拍照记'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Tab 骨架双语：英文标签渲染（D-15）', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpApp(tester);

    for (final label in <String>['Home', 'Log', 'Stats', 'Community', 'Me']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Fasting'), findsOneWidget);

    await unmount(tester);
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });
}
