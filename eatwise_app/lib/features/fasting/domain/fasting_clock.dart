import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:timezone/timezone.dart' as tz;

/// 计时锚点工具（《规格-M2》§3：锚点生成与本地日换算）。
///
/// 纪律（§3.4）：一切计时计算只基于 UTC 锚点；
/// 展示层唯一入口 `toLocal(utc, deviceTimeZone)`。

/// 某日本地自然日的进食窗口锚点（§3.2 `anchorsFor`）。
///
/// 返回 `(eatStartUtc, eatEndUtc)`，UTC epoch 秒。
/// 跨午夜进食窗口（eatEnd ≤ eatStart）防御：eatEndUtc += 24h。
({int eatStartUtc, int eatEndUtc}) anchorsFor(
  FastingPlan plan,
  LocalDate date,
  tz.Location location,
) {
  final start = tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    plan.eatStartMinutes ~/ 60,
    plan.eatStartMinutes % 60,
  );
  final end = tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    plan.eatEndMinutes ~/ 60,
    plan.eatEndMinutes % 60,
  );
  var endUtc = _epochSec(end);
  if (plan.eatEndMinutes <= plan.eatStartMinutes) {
    endUtc += 24 * 3600; // §3.2：跨午夜进食窗口防御
  }
  return (eatStartUtc: _epochSec(start), eatEndUtc: endUtc);
}

/// UTC epoch 秒 → 指定时区下的本地自然日（归属日计算基础，D-07）。
LocalDate localDateOf(int utcSec, tz.Location location) {
  final dt = tz.TZDateTime.from(
    DateTime.fromMillisecondsSinceEpoch(utcSec * 1000, isUtc: true),
    location,
  );
  return LocalDate(dt.year, dt.month, dt.day);
}

/// 某时区下本地自然日 0:00 的 UTC epoch 秒（方案次日生效用，D-06）。
int localMidnightUtc(LocalDate date, tz.Location location) {
  return _epochSec(tz.TZDateTime(location, date.year, date.month, date.day));
}

/// UTC epoch 秒 → 指定时区墙钟（展示层唯一入口，§3.1）。
tz.TZDateTime toLocal(int utcSec, tz.Location location) {
  return tz.TZDateTime.from(
    DateTime.fromMillisecondsSinceEpoch(utcSec * 1000, isUtc: true),
    location,
  );
}

int _epochSec(tz.TZDateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;
