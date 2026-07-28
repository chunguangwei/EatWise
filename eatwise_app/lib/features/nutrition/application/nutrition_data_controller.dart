import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/food_entry_dao.dart';
import 'package:eatwise/core/storage/providers.dart';
import 'package:eatwise/features/fasting/domain/daily_nutrition.dart';
import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/fasting/presentation/mini_signal_cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 数据页（/data）application 层：日期切换 + 当日信号灯判定 + 近 7 日趋势。
///
/// 数据流：drift DailyNutritionCaches 聚合缓存（本地预估，§2.6）→
/// [DailyIntake] → `evaluateDailySignals`（signal_light/daily_nutrition 领域
/// 纯函数，D-05 闭区间）→ 落区 + 建议 key；当日 0 条记录 → hasData=false，
/// 前端不渲染信号灯（§3.2 / D-05）。目标值复用首页
/// [nutritionGoalProvider]（M1 快照，缺失走 D-04 兜底并提示补全）。

/// 数据页时钟（测试可拨动；日期上限「不可超今天」以它为基准）。
final Provider<DateTime> nutritionNowProvider = Provider<DateTime>((ref) {
  return DateTime.now();
});

/// 取本地日期部分（午夜归零）。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 本地日期 → 聚合缓存键（yyyy-MM-dd，与 FoodEntry.localDate 同口径）。
String localDateOf(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// 数据页选中日（本地时区，仅日期）。
final NotifierProvider<SelectedDateController, DateTime> selectedDateProvider =
    NotifierProvider<SelectedDateController, DateTime>(
      SelectedDateController.new,
    );

/// 日期切换控制器：前一天 / 后一天（不可超今天）/ 回到今天。
class SelectedDateController extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(ref.watch(nutritionNowProvider));

  /// 今天（时钟基准的日期部分）。
  DateTime get _today => dateOnly(ref.read(nutritionNowProvider));

  /// 是否还能往后翻（选中日早于今天）。
  bool get canGoNext => state.isBefore(_today);

  /// 前一天。
  void prevDay() {
    state = state.subtract(const Duration(days: 1));
  }

  /// 后一天；已到今天则不动作（PRD M4：不可超今天）。
  void nextDay() {
    if (canGoNext) state = state.add(const Duration(days: 1));
  }

  /// 回到今天。
  void backToToday() {
    state = _today;
  }
}

/// 「后一天」按钮可用态（派生，供按钮禁用渲染）。
final Provider<bool> canGoNextDayProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedDateProvider);
  final today = dateOnly(ref.watch(nutritionNowProvider));
  return selected.isBefore(today);
});

/// 是否为「今天」视图（隐藏「回到今天」按钮）。
final Provider<bool> isTodaySelectedProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedDateProvider);
  final today = dateOnly(ref.watch(nutritionNowProvider));
  return selected == today;
});

/// 数据页聚合缓存读取端口（测试可换内存实现）。
abstract interface class NutritionDataSource {
  /// 某日聚合缓存流（无记录日为 null）。
  Stream<DailyNutritionCache?> watchDay(String localDate);

  /// 日期区间聚合缓存流（含端点，按日期升序；趋势图用）。
  Stream<List<DailyNutritionCache>> watchRange(String fromDate, String toDate);
}

/// drift 实现：读 DailyNutritionCaches 聚合缓存（本地预估）。
final class DriftNutritionDataSource implements NutritionDataSource {
  const DriftNutritionDataSource(this._dao, {required this.userId});

  final FoodEntryDao _dao;

  /// 归属用户。〔集成说明〕与 recordRepository 缺省口径一致（anonymous）；
  /// M7 登录态贯通后按会话 userId 装配。
  final String userId;

  @override
  Stream<DailyNutritionCache?> watchDay(String localDate) {
    return _dao.watchDailyNutrition(userId, localDate);
  }

  @override
  Stream<List<DailyNutritionCache>> watchRange(String fromDate, String toDate) {
    return _dao.watchDailyNutritionRange(userId, fromDate, toDate);
  }
}

/// 数据源装配（生产：drift；测试：override 为内存实现）。
final Provider<NutritionDataSource> nutritionDataSourceProvider =
    Provider<NutritionDataSource>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return DriftNutritionDataSource(db.foodEntryDao, userId: 'anonymous');
    });

