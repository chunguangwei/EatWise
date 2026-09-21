import 'dart:convert';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_sync.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
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

/// 记录 PUT/GET/extend 调用并可控失败的假 API。
class _FakeApi implements FastingPlanApi {
  _FakeApi({this.fail = false, this.current});

  final bool fail;

  /// [FastingPlanApi.fetchCurrent] 的返回值（null = 无方案可回填）。
  final FastingPlan? current;

  /// 非 null 时 [FastingPlanApi.extendFast] / [fetchCurrent] 抛该异常。
  Object? error;

  /// [FastingPlanApi.fetchActiveRecordId] 的返回值。
  String? activeRecordId = 'srv-r1';

  final List<FastingPlan> puts = <FastingPlan>[];
  final List<({String clientRequestId, String recordId, int extendMinutes})>
  extends_ = <({String clientRequestId, String recordId, int extendMinutes})>[];
  int fetchCurrentCalls = 0;

  @override
  Future<void> putCurrent(FastingPlan plan) async {
    puts.add(plan);
    if (fail) throw const NetworkApiException();
  }

  @override
  Future<FastingPlan?> fetchCurrent() async {
    fetchCurrentCalls++;
    final e = error;
    if (e != null) throw e;
    return current;
  }

  @override
  Future<String?> fetchActiveRecordId() async {
    final e = error;
    if (e != null) throw e;
    return activeRecordId;
  }

