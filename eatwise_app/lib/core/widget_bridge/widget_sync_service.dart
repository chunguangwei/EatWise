import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/widget_bridge/home_widget_gateway.dart';
import 'package:eatwise/core/widget_bridge/widget_data_provider.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_texts.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 小组件同步服务（《规格-M2 断食计时状态机》§8：状态迁移副作用链上的
/// 「刷新小组件」统一出口）。
///
/// 经 home_widget 把「状态枚举 + 目标锚点 UTC 毫秒」写入共享容器
/// （iOS App Group UserDefaults / Android HomeWidgetPreferences），
/// 再触发小组件重渲染；倒计时不传剩余值，由原生侧活控件自治渲染（§8）。
///
/// 纪律：同步失败（插件未注册/平台异常）只记日志、**绝不阻断计时主流程**
/// （对齐通知调度器的降级纪律，合规 §3）。

/// 共享键（跨平台契约：Dart 写入 ↔ Android Kotlin / iOS Swift 读取）。
abstract final class WidgetDataKeys {
  /// 状态枚举名：`noPlan` / `eating` / `fasting` / `fastingExtended`。
  static const String state = 'fasting_state';

  /// 目标锚点 UTC epoch 毫秒（fasting → 计划进食开始；eating → 进食结束）。
  static const String targetAnchorUtcMs = 'target_anchor_utc_ms';

  /// 目标锚点本地墙钟「HH:mm」（Android 2×2「到点时刻」降级，§4.5）。
  static const String targetWallClock = 'target_wallclock';

  /// 到点整行文案（本地化，如「12:00 可进食」）。
  static const String dueLine = 'due_line';

  /// 状态文案（本地化，如「断食中」）。
  static const String statusLabel = 'status_label';

  /// 无方案引导文案（本地化）。
  static const String noPlanLabel = 'no_plan_label';

  /// 归属日整行文案（本地化，「本次断食计入 7月29日」）。
  static const String attributionLabel = 'attribution_label';

  /// 归属日 `yyyy-MM-dd`（D-07）。
  static const String attributionDate = 'attribution_date';

  /// 方案标识（如 `16:8`）。
  static const String planLabel = 'plan_label';

  /// 进食窗口墙钟标签（如「12:00–20:00」）。
  static const String eatWindowLabel = 'eat_window_label';

  /// 本周期累计延长分钟数（D-10）。
  static const String extendedMinutes = 'extended_minutes';
}

/// iOS App Group（技术选型 §3〔假设 bundle 前缀〕：group.com.eatwise.shared）。
const String kWidgetAppGroupId = 'group.com.eatwise.shared';

/// iOS Widget kind（与 ios/EatWiseWidget 中 `kind` 一致）。
const String kWidgetIosKind = 'EatWiseWidget';

/// Android AppWidgetProvider 全限定名（updateWidget 广播目标）。
const String kWidgetAndroidProvider =
    'com.eatwise.eatwise.EatWiseWidgetProvider';

/// 小组件同步服务。
final class WidgetSyncService {
  WidgetSyncService({required this.gateway});

  /// 底层桥接网关（测试可注入替身）。
  final HomeWidgetGateway gateway;

  /// App Group 是否已设置（iOS 只需一次）。
  bool _appGroupReady = false;

  /// 上次成功同步的数据（diff 跳过：锚点未变时不惊动系统小组件框架，
  /// tick 跨分钟边界的高频调用由此降为近零成本）。
  WidgetFastingData? _lastSynced;

