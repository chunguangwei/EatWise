import 'package:eatwise/core/widgets/chart_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dense chart labels stay inside bounds and never overlap at large text',
    () {
      for (final width in [200.0, 288.0, 343.0, 600.0]) {
        for (final scale in [1.0, 1.5, 2.0, 3.0]) {
          final layout = ChartLabelLayout(
            width: width,
            style: const TextStyle(fontSize: 12, height: 1.4),
            textScaler: TextScaler.linear(scale),
          );
          for (final i in chartLabelPriority(7)) {
            layout.place('2100', width * i / 6, 0);
          }
          expect(layout.bounds, isNotEmpty);
          // Newest value is reserved first, even at the right edge.
          expect(layout.bounds.first.right, width);
          for (var i = 0; i < layout.bounds.length; i++) {
            final rect = layout.bounds[i];
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            for (var j = i + 1; j < layout.bounds.length; j++) {
              expect(rect.inflate(6).overlaps(layout.bounds[j]), isFalse);
            }
          }
        }
      }
    },
  );

  test('year labels near the final date do not pile up at the right edge', () {
    final layout = ChartLabelLayout(
      width: 280,
      style: const TextStyle(fontSize: 12),
    );
    for (final i in chartLabelPriority(13)) {
      layout.place('2026/10', 280 * i / 12, 0);
    }
    expect(layout.bounds.length, lessThan(13));
    expect(layout.bounds.first.right, 280);
  });
}
