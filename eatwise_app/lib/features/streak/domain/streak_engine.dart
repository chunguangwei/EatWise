import 'package:eatwise/features/streak/domain/streak_types.dart';

/// 结算结果（MIDNIGHT_SETTLEMENT 副作用，§2.3 T3/T4/T7）。
final class SettlementResult {
  const SettlementResult({
    this.newlyMissed = const [],
    this.newlyBroken = const [],
  });

  /// 本次结算新判定的断签日（进入「断签待处理」，需弹断签弹窗）。
  final List<String> newlyMissed;

  /// 本次结算因超出 7 天窗口而关闭的断签日（PENDING_MEND → BROKEN）。
  final List<String> newlyBroken;
}

/// 补签卡使用结果（T6）。
final class MendResult {
  const MendResult({
    required this.restoredStreak,
    required this.cardsLeft,
    required this.newMilestones,
  });

  /// 补签后重算的当前连胜（§2.5：gap 闭合时 = 断签前 S + 1 + k）。
  final int restoredStreak;

  /// 当月剩余补签卡。
  final int cardsLeft;

  /// 本次补签跨越而首次解锁的里程碑（含补签日计入，§2.5〔假设〕）。
  final List<int> newMilestones;
}

/// 补签被拒绝的原因（UI 提示用）。
enum MendRejectReason {
  /// 断签日超出 7 天补签窗口。
  outOfWindow,

  /// 当日库存为 0（本月已用完）。
  noCardsLeft,

  /// 该日已达标或已补签（同一断签日只能补 1 次）。
  alreadyQualified,

  /// 该日不是断签日（无断签记录）。
  notMissed,
}

/// streak 本地推演引擎（《规格-M5》第二章状态机 + 第三章补签卡账本）。
///
/// 定位：服务端 S1 为权威；本引擎用于离线推演与即时反馈（§2.4 冲突原则：
/// 本地先算先展示，拉到服务端结果后覆盖）。归属日全部 `yyyy-MM-dd`
/// 本地自然日字符串（D-07），可比较、可经 [diffIsoDays] 做日期算术。
///
/// 重算规则（§2.5）：streak 由「达标日集合（含已补签日）」推导——
/// 当前连胜 = 以今天/昨天收尾的最长连续段；补签日加入集合后 gap 闭合，
/// 公式 S + 1 + k 由链式重算自然得出，无需特判。
final class StreakEngine {
  StreakEngine();

  /// 达标日集合（含已补签日，§6.3 dayStatus ∈ {ACHIEVED, MENDED}）。
  final Set<String> qualifiedDates = <String>{};

  /// 7 天窗口内的未补签断签日（§6.1 pendingMendDates；支持多日 gap）。
  final Set<String> pendingMendDates = <String>{};

  /// 已超出补签窗口的断签日（BROKEN 依据；不再自动弹断签弹窗）。
  final Set<String> brokenDates = <String>{};

  /// 已结算到的自然日（含；启动补结算从次日继续）。
  String? lastSettledDate;

  /// 当月补签卡库存（0–2）。
  int mendCardBalance = kMendCardMonthlyGrant;

  /// 当前库存所属月份 `yyyy-MM`（月初重置判定）。
  String mendCardMonth = '';

  /// 本月已用张数（≤2）。
  int mendCardUsedThisMonth = 0;

  /// 已补签的断签日（同一断签日只能补 1 次）。
  final Set<String> mendedDates = <String>{};

  /// 已永久解锁的里程碑档位（§5.1：每档只解锁一次）。
  final Set<int> unlockedMilestones = <int>{};

  /// 历史最长连胜（只增不减）。
  int longestStreak = 0;

  // ---------------------------------------------------------------- 查询

  /// 当前连胜：以今天或昨天收尾的最长连续达标段。
  /// （今天已达标 → 含今天；否则看昨天收尾的段——今天进行中尚未结算。）
  int currentStreak(String today) {
    final yesterday = addDaysToIsoDate(today, -1);
    final end = qualifiedDates.contains(today)
        ? today
        : qualifiedDates.contains(yesterday)
        ? yesterday
        : null;
    if (end == null) return 0;
    var count = 1;
    var cursor = end;
    while (qualifiedDates.contains(addDaysToIsoDate(cursor, -1))) {
      cursor = addDaysToIsoDate(cursor, -1);
      count++;
    }
    return count;
  }

  /// 状态推导（§2.1/§2.3）。
  StreakStatus status(String today) {
    if (currentStreak(today) > 0) return StreakStatus.inStreak;
    if (pendingMendDates.any((d) => _withinMendWindow(d, today))) {
      return StreakStatus.pendingMend;
    }
    if (brokenDates.isNotEmpty) return StreakStatus.broken;
    return StreakStatus.noStreak;
  }

