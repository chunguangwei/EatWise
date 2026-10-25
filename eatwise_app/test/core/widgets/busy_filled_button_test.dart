import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/widgets/busy_filled_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final busy in [false, true]) {
    testWidgets(
      'Long submit labels remain readable at large text scale: $busy',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: BusyFilledButton(
                    label: 'Save account changes',
                    busyLabel: 'Saving account changes…',
                    busy: busy,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
