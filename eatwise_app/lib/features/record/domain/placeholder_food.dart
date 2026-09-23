import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';

/// 占位食物行判定（名称==id 双列）：下行记录引用的食物行本地缺失时合成
/// （RemoteRecordSync._ensurePlaceholderFood），名称暂存 foodId 字面量。
///
/// 占位行由 RemoteRecordSync.backfillPlaceholderFoods 经 /foods/batch-get
/// 回查补真名；服务端已删（查不到）的保留占位，UI 用 [displayFoodName]
/// 回退「未知食物」，id 在食物详情页仍可查（详情页小字展示）。
bool isPlaceholderFood(Food food) {
  return food.nameZh == food.id && food.nameEn == food.id;
}

/// 食物展示名（占位行回退「未知食物」，其余按语种）。
String displayFoodName(Translations t, Food food, {required bool isEn}) {
  if (isPlaceholderFood(food)) return t.record.unknownFood;
  return isEn ? food.nameEn : food.nameZh;
}
