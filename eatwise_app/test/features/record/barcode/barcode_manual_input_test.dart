import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_manual_input.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手动输码对话框测试：格式校验（非法原地提示不关窗）+ 合法返回条码。
void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  Future<void> pumpHost(
    WidgetTester tester, {
    required void Function(String? code) onResult,
  }) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  final code = await showBarcodeManualInput(
                    context,
                    BarcodeStrings.of(context),
                  );
                  onResult(code);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('非法条码（短于 8 位）→ 原地错误提示，弹窗不关闭', (tester) async {
    String? result = 'untouched';
    await pumpHost(tester, onResult: (code) => result = code);

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('查询'));
    await tester.pump();

    expect(find.text('条码格式不正确，应为 8–14 位数字'), findsOneWidget);
    expect(find.text('输入条码'), findsOneWidget); // 弹窗仍在
    expect(result, 'untouched');
  });

  testWidgets('输入修正后错误提示消失，合法条码返回', (tester) async {
    String? result;
    await pumpHost(tester, onResult: (code) => result = code);

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('查询'));
    await tester.pump();
    expect(find.text('条码格式不正确，应为 8–14 位数字'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '6901234567892');
    await tester.pump();
    expect(find.text('条码格式不正确，应为 8–14 位数字'), findsNothing);

    await tester.tap(find.text('查询'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(result, '6901234567892');
    expect(find.text('输入条码'), findsNothing);
  });

  testWidgets('取消 → 返回 null', (tester) async {
    var called = false;
    String? result;
    await pumpHost(
      tester,
      onResult: (code) {
        called = true;
        result = code;
      },
    );

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(called, isTrue);
    expect(result, isNull);
  });
}
