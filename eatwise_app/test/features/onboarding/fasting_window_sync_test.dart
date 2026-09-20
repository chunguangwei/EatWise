import 'dart:convert';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:eatwise/features/fasting/domain/window_rules.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/application/onboarding_gate.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:eatwise/features/onboarding/domain/plan_recommendation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../fasting/tz_test_helper.dart';

/// 记录 PUT 调用并可控失败的假 API。
class _FakeApi implements FastingPlanApi {
  _FakeApi({this.fail = false});

  final bool fail;
  final List<FastingPlan> puts = <FastingPlan>[];

  @override
  Future<void> putCurrent(FastingPlan plan) async {
    puts.add(plan);
    if (fail) throw const NetworkApiException();
  }
}

/// 方案上行同步（FastingPlanSync）单测 + `startPrimaryPlan(window:)`
/// 自定义窗口接线（controller 级）：脏标记、flush 迁移/清脏、
/// 失败保留、首启/换方案两条路径的落盘口径。
void main() {
  final fixedNowUtc =
      DateTime.utc(2026, 7, 28, 7).millisecondsSinceEpoch ~/ 1000;
  late tz.Location bjt;
  late SharedPreferences prefs;

  setUpAll(() async {
    await initTestTimeZones();
    bjt = tz.getLocation('Asia/Shanghai');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  FastingPlanSync buildSync(_FakeApi api, {String uid = 'u1'}) =>
      FastingPlanSync(api: api, prefs: prefs, userId: () => uid);

  const dirtyKey = 'fasting_plan_dirty_u1';
  const anonDirtyKey = 'fasting_plan_dirty_anonymous';
  final plan10 = buildWindow(eatingHours: 10, startMinutes: 540);

  group('FastingPlanSync', () {
    test('flush：登录态有脏 → PUT 成功后清脏', () async {
      final api = _FakeApi();
      final sync = buildSync(api);
      await prefs.setString(
        dirtyKey,
        jsonEncode(<String, Object?>{
          'planId': plan10.planId,
          'eatStartMinutes': 540,
          'eatEndMinutes': 1140,
        }),
      );
      await sync.flush();
      expect(api.puts.single, plan10.toFastingPlan());
      expect(prefs.getString(dirtyKey), isNull);
    });

    test('flush：PUT 失败保留脏标记（同步轮重试）', () async {
      final api = _FakeApi(fail: true);
      final sync = buildSync(api);
      await prefs.setString(
        dirtyKey,
        jsonEncode(<String, Object?>{
          'planId': plan10.planId,
          'eatStartMinutes': 540,
          'eatEndMinutes': 1140,
        }),
      );
      await expectLater(sync.flush(), throwsA(isA<ApiException>()));
      expect(prefs.getString(dirtyKey), isNotNull);
    });

    test('flush：未登录 no-op；匿名脏在登录后迁移上行', () async {
      final api = _FakeApi();
      var uid = 'anonymous';
      final sync = FastingPlanSync(api: api, prefs: prefs, userId: () => uid);
      await prefs.setString(
        anonDirtyKey,
        jsonEncode(<String, Object?>{
          'planId': plan10.planId,
          'eatStartMinutes': 540,
          'eatEndMinutes': 1140,
        }),
      );
      await sync.flush();
      expect(api.puts, isEmpty); // 匿名不上行，脏保留
      expect(prefs.getString(anonDirtyKey), isNotNull);

      uid = 'u1';
      await sync.flush();
      expect(api.puts.single, plan10.toFastingPlan());
      expect(prefs.getString(dirtyKey), isNull);
      expect(prefs.getString(anonDirtyKey), isNull); // 迁移后删除
    });

    test('flush：无脏 / 脏数据损坏均安全 no-op（损坏清键）', () async {
      final api = _FakeApi();
      final sync = buildSync(api);
      await sync.flush();
      expect(api.puts, isEmpty);

      await prefs.setString(dirtyKey, 'not-json');
      await sync.flush();
      expect(api.puts, isEmpty);
      expect(prefs.getString(dirtyKey), isNull);
    });

    test('markDirtyAndTryFlush：写脏后即时上行成功则清脏', () async {
      final api = _FakeApi();
      final sync = buildSync(api);
      sync.markDirtyAndTryFlush(plan10.toFastingPlan());
      await Future<void>.delayed(Duration.zero);
      expect(api.puts.single, plan10.toFastingPlan());
      expect(prefs.getString(dirtyKey), isNull);
    });

    test('markDirtyAndTryFlush：上行失败静默且脏保留', () async {
      final api = _FakeApi(fail: true);
      final sync = buildSync(api);
      sync.markDirtyAndTryFlush(plan10.toFastingPlan());
      await Future<void>.delayed(Duration.zero);
      expect(api.puts.single, plan10.toFastingPlan());
      expect(prefs.getString(dirtyKey), isNotNull);
    });
  });

  group('startPrimaryPlan(window:) 接线', () {
    Future<({ProviderContainer container, OnboardingStore store})>
    buildContainer({List<Override> extra = const <Override>[]}) async {
      final container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          onboardingGateProvider.overrideWithValue(
            OnboardingGate(completed: false),
          ),
          nowUtcProvider.overrideWithValue(fixedNowUtc),
          deviceLocationProvider.overrideWithValue(bjt),
          ...extra,
        ],
      );
      addTearDown(container.dispose);
      return (
        container: container,
        store: SharedPreferencesOnboardingStore(prefs),
      );
    }

    test(
      'provider 未 override 时 startPrimaryPlan 不受上行影响（测试环境 null 兜底）',
      () async {
        final (:container, :store) = await buildContainer();
        final controller = container.read(
          onboardingControllerProvider.notifier,
        );
        controller.skipQuiz();
        final result = controller.startPrimaryPlan(
          window: buildWindow(eatingHours: 10, startMinutes: 540),
        );
        expect(result.pendingEffectiveDate, isNull);
        final plan = store.loadActivePlan()!.plan;
        expect(plan.id, '14:10@09:00');
        expect(plan.eatStartMinutes, 540);
        expect(plan.eatEndMinutes, 1140);
        // 匿名 + provider 兜底：脏键落 anonymous，不炸。
        await Future<void>.delayed(Duration.zero);
        expect(
          prefs.getString('fasting_plan_dirty_anonymous'),
          contains('14:10@09:00'),
        );
      },
    );

    test('装配同步器：启动即置脏并上行自定义窗口方案', () async {
      final api = _FakeApi();
      final (:container, :store) = await buildContainer(
        extra: <Override>[
          fastingPlanSyncProvider.overrideWithValue(
            FastingPlanSync(api: api, prefs: prefs, userId: () => 'u1'),
          ),
        ],
      );
      final controller = container.read(onboardingControllerProvider.notifier);
      controller.skipQuiz();
      controller.startPrimaryPlan(
        window: buildWindow(eatingHours: 6, startMinutes: 720),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        api.puts.single,
        FastingPlan(
          id: '18:6@12:00',
          eatStartMinutes: 720,
          eatEndMinutes: 1080,
        ),
      );
      expect(store.loadActivePlan()!.plan.id, '18:6@12:00');
      expect(prefs.getString(dirtyKey), isNull); // 上行成功已清脏
    });

    test('窗口等价判换方案：同窗口自定义 id 视为同方案立即重写（D-06）', () async {
      final (:container, :store) = await buildContainer();
      final controller = container.read(onboardingControllerProvider.notifier);
      controller.skipQuiz(); // 兜底 16:8 12:00–20:00
      controller.startPrimaryPlan();

      // 自定义 8h@12:00 → 窗口与生效方案等价 → 不算换方案，直接重写。
      final same = buildWindow(eatingHours: 8, startMinutes: 720);
      expect(controller.isPlanChangeAgainst(same.toFastingPlan()), isFalse);
      final r1 = controller.startPrimaryPlan(window: same);
      expect(r1.pendingEffectiveDate, isNull);
      expect(store.loadPendingPlan(), isNull);
      expect(store.loadActivePlan()!.plan.id, '16:8@12:00');

      // 自定义 8h@09:00 → 窗口不同 → pending 次日生效。
      final other = buildWindow(eatingHours: 8, startMinutes: 540);
      expect(controller.isPlanChangeAgainst(other.toFastingPlan()), isTrue);
      final r2 = controller.startPrimaryPlan(window: other);
      expect(r2.pendingEffectiveDate, const LocalDate(2026, 7, 29));
      expect(store.loadPendingPlan()!.plan.id, '16:8@09:00');
      // 当日生效方案不动
      expect(store.loadActivePlan()!.plan.id, '16:8@12:00');
    });
  });

  group('recommendedStartMinutes', () {
    test('各时长推荐起点（D-03 默认窗口）', () {
      expect(recommendedStartMinutes(10), 600); // 14:10 → 10:00
      expect(recommendedStartMinutes(8), 720); // 16:8 → 12:00
      expect(recommendedStartMinutes(6), 720); // 18:6 → 12:00
      expect(() => recommendedStartMinutes(7), throwsArgumentError);
    });
  });
}
