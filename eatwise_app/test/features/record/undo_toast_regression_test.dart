import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D-11 撤销吐司回归测试：带 action 的 SnackBar 必须 10 秒自动消失。
///
/// 背景：Flutter ≥3.44 起 `SnackBar.persist` 在 action 非空时默认 true
///（snack_bar.dart: `persist = persist ?? action != null`），
/// 导致「已记录·撤销」吐司永不自动消失（真机复现）。两处吐司
///（record_page / light_record_section）均显式 `persist: false`，
/// 本测试锚定该行为，防框架默认值变动再次引入回归。
void main() {
  testWidgets('带 action 且 persist:false 的 SnackBar 在 duration 后自动消失', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已记录'),
                    duration: const Duration(seconds: 10),
                    persist: false, // D-11：10 秒撤销窗后必须自动消失
                    action: SnackBarAction(label: '撤销', onPressed: () {}),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已记录'), findsOneWidget);
    // 10 秒撤销窗到期 + 退出动画后应消失
    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已记录'), findsNothing);
  });
}
