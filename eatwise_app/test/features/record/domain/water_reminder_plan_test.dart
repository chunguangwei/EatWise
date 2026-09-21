import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/record/domain/water_reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../fasting/tz_test_helper.dart';

/// 喝水提醒计划纯函数测试。
///
/// 核心口径验证：触发点完全由生效方案进食窗口派生（不写死时长）、
/// 达标当日停发（按归属日分组）、建议量随剩余量收敛并对齐 50ml 档、
/// 跨午夜窗口的次日晨段不漏、id 空间与断食（kind 0/1/2）互斥。
void main() {
  const plan168 = FastingPlan.plan16x8; // 进食 12:00–20:00
  const plan1410 = FastingPlan.plan14x10; // 进食 10:00–20:00
  // 跨午夜窗口 22:00–06:00（eatEnd ≤ eatStart 防御口径）。
  const planCrossMidnight = FastingPlan(
    id: '12:12@22',
    eatStartMinutes: 22 * 60,
    eatEndMinutes: 6 * 60,
  );
  late final tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  // 北京 = UTC+8：本地 12:00 = utc 04:00。
  int utc(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 7, day, hour, minute).millisecondsSinceEpoch ~/ 1000;

  // now = 本地 7/28 09:00（进食窗口开始前）。
  final now = utc(28, 1);

  List<PlannedWaterReminder> build({
    FastingPlan plan = plan168,
    int alreadyMl = 0,
    int goalMl = 2000,
    int nowUtcSec = 0,
  }) {
    return buildWaterReminderPlan(
      plan: plan,
      alreadyMl: alreadyMl,
      nowUtcSec: nowUtcSec == 0 ? now : nowUtcSec,
      location: bjt,
      goalMl: goalMl,
    );
  }

  group('触发点由进食窗口派生（不写死时长）', () {
    test('16:8 每天 8 个整点；14:10 每天 10 个 —— 48h 视界内计数随窗口变化', () {
      final p168 = build();
      final p1410 = build(plan: plan1410);
      // 今日 12–19 点（eatEnd 20:00 半开）+ 明日同段 = 8×2
      expect(p168, hasLength(16));
      expect(p1410, hasLength(20));
      // 触发时刻全部落在进食窗口内（本地整点）
      for (final r in p168) {
        final localHour = ((r.triggerAtUtcSec + 8 * 3600) ~/ 3600) % 24;
        expect(localHour, inInclusiveRange(12, 19));
        expect(r.triggerAtUtcSec % 3600, 0); // 整点对齐
      }
    });

    test('窗口外不触发；视界裁剪到 (now, now+48h]', () {
      final items = build();
      expect(items.first.triggerAtUtcSec, utc(28, 4)); // 今日 12:00
      expect(
        items.every((r) => r.triggerAtUtcSec > now),
        isTrue,
      ); // now 之前的整点不补发
      expect(items.every((r) => r.triggerAtUtcSec <= now + 48 * 3600), isTrue);
    });
  });

  group('达标停发（归属日分组）', () {
    test('今日已达标 → 今日全部剔除，次日重新计数不受影响', () {
      final items = build(alreadyMl: 2000);
      expect(items, hasLength(8)); // 仅剩次日 8 个
      expect(
        items.every((r) => r.triggerAtUtcSec >= utc(29, 4)),
        isTrue,
      ); // 全部 ≥ 次日 12:00
    });

    test('超额摄入同样停发（remaining ≤ 0 判定含负值）', () {
      expect(build(alreadyMl: 2500), hasLength(8));
    });
  });

  group('建议量动态分配', () {
    test('零摄入 2000ml / 8 点 → 每点 250，总量恰等于目标', () {
      final items = build();
      final today = items.where((r) => r.triggerAtUtcSec < utc(29, 4)).toList();
      expect(today.map((r) => r.suggestedMl), everyElement(equals(250)));
      expect(today.fold<int>(0, (s, r) => s + r.suggestedMl), 2000);
      // remaining 递减：首条 2000，末条 250
      expect(today.first.remainingMl, 2000);
      expect(today.last.remainingMl, 250);
    });

    test('已喝 1000 → 建议量收敛：剩余量 ÷ 剩余点数 上取整对齐 50 档', () {
      final items = build(alreadyMl: 1000);
      final today = items.where((r) => r.triggerAtUtcSec < utc(29, 4)).toList();
      // ceil(1000/8)=125→150 ×4 后剩余 400 → 100 ×4，总和恰补满缺口
      expect(today.first.suggestedMl, 150);
      expect(today.first.remainingMl, 1000);
      expect(today.last.suggestedMl, 100);
      expect(today.every((r) => r.suggestedMl % 50 == 0), isTrue); // 50ml 档对齐
      expect(today.fold<int>(0, (s, r) => s + r.suggestedMl), 1000);
      // 逐条递减：remaining 严格不升
      for (var i = 1; i < today.length; i++) {
        expect(
          today[i].remainingMl,
          lessThanOrEqualTo(today[i - 1].remainingMl),
        );
      }
    });

    test('次日按 0 起算（今日剩余缺口不背到明天）', () {
      final items = build(alreadyMl: 1800);
      final tomorrow = items
          .where((r) => r.triggerAtUtcSec >= utc(29, 4))
          .toList();
      expect(tomorrow.first.remainingMl, 2000);
    });
  });

  group('跨午夜窗口（22:00–06:00）', () {
    test('次日晨段 00:00–05:00 整点不漏，归属次日自然日', () {
      final items = build(plan: planCrossMidnight);
      final triggers = items.map((r) => r.triggerAtUtcSec).toSet();
      // d28 窗口段：22、23 点；d29 晨段：0–5 点（= utc d28 16–21）
      expect(triggers, contains(utc(28, 14))); // d28 22:00
      expect(triggers, contains(utc(28, 16))); // d29 00:00
      expect(triggers, contains(utc(28, 21))); // d29 05:00
      // 24h 视界内：d28(22,23) + d29(0..5,22,23) + d30(0..5) = 16
      expect(items, hasLength(16));
      // 归属日分组：晨段归属 d29（与 d29 晚段同日、共享建议量分配）
      final d29 = items
          .where(
            (r) =>
                r.triggerAtUtcSec >= utc(28, 16) &&
                r.triggerAtUtcSec < utc(29, 16),
          )
          .toList();
      expect(d29, hasLength(8));
      expect(
        d29.every((r) => r.attributionDate == d29.first.attributionDate),
        isTrue,
      );
    });
  });

  group('id 空间与断食互斥', () {
    test('kind=3：同触发分钟 id 末位恒 3，不与断食 0/1/2 相撞', () {
      final items = build(plan: planCrossMidnight);
      expect(
        items.every(
          (r) => r.id == waterReminderNotificationId(r.triggerAtUtcSec),
        ),
        isTrue,
      );
      expect(items.every((r) => r.id % 10 == 3), isTrue);
      expect(items.map((r) => r.id).toSet(), hasLength(items.length)); // 无重复
    });
  });

  test('输出按触发时刻升序', () {
    final items = build(plan: planCrossMidnight);
    final ts = items.map((r) => r.triggerAtUtcSec).toList();
    expect(ts, [...ts]..sort());
  });
}
