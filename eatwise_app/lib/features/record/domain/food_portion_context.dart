import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/domain/placeholder_food.dart';
import 'package:eatwise/features/record/domain/record_models.dart';

/// Describe persisted provenance without assigning a food a health rating.
enum FoodDataOrigin { library, manual, community, estimated, unknown }

FoodDataOrigin foodDataOrigin(Food food) {
  if (isPlaceholderFood(food)) return FoodDataOrigin.unknown;
  final source = food.source.trim().toLowerCase();
  if (source == 'llm-estimate' || source == 'llmestimate') {
    return FoodDataOrigin.estimated;
  }
  // Approval also applies to corrections of library foods; it is not provenance.
  if (source == 'community') {
    return FoodDataOrigin.community;
  }
  if (food.isCustom) {
    return source == 'manual' ? FoodDataOrigin.manual : FoodDataOrigin.unknown;
  }
  // Older seed imports did not persist the source, so their default "manual"
  // means a library row. It does not establish a specific publication or author.
  return switch (source) {
    'manual' ||
    'cfct' ||
    'curated' ||
    'usda-sr' ||
    'eatwise' => FoodDataOrigin.library,
    _ => FoodDataOrigin.unknown,
  };
}

/// Percentage of the current calorie target provided by this exact portion.
/// No dietary rating or exercise allowance is inferred. Values above 100%
/// remain visible; unavailable input/targets are not represented as zero.
double? portionCalorieTargetPercent({
  required double? amountG,
  required double kcalPer100g,
  required int targetKcal,
}) {
  if (amountG == null ||
      !isFoodAmountInRange(amountG) ||
      !kcalPer100g.isFinite ||
      kcalPer100g < 0 ||
      targetKcal <= 0) {
    return null;
  }
  final percent = (amountG / 100) * kcalPer100g / targetKcal * 100;
  return percent.isFinite ? percent : null;
}

/// Preserve a visible distinction between tiny positive amounts and zero.
String formatPortionPercent(double percent) {
  if (percent > 0 && percent < 0.1) return '<0.1';
  final rounded = percent.toStringAsFixed(1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}
