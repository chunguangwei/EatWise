import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/core/storage/exercise_log_dao.dart';
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
/// 两态同步 pending/synced，无冲突场景〔假设〕）、ExerciseLog（手动记运动，
/// 设备级纯本地不上行）。
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
    ExerciseLogs,
  ],
  daos: <Type>[
    FoodDao,
    FoodEntryDao,
    FastingRecordDao,
    WaterLogDao,
    ExerciseLogDao,
  ],
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
  int get schemaVersion => 10;

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
      // v6：Foods 补共享贡献审核状态（contributionStatus，K2 众包候选）。
      if (from < 6) {
        await m.addColumn(foods, foods.contributionStatus);
      }
      // v7：FoodEntries 补断食期用餐标记（duringFast，阶段 C，纯本地属性）。
      if (from < 7) {
        await m.addColumn(foodEntries, foodEntries.duringFast);
      }
      // v8：FoodEntries 补餐次（mealType 可空，薄荷走查优化点 2，纯本地属性；
      // 历史记录无餐次，展示归入「其他」组）。
      if (from < 8) {
        await m.addColumn(foodEntries, foodEntries.mealType);
      }
      // v9：新增 ExerciseLogs（手动记运动，无 GMS 设备兜底；设备级纯本地）。
      if (from < 9) {
        await m.createTable(exerciseLogs);
      }
      // v10：ExerciseLogs 补来源标记（source 可空：null=手动录入，
      // 'screenshot'=截图识别导入）。from<9 时 createTable 已按最新口径
      // 建表（含 source 列），仅 v9 老库需补列（同 v3→v4 口径）。
      if (from >= 9 && from < 10) {
        await m.addColumn(exerciseLogs, exerciseLogs.source);
      }
    },
  );
}
