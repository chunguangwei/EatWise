import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:eatwise/features/streak/presentation/streak_banner.dart';
import 'package:eatwise/features/streak/presentation/streak_break_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 断签弹窗三态（评审硬性：「连胜如何计算」+ 剩余次数 + 三态之一，中英双语）
/// + 首页连胜横幅显示边界（streak=0 不显示火焰 / 999+）。
void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Widget wrap(Widget child) {
    return TranslationProvider(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  StreakBreakDialog dialogOf(
    MendCardVisualState state, {
    int cardsLeft = 2,
    int restoreDays = 4,
    VoidCallback? onMend,
  }) {
    return StreakBreakDialog(
      visualState: state,
      cardsLeft: cardsLeft,
      restoreDays: restoreDays,
      onMend: onMend ?? () {},
      onDismiss: () {},
    );
  }

  group('断签弹窗（§4 三要素 + 三态）', () {
    testWidgets('可补签：说明 + 剩余次数 + 主按钮可用', (tester) async {
      var mended = false;
      await tester.pumpWidget(
        wrap(
          dialogOf(MendCardVisualState.mendable, onMend: () => mended = true),
        ),
      );
      // 要素①：连胜如何计算；要素②：剩余次数。
      expect(find.text('哎呀，连胜中断了'), findsOneWidget);
      expect(find.textContaining('连胜只按「断食打卡达标」累计'), findsOneWidget);
      expect(find.text('本月剩余补签卡：2 张'), findsOneWidget);
      // 要素③：可补签主按钮（轻盈绿填充，可点按）。
      final cta = find.widgetWithText(FilledButton, '使用补签卡，恢复 4 天连胜');
      expect(cta, findsOneWidget);
      expect(tester.widget<FilledButton>(cta).onPressed, isNotNull);
      await tester.tap(cta);
      expect(mended, isTrue);
      // 次按钮。
      expect(find.text('知道了，重新开始'), findsOneWidget);
    });

    testWidgets('已用尽：按钮置灰 + 下月发放说明', (tester) async {
      await tester.pumpWidget(
        wrap(dialogOf(MendCardVisualState.exhausted, cardsLeft: 0)),
      );
      expect(find.text('本月剩余补签卡：0 张'), findsOneWidget);
      final cta = find.widgetWithText(FilledButton, '使用补签卡，恢复 4 天连胜');
      expect(tester.widget<FilledButton>(cta).onPressed, isNull);
      expect(find.textContaining('本月补签卡已用完'), findsOneWidget);
    });

    testWidgets('已断签超 7 天：不展示补签按钮，仅窗口关闭说明', (tester) async {
      await tester.pumpWidget(wrap(dialogOf(MendCardVisualState.unmendable)));
      expect(find.textContaining('补签窗口已关闭'), findsOneWidget);
      expect(find.textContaining('使用补签卡'), findsNothing);
      // 三要素①②仍在（评审硬性缺一不可）。
      expect(find.textContaining('连胜只按「断食打卡达标」累计'), findsOneWidget);
      expect(find.text('本月剩余补签卡：2 张'), findsOneWidget);
    });

    testWidgets('英文语言环境：三要素英文文案', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await tester.pumpWidget(
        wrap(dialogOf(MendCardVisualState.mendable, cardsLeft: 1)),
      );
      expect(find.text('Your streak was interrupted'), findsOneWidget);
      expect(
        find.textContaining('counts only days you complete'),
        findsOneWidget,
      );
      expect(find.text('Mend Cards left this month: 1'), findsOneWidget);
      expect(
        find.text('Use a Mend Card to restore your 4-day streak'),
        findsOneWidget,
      );
    });
  });

  group('首页连胜横幅（显示边界）', () {
    testWidgets('streak=0：不显示火焰，显示引导文案', (tester) async {
      await tester.pumpWidget(wrap(const StreakBanner(currentStreak: 0)));
      expect(find.text('完成今天断食，开启第 1 天'), findsOneWidget);
      expect(find.textContaining('🔥'), findsNothing);
    });

    testWidgets('streak=7：连续 7 天 🔥', (tester) async {
      await tester.pumpWidget(wrap(const StreakBanner(currentStreak: 7)));
      expect(find.text('连续 7 天 🔥'), findsOneWidget);
    });

    testWidgets('streak=1234：999+ 截断', (tester) async {
      await tester.pumpWidget(wrap(const StreakBanner(currentStreak: 1234)));
      expect(find.text('连续 999+ 天 🔥'), findsOneWidget);
    });
  });
}