  @override
  Future<void> extendFast({
    required String clientRequestId,
    required String recordId,
    required int extendMinutes,
  }) async {
    extends_.add((
      clientRequestId: clientRequestId,
      recordId: recordId,
      extendMinutes: extendMinutes,
    ));
    final e = error;
    if (e != null) throw e;
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

  group('pull 下行回填（重装/换机）', () {
    final custom8 = FastingPlan(
      id: '16:8@09:00',
      eatStartMinutes: 540,
      eatEndMinutes: 1020,
    );

    FastingPlanSync buildPullSync(
      _FakeApi api, {
      OnboardingStore? store,
      String uid = 'u1',
      void Function()? onApplied,
    }) => FastingPlanSync(
      api: api,
      prefs: prefs,
      userId: () => uid,
      onboardingStore: store,
      onPlanApplied: onApplied,
      nowUtc: () => fixedNowUtc,
      location: () => bjt,
    );

    test('未登录 no-op：不发 GET', () async {
      final api = _FakeApi(current: custom8);
      final store = InMemoryOnboardingStore();
      await buildPullSync(api, store: store, uid: 'anonymous').pull();
      expect(api.fetchCurrentCalls, 0);
      expect(store.loadActivePlan(), isNull);
    });

    test('本地已有生效方案：不覆盖', () async {
      final api = _FakeApi(current: custom8);
      final store = InMemoryOnboardingStore();
      store.saveActivePlan(
        ActivePlanSnapshot(
          plan: FastingPlan.plan14x10,
          initialState: 'fasting',
          startedAtUtc: fixedNowUtc,
        ),
      );
      await buildPullSync(api, store: store).pull();
      expect(api.fetchCurrentCalls, 0); // 存在性短路，连 GET 都不发
      expect(store.loadActivePlan()!.plan, FastingPlan.plan14x10);
    });

    test('本地无方案：回填 + 放行引导 + 回调；重复 pull 幂等', () async {
      final api = _FakeApi(current: custom8);
      final store = InMemoryOnboardingStore();
      var applied = 0;
      final sync = buildPullSync(api, store: store, onApplied: () => applied++);
      await sync.pull();
      final saved = store.loadActivePlan()!;
      expect(saved.plan, custom8);
      expect(saved.startedAtUtc, fixedNowUtc);
      // 快照字段与 resolveState 口径一致（假时钟 fixedNowUtc 落点）。
      final expected = resolveState(fixedNowUtc, custom8, bjt);
      expect(saved.initialState, expected.state.name);
      expect(saved.targetUtc, expected.targetUtc);
      expect(saved.attributionDate, expected.attributionPreview?.toIsoString());
      expect(store.isOnboardingCompleted, isTrue);
      // 二次 pull：本地已有方案 → 不再回填、不再回调。
      await sync.pull();
      expect(applied, 1);
    });

    test('服务端无可重建方案 / 拉取失败：静默不回填', () async {
      final store = InMemoryOnboardingStore();
      await buildPullSync(_FakeApi(), store: store).pull(); // current=null
      expect(store.loadActivePlan(), isNull);

      final failing = _FakeApi(current: custom8)
        ..error = const NetworkApiException();
      await buildPullSync(failing, store: store).pull();
      expect(store.loadActivePlan(), isNull);
      expect(store.isOnboardingCompleted, isFalse);
    });

    test('引导存储未装配：no-op 不抛', () async {
      final api = _FakeApi(current: custom8);
      await buildPullSync(api).pull();
      expect(api.fetchCurrentCalls, 0);
    });
  });

  group('F3 延长队列（queueExtend + flush 重放）', () {
    const extendKey = 'fasting_extend_pending_u1';
    const anonExtendKey = 'fasting_extend_pending_anonymous';

    void seedQueue(String key, List<Map<String, Object?>> items) {
      prefs.setString(key, jsonEncode(items));
    }

    Map<String, Object?> item({
      String cid = 'c1',
      String rid = 'r1',
      int min = 30,
    }) => <String, Object?>{
      'clientRequestId': cid,
      'recordId': rid,
      'extendMinutes': min,
    };

    test('queueExtend：落 prefs；同一 clientRequestId 去重', () async {
      final sync = buildSync(_FakeApi());
      await sync.queueExtend(
        recordId: 'r1',
        clientRequestId: 'c1',
        extendMinutes: 30,
      );
      await sync.queueExtend(
        recordId: 'r1',
        clientRequestId: 'c1',
        extendMinutes: 30,
      );
      final raw = prefs.getString(extendKey)!;
      expect(jsonDecode(raw), hasLength(1));
    });

    test('flush：队列重放成功后清键', () async {
      final api = _FakeApi();
      seedQueue(extendKey, [item()]);
      await buildSync(api).flush();
      expect(api.extends_.single.recordId, 'r1');
      expect(prefs.getString(extendKey), isNull);
    });

    test('flush：网络失败保留队列；终态码丢弃该项', () async {
      final network = _FakeApi()..error = const NetworkApiException();
      seedQueue(extendKey, [item()]);
      await buildSync(network).flush();
      expect(prefs.getString(extendKey), contains('c1'));

      final terminal = _FakeApi()
        ..error = const BusinessApiException(
          httpStatus: 409,
          code: 'FASTING_ALREADY_ENDED',
          message: 'ended',
        );
      await buildSync(terminal).flush();
      expect(prefs.getString(extendKey), isNull); // 终态丢弃
    });

    test('flush：pending recordId 重放前补解析', () async {
      final api = _FakeApi();
      seedQueue(extendKey, [item(rid: FastingPlanSync.kPendingRecordId)]);
      await buildSync(api).flush();
      expect(api.extends_.single.recordId, 'srv-r1'); // fake 解析值
      expect(prefs.getString(extendKey), isNull);
    });

    test('flush：方案 PUT 失败仍重放延长队列，并按原契约抛出', () async {
      final api = _FakeApi(fail: true)..error = null; // fail 只影响 putCurrent
      await prefs.setString(
        dirtyKey,
        jsonEncode(<String, Object?>{
          'planId': plan10.planId,
          'eatStartMinutes': 540,
          'eatEndMinutes': 1140,
        }),
      );
      seedQueue(extendKey, [item()]);
      await expectLater(buildSync(api).flush(), throwsA(isA<ApiException>()));
      expect(api.extends_.single.clientRequestId, 'c1'); // 队列未被 PUT 失败阻断
      expect(prefs.getString(extendKey), isNull);
      expect(prefs.getString(dirtyKey), isNotNull); // 脏保留
    });

    test('匿名队列在登录后迁移重放', () async {
      final api = _FakeApi();
      var uid = 'anonymous';
      final sync = FastingPlanSync(api: api, prefs: prefs, userId: () => uid);
      await sync.queueExtend(
        recordId: 'r1',
        clientRequestId: 'c1',
        extendMinutes: 30,
      );
      expect(prefs.getString(anonExtendKey), contains('c1'));
      await sync.flush();
      expect(api.extends_, isEmpty); // 匿名不上行

      uid = 'u1';
      await sync.flush();
      expect(api.extends_.single.clientRequestId, 'c1');
      expect(prefs.getString(anonExtendKey), isNull);
      expect(prefs.getString(extendKey), isNull);
    });

    test('队列损坏清键；空队列 no-op', () async {
      final api = _FakeApi();
      await prefs.setString(extendKey, 'not-json');
      await buildSync(api).flush();
      expect(prefs.getString(extendKey), isNull);
      expect(api.extends_, isEmpty);
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
