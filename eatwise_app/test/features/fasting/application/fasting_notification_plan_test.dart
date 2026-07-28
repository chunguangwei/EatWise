import 'package:eatwise/features/fasting/application/fasting_notification_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../tz_test_helper.dart';

/// 《规格-M2 断食计时状态机》§7 通知计划的纯逻辑测试。
///
/// 时间线约定（与 §6 边界用例表一致）：BJT = Asia/Shanghai（UTC+8），
/// 默认方案 16:8（进食 12:00–20:00）；d = 2026-07-28。
void main() {
  const plan = FastingPlan.plan16x8;
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  int utc(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 7, day, hour, minute).millisecondsSinceEpoch ~/ 1000;

  // BJT 12:00 = UTC 04:00；BJT 20:00 = UTC 12:00；BJT 11:45 = UTC 03:45。
  group('buildFastingNotificationPlan（16:8，BJT）', () {
    test('断食中（d 08:00 BJT）：未来 48h 排 6 条，跨午夜窗口不跳变', () {
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 0), // d 08:00 BJT
        location: bjt,
      );

      expect(items, hasLength(6));
      expect(items.map((e) => (e.kind, e.triggerAtUtcSec)).toList(), [
        (FastingNotificationKind.eatSoon, utc(28, 3, 45)),
        (FastingNotificationKind.eatStart, utc(28, 4)),
        (FastingNotificationKind.fastStart, utc(28, 12)),
        (FastingNotificationKind.eatSoon, utc(29, 3, 45)),
        (FastingNotificationKind.eatStart, utc(29, 4)),
        (FastingNotificationKind.fastStart, utc(29, 12)),
      ]);
    });

    test('进食窗口中（d 15:00 BJT）：已过触发点剔除，48h 窗口边界裁剪', () {
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 7), // d 15:00 BJT
        location: bjt,
      );

      expect(items.map((e) => (e.kind, e.triggerAtUtcSec)).toList(), [
        (FastingNotificationKind.fastStart, utc(28, 12)),
        (FastingNotificationKind.eatSoon, utc(29, 3, 45)),
        (FastingNotificationKind.eatStart, utc(29, 4)),
        (FastingNotificationKind.fastStart, utc(29, 12)),
        (FastingNotificationKind.eatSoon, utc(30, 3, 45)),
        (FastingNotificationKind.eatStart, utc(30, 4)),
        // d+2 20:00 BJT（= utc(30, 12)）超出 48h，被裁剪
      ]);
    });

    test('窗口边界：恰好在 horizon 终点（含）与超出 1 秒（剔）', () {
      final now = utc(28, 2, 45); // d 10:45 BJT
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: now,
        location: bjt,
        horizonSec: 3600,
      );
      // eatSoon = now + 3600，恰好在窗口终点（闭区间）→ 保留；
      // eatStart = now + 4500 → 裁剪。
      expect(items, hasLength(1));
      expect(items.single.kind, FastingNotificationKind.eatSoon);
      expect(items.single.triggerAtUtcSec, now + 3600);
    });

    test('延长 30min（D-10）：当前周期锚点后移，次日周期不受影响', () {
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 0), // d 08:00 BJT，断食中
        location: bjt,
        extensionMinutes: 30,
      );

      expect(items.map((e) => (e.kind, e.triggerAtUtcSec)).toList(), [
        // 当日（当前周期目标日）：进食开始 12:00→12:30，
        // 进食结束 20:00→20:30（进食窗口时长不压缩，T5）
        (FastingNotificationKind.eatSoon, utc(28, 4, 15)),
        (FastingNotificationKind.eatStart, utc(28, 4, 30)),
        (FastingNotificationKind.fastStart, utc(28, 12, 30)),
        // 次日：延长不跨周期继承（§4.3）
        (FastingNotificationKind.eatSoon, utc(29, 3, 45)),
        (FastingNotificationKind.eatStart, utc(29, 4)),
        (FastingNotificationKind.fastStart, utc(29, 12)),
      ]);
    });

    test('进食中延长参数只作用于「下一个」周期目标日', () {
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 7), // d 15:00 BJT，进食中
        location: bjt,
        extensionMinutes: 30,
      );
      // now 之后第一个进食开始锚点是 d+1 12:00 → d+1 锚点整体后移
      expect(items[1].triggerAtUtcSec, utc(29, 4, 15)); // eatSoon d+1
      expect(items[2].triggerAtUtcSec, utc(29, 4, 30)); // eatStart d+1
      expect(items[3].triggerAtUtcSec, utc(29, 12, 30)); // fastStart d+1
    });

    test('eatStart 携带打卡归属日（D-07 预计算值），其余类型为空', () {
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 0),
        location: bjt,
      );
      for (final item in items) {
        if (item.kind == FastingNotificationKind.eatStart) {
          expect(item.attributionDate, isNotNull);
        } else {
          expect(item.attributionDate, isNull);
        }
      }
      // d 12:00 BJT 的归属日 = 2026-07-28
      expect(items[1].attributionDate, const LocalDate(2026, 7, 28));
      expect(items[4].attributionDate, const LocalDate(2026, 7, 29));
    });

    test('通知 id 确定性且 int32 安全', () {
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 0),
        location: bjt,
      );
      final ids = items.map((e) => e.id).toSet();
      expect(ids, hasLength(items.length)); // 窗口内唯一
      for (final item in items) {
        expect(item.id, fastingNotificationId(item.triggerAtUtcSec, item.kind));
        expect(item.id, lessThan(1 << 31));
        expect(item.id, greaterThan(0));
      }
    });
  });

  group('跨午夜进食窗口（20:00–次日 12:00，§3.2 防御）', () {
    const nightPlan = FastingPlan(
      id: 'night',
      eatStartMinutes: 20 * 60,
      eatEndMinutes: 12 * 60,
    );

    test('进食结束锚点 +24h，触发点按序排列', () {
      final items = buildFastingNotificationPlan(
        plan: nightPlan,
        nowUtcSec: utc(28, 0), // d 08:00 BJT
        location: bjt,
      );
      expect(items.map((e) => (e.kind, e.triggerAtUtcSec)).toList(), [
        // d-1 的进食窗口（20:00–次日 12:00）→ 断食开始 = d 12:00 BJT
        (FastingNotificationKind.fastStart, utc(28, 4)),
        (FastingNotificationKind.eatSoon, utc(28, 11, 45)),
        (FastingNotificationKind.eatStart, utc(28, 12)),
        // d 的进食窗口 → 断食开始 = d+1 12:00 BJT
        (FastingNotificationKind.fastStart, utc(29, 4)),
        (FastingNotificationKind.eatSoon, utc(29, 11, 45)),
        (FastingNotificationKind.eatStart, utc(29, 12)),
      ]);
      // 当日进食窗口时长 16h（不压缩）
      expect(items[3].triggerAtUtcSec - items[2].triggerAtUtcSec, 16 * 3600);
    });
  });

  group('时区与夏令时（§6-B8/B11）', () {
    test('America/New_York：同一 UTC now 下锚点按新时区墙钟生成', () {
      final ny = tz.getLocation('America/New_York');
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: utc(28, 12), // d 08:00 EDT（UTC-4）
        location: ny,
      );
      // 纽约 12:00 EDT = 16:00 UTC；20:00 EDT = 次日 00:00 UTC
      expect(items[0].triggerAtUtcSec, utc(28, 15, 45)); // eatSoon
      expect(items[1].triggerAtUtcSec, utc(28, 16)); // eatStart
      expect(items[2].triggerAtUtcSec, utc(29, 0)); // fastStart
      expect(items[1].attributionDate, const LocalDate(2026, 7, 28));
    });

    test('夏令时春天拨快日：当日断食实际 15h，锚点仍按本地墙钟 12:00', () {
      final ny = tz.getLocation('America/New_York');
      // 2026-03-08 美国夏令时开始（02:00→03:00）
      final now = DateTime.utc(2026, 3, 8, 6).millisecondsSinceEpoch ~/ 1000;
      final items = buildFastingNotificationPlan(
        plan: plan,
        nowUtcSec: now, // 01:00 EST，断食中
        location: ny,
      );
      final eatStart = items.firstWhere(
        (e) => e.kind == FastingNotificationKind.eatStart,
      );
      // 12:00 EDT = 16:00 UTC；前一日 20:00 EST = 当日 01:00 UTC → 实际 15h
      expect(
        eatStart.triggerAtUtcSec,
        DateTime.utc(2026, 3, 8, 16).millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        eatStart.triggerAtUtcSec -
            (DateTime.utc(2026, 3, 8, 1).millisecondsSinceEpoch ~/ 1000),
        15 * 3600,
      );
      expect(eatStart.attributionDate, const LocalDate(2026, 3, 8));
    });
  });
}
