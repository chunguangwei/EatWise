import 'package:eatwise/features/legal/application/privacy_gate.dart';
import 'package:eatwise/features/legal/data/privacy_consent_store.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首启隐私授权存储（合规 §4.1；main 注入 SharedPreferences 后生效，
/// 测试/预览降级内存实现——缺省未同意，门禁拦截进 /legal/consent）。
final privacyConsentStoreProvider = Provider<PrivacyConsentStore>((ref) {
  try {
    return SharedPreferencesPrivacyConsentStore(
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return InMemoryPrivacyConsentStore();
  }
});

/// 隐私授权路由门禁（main override 为持久实例并接入 GoRouter）。
final privacyGateProvider = Provider<PrivacyGate>((ref) {
  return PrivacyGate(
    agreed: ref.watch(privacyConsentStoreProvider).hasAgreedCurrentPolicy,
  );
});

/// 健康数据单独同意状态（UI 只读）。
final class PrivacyConsentState {
  const PrivacyConsentState({required this.healthDataGranted});

  /// 健康数据敏感个人信息单独同意（PIPL §29）。
  final bool healthDataGranted;
}

/// 隐私授权控制器：首启弹窗同意落盘 + 设置页健康数据授权开关（§4.4）。
final privacyConsentControllerProvider =
    StateNotifierProvider<PrivacyConsentController, PrivacyConsentState>((ref) {
      return PrivacyConsentController(
        store: ref.watch(privacyConsentStoreProvider),
        gate: ref.watch(privacyGateProvider),
      );
    });

final class PrivacyConsentController
    extends StateNotifier<PrivacyConsentState> {
  PrivacyConsentController({required this.store, required this.gate})
    : super(PrivacyConsentState(healthDataGranted: store.healthDataGranted));

  final PrivacyConsentStore store;
  final PrivacyGate gate;

  /// 首启弹窗「同意并继续」：主同意 + 健康数据单独同意落盘，翻转门禁放行。
  /// 埋点授权默认跟随主同意，由调用方接 `AnalyticsService.setAnalyticsConsent`
  /// （合规红线：弹窗完成前 AnalyticsService 保持 suppressed，ConsentStore
  /// 缺省 false 已保证）。
  Future<void> agree({required bool healthDataGranted}) async {
    await store.agree(healthDataGranted: healthDataGranted);
    state = PrivacyConsentState(healthDataGranted: healthDataGranted);
    gate.agreed = true;
  }

  /// 设置页健康数据授权开关（§4.4 撤回路径：关闭后停止健康数据上云，
  /// 云端数据处理〔假设：30 天内删除或匿名化〕由服务端实现后接管）。
  Future<void> setHealthDataGranted(bool granted) async {
    await store.setHealthDataGranted(granted);
    state = PrivacyConsentState(healthDataGranted: granted);
  }
}
