import 'package:eatwise/features/record/domain/food_portion_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portion amount determines the share of the current daily target', () {
    expect(
      portionCalorieTargetPercent(
        amountG: 200,
        kcalPer100g: 116,
        targetKcal: 2000,
      ),
      closeTo(11.6, 1e-9),
    );
    expect(
      portionCalorieTargetPercent(
        amountG: 5000,
        kcalPer100g: 116,
        targetKcal: 2000,
      ),
      closeTo(290, 1e-9),
    );
  });

  test('missing, non-finite or out-of-range portions have no share', () {
    for (final amount in <double?>[
      null,
      0,
      -1,
      0.09,
      5000.1,
      double.nan,
      double.infinity,
    ]) {
      expect(
        portionCalorieTargetPercent(
          amountG: amount,
          kcalPer100g: 116,
          targetKcal: 2000,
        ),
        isNull,
      );
    }
  });

  test('unavailable targets and invalid calories have no share', () {
    for (final target in [0, -1]) {
      expect(
        portionCalorieTargetPercent(
          amountG: 100,
          kcalPer100g: 116,
          targetKcal: target,
        ),
        isNull,
      );
    }
    for (final kcal in [-1.0, double.nan, double.infinity, double.maxFinite]) {
      expect(
        portionCalorieTargetPercent(
          amountG: 5000,
          kcalPer100g: kcal,
          targetKcal: 2000,
        ),
        isNull,
      );
    }
  });

  test('zero calories retain a valid zero share', () {
    expect(
      portionCalorieTargetPercent(
        amountG: 100,
        kcalPer100g: 0,
        targetKcal: 2000,
      ),
      0,
    );
  });

  test('tiny positive shares remain distinguishable from zero', () {
    final tiny = portionCalorieTargetPercent(
      amountG: 0.1,
      kcalPer100g: 116,
      targetKcal: 2000,
    )!;
    expect(formatPortionPercent(tiny), '<0.1');
    expect(formatPortionPercent(0), '0');
    expect(formatPortionPercent(11.6), '11.6');
    expect(formatPortionPercent(290), '290');
  });
}
