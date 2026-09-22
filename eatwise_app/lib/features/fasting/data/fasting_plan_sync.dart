import 'dart:async';
import 'dart:convert';

import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/core/time/timezone_bootstrap.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/domain/fasting_engine.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:eatwise/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// 断食方案上行同步（进食窗口自选：客户端方案 → `PUT /fasting-plans/current`）。
///
/// 脏标记语义：方案本地写入（一键启动/换方案登记）与 T13 转正时
/// [markDirtyAndTryFlush]——prefs 键 `fasting_plan_dirty_<userId>` 存待上行
/// plan JSON（存在即脏）；fire-and-forget 尝试一次 PUT，失败保留脏标记，
/// 由 RecordSyncEngine 开头的 flush 重试（登录态下行 PUT 成功后
/// 清脏）。匿名期写入的脏方案在登录后的首轮同步迁移到真实 userId 再上行
/// （与运动/体重 pending「登录成功触发上行」同口径）。服务端生效语义
/// （首方案立即/改动次日 0 点，D-06）由服务端判定，客户端只管幂等 PUT。
///
/// 另有两条从属链路共用本类的 prefs 命名空间与同步时机：
/// - [pull]：方案下行回填（重装/换机，登录成功/恢复会话时触发）；
/// - [queueExtend]：F3 延长上报失败后的待上报队列，[flush] 顺带重放
///   （服务端幂等键 clientRequestId，重放不会重复累计）。
class FastingPlanSync {
  FastingPlanSync({
    required this.api,
    required this.prefs,
    required this.userId,
    this.onboardingStore,
    this.onPlanApplied,
    int Function()? nowUtc,
    tz.Location Function()? location,
  }) : nowUtc = nowUtc ?? _defaultNowUtc,
       location = location ?? _defaultLocation;

  /// 方案上行接口（timer 侧 F3 上报也复用同一实例）。
  final FastingPlanApi api;

  /// 脏标记 / 延长待上报队列持久化。
  final SharedPreferences prefs;

  /// 当前用户 ID（未登录 `anonymous`；与记录侧同口径）。
  final String Function() userId;

  /// 引导存储（[pull] 回填生效方案用；未注入按「不适用」no-op）。
  final OnboardingStore? onboardingStore;

  /// 回填生效后的回调（provider 接线 gate 放行 + 计时主控重建信号；可空）。
  final VoidCallback? onPlanApplied;

  /// 当前时刻（UTC epoch 秒；测试注入假时钟）。
  final int Function() nowUtc;

  /// 设备时区（回填快照的 resolveState 用；默认 Asia/Shanghai 兜底 UTC）。
  final tz.Location Function() location;

  static const String _dirtyPrefix = 'fasting_plan_dirty_';

  static const String _extendPrefix = 'fasting_extend_pending_';

  /// 队列项入队时未解析到服务端记录 ID 的占位值（[flush] 重放前补解析）。
  static const String kPendingRecordId = 'pending';

  /// F3 重放的终态错误码：记录不存在/已结束/超上限/payload 不符/参数
  /// 非法——重放必然同样失败，直接丢弃队列项；其余（网络/超时/5xx）保留
  /// 待下一同步轮。
  static const Set<String> kExtendTerminalCodes = <String>{
    'NOT_FOUND',
    'FASTING_ALREADY_ENDED',
    'FASTING_EXTEND_LIMIT',
    'IDEMPOTENCY_PAYLOAD_MISMATCH',
    'VALIDATION_ERROR',
  };

  String _dirtyKey(String uid) => '$_dirtyPrefix$uid';

  String _extendKey(String uid) => '$_extendPrefix$uid';

  static int _defaultNowUtc() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  /// 同 [deviceLocationProvider]：生产取 main 启动装配后的设备时区，
  /// 未装配（纯单测）回退 Asia/Shanghai。
  static tz.Location _defaultLocation() {
    return deviceLocationFallback();
  }

  /// 方案本地写入/转正：置脏 + fire-and-forget 尝试一次上行。
  ///
  /// 失败静默（脏标记保留，[flush] 在同步轮重试），不阻断本地计时主流程。
  void markDirtyAndTryFlush(FastingPlan plan) {
    unawaited(
      () async {
        final uid = userId();
        await prefs.setString(_dirtyKey(uid), jsonEncode(_encode(plan)));
        await flush();
      }().onError<Object>((e, _) {
        // 网络/装配失败：脏标记已落（或下次写入补落），同步轮重试。
        debugPrint('FastingPlanSync: 上行失败（已忽略，待同步重试） $e');
      }),
    );
  }

