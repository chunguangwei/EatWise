import 'dart:async';
import 'dart:convert';

import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/fasting/data/fasting_plan_api.dart';
import 'package:eatwise/features/fasting/domain/fasting_plan.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 断食方案上行同步（进食窗口自选：客户端方案 → `PUT /fasting-plans/current`）。
///
/// 脏标记语义：方案本地写入（一键启动/换方案登记）与 T13 转正时
/// [markDirtyAndTryFlush]——prefs 键 `fasting_plan_dirty_<userId>` 存待上行
/// plan JSON（存在即脏）；fire-and-forget 尝试一次 PUT，失败保留脏标记，
/// 由 RecordSyncEngine 开头的 flush 重试（登录态下行 PUT 成功后
/// 清脏）。匿名期写入的脏方案在登录后的首轮同步迁移到真实 userId 再上行
/// （与运动/体重 pending「登录成功触发上行」同口径）。服务端生效语义
/// （首方案立即/改动次日 0 点，D-06）由服务端判定，客户端只管幂等 PUT。
class FastingPlanSync {
  FastingPlanSync({
    required this.api,
    required this.prefs,
    required this.userId,
  });

  /// 方案上行接口。
  final FastingPlanApi api;

  /// 脏标记持久化。
  final SharedPreferences prefs;

  /// 当前用户 ID（未登录 `anonymous`；与记录侧同口径）。
  final String Function() userId;

  static const String _dirtyPrefix = 'fasting_plan_dirty_';

  String _dirtyKey(String uid) => '$_dirtyPrefix$uid';

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

  /// 登录态下行 PUT 待上行方案；成功后清脏。未登录/无脏标记为 no-op。
  ///
  /// 上行失败抛 ApiException（由 RecordSyncEngine 吞掉保留脏标记）。
  Future<void> flush() async {
    final uid = userId();
    // 匿名 PUT 必 401；脏标记保留，登录后首轮同步迁移并上行。
    if (uid == 'anonymous') return;
    final key = _dirtyKey(uid);
    var raw = prefs.getString(key);
    if (raw == null) {
      // 登录迁移：匿名期写入的脏方案换挂到真实 userId 后上行。
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
    await prefs.remove(key);
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
        );
      } on Object {
        return null;
      }
    });
