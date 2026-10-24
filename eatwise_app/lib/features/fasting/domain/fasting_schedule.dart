import 'package:eatwise/features/fasting/domain/fast_cycle.dart';
import 'package:eatwise/features/fasting/domain/fasting_clock.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:timezone/timezone.dart' as tz;

/// 进食窗口的 UTC 锚点，供断食与喝水通知共用。
typedef FastingEatingWindow = ({int eatStartUtc, int eatEndUtc});

/// 生成当前方案在未来周期使用、并由真实进行中断食/提前破窗覆盖的进食窗口。
///
/// [activeCycle] 未到自身 `plannedEndUtc` 且未关闭时优先于当前方案重推导；
/// [extensionMinutes] 仅为旧调用方保留，activeCycle 存在（包括已过期）时
/// 不再按静态方案猜测延长目标日。
List<FastingEatingWindow> buildEffectiveFastingEatingWindows({
  required FastingPlan plan,
  required int nowUtcSec,
  required tz.Location location,
  int extensionMinutes = 0,
  FastCycle? activeCycle,
  int? earlyEatEndUtc,
  String? lastClosedCycleId,
}) {
  final today = localDateOf(nowUtcSec, location);

  LocalDate? legacyExtensionTargetDate;
  if (activeCycle == null && extensionMinutes > 0) {
    for (
      var offset = -1;
      offset <= 2 && legacyExtensionTargetDate == null;
      offset++
    ) {
      final date = today.addDays(offset);
      if (anchorsFor(plan, date, location).eatStartUtc > nowUtcSec) {
        legacyExtensionTargetDate = date;
      }
    }
  }

  final windows = <FastingEatingWindow>[];
  for (var offset = -1; offset <= 2; offset++) {
    final date = today.addDays(offset);
    var anchors = anchorsFor(plan, date, location);
    if (date == legacyExtensionTargetDate) {
      final shiftSec = extensionMinutes * 60;
      anchors = (
        eatStartUtc: anchors.eatStartUtc + shiftSec,
        eatEndUtc: anchors.eatEndUtc + shiftSec,
      );
    }
    windows.add(anchors);
  }

  final active = activeCycle;
  if (active != null &&
      nowUtcSec < active.plannedEndUtc &&
      _stableId(active) != lastClosedCycleId) {
    windows.removeWhere(
      (window) => _overlaps(
        window,
        startUtc: active.startUtc,
        endUtc: active.eatWindowEndUtc,
      ),
    );
    windows.add((
      eatStartUtc: active.plannedEndUtc,
      eatEndUtc: active.eatWindowEndUtc,
    ));
  }

  final earlyEatEnd = earlyEatEndUtc;
  if (earlyEatEnd != null && nowUtcSec < earlyEatEnd) {
    final closedPlannedEnd = _plannedEndFromStableId(lastClosedCycleId);
    var replaceIndex = -1;
    if (closedPlannedEnd != null && earlyEatEnd > closedPlannedEnd) {
      replaceIndex = windows.indexWhere(
        (window) =>
            window.eatStartUtc == closedPlannedEnd &&
            earlyEatEnd <= window.eatEndUtc,
      );
    }
    if (replaceIndex < 0) {
      replaceIndex = windows.indexWhere(
        (window) =>
            earlyEatEnd > window.eatStartUtc && earlyEatEnd <= window.eatEndUtc,
      );
    }
    if (replaceIndex >= 0) windows.removeAt(replaceIndex);
    windows.add((eatStartUtc: nowUtcSec, eatEndUtc: earlyEatEnd));
  }

  windows.sort((a, b) {
    final byStart = a.eatStartUtc.compareTo(b.eatStartUtc);
    return byStart != 0 ? byStart : a.eatEndUtc.compareTo(b.eatEndUtc);
  });
  return windows;
}

bool _overlaps(
  FastingEatingWindow window, {
  required int startUtc,
  required int endUtc,
}) {
  return window.eatStartUtc < endUtc && window.eatEndUtc > startUtc;
}

String _stableId(FastCycle cycle) => '${cycle.startUtc}:${cycle.plannedEndUtc}';

int? _plannedEndFromStableId(String? stableId) {
  if (stableId == null) return null;
  final separator = stableId.lastIndexOf(':');
  if (separator < 0 || separator == stableId.length - 1) return null;
  return int.tryParse(stableId.substring(separator + 1));
}