  /// 方案下行回填（重装/换机恢复；登录成功/恢复会话时与 settingsPrefs.pull
  /// 同点位触发）：仅当本地**没有**生效方案时，把服务端当前方案落为
  /// 生效快照并放行引导（本地有方案以上行为准，不覆盖）。失败静默。
  Future<void> pull() async {
    final uid = userId();
    // 匿名 GET 必 401；未登录无从回填。
    if (uid == 'anonymous') return;
    final store = onboardingStore;
    if (store == null) return; // 引导存储未装配：不适用
    try {
      if (store.loadActivePlan() != null) return;
      final plan = await api.fetchCurrent();
      if (plan == null) return;
      // 回填即收敛：本机没有「更新的选择」，不再 markDirtyAndTryFlush。
      final now = nowUtc();
      final snapshot = resolveState(now, plan, location());
      store.saveActivePlan(
        ActivePlanSnapshot(
          plan: plan,
          initialState: snapshot.state.name,
          targetUtc: snapshot.targetUtc,
          attributionDate: snapshot.attributionPreview?.toIsoString(),
          startedAtUtc: now,
        ),
      );
      store.markOnboardingCompleted();
      // gate 放行 + 计时主控重建（未装配环境内部各自吞掉）。
      onPlanApplied?.call();
    } on Object catch (e) {
      debugPrint('FastingPlanSync.pull: 下行回填失败（已忽略） $e');
    }
  }

  /// F3 延长上报入队（timer 侧 fire-and-forget 上报失败时调用；匿名也入队，
  /// 登录后首轮同步迁移上行与脏方案同口径）。
  ///
  /// 同一 [clientRequestId] 去重（重复失败不重复入队）；队列项 payload
  /// 永不改写——服务端幂等校验 payloadHash={recordId, extendMinutes}，
  /// 重放必须原样发送。
  Future<void> queueExtend({
    required String recordId,
    required String clientRequestId,
    required int extendMinutes,
  }) async {
    final key = _extendKey(userId());
    final queue =
        _decodeQueue(prefs.getString(key)) ?? <Map<String, Object?>>[];
    if (queue.any((e) => e['clientRequestId'] == clientRequestId)) return;
    queue.add(<String, Object?>{
      'recordId': recordId,
      'clientRequestId': clientRequestId,
      'extendMinutes': extendMinutes,
    });
    await prefs.setString(key, jsonEncode(queue));
  }

  /// 登录态下行 PUT 待上行方案 + 重放 F3 延长待上报队列；成功后清脏/清项。
  /// 未登录为 no-op。
  ///
  /// 方案 PUT 失败抛 ApiException（由 RecordSyncEngine 吞掉保留脏标记）；
  /// 延长队列逐项自处理：成功/终态码清项，网络类失败保留。
  Future<void> flush() async {
    final uid = userId();
    // 匿名 PUT 必 401；脏标记保留，登录后首轮同步迁移并上行。
    if (uid == 'anonymous') return;
    Object? putFailure;
    try {
      await _flushDirtyPlan(uid);
    } on Object catch (e) {
      // 方案上行失败不阻断延长队列重放；末尾按原契约重抛。
      putFailure = e;
    }
    await _flushExtendQueue(uid);
    if (putFailure != null) throw putFailure;
  }

  bool _flushing = false;

  Future<void> _flushDirtyPlan(String uid) async {
    // 串行化：并发两次 flush（写入即 flush 与引擎同步轮同时触发）时，
    // 两个 PUT 到达服务端的顺序不定——旧 PUT 后到会用旧方案覆盖新方案，
    // 且其后的 remove 误擦新脏标记，两端永久分叉（走查 L5）。在途时后来
    // 者直接返回（脏标记保留，下一同步轮重试）。
    if (_flushing) return;
    _flushing = true;
    try {
      final key = _dirtyKey(uid);
      var raw = prefs.getString(key);
      if (raw == null) {
        // 登录迁移：匿名期写入的脏方案/延长队列换挂到真实 userId 后上行。
        final anonKey = _dirtyKey('anonymous');
        raw = prefs.getString(anonKey);
        if (raw == null) return;
        await prefs.setString(key, raw);
        await prefs.remove(anonKey);
      }
      final plan = _decode(raw);
      if (plan == null) {
        await prefs.remove(key); // 脏数据损坏：清掉，等下次方案写入重落
        return;
      }
      await api.putCurrent(plan);
      // compare-and-delete：PUT 在途期间用户又改方案（raw 被覆写）时保留
      // 脏标记给下一轮，绝不误擦未上行的新方案。
      if (prefs.getString(key) == raw) {
        await prefs.remove(key);
      }
    } finally {
      _flushing = false;
    }
  }

