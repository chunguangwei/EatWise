import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/fasting_record_dao.dart';
import 'package:eatwise/core/storage/food_dao.dart';
import 'package:eatwise/core/storage/food_entry_dao.dart';
import 'package:eatwise/core/storage/sync_status.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/storage/water_log_dao.dart';

part 'database.g.dart';

/// 本地 SQLite 数据库（drift，D-17）。
///
/// 覆盖 M3 实体：FoodEntry（四态持久化，D-20）、Food（双语食物库，D-16）、
/// DailyNutrition 聚合缓存（本地预估，§2.6）、WaterLog（饮水轻量记录，
/// 两态同步 pending/synced，无冲突场景〔假设〕）。
///
/// 〔集成说明〕SQLCipher 加密（《规格-数据同步与四态持久化》§7.2）在 M0 另行
/// 接入，本类预留 QueryExecutor 注入点，加密 executor 就绪后无需改表结构。
@DriftDatabase(
  tables: <Type>[
    FoodEntries,
    Foods,
    DailyNutritionCaches,
    FastingRecords,
    WaterLogs,
  ],
  daos: <Type>[FoodDao, FoodEntryDao, FastingRecordDao, WaterLogDao],
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2：新增 FastingRecords（M5 streak 结算 / M6 趋势数据源）。
      if (from < 2) {
        await m.createTable(fastingRecords);
      }
      // v3：新增 WaterLogs（M3 饮水轻量记录，PRD M3 功能点 4）。
      if (from < 3) {
        await m.createTable(waterLogs);
      }
      // v4：WaterLogs 补两态同步字段（clientRequestId/serverId/syncState/deleted）。
      // from<3 时 createTable 已按最新口径建表（含同步列），仅 v3 老库需补列。
      if (from >= 3 && from < 4) {
        await m.addColumn(waterLogs, waterLogs.clientRequestId);
        await m.addColumn(waterLogs, waterLogs.serverId);
        await m.addColumn(waterLogs, waterLogs.syncState);
        await m.addColumn(waterLogs, waterLogs.deleted);
      }
      // v5：Foods 补自定义食物字段（isCustom/customSyncPending/
      // customClientRequestId，K2 个人库 + 离线 pending 上行幂等键）。
      if (from < 5) {
        await m.addColumn(foods, foods.isCustom);
        await m.addColumn(foods, foods.customSyncPending);
        await m.addColumn(foods, foods.customClientRequestId);
      }
    },
  );
}
