/// 餐次（薄荷走查优化点 2：记录页按早/午/晚/加餐分组展示）。
///
/// [suggestMealType] 为入账时餐次 chips 的智能预判默认值（用户可改）；
/// [groupByMealType] 为今日记录列表分组（固定组序，无餐次历史数据归「其他」）。
library;

import 'package:eatwise/core/storage/tables.dart';

/// 餐次分组固定顺序（null = 「其他」组，v8 前无餐次的历史记录）。
const List<MealType?> mealGroupOrder = <MealType?>[
  MealType.breakfast,
  MealType.lunch,
  MealType.dinner,
  MealType.snack,
  null,
];

/// 按本地小时智能预判餐次（〔假设〕时段划分）：
/// 5–10 点早餐、10–15 午餐、15–21 晚餐、其余加餐。`hour` 取 0–23，
/// 越界输入按取模归一。
MealType suggestMealType(int hour) {
  final h = hour % 24;
  if (h >= 5 && h < 10) return MealType.breakfast;
  if (h >= 10 && h < 15) return MealType.lunch;
  if (h >= 15 && h < 21) return MealType.dinner;
  return MealType.snack;
}

/// 一组记录（`mealType` 为该组的餐次键；null = 「其他」组）。
typedef MealGroup<T> = ({MealType? mealType, List<T> items});

/// 按餐次分组（组序固定早/午/晚/加餐/其他，空组不返回；组内保持原顺序）。
List<MealGroup<T>> groupByMealType<T>(
  Iterable<T> items,
  MealType? Function(T item) mealTypeOf,
) {
  final byMeal = <MealType?, List<T>>{};
  for (final item in items) {
    byMeal.putIfAbsent(mealTypeOf(item), () => <T>[]).add(item);
  }
  return <MealGroup<T>>[
    for (final key in mealGroupOrder)
      if (byMeal[key] case final group?) (mealType: key, items: group),
  ];
}