  /// 补签卡三态（§3.2 伪代码，按序求值命中即止）。
  MendCardVisualState mendCardVisualState(String today) {
    _ensureMonth(today);
    final hasMendable = pendingMendDates.any(
      (d) => _withinMendWindow(d, today),
    );
    if (!hasMendable) return MendCardVisualState.unmendable;
    return mendCardBalance >= 1
        ? MendCardVisualState.mendable
        : MendCardVisualState.exhausted;
  }

  /// 断签日 D 的可补窗口：[D, D+6]（today - D ≤ 6，§3.1）。
  bool _withinMendWindow(String missedDate, String today) {
    final diff = diffIsoDays(today, missedDate);
    return diff >= 0 && diff <= kMendWindowDays;
  }

  /// 补签预览：假设 [date] 补签成功后的当前连胜（弹窗 CTA「恢复 N 天连胜」）。
  /// 不改变引擎状态。
  int previewMendRestore(String date, {required String today}) {
    final saved = qualifiedDates.contains(date);
    qualifiedDates.add(date);
    final restored = currentStreak(today);
    if (!saved) qualifiedDates.remove(date);
    return restored;
  }

  // ---------------------------------------------------------------- 事件

  /// DAY_ACHIEVED（T1/T2/T8/T9）。幂等：同一归属日重复到达不重复 +1。
  ///
  /// 返回本次首次解锁的里程碑档位（无则空表）。
  List<int> applyDayAchieved(String date, {required String today}) {
    _ensureMonth(today);
    if (!qualifiedDates.add(date)) return const <int>[]; // 幂等去重
    return _recomputeLongestAndMilestones(today);
  }

  /// DAY_MISSED（T10）：仅记录断签日（当日进行中破窗 >15 分钟），
  /// 不归零——真正归零发生在次日 0 点结算后的状态推导。
  void applyDayMissed(String date) {
    if (qualifiedDates.contains(date)) return;
    if (brokenDates.contains(date)) return;
    pendingMendDates.add(date);
  }

  /// MIDNIGHT_SETTLEMENT（T3/T4/T5/T7）：对 (lastSettledDate, today-1]
  /// 区间逐日补结算——App 启动时调用即覆盖多日未启动的补结算（§2.4）。
  ///
  /// 判定：区间内无达标记录且用户已有 streak 历史 → 断签（T3/T4）；
  /// 从未有 streak（未启动方案）不产生断签（T5〔假设〕：以「曾有任何
  /// 达标日」近似 streak 历史）。窗口外断签日转入 BROKEN（T7）。
  SettlementResult settleUpTo(String today) {
    _ensureMonth(today);
    final newlyMissed = <String>[];
    final newlyBroken = <String>[];

    final yesterday = addDaysToIsoDate(today, -1);
    // 首次结算不回溯历史（无基线），仅从昨天开始。
    var cursor = lastSettledDate == null
        ? yesterday
        : addDaysToIsoDate(lastSettledDate!, 1);
    while (diffIsoDays(cursor, yesterday) <= 0) {
      if (!qualifiedDates.contains(cursor) &&
          !pendingMendDates.contains(cursor) &&
          !brokenDates.contains(cursor)) {
        final hasStreakHistory =
            qualifiedDates.any((d) => diffIsoDays(d, cursor) < 0) ||
            pendingMendDates.any((d) => diffIsoDays(d, cursor) < 0);
        if (hasStreakHistory) {
          pendingMendDates.add(cursor);
          newlyMissed.add(cursor);
        }
      }
      cursor = addDaysToIsoDate(cursor, 1);
    }
    lastSettledDate = yesterday;

    // T7：窗口关闭（today - D > 6）→ BROKEN，清除补签入口。
    for (final d in pendingMendDates.toList()) {
      if (!_withinMendWindow(d, today)) {
        pendingMendDates.remove(d);
        brokenDates.add(d);
        newlyBroken.add(d);
      }
    }
    return SettlementResult(newlyMissed: newlyMissed, newlyBroken: newlyBroken);
  }

  /// USE_MEND_CARD（T6）：库存 ≥1 且断签日在 7 天窗口内 → 补签恢复。
  ///
  /// 校验失败抛出 [MendRejected]；成功副作用：库存 −1、断签日记 MENDED、
  /// streak 按 §2.5 链式重算（gap 未全闭合时从最近连续段重算，QA #14）。
  MendResult useMendCard(String date, {required String today}) {
    _ensureMonth(today);
    if (qualifiedDates.contains(date) || mendedDates.contains(date)) {
      throw const MendRejected(MendRejectReason.alreadyQualified);
    }
    if (!pendingMendDates.contains(date) && !brokenDates.contains(date)) {
      throw const MendRejected(MendRejectReason.notMissed);
    }
    if (!_withinMendWindow(date, today)) {
      throw const MendRejected(MendRejectReason.outOfWindow);
    }
    if (mendCardBalance < 1 ||
        mendCardUsedThisMonth >= kMendCardMonthlyUseCap) {
      throw const MendRejected(MendRejectReason.noCardsLeft);
    }

    mendCardBalance -= 1;
    mendCardUsedThisMonth += 1;
    mendedDates.add(date);
    pendingMendDates.remove(date);
    brokenDates.remove(date);
    qualifiedDates.add(date); // 补签日视同达标日（D-12）

    final milestones = _recomputeLongestAndMilestones(today);
    return MendResult(
      restoredStreak: currentStreak(today),
      cardsLeft: mendCardBalance,
      newMilestones: milestones,
    );
  }

