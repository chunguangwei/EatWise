/// streak 领域类型与常量（《规格-M5 streak 状态机与补签卡规则》，D-12）。
///
/// 唯一口径：streak 只按「断食打卡达标」（D-08）累计；
/// 饮食记录天数独立统计，不进 streak、不影响断签、不触发里程碑。
library;

/// streak 状态机四状态（§2.1）。
enum StreakStatus {
  /// 当前连续天数 = 0，且无可补签的断签日。
  noStreak,

  /// 当前连续天数 ≥ 1，最近一个归属日已达标（或当日进行中尚未结算）。
  inStreak,

  /// 断签日仍在 7 天补签窗口内，streak 已归零，可补签恢复。
  pendingMend,

  /// 断签日已超出 7 天窗口（不可再补），UI 与无连胜一致。
  broken,
}

/// 补签卡三态（§3.2，断签弹窗/补签入口固定呈现其一，评审硬性）。
enum MendCardVisualState {
  /// 存在窗口内未补断签日且库存 ≥1：主按钮「使用补签卡恢复连胜」。
  mendable,

  /// 存在窗口内未补断签日但库存 = 0：按钮置灰「本月已用完」。
  exhausted,

  /// 无可补断签日（窗口已关闭）：仅说明 + 「补签窗口已关闭」。
  unmendable,
}

/// 里程碑档位（§5.1，PRD M5 固定三档）。
const List<int> kStreakMilestones = <int>[3, 7, 30];

/// 每月 1 日发放补签卡张数（D-12；服务端热配置，客户端同源常量）。
const int kMendCardMonthlyGrant = 2;

/// 补签卡库存上限（不累积，月底清零、月初重置为 2）。
const int kMendCardStockCap = 2;

/// 每月使用上限（张/自然月）。
const int kMendCardMonthlyUseCap = 2;

/// 补签窗口（自然日）：断签日 D 可补窗口为 [D, D+6]，第 8 天起不可补（§3.1）。
///
/// 〔遗留〕服务端 S2 现按 `today - D <= 7` 放行（比规格表多 1 天），
/// 客户端按规格表 `today - D <= 6` 判定，QA 用例 #11 以客户端口径为准。
const int kMendWindowDays = 6;

/// streak 天数显示边界（《规格-设计交付规范与全局UI四态》）：
/// 0 → 不显示火焰（首页隐藏连胜标识）；> 999 → `999+` 截断。
String formatStreakCount(int streak) {
  if (streak <= 0) return '';
  if (streak > 999) return '999+';
  return '$streak';
}

/// `yyyy-MM-dd` 自然日加减天数（与 D-07 归属日字符串同格式）。
String addDaysToIsoDate(String isoDate, int days) {
  final d = DateTime.parse(isoDate);
  final shifted = DateTime.utc(d.year, d.month, d.day + days);
  return isoOf(shifted);
}

/// DateTime → `yyyy-MM-dd`（取 UTC 日历字段；调用方保证传入的是自然日边界）。
String isoOf(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// 两个 `yyyy-MM-dd` 的自然日差（a - b，可负）。
int diffIsoDays(String a, String b) {
  final da = DateTime.parse(a);
  final db = DateTime.parse(b);
  return DateTime.utc(
    da.year,
    da.month,
    da.day,
  ).difference(DateTime.utc(db.year, db.month, db.day)).inDays;
}

/// `yyyy-MM-dd` → `yyyy-MM`（补签卡月份键）。
String monthOf(String isoDate) => isoDate.substring(0, 7);
