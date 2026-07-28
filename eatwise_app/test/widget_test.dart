import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/features/fasting/presentation/fasting_timer_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/fasting/presentation/fasting_presentation_test_helper.dart';

void main() {
  testWidgets('M0 基建冒烟：App 启动、5 Tab 骨架、主题与双语可用', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(AppDatabase.memory()),
            localNotificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
          ],
          child: const EatWiseApp(),
        ),
      ),
    );
    // 注：不用 pumpAndSettle——go_router/slang 存在持续帧调度，settle 不收敛。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 5 Tab 骨架渲染（中文，D-15）
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);
    expect(find.text('社区'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    // 无方案态：引导 CTA 卡（四态规范 3.4 首页空态）
    expect(find.text('选择你的断食方案'), findsOneWidget);

    // 切换到英文即时生效（D-15）
    await LocaleSettings.setLocale(AppLocale.en);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Choose your fasting plan'), findsOneWidget);

    // Token 主题已挂载
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).extension<AppColors>(), isNotNull);
    expect(
      Theme.of(context).extension<AppColors>()!.brandPrimary,
      const Color(0xFF3DBE8B),
    );

    // 卸载（取消首页每秒 tick 的周期 Timer，避免收尾判定 Timer 未决）。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
