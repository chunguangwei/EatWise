import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:timezone/timezone.dart' as tz;

/// 测试用时区数据库初始化（与 test/features/fasting/tz_test_helper.dart 同法：
/// flutter test 环境不支持 `Isolate.resolvePackageUriSync`，手动定位数据文件）。
Future<void> initRecordTestTimeZones() async {
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = (config['packages']! as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final tzPackage = packages.firstWhere((p) => p['name'] == 'timezone');
  var rootUri = Uri.parse(tzPackage['rootUri']! as String);
  if (!rootUri.path.endsWith('/')) {
    rootUri = rootUri.replace(path: '${rootUri.path}/');
  }
  final packageUri = Uri.parse(tzPackage['packageUri']! as String);
  final dataUri = rootUri.resolveUri(packageUri).resolve('data/latest_all.tzf');
  final bytes = await File.fromUri(dataUri).readAsBytes();
  tz.initializeDatabase(bytes);
}

/// 食物库种子数据（D-16：中英双语名称 + 别名 + 每 100g 四营养）。
Future<void> seedFoods(AppDatabase db) {
  return db.foodDao.upsertAll(<FoodsCompanion>[
    const FoodsCompanion(
      id: Value('f-rice'),
      nameZh: Value('白米饭'),
      nameEn: Value('White Rice'),
      aliasesZh: Value('["米饭","白饭"]'),
      aliasesEn: Value('["rice","steamed rice"]'),
      kcalPer100g: Value(116),
      proteinPer100g: Value(2.6),
      carbPer100g: Value(25.9),
      fatPer100g: Value(0.3),
    ),
    const FoodsCompanion(
      id: Value('f-egg'),
      nameZh: Value('鸡蛋'),
      nameEn: Value('Egg'),
      aliasesZh: Value('["水煮蛋","笨蛋"]'),
      aliasesEn: Value('["boiled egg"]'),
      kcalPer100g: Value(144),
      proteinPer100g: Value(13.3),
      carbPer100g: Value(2.8),
      fatPer100g: Value(8.8),
    ),
    const FoodsCompanion(
      id: Value('f-chicken'),
      nameZh: Value('鸡胸肉'),
      nameEn: Value('Chicken Breast'),
      aliasesZh: Value('["鸡胸"]'),
      aliasesEn: Value('["chicken"]'),
      kcalPer100g: Value(133),
      proteinPer100g: Value(19.4),
      carbPer100g: Value(2.5),
      fatPer100g: Value(5),
    ),
  ]);
}