  /// 重放延长队列：成功清项；[kExtendTerminalCodes] 终态丢弃（重放必然
  /// 同样失败）；其余异常保留，下一同步轮再试。
  Future<void> _flushExtendQueue(String uid) async {
    final key = _extendKey(uid);
    var raw = prefs.getString(key);
    final anonKey = _extendKey('anonymous');
    final anonRaw = uid == 'anonymous' ? null : prefs.getString(anonKey);
    if (anonRaw != null) {
      // 登录迁移：匿名期入队的延长事件换挂到真实 userId（与脏方案同口径）。
      final merged = <Map<String, Object?>>[
        ...?_decodeQueue(raw),
        ...?_decodeQueue(anonRaw),
      ];
      raw = merged.isEmpty ? null : jsonEncode(merged);
      await prefs.remove(anonKey);
      if (raw == null) {
        await prefs.remove(key);
        return;
      }
      await prefs.setString(key, raw);
    }
    if (raw == null) return;
    final queue = _decodeQueue(raw);
    if (queue == null) {
      await prefs.remove(key); // 队列损坏：清掉，等下次延长失败重落
      return;
    }
    final remaining = <Map<String, Object?>>[];
    for (final item in queue) {
      try {
        var recordId = item['recordId']! as String;
        if (recordId == kPendingRecordId) {
          // 入队时未取到服务端记录 ID（fetchActiveRecordId 也失败）：
          // 重放前补解析；解析失败按网络类失败保留。
          final resolved = await api.fetchActiveRecordId();
          if (resolved == null) {
            remaining.add(item);
            continue;
          }
          recordId = resolved;
          item['recordId'] = recordId;
        }
        await api.extendFast(
          clientRequestId: item['clientRequestId']! as String,
          recordId: recordId,
          extendMinutes: item['extendMinutes']! as int,
        );
      } on ApiException catch (e) {
        if (kExtendTerminalCodes.contains(e.code)) {
          debugPrint(
            'FastingPlanSync: 延长上报终态丢弃(${e.code}) ${item['clientRequestId']}',
          );
        } else {
          remaining.add(item);
        }
      }
    }
    if (remaining.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(remaining));
    }
  }

  /// 延长队列解码；数据损坏返回 null（区别于空队列）。
  static List<Map<String, Object?>>? _decodeQueue(String? raw) {
    if (raw == null) return <Map<String, Object?>>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Map<String, Object?>.from(e! as Map<dynamic, dynamic>))
          .toList();
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _encode(FastingPlan plan) => <String, Object?>{
    'planId': plan.id,
    'eatStartMinutes': plan.eatStartMinutes,
    'eatEndMinutes': plan.eatEndMinutes,
  };

  static FastingPlan? _decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return FastingPlan(
        id: json['planId']! as String,
        eatStartMinutes: json['eatStartMinutes']! as int,
        eatEndMinutes: json['eatEndMinutes']! as int,
      );
    } on Object {
      return null;
    }
  }
}

/// 方案同步 Provider（dio/prefs/认证未装配的测试环境返回 null：
/// 调用方按「未装配跳过」处理，与 RecordSyncEngine 可选依赖同口径）。
final Provider<FastingPlanSync?> fastingPlanSyncProvider =
    Provider<FastingPlanSync?>((ref) {
      try {
        return FastingPlanSync(
          api: FastingPlanApi(ref.watch(apiDioProvider)),
          prefs: ref.watch(sharedPreferencesProvider),
          userId: () {
            try {
              return ref.read(authControllerProvider).userId ?? 'anonymous';
            } on Object {
              return 'anonymous'; // 认证未装配的测试/演示环境按未登录处理
            }
          },
          onboardingStore: SharedPreferencesOnboardingStore(
            ref.watch(sharedPreferencesProvider),
          ),
          onPlanApplied: () {
            // pull 回填生效：引导放行 + 计时主控重建（同 startPrimaryPlan
            // 收尾口径；未装配环境各自吞掉）。
            try {
              ref.read(onboardingGateProvider).completed = true;
            } on Object {
              // gate 未 override（测试/预览）：路由门禁不适用。
            }
            try {
              ref.read(planVersionProvider.notifier).state++;
            } on Object {
              // 信号量未装配：无计时主控在跑，无需重建。
            }
          },
        );
      } on Object {
        return null;
      }
    });