  /// 月初重置（§3.1：进入新月 → 清零重发 2 张，上限 2，不累积）。
  /// 返回是否发生了重置（用于 `mend_card_granted` / `mend_cards_expired` 埋点）。
  bool _ensureMonth(String today) {
    final month = monthOf(today);
    if (mendCardMonth == month) return false;
    final hadMonth = mendCardMonth.isNotEmpty;
    mendCardMonth = month;
    mendCardBalance = kMendCardMonthlyGrant.clamp(0, kMendCardStockCap);
    mendCardUsedThisMonth = 0;
    mendedDates.clear();
    return hadMonth;
  }

  /// 月初重置（注册/首用初始化）：显式入口，供服务端对账后对齐月份。
  void alignMendCards({
    required String month,
    required int balance,
    required int used,
  }) {
    mendCardMonth = month;
    mendCardBalance = balance.clamp(0, kMendCardStockCap);
    mendCardUsedThisMonth = used;
  }

  /// 全量重算历史最长 + 里程碑首次解锁（§5.1：每档永久解锁一次，
  /// 再次达到不重复解锁；返回本次新解锁档位供轻量庆祝）。
  List<int> _recomputeLongestAndMilestones(String today) {
    final sorted = qualifiedDates.toList()..sort();
    var run = 0;
    String? prev;
    for (final d in sorted) {
      run = prev != null && diffIsoDays(d, prev) == 1 ? run + 1 : 1;
      if (run > longestStreak) longestStreak = run;
      prev = d;
    }
    final current = currentStreak(today);
    final unlocked = <int>[];
    for (final m in kStreakMilestones) {
      if (current >= m && unlockedMilestones.add(m)) unlocked.add(m);
    }
    return unlocked;
  }

  /// 服务端对账覆盖（§2.4 冲突原则：服务端权威，本地推演让位）。
  void applyServerSnapshot({
    required int longestStreakOverride,
    required Set<String> serverQualifiedDates,
  }) {
    qualifiedDates
      ..clear()
      ..addAll(serverQualifiedDates);
    if (longestStreakOverride > longestStreak) {
      longestStreak = longestStreakOverride;
    }
  }

  // ---------------------------------------------------------------- 序列化

  Map<String, dynamic> toJson() => <String, dynamic>{
    'qualifiedDates': qualifiedDates.toList()..sort(),
    'pendingMendDates': pendingMendDates.toList()..sort(),
    'brokenDates': brokenDates.toList()..sort(),
    'lastSettledDate': lastSettledDate,
    'mendCardBalance': mendCardBalance,
    'mendCardMonth': mendCardMonth,
    'mendCardUsedThisMonth': mendCardUsedThisMonth,
    'mendedDates': mendedDates.toList()..sort(),
    'unlockedMilestones': unlockedMilestones.toList()..sort(),
    'longestStreak': longestStreak,
  };

  static StreakEngine fromJson(Map<String, dynamic> json) {
    final engine = StreakEngine();
    engine.qualifiedDates.addAll(
      (json['qualifiedDates'] as List<dynamic>? ?? const []).cast<String>(),
    );
    engine.pendingMendDates.addAll(
      (json['pendingMendDates'] as List<dynamic>? ?? const []).cast<String>(),
    );
    engine.brokenDates.addAll(
      (json['brokenDates'] as List<dynamic>? ?? const []).cast<String>(),
    );
    engine.lastSettledDate = json['lastSettledDate'] as String?;
    engine.mendCardBalance =
        (json['mendCardBalance'] as num?)?.toInt() ?? kMendCardMonthlyGrant;
    engine.mendCardMonth = json['mendCardMonth'] as String? ?? '';
    engine.mendCardUsedThisMonth =
        (json['mendCardUsedThisMonth'] as num?)?.toInt() ?? 0;
    engine.mendedDates.addAll(
      (json['mendedDates'] as List<dynamic>? ?? const []).cast<String>(),
    );
    engine.unlockedMilestones.addAll(
      (json['unlockedMilestones'] as List<dynamic>? ?? const []).map(
        (e) => (e as num).toInt(),
      ),
    );
    engine.longestStreak = (json['longestStreak'] as num?)?.toInt() ?? 0;
    return engine;
  }
}

/// 补签被拒绝（T6 校验失败）。
final class MendRejected implements Exception {
  const MendRejected(this.reason);

  final MendRejectReason reason;

  @override
  String toString() => 'MendRejected($reason)';
}
