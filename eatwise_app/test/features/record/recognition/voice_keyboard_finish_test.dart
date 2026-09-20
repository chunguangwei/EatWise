import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/recognition/presentation/ondevice_recording_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 语音记键盘输入「完成」按钮回归（真机走查 bug：键盘敲字后完成钮永远灰色）。
/// 根因：TextField.onChanged 只写 _text 不 setState，按钮门控
/// `_typing && _effectiveText().isNotEmpty` 永不重估。
void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.zhCn));

  testWidgets('端侧录音面板：键盘输入文本后「完成」按钮变可点', (tester) async {
    Future<void> pump() => tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SafeArea(child: OnDeviceRecordingSheet())),
        ),
      ),
    );
    await pump();
    await tester.pumpAndSettle();

    final finish = find.widgetWithText(FilledButton, '完成');
    expect(
      tester.widget<FilledButton>(finish).onPressed,
      isNull,
      reason: '空文本时完成钮应禁用',
    );

    // 先点键盘切换钮进入键盘输入态（idle 态文本区是状态文案不是输入框）。
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '一个鸡蛋');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(finish).onPressed,
      isNotNull,
      reason: '输入文本后完成钮必须可点（灰色 bug 回归）',
    );

    await tester.tap(finish);
    await tester.pumpAndSettle();
  });
}