  /// 同步一份小组件数据：写共享容器 + 触发重渲染。
  ///
  /// 数据与上次相同（锚点/状态/文案均未变）时跳过全部平台调用。
  /// 任何平台异常吞掉记日志，不向上抛。
  Future<void> sync(WidgetFastingData data) async {
    if (data == _lastSynced) return;
    try {
      if (!_appGroupReady) {
        await gateway.setAppGroupId(kWidgetAppGroupId);
        _appGroupReady = true;
      }
      await gateway.saveData(WidgetDataKeys.state, data.state.name);
      await gateway.saveData(
        WidgetDataKeys.targetAnchorUtcMs,
        data.targetAnchorUtcMs,
      );
      await gateway.saveData(
        WidgetDataKeys.targetWallClock,
        data.targetWallClockLabel,
      );
      await gateway.saveData(WidgetDataKeys.dueLine, data.dueLineLabel);
      await gateway.saveData(WidgetDataKeys.statusLabel, data.statusLabel);
      await gateway.saveData(WidgetDataKeys.noPlanLabel, data.noPlanLabel);
      await gateway.saveData(
        WidgetDataKeys.attributionLabel,
        data.attributionLabel,
      );
      await gateway.saveData(
        WidgetDataKeys.attributionDate,
        data.attributionDate?.toIsoString(),
      );
      await gateway.saveData(WidgetDataKeys.planLabel, data.planLabel);
      await gateway.saveData(
        WidgetDataKeys.eatWindowLabel,
        data.eatWindowLabel,
      );
      await gateway.saveData(
        WidgetDataKeys.extendedMinutes,
        data.extendedMinutes,
      );
      await gateway.updateWidget(
        qualifiedAndroidName: kWidgetAndroidProvider,
        iOSName: kWidgetIosKind,
      );
      _lastSynced = data;
    } on Object catch (e) {
      // 降级：小组件刷新失败不阻断计时（下次触发链自然重试）。
      debugPrint('WidgetSyncService.sync 失败（已降级，不影响计时）: $e');
    }
  }

  /// 清空小组件数据（无方案/退出登录等场景），下次 sync 强制全量写。
  Future<void> clear() async {
    _lastSynced = null;
    try {
      await sync(
        const WidgetFastingData(
          state: FastingState.noPlan,
          statusLabel: '',
          noPlanLabel: '',
        ),
      );
    } on Object {
      // sync 内部已兜底，此处防御性吞掉。
    }
  }
}

/// 由当前 [Translations] 生成小组件文案解析器（D-15：文案走 i18n key）。
///
/// 状态文案/归属日复用 `fasting.home.*` 既有 key；到点整行文案用
/// `fasting.widget.dueEat/dueEatEnd`（携带本地化语序）。
WidgetTextResolver slangWidgetTextResolver(Translations t) {
  final locale = t.$meta.locale;
  return (FastingState state, LocalDate? attribution, String? wallClock) {
    final status = switch (state) {
      FastingState.noPlan => t.fasting.home.stateNoPlan,
      FastingState.eating => t.fasting.home.stateEating,
      FastingState.fasting => t.fasting.home.stateFasting,
      FastingState.fastingExtended => t.fasting.home.stateFastingExtended,
    };
    final due = wallClock == null
        ? null
        : switch (state) {
            FastingState.eating => t.fasting.widget.dueEatEnd(time: wallClock),
            FastingState.fasting || FastingState.fastingExtended =>
              t.fasting.widget.dueEat(time: wallClock),
            FastingState.noPlan => null,
          };
    return (
      statusLabel: status,
      noPlanLabel: t.fasting.home.startPlan,
      dueLineLabel: due,
      attributionLabel: attribution == null
          ? null
          : t.fasting.home.attribution(
              date: formatAttributionDate(attribution, locale: locale),
            ),
    );
  };
}

/// home_widget 网关（生产实现；测试 override 替身）。
final homeWidgetGatewayProvider = Provider<HomeWidgetGateway>((ref) {
  return const HomeWidgetPluginGateway();
});

/// 小组件同步服务（diff + 降级兜底）。
final widgetSyncServiceProvider = Provider<WidgetSyncService>((ref) {
  return WidgetSyncService(gateway: ref.watch(homeWidgetGatewayProvider));
});

/// 小组件数据计算器（slang 文案随当前语言）。
final widgetDataProviderProvider = Provider<WidgetDataProvider>((ref) {
  final t = LocaleSettings.currentLocale.buildSync();
  return WidgetDataProvider(textResolver: slangWidgetTextResolver(t));
});
