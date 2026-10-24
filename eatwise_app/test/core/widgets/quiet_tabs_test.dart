import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/widgets/quiet_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('轻量页签可选中且触控高度不小于 44', (tester) async {
    var selected = 7;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppQuietTabs<int>(
            values: const <int>[7, 30, 90],
            selected: selected,
            labelOf: (value) => '$value days',
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.text('7 days')).height, greaterThan(0));
    expect(
      tester.getSize(find.byType(InkWell).first).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('30 days'));
    expect(selected, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 宽与大字体下暗色页签无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: AppQuietTabs<int>(
              values: const <int>[7, 30, 90, 365],
              selected: 30,
              labelOf: (value) => '$value days',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('30 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
