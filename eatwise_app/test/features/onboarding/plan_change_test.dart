import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../fasting/tz_test_helper.dart';

/// 换方案链路（D-06/T12/T13）controller 级单测：
/// 首启立即生效；已有生效方案且窗口不同 → 登记 pendingPlan，
/// 次日 0:00 本地生效，当日方案与锚点不动。
void main() {
  // 固定时钟：2026-07-28 15:00（Asia/Shanghai）= UTC 07:00。
  final fixedNowUtc =
      DateTime.utc(2026, 7, 28, 7).millisecondsSinceEpoch ~/ 1000;
  late tz.Location bjt;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  Future<({ProviderContainer container, OnboardingStore store})>
  buildContainer() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        onboardingGateProvider.overrideWithValue(
          OnboardingGate(completed: false),
        ),
        nowUtcProvider.overrideWithValue(fixedNowUtc),
        deviceLocationProvider.overrideWithValue(bjt),
      ],
    );
    addTearDown(container.dispose);
    return (
      container: container,
      store: SharedPreferencesOnboardingStore(prefs),
    );
  }

  test('首启：立即生效，无 pendingPlan，planVersion +1', () async {
    final (:container, :store) = await buildContainer();
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.skipQuiz(); // 兜底推荐 16:8
    expect(controller.isPlanChange, isFalse);

    final result = controller.startPrimaryPlan();
    expect(result.pendingEffectiveDate, isNull);
    expect(store.loadActivePlan()!.plan, FastingPlan.plan16x8);
    expect(store.loadPendingPlan(), isNull);
    // 方案写入信号量 +1（计时主控据此重建，修复 watch store 不触发重建）
    expect(container.read(planVersionProvider), 1);
  });

  test('换方案：登记 pendingPlan（次日 0:00 本地生效），当日方案不动', () async {
    final (:container, :store) = await buildContainer();
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.skipQuiz();
    controller.startPrimaryPlan(); // 首启 16:8

    // 升备选 14:10 为主推荐 → 构成换方案
    final rec = container.read(onboardingControllerProvider).recommendation!;
    controller.promoteAlternative(rec.alternatives.single);
    expect(controller.isPlanChange, isTrue);
    expect(controller.planChangeEffectiveDate, const LocalDate(2026, 7, 29));

    final result = controller.startPrimaryPlan();
    expect(result.pendingEffectiveDate, const LocalDate(2026, 7, 29));
    // 当日方案与锚点不动，pendingPlan 已登记
    expect(store.loadActivePlan()!.plan, FastingPlan.plan16x8);
    final pending = store.loadPendingPlan()!;
    expect(pending.plan, FastingPlan.plan14x10);
    expect(pending.effectiveDate, const LocalDate(2026, 7, 29));
    // 生效时刻 = 本地 2026-07-29 00:00 = UTC 2026-07-28 16:00
    expect(
      pending.effectiveUtc,
      DateTime.utc(2026, 7, 28, 16).millisecondsSinceEpoch ~/ 1000,
    );
    // 到期判定（domain 纯函数）：未到点不转正，到点转正
    expect(activatePendingPlan(pending, fixedNowUtc), isNull);
    expect(
      activatePendingPlan(pending, pending.effectiveUtc),
      FastingPlan.plan14x10,
    );
  });

  test('换同方案：不登记 pendingPlan，直接重写立即生效', () async {
    final (:container, :store) = await buildContainer();
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.skipQuiz();
    controller.startPrimaryPlan();

    // 主推荐仍是 16:8（与生效方案相同）→ 立即重写，不走次日生效
    expect(controller.isPlanChange, isFalse);
    final result = controller.startPrimaryPlan();
    expect(result.pendingEffectiveDate, isNull);
    expect(store.loadPendingPlan(), isNull);
    expect(store.loadActivePlan()!.plan, FastingPlan.plan16x8);
  });
}
