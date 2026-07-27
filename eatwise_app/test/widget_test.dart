import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('M0 基建冒烟：App 启动、主题与双语可用', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    await tester.pumpWidget(
      TranslationProvider(child: const ProviderScope(child: EatWiseApp())),
    );
    // 注：不用 pumpAndSettle——go_router/slang 存在持续帧调度，settle 不收敛。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 中文文案渲染
    expect(find.text('断食计时'), findsOneWidget);
    expect(find.text('结束断食'), findsOneWidget);

    // 切换到英文即时生效（D-15）
    await LocaleSettings.setLocale(AppLocale.en);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('End fast'), findsOneWidget);

    // Token 主题已挂载
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).extension<AppColors>(), isNotNull);
    expect(
      Theme.of(context).extension<AppColors>()!.brandPrimary,
      const Color(0xFF3DBE8B),
    );
  });
}
