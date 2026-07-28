// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'food_entry_dao.dart';

// ignore_for_file: type=lint
mixin _$FoodEntryDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoodsTable get foods => attachedDatabase.foods;
  $FoodEntriesTable get foodEntries => attachedDatabase.foodEntries;
  $DailyNutritionCachesTable get dailyNutritionCaches =>
      attachedDatabase.dailyNutritionCaches;
  FoodEntryDaoManager get managers => FoodEntryDaoManager(this);
}

class FoodEntryDaoManager {
  final _$FoodEntryDaoMixin _db;
  FoodEntryDaoManager(this._db);
  $$FoodsTableTableManager get foods =>
      $$FoodsTableTableManager(_db.attachedDatabase, _db.foods);
  $$FoodEntriesTableTableManager get foodEntries =>
      $$FoodEntriesTableTableManager(_db.attachedDatabase, _db.foodEntries);
  $$DailyNutritionCachesTableTableManager get dailyNutritionCaches =>
      $$DailyNutritionCachesTableTableManager(
        _db.attachedDatabase,
        _db.dailyNutritionCaches,
      );
}
