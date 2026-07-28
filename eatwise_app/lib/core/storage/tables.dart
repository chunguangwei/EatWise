import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/sync_status.dart';

/// M3 录入方式（PRD M3：拍照识别 / 语音录入 / 常吃复用 / 手动搜索）。
enum EntrySource { photo, voice, frequent, manual }

/// FoodEntry 单条饮食记录（PRD 第五章 + 《规格-数据同步与四态持久化》§1.2）。
///
/// 时间戳全部 UTC ISO8601 存储（D-07），渲染按设备本地时区换算；
/// `localDate` 为按设备时区换算的归属日（yyyy-MM-dd），供 DailyNutrition
/// 聚合与查询使用。
class FoodEntries extends Table {
  /// 本地主键（UUIDv4），客户端生成，全生命周期不变。
  TextColumn get localId => text()();

  /// 归属用户；未登录为 `anonymous`（T18）。
  TextColumn get userId => text()();

  /// 服务端主键，首次同步成功后回填（T4）。
  TextColumn get serverId => text().nullable()();

  /// 幂等键（UUIDv4）：每次上行操作生成，重试复用同一键（§2.2）。
  TextColumn get clientRequestId => text()();

  /// 四态同步状态（§1.1）。
  TextColumn get syncStatus => textEnum<SyncStatus>()();

  /// 本地每次修改 +1。
  IntColumn get localVersion => integer().withDefault(const Constant(1))();

  /// 最近一次同步成功的服务端版本号（etag 语义）。
  IntColumn get serverVersion => integer().nullable()();

  /// 最近一次同步成功的服务端时间戳（UTC），LWW 仲裁依据。
  TextColumn get serverUpdatedAt => text().nullable()();

  /// 连续重试次数，用于退避计算（§4.2）。
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// 最近一次失败原因码。
  TextColumn get lastError => text().nullable()();

  /// 本地软删标记（tombstone）。
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// 就餐时间（UTC ISO8601）。
  TextColumn get datetimeUtc => text()();

  /// 归属日（本地时区 yyyy-MM-dd，D-07 口径的聚合键）。
  TextColumn get localDate => text()();

  /// 关联食物库条目（D-16）。
  TextColumn get foodId => text().references(Foods, #id)();

  /// 份量（克）。
  RealColumn get amountG => real()();

  /// 营养快照：按份量换算后的热量（kcal）。
  RealColumn get kcal => real()();

  /// 营养快照：蛋白质（g）。
  RealColumn get proteinG => real()();

  /// 营养快照：碳水（g）。
  RealColumn get carbG => real()();

  /// 营养快照：脂肪（g）。
  RealColumn get fatG => real()();

  /// 录入方式。
  TextColumn get source => textEnum<EntrySource>()();

  /// 备注。
  TextColumn get note => text().nullable()();

  /// 本地创建时间（UTC ISO8601）。
  TextColumn get createdAtUtc => text()();

  /// 本地最后修改时间（UTC ISO8601）。
  TextColumn get updatedAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {localId};
}

/// Food 食物库（PRD 第五章 + D-16：自建核心库，中英双语条目 + 别名，
/// 每 100g 热量/蛋白/碳水/脂肪）。
class Foods extends Table {
  /// 食物条目 ID。
  TextColumn get id => text()();

  /// 中文名（D-15）。
  TextColumn get nameZh => text()();

  /// 英文名（D-15）。
  TextColumn get nameEn => text()();

  /// 中文别名（JSON 字符串数组，LIKE 搜索直接匹配）。
  TextColumn get aliasesZh => text().withDefault(const Constant('[]'))();

  /// 英文别名（JSON 字符串数组）。
  TextColumn get aliasesEn => text().withDefault(const Constant('[]'))();

  /// 每 100g 热量（kcal）。
  RealColumn get kcalPer100g => real()();

  /// 每 100g 蛋白质（g）。
  RealColumn get proteinPer100g => real()();

  /// 每 100g 碳水（g）。
  RealColumn get carbPer100g => real()();

  /// 每 100g 脂肪（g）。
  RealColumn get fatPer100g => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// DailyNutrition 聚合缓存（PRD 第五章：由 FoodEntry 聚合）。
///
/// 正式口径由服务端派生（§2.6，D-12 一致性约束）；本表为客户端离线期间的
/// 「本地预估」缓存，`isLocalEstimate=true` 时 UI 角标注明「待云端校准」。
/// 无四态、无上行，仅随本地重算/增量下行刷新。
class DailyNutritionCaches extends Table {
  /// 归属用户。
  TextColumn get userId => text()();

  /// 归属日（本地时区 yyyy-MM-dd）。
  TextColumn get date => text()();

  /// 当日记录条数。
  IntColumn get entryCount => integer().withDefault(const Constant(0))();

  /// 累计热量（kcal）。
  RealColumn get kcal => real().withDefault(const Constant(0))();

  /// 累计蛋白质（g）。
  RealColumn get proteinG => real().withDefault(const Constant(0))();

  /// 累计碳水（g）。
  RealColumn get carbG => real().withDefault(const Constant(0))();

  /// 累计脂肪（g）。
  RealColumn get fatG => real().withDefault(const Constant(0))();

  /// 是否本地预估值（§2.6）；联网后以下行服务端值为准覆盖。
  BoolColumn get isLocalEstimate =>
      boolean().withDefault(const Constant(true))();

  /// 最近重算时间（UTC ISO8601）。
  TextColumn get updatedAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, date};
}