/// 选中日聚合缓存流。
final StreamProvider<DailyNutritionCache?> dayCacheProvider =
    StreamProvider<DailyNutritionCache?>((ref) {
      final date = ref.watch(selectedDateProvider);
      return ref.watch(nutritionDataSourceProvider).watchDay(localDateOf(date));
    });

/// 选中日累计摄入（0 条记录 → null 走空态）。
final Provider<DailyIntake?> dayIntakeProvider = Provider<DailyIntake?>((ref) {
  final cache = ref.watch(dayCacheProvider).valueOrNull;
  if (cache == null || cache.entryCount == 0) return null;
  return DailyIntake(
    entryCount: cache.entryCount,
    kcal: cache.kcal,
    proteinG: cache.proteinG,
    carbG: cache.carbG,
    fatG: cache.fatG,
  );
});

/// 选中日信号灯判定（D-05；规则热配置当前用内置默认值，
/// 与首页 mini 信号卡同口径）。
final Provider<DailySignal> daySignalsProvider = Provider<DailySignal>((ref) {
  final intake = ref.watch(dayIntakeProvider);
  final goal = ref.watch(nutritionGoalProvider);
  return evaluateDailySignals(
    intake ??
        const DailyIntake(
          entryCount: 0,
          kcal: 0,
          proteinG: 0,
          carbG: 0,
          fatG: 0,
        ),
    goal,
    NutritionRuleConfig.defaults,
  );
});

/// 当前餐段（建议模板 `{meal_action}` 插值用，§4.1〔假设〕）。
final Provider<MealSegment> mealSegmentProvider = Provider<MealSegment>((ref) {
  final now = ref.watch(nutritionNowProvider);
  return mealSegmentForMinutes(now.hour * 60 + now.minute);
});

/// 一句话总结语气（H2，温和品牌语气）。
enum DaySummaryTone { empty, allGreen, hasYellow, hasRed }

/// 总结语气判定：无记录 → empty；任一红 → hasRed；任一黄 → hasYellow；
/// 全绿 → allGreen。
final Provider<DaySummaryTone> daySummaryProvider = Provider<DaySummaryTone>((
  ref,
) {
  final signal = ref.watch(daySignalsProvider);
  if (!signal.hasData) return DaySummaryTone.empty;
  var hasYellow = false;
  for (final verdict in signal.verdicts.values) {
    if (verdict.zone == SignalZone.red) return DaySummaryTone.hasRed;
    if (verdict.zone == SignalZone.yellow) hasYellow = true;
  }
  return hasYellow ? DaySummaryTone.hasYellow : DaySummaryTone.allGreen;
});

/// 近 7 日聚合缓存流（以选中日为终点，随日期切换联动）。
final StreamProvider<List<DailyNutritionCache>> weeklyTrendProvider =
    StreamProvider<List<DailyNutritionCache>>((ref) {
      final end = ref.watch(selectedDateProvider);
      final start = end.subtract(const Duration(days: 6));
      return ref
          .watch(nutritionDataSourceProvider)
          .watchRange(localDateOf(start), localDateOf(end));
    });

/// 近 7 日热量序列（长度 7，无记录日为 null，按日期升序对齐）。
final Provider<List<double?>> weeklyKcalProvider = Provider<List<double?>>((
  ref,
) {
  final end = ref.watch(selectedDateProvider);
  final caches = ref.watch(weeklyTrendProvider).valueOrNull;
  final byDate = <String, double>{
    for (final c in caches ?? const <DailyNutritionCache>[])
      if (c.entryCount > 0) c.date: c.kcal,
  };
  return List<double?>.generate(7, (i) {
    final date = localDateOf(end.subtract(Duration(days: 6 - i)));
    return byDate[date];
  });
});

/// 近 7 日断食时长序列（小时）。
///
/// 〔假设/遗留〕断食历史尚未持久化（FastingCycleStore 仅存进行中周期与
/// 最近一条闭合记录），M6 深度趋势接入真实历史；当前恒为空序列，
/// 趋势图走空态引导。
final Provider<List<double?>> weeklyFastingHoursProvider =
    Provider<List<double?>>((ref) {
      ref.watch(selectedDateProvider);
      return List<double?>.filled(7, null);
    });
