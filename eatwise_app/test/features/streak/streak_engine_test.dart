import 'package:eatwise/features/streak/domain/streak_engine.dart';
import 'package:eatwise/features/streak/domain/streak_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// streak 状态机 + 补签卡账本 + 里程碑（《规格-M5》第二/三/五章 + QA 用例 #1–#15、#18/#19）。
void main() {
  const today = '2026-07-28';

  StreakEngine engineWith(List<String> achieved) {
    final engine = StreakEngine();
    engine.mendCardMonth = monthOf(today);
    for (final d in achieved) {
      engine.applyDayAchieved(d, today: today);
    }
    return engine;
  }

  /// 逐日推进结算到 [today]（首日无基线时仅从昨天起结算，与引擎语义一致）。
  void settleDayByDay(StreakEngine engine, String from, String to) {
    var cursor = from;
    while (diffIsoDays(cursor, to) <= 0) {
      engine.settleUpTo(cursor);
      cursor = addDaysToIsoDate(cursor, 1);
    }
  }

  group('状态机迁移（§2.3 T1–T10）', () {
    test('T1 无连胜 + 当日达标 → 连胜中，currentStreak=1', () {
      final engine = StreakEngine();
      expect(engine.status(today), StreakStatus.noStreak);
      engine.applyDayAchieved(today, today: today);
      expect(engine.status(today), StreakStatus.inStreak);
      expect(engine.currentStreak(today), 1);
    });

    test('T2 连胜中 + 次日达标 → +1 并刷新最长连胜', () {
      final engine = engineWith(['2026-07-26', '2026-07-27']);
      engine.applyDayAchieved(today, today: today);
      expect(engine.currentStreak(today), 3);
      expect(engine.longestStreak, 3);
    });

    test('T3 连胜中 + 跨天结算前一日未达标 → 归零 + 断签待处理', () {
      final engine = engineWith(['2026-07-25', '2026-07-26']);
      // 07-27 无记录；今天 07-28 结算。
      final result = engine.settleUpTo(today);
      expect(result.newlyMissed, ['2026-07-27']);
      expect(engine.currentStreak(today), 0);
      expect(engine.status(today), StreakStatus.pendingMend);
      expect(engine.pendingMendDates, contains('2026-07-27'));
    });

    test('T5 从未有 streak 的用户断签不产生断签待处理、不弹窗', () {
      final engine = StreakEngine();
      final result = engine.settleUpTo(today);
      expect(result.newlyMissed, isEmpty);
      expect(engine.status(today), StreakStatus.noStreak);
    });

    test('T7 断签日超出 7 天窗口 → 窗口关闭不可再补（转入 brokenDates）', () {
      final engine = engineWith(['2026-07-18', '2026-07-19']);
      engine.settleUpTo('2026-07-21'); // 07-20 断签
      expect(engine.status('2026-07-21'), StreakStatus.pendingMend);
      // 推进到 07-28：07-20/07-21 超窗关闭；期间逐日断签仍在各自窗口内
      // （最近断签日恒可补，BROKEN 仅在无窗口内断签日时出现，见 T9 构造）。
      final result = engine.settleUpTo(today);
      expect(result.newlyBroken, contains('2026-07-20'));
      expect(engine.brokenDates, contains('2026-07-20'));
      expect(
        () => engine.useMendCard('2026-07-20', today: today),
        throwsA(
          isA<MendRejected>().having(
            (e) => e.reason,
            'reason',
            MendRejectReason.outOfWindow,
          ),
        ),
      );
    });

    test('T8 断签待处理 + 新一天达标 → 从新日起算 = 1，旧断签仍可补', () {
      final engine = engineWith(['2026-07-25', '2026-07-26']);
      engine.settleUpTo(today); // 07-27 断签
      engine.applyDayAchieved(today, today: today);
      expect(engine.status(today), StreakStatus.inStreak);
      expect(engine.currentStreak(today), 1);
      expect(engine.pendingMendDates, contains('2026-07-27'));
    });

    test('T9 已断签 + 当日达标 → 开启新一段连胜 = 1', () {
      // 经序列化播种 BROKEN 态（窗口内无断签日、存在超窗断签日）。
      final engine = StreakEngine.fromJson(<String, dynamic>{
        'qualifiedDates': ['2026-07-15'],
        'brokenDates': ['2026-07-16'],
        'mendCardMonth': '2026-07',
      });
      expect(engine.status(today), StreakStatus.broken);
      engine.applyDayAchieved(today, today: today);
      expect(engine.currentStreak(today), 1);
      expect(engine.status(today), StreakStatus.inStreak);
    });

    test('T10 当日进行中破窗仅记录，归零发生在次日结算', () {
      final engine = engineWith(['2026-07-26', '2026-07-27']);
      engine.applyDayMissed(today); // 当日破窗 >15 分钟
      expect(engine.currentStreak(today), 2); // 当日不归零
      final tomorrow = addDaysToIsoDate(today, 1);
      engine.settleUpTo(tomorrow);
      expect(engine.currentStreak(tomorrow), 0);
    });

    test('幂等：同一归属日重复达标不重复 +1', () {
      final engine = StreakEngine();
      engine.applyDayAchieved(today, today: today);
      engine.applyDayAchieved(today, today: today);
      expect(engine.currentStreak(today), 1);
    });

    test('启动补结算：连续多日未启动，逐日补齐断签判定', () {
      final engine = engineWith(['2026-07-22']);
      // 上次结算到 07-23（首日无基线只结算昨天）；今天 07-28 启动补结算。
      final first = engine.settleUpTo('2026-07-24');
      expect(first.newlyMissed, ['2026-07-23']);
      final result = engine.settleUpTo(today);
      expect(result.newlyMissed, [
        '2026-07-24',
        '2026-07-25',
        '2026-07-26',
        '2026-07-27',
      ]);
      expect(engine.pendingMendDates.length, 5);
    });
  });

  group('补签卡规则（§3 + QA #10–#15）', () {
    test('月初重置：上月剩 2 张未用 → 本月 1 日库存 = 2（不累积，QA #10）', () {
      final engine = StreakEngine();
      engine.mendCardMonth = '2026-04';
      engine.mendCardBalance = 2;
      engine.settleUpTo('2026-05-01'); // 进入新月触发重置
      expect(engine.mendCardMonth, '2026-05');
      expect(engine.mendCardBalance, 2);
      expect(engine.mendCardUsedThisMonth, 0);
    });

    test('库存上限 2：任何途径不突破上限', () {
      final engine = StreakEngine();
      engine.alignMendCards(month: '2026-07', balance: 5, used: 0);
      expect(engine.mendCardBalance, 2);
    });

    test('7 天窗口边界：D+6 可补，D+7 不可补（QA #11）', () {
      final engine = engineWith(['2026-07-20']);
      engine.settleUpTo('2026-07-22'); // 07-21 断签
      engine.settleUpTo('2026-07-23'); // 07-22 断签
      // 07-22 断签：07-28 = D+6 → 可补
      final result = engine.useMendCard('2026-07-22', today: today);
      expect(result.cardsLeft, 1);
      // 07-21 断签：07-28 = D+7 → 不可补
      expect(
        () => engine.useMendCard('2026-07-21', today: today),
        throwsA(
          isA<MendRejected>().having(
            (e) => e.reason,
            'reason',
            MendRejectReason.outOfWindow,
          ),
        ),
      );
    });

    test('每月最多 2 张：第 3 张被拒绝（QA #15）', () {
      final engine = engineWith(['2026-07-20']);
      settleDayByDay(engine, '2026-07-22', '2026-07-26'); // 07-21..07-25 断签
      engine.useMendCard('2026-07-24', today: '2026-07-26');
      engine.useMendCard('2026-07-25', today: '2026-07-26');
      expect(
        () => engine.useMendCard('2026-07-23', today: '2026-07-26'),
        throwsA(
          isA<MendRejected>().having(
            (e) => e.reason,
            'reason',
            MendRejectReason.noCardsLeft,
          ),
        ),
      );
    });

    test('同一断签日只能补 1 次；已达标日不可补（QA #13）', () {
      final engine = engineWith(['2026-07-26']);
      engine.settleUpTo(today); // 07-27 断签
      engine.useMendCard('2026-07-27', today: today);
      expect(
        () => engine.useMendCard('2026-07-27', today: today),
        throwsA(isA<MendRejected>()),
      );
      expect(
        () => engine.useMendCard('2026-07-26', today: today),
        throwsA(isA<MendRejected>()),
      );
    });

    test('补签恢复 streak：S + 1 + k（gap 闭合，§2.5 / QA #13）', () {
      // 断签前 S=2（25/26），27 断签，28 新达标（k=1）→ 补 27 → 2+1+1=4
      final engine = engineWith(['2026-07-25', '2026-07-26', today]);
      engine.settleUpTo(today);
      final result = engine.useMendCard('2026-07-27', today: today);
      expect(result.restoredStreak, 4);
      expect(engine.currentStreak(today), 4);
      expect(engine.longestStreak, 4);
      expect(engine.status(today), StreakStatus.inStreak);
    });

    test('多日 gap：2 张卡全补 2 断签日 → 恢复连续；gap 3 天补 2 → 最近段重算（QA #14）', () {
      // gap 恰 2 天且全补 → 闭合恢复原 streak
      final e2 = engineWith(['2026-07-25', today]);
      settleDayByDay(e2, '2026-07-27', today); // 07-26/27 断签
      e2.useMendCard('2026-07-26', today: today);
      e2.useMendCard('2026-07-27', today: today);
      expect(e2.currentStreak(today), 4); // 25+26+27+28 连续

      // gap 4 天只能补 2 → 不恢复原值，从最近连续段重算
      final e1 = engineWith(['2026-07-23', today]);
      settleDayByDay(e1, '2026-07-25', today); // 07-24..07-27 断签
      e1.useMendCard('2026-07-26', today: today);
      e1.useMendCard('2026-07-27', today: today);
      expect(e1.currentStreak(today), 3); // 26(m)+27(m)+28
    });

    test('三态判定：可补签 / 已用尽 / 已断签（QA #12）', () {
      final engine = engineWith(['2026-07-25']);
      settleDayByDay(engine, '2026-07-27', today); // 07-26/27 断签，库存 2
      expect(engine.mendCardVisualState(today), MendCardVisualState.mendable);
      engine.useMendCard('2026-07-26', today: today);
      engine.useMendCard('2026-07-27', today: today);
      expect(engine.mendCardBalance, 0);

      // 用完后仍存在窗口内断签日 → 已用尽
      final engine2 = engineWith(['2026-07-25']);
      settleDayByDay(engine2, '2026-07-27', today);
      engine2.mendCardBalance = 0;
      expect(engine2.mendCardVisualState(today), MendCardVisualState.exhausted);

      // 无窗口内断签日（超窗已关闭）→ 已断签
      final engine3 = StreakEngine.fromJson(<String, dynamic>{
        'qualifiedDates': ['2026-07-18'],
        'brokenDates': ['2026-07-19'],
        'mendCardMonth': '2026-07',
      });
      expect(
        engine3.mendCardVisualState(today),
        MendCardVisualState.unmendable,
      );
    });
  });

  group('里程碑（§5.1 + QA #18/#19）', () {
    test('首次达 3 解锁一次；断签后重新达档不重复解锁（QA #18）', () {
      final engine = StreakEngine();
      expect(engine.applyDayAchieved('2026-07-26', today: today), isEmpty);
      engine.applyDayAchieved('2026-07-27', today: today);
      expect(engine.applyDayAchieved(today, today: today), [3]);
      // 断签后重新达 3 → 不重复解锁
      engine.settleUpTo('2026-07-30'); // 07-29 断签
      final mRe = <int>[
        ...engine.applyDayAchieved('2026-07-30', today: '2026-07-30'),
        ...engine.applyDayAchieved('2026-07-31', today: '2026-07-31'),
        ...engine.applyDayAchieved('2026-08-01', today: '2026-08-01'),
      ];
      expect(mRe, isEmpty);
      expect(engine.unlockedMilestones, [3]);
    });

    test('补签跨越里程碑：2 天 + 补 1 天 = 3 天触发（QA #19）', () {
      final engine = engineWith(['2026-07-25', '2026-07-26']);
      engine.settleUpTo(today); // 07-27 断签 → 连胜归零
      final result = engine.useMendCard('2026-07-27', today: today);
      expect(result.restoredStreak, 3);
      expect(result.newMilestones, [3]);
    });

    test('30 天里程碑解锁', () {
      final engine = StreakEngine();
      var unlocked = <int>[];
      for (var i = 29; i >= 0; i--) {
        unlocked = engine.applyDayAchieved(
          addDaysToIsoDate(today, -i),
          today: today,
        );
      }
      expect(unlocked, [30]);
      expect(engine.currentStreak(today), 30);
      expect(engine.longestStreak, 30);
    });
  });

  group('显示边界（四态规范）', () {
    test('streak=0 → 空串（首页不显示火焰）；>999 → 999+', () {
      expect(formatStreakCount(0), '');
      expect(formatStreakCount(-1), '');
      expect(formatStreakCount(7), '7');
      expect(formatStreakCount(999), '999');
      expect(formatStreakCount(1000), '999+');
      expect(formatStreakCount(12345), '999+');
    });
  });

  group('序列化往返（离线推演快照持久化）', () {
    test('toJson/fromJson 保持全部状态', () {
      final engine = engineWith(['2026-07-26']);
      engine.settleUpTo(today); // 07-27 断签
      engine.useMendCard('2026-07-27', today: today);
      final restored = StreakEngine.fromJson(engine.toJson());
      expect(restored.qualifiedDates, engine.qualifiedDates);
      expect(restored.mendedDates, engine.mendedDates);
      expect(restored.longestStreak, engine.longestStreak);
      expect(restored.mendCardBalance, engine.mendCardBalance);
      expect(restored.unlockedMilestones, engine.unlockedMilestones);
      expect(restored.lastSettledDate, engine.lastSettledDate);
    });
  });
}
