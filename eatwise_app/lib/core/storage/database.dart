import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/fasting_record_dao.dart';
import 'package:eatwise/core/storage/food_dao.dart';
import 'package:eatwise/core/storage/food_entry_dao.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';

part 'database.g.dart';

/// 本地 SQLite 数据库（drift，D-17）。
///
/// 覆盖 M3 实体：FoodEntry（四态持久化，D-20）、Food（双语食物库，D-16）、
/// DailyNutrition 聚合缓存（本地预估，§2.6）。
///
/// 〔集成说明〕SQLCipher 加密（《规格-数据同步与四态持久化》§7.2）在 M0 另行
/// 接入，本类预留 QueryExecutor 注入点，加密 executor 就绪后无需改表结构。
@DriftDatabase(
  tables: <Type>[FoodEntries, Foods, DailyNutritionCaches, FastingRecords],
  daos: <Type>[FoodDao, FoodEntryDao, FastingRecordDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 测试用内存库。
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  /// 生产库：在 [directoryPath] 下创建/打开 eatwise.db。
  ///
  /// 〔集成说明〕目录由集成方提供（应用文档目录，需在 pubspec 声明
  /// path_provider 直接依赖后解析）；Android 原生 sqlite3 由
  /// sqlite3_flutter_libs 提供（D-17）。
  static AppDatabase openAt(String directoryPath) {
    final file = File('$directoryPath/eatwise.db');
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2：新增 FastingRecords（M5 streak 结算 / M6 趋势数据源）。
      if (from < 2) {
        await m.createTable(fastingRecords);
      }
    },
  );
}
