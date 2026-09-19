import 'package:drift/drift.dart';
import 'package:eatwise/core/storage/sync_status.dart';

/// M3 录入方式（PRD M3：拍照识别 / 语音录入 / 常吃复用 / 手动搜索；
/// barcode 为包装食品扫码扩充入口）。
enum EntrySource { photo, voice, frequent, manual, barcode }

/// 餐次（薄荷走查优化点 2：记录页按早/午/晚/加餐分组展示）。
/// 可空：v8 前的历史记录无餐次，展示归入「其他」组。
enum MealType { breakfast, lunch, dinner, snack }

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

  /// 断食期用餐标记（阶段 C）：入账时断食计时进行中（fasting/fastingExtended）
  /// 为 true；仅本地属性，不上行服务端。
  BoolColumn get duringFast => boolean().withDefault(const Constant(false))();

  /// 餐次（薄荷走查优化点 2；可空——v8 前历史记录无餐次归入「其他」组）。
  /// 仅本地属性，不上行服务端（与 duringFast 同口径）。
  TextColumn get mealType => textEnum<MealType>().nullable()();

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

  /// 是否用户自定义食物（K2 个人库；搜索结果带「自定义」标签）。
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  /// 自定义食物待上行标记（离线保存为 true，上行 /foods/custom 成功转 false）。
  BoolColumn get customSyncPending =>
      boolean().withDefault(const Constant(false))();

  /// 自定义食物上行幂等键（UUIDv4，/foods/custom 重试复用，§2.2）。
  TextColumn get customClientRequestId =>
      text().withDefault(const Constant(''))();

  /// 共享贡献审核状态（K2 众包）：null=未贡献（标签「自定义」），
  /// pending=审核中 / approved=已共享 / rejected=未通过；
  /// 非自定义行下行标记 approved 时表示社区共享食物（标签「社区」）。
  TextColumn get contributionStatus => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// FastingRecord 断食历史（M5 streak 结算与 M6 趋势数据源）。
///
/// 归属日 `attributionDate` 按 D-07 冻结（进食窗口所属自然日，写入后不改写）；
/// `qualified` 为 D-08 达标判定，streak 唯一口径（D-12）。
/// 时间锚点全部 UTC epoch 秒（《规格-M2》§3.1）。
class FastingRecords extends Table {
  /// 本地主键：`userId-attributionDate`（每归属日至多一条关闭记录，幂等 upsert）。
  TextColumn get localId => text()();

  /// 归属用户；未登录为 `anonymous`。
  TextColumn get userId => text()();

  /// 打卡归属日（本地时区 yyyy-MM-dd，D-07，冻结不改写）。
  TextColumn get attributionDate => text()();

  /// 断食开始锚点（UTC epoch 秒）。
  IntColumn get startUtc => integer()();

  /// 实际结束锚点（UTC epoch 秒）。
  IntColumn get endUtc => integer()();

  /// 实际断食时长（秒）。
  IntColumn get actualSec => integer()();

  /// 计划断食时长（秒，含延长）。
  IntColumn get plannedSec => integer()();

  /// 本周期累计延长分钟数（D-10）。
  IntColumn get extendedMinutes => integer()();

  /// 终态（CycleResult 枚举名）。
  TextColumn get result => text()();

  /// 是否达标（D-08，streak 唯一口径，D-12）。
  BoolColumn get qualified => boolean()();

  /// 上行幂等键（UUIDv4，F2 上报复用，§2.2）。
  TextColumn get clientRequestId => text()();

  /// 四态同步状态（D-20）。
  TextColumn get syncStatus => textEnum<SyncStatus>()();

  /// 本地创建时间（UTC ISO8601）。
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {localId};
}

/// 饮水记录两态同步状态（轻量口径：无冲突场景〔假设〕，仅 pending/synced）。
enum WaterSyncState { pending, synced }

/// WaterLog 单条饮水记录（PRD M3 功能点 4：饮水轻量记录）。
///
/// 轻量两态同步：入账落 pending 待上行，上行成功回填 serverId 转 synced；
/// 撤销（D-11）未上行直接物理删除、已上行置 tombstone 待上行 delete op。
/// 无 update op〔假设：饮水无编辑/冲突场景〕；`localDate` 为按设备时区
/// 换算的归属日（yyyy-MM-dd），供当日累计聚合。
class WaterLogs extends Table {
  /// 本地主键（UUIDv4），客户端生成。
  TextColumn get localId => text()();

  /// 归属用户；未登录为 `anonymous`。
  TextColumn get userId => text()();

  /// 本次饮水量（毫升）。
  IntColumn get amountMl => integer()();

  /// 饮水时间（UTC ISO8601）。
  TextColumn get datetimeUtc => text()();

  /// 归属日（本地时区 yyyy-MM-dd，当日累计聚合键）。
  TextColumn get localDate => text()();

  /// 上行幂等键（UUIDv4，入账生成，重试/删除 op 复用，§2.2）。
  TextColumn get clientRequestId => text().withDefault(const Constant(''))();

  /// 服务端主键，首次上行成功回填。
  TextColumn get serverId => text().nullable()();

  /// 两态同步状态（pending/synced）。
  TextColumn get syncState => textEnum<WaterSyncState>().withDefault(
    Constant(WaterSyncState.pending.name),
  )();

  /// 本地 tombstone：已上行记录的撤销标记（上行 delete op 后物理清除）。
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// 本地创建时间（UTC ISO8601）。
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {localId};
}

/// ExerciseLog 手动记运动（无 GMS 设备手动兜底：鸿蒙等 Health Connect /
/// HealthKit 不可用场景）。
///
/// 设备级数据：纯本地落库、不上行服务端（无同步字段，与饮食四态不同口径）。
/// `typeKey` 为 `features/health/domain/exercise_types.dart` 的稳定键；
/// `kcal` 为入账快照（MET 估算值或用户手改覆盖值）。
class ExerciseLogs extends Table {
  /// 本地主键（UUIDv4），客户端生成。
  TextColumn get localId => text()();

  /// 归属用户；未登录为 `anonymous`（与 FoodEntries 同口径）。
  TextColumn get userId => text()();

  /// 运动类型键（walk/jog/run/cycling/...，见 exercise_types.dart）。
  TextColumn get typeKey => text()();

  /// 时长（分钟；截图活动统计导入无时长口径时为 0）。
  IntColumn get durationMin => integer()();

  /// 消耗快照（kcal；MET 估算或用户覆盖值）。
  RealColumn get kcal => real()();

  /// 来源标记：null = 手动录入；'screenshot' = 截图识别导入。
  TextColumn get source => text().nullable()();

  /// 步数快照（可空）：走路按步数录入 / 截图活动统计导入时落库；
  /// 数据页「步数」展示 = 系统步数（如有）+ 本列当日合计。
  IntColumn get steps => integer().nullable()();

  /// 归属日（本地时区 yyyy-MM-dd，当日合计聚合键，D-07 口径）。
  TextColumn get localDate => text()();

  /// 本地创建时间（UTC ISO8601）。
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {localId};
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
