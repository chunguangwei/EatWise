import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_client.dart';
import 'package:eatwise/core/analytics/analytics_context.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/analytics/consent_store.dart';
import 'package:eatwise/core/analytics/device_identity_store.dart';
import 'package:eatwise/core/analytics/event_queue_store.dart';
import 'package:eatwise/core/analytics/page_stay_tracker.dart';
import 'package:eatwise/core/network/cert_pinning.dart';
import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/auth/application/auth_providers.dart';
import 'package:eatwise/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 隐私授权存储（D-18：默认未授权不采集）。
///
/// 生产由 main() 注入 SharedPreferences 后自然生效；未注入场景
/// （测试/预览）降级内存实现（缺省未授权 → 全部事件 suppressed）。
final consentStoreProvider = Provider<ConsentStore>((ref) {
  try {
    return SharedPreferencesConsentStore(ref.watch(sharedPreferencesProvider));
  } on Object {
    return InMemoryConsentStore();
  }
});

/// 事件离线队列（SharedPreferences JSON；drift 加密表为规范后续项）。
final analyticsQueueStoreProvider = Provider<EventQueueStore>((ref) {
  try {
    return SharedPreferencesEventQueueStore(
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return InMemoryEventQueueStore();
  }
});

/// 设备身份（授权后首次上报时惰性生成，§1.6-1）。
final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>((ref) {
  try {
    return SharedPreferencesDeviceIdentityStore(
      ref.watch(sharedPreferencesProvider),
    );
  } on Object {
    return InMemoryDeviceIdentityStore();
  }
});

/// 公共属性注入器（§1.2）：locale 跟随 slang（D-15），user_id 取登录态
/// 并 HMAC 匿名化，platform/os_version 探测 dart:io。
final analyticsContextProvider = Provider<AnalyticsContext>((ref) {
  return AnalyticsContext(
    deviceIdentityStore: ref.watch(deviceIdentityStoreProvider),
    userIdResolver: () {
      try {
        return ref.read(authControllerProvider).userId;
      } on Object {
        return null;
      }
    },
    localeTag: () {
      try {
        return LocaleSettings.currentLocale.languageTag;
      } on Object {
        return 'zh-CN';
      }
    },
  );
});

/// 上报通道：debug 并列 logging 通道（开发自测，§5.1-①）+ 自建采集网关
/// （§1.3 主通道；裸 Dio 仅带 baseUrl，不走认证拦截——授权后未登录也可上报）。
final analyticsClientsProvider = Provider<List<AnalyticsClient>>((ref) {
  final dio = Dio(BaseOptions(baseUrl: ref.watch(apiConfigProvider).baseUrl));
  // 与 API 客户端同一生产自签名证书锁定（见 core/network/cert_pinning.dart）。
  final pinnedContext = ref.watch(pinnedSecurityContextProvider);
  if (pinnedContext != null) {
    applyCertPinning(dio, pinnedContext);
  }
  final transport = RemoteAnalyticsClient(dio: dio);
  return <AnalyticsClient>[
    if (kDebugMode) const LoggingAnalyticsClient(),
    transport,
  ];
});

/// 埋点采集服务（单例）。
///
/// 注意：provider 只构造不启动——定时 flush / 启动重放 / 生命周期观察由
/// main() 显式 `start()` 接线（避免测试环境悬挂 Timer）。
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final service = AnalyticsService(
    consentStore: ref.watch(consentStoreProvider),
    queueStore: ref.watch(analyticsQueueStoreProvider),
    context: ref.watch(analyticsContextProvider),
    clients: ref.watch(analyticsClientsProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// 设置页「数据分析开关」读接口（§1.6-2；设置 UI 开关留 TODO，
/// 写入走 [AnalyticsService.setAnalyticsConsent]）。
final analyticsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(consentStoreProvider).analyticsGranted;
});

/// 页面停留采集（§4.2）：NavigatorObserver 挂 GoRouter（main 接线），
/// Tab 切换由 HomeShell 调 [PageStayTracker.onTabSwitch]。
final pageStayTrackerProvider = Provider<PageStayTracker>((ref) {
  return PageStayTracker(analytics: ref.watch(analyticsServiceProvider));
});
