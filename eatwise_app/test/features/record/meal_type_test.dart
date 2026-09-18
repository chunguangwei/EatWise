import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/domain/meal_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// 餐次纯函数（薄荷走查优化点 2）：智能预判时段 + 今日列表分组。
void main() {
  group('suggestMealType（5–10 早 / 10–15 午 / 15–21 晚 / 其余加餐）', () {
    test('边界：5 点早餐、10 点午餐、15 点晚餐、21 点加餐', () {
      expect(suggestMealType(5), MealType.breakfast);
      expect(suggestMealType(9), MealType.breakfast);
      expect(suggestMealType(10), MealType.lunch);
      expect(suggestMealType(14), MealType.lunch);
      expect(suggestMealType(15), MealType.dinner);
      expect(suggestMealType(20), MealType.dinner);
      expect(suggestMealType(21), MealType.snack);
      expect(suggestMealType(4), MealType.snack);
      expect(suggestMealType(0), MealType.snack);
      expect(suggestMealType(23), MealType.snack);
    });

    test('越界输入按 24 小时取模归一', () {
      expect(suggestMealType(24), MealType.snack); // 0 点
      expect(suggestMealType(29), MealType.breakfast); // 5 点
    });
  });

  group('groupByMealType（固定组序 + 无餐次归「其他」）', () {
    test('组序早/午/晚/加餐/其他，空组不返回，组内保持原顺序', () {
      final items = <(String, MealType?)>[
        ('a', MealType.dinner),
        ('b', null), // 历史无餐次 → 其他
        ('c', MealType.breakfast),
        ('d', MealType.dinner),
        ('e', MealType.snack),
      ];
      final groups = groupByMealType(items, (item) => item.$2);
      expect(groups.map((g) => g.mealType), <MealType?>[
        MealType.breakfast,
        MealType.dinner,
        MealType.snack,
        null,
      ]);
      expect(groups[0].items.map((i) => i.$1), <String>['c']);
      expect(groups[1].items.map((i) => i.$1), <String>['a', 'd']);
      expect(groups[3].items.map((i) => i.$1), <String>['b']);
    });

    test('空输入 → 空分组', () {
      expect(groupByMealType(<int>[], (i) => MealType.lunch), isEmpty);
    });
  });
}
