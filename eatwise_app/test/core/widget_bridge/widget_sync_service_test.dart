import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/widget_bridge/home_widget_gateway.dart';
import 'package:eatwise/core/widget_bridge/widget_data_provider.dart';
import 'package:eatwise/core/widget_bridge/widget_deep_link.dart';
import 'package:eatwise/core/widget_bridge/widget_sync_service.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录型 home_widget 网关替身。
final class FakeHomeWidgetGateway implements HomeWidgetGateway {
  final Map<String, Object?> saved = <String, Object?>{};
  final List<String> appGroupIds = <String>[];
  int updateCalls = 0;
  Object? error;
  Uri? initialUri;

  final StreamController<Uri?> clickController =
      StreamController<Uri?>.broadcast();

  Future<void> dispose() => clickController.close();

  @override
  Future<void> setAppGroupId(String groupId) async {
    appGroupIds.add(groupId);
    if (error != null) throw error!;
  }

  @override
  Future<void> saveData(String key, Object? value) async {
    if (error != null) throw error!;
    saved[key] = value;
  }

  @override
  Future<void> updateWidget({
    required String qualifiedAndroidName,
    required String iOSName,
  }) async {
    if (error != null) throw error!;
    updateCalls += 1;
    saved['__android__'] = qualifiedAndroidName;
    saved['__ios__'] = iOSName;
  }

  @override
  Stream<Uri?> get clickStream => clickController.stream;

  @override
  Future<Uri?> initialClickUri() async => initialUri;
}

WidgetFastingData sampleData({int anchorMs = 1785000000000}) {
  return WidgetFastingData(
    state: FastingState.fasting,
    statusLabel: '断食中',
    noPlanLabel: '选择你的断食方案',
    targetAnchorUtcMs: anchorMs,
    targetWallClockLabel: '12:00',
    dueLineLabel: '12:00 可进食',
    attributionDate: const LocalDate(2026, 7, 29),
    attributionLabel: '本次断食计入 7月29日',
    planLabel: '16:8',
    eatWindowLabel: '12:00–20:00',
  );
}

void main() {
  group('WidgetSyncService', () {
    late FakeHomeWidgetGateway gateway;
    late WidgetSyncService service;

    setUp(() {
      gateway = FakeHomeWidgetGateway();
      service = WidgetSyncService(gateway: gateway);
    });

    test('首次同步：写全部共享键 + App Group + updateWidget 双端名', () async {
      await service.sync(sampleData());

      expect(gateway.appGroupIds, <String>['group.com.eatwise.shared']);
      expect(gateway.saved[WidgetDataKeys.state], 'fasting');
      expect(gateway.saved[WidgetDataKeys.targetAnchorUtcMs], 1785000000000);
      expect(gateway.saved[WidgetDataKeys.targetWallClock], '12:00');
      expect(gateway.saved[WidgetDataKeys.dueLine], '12:00 可进食');
      expect(gateway.saved[WidgetDataKeys.statusLabel], '断食中');
      expect(gateway.saved[WidgetDataKeys.attributionDate], '2026-07-29');
      expect(gateway.saved[WidgetDataKeys.planLabel], '16:8');
      expect(gateway.saved[WidgetDataKeys.eatWindowLabel], '12:00–20:00');
      expect(gateway.saved[WidgetDataKeys.extendedMinutes], 0);
      expect(gateway.updateCalls, 1);
      expect(
        gateway.saved['__android__'],
        'com.eatwise.eatwise.EatWiseWidgetProvider',
      );
      expect(gateway.saved['__ios__'], 'EatWiseWidget');
    });

    test('diff：数据未变跳过平台调用；锚点变化重新同步', () async {
      await service.sync(sampleData());
      await service.sync(sampleData());
      expect(gateway.updateCalls, 1);

      await service.sync(sampleData(anchorMs: 1785001800000));
      expect(gateway.updateCalls, 2);
      expect(gateway.saved[WidgetDataKeys.targetAnchorUtcMs], 1785001800000);
    });

    test('noPlan：锚点键写 null（删除共享键），App Group 只设一次', () async {
      await service.sync(sampleData());
      await service.sync(
        const WidgetFastingData(
          state: FastingState.noPlan,
          statusLabel: '还未开始断食方案',
          noPlanLabel: '选择你的断食方案',
        ),
      );

      expect(gateway.saved[WidgetDataKeys.state], 'noPlan');
      expect(gateway.saved[WidgetDataKeys.targetAnchorUtcMs], isNull);
      expect(gateway.saved[WidgetDataKeys.attributionDate], isNull);
      expect(gateway.appGroupIds, hasLength(1));
    });

    test('平台异常降级：不抛异常，下次数据变化仍可重试', () async {
      gateway.error = StateError('plugin missing');
      await expectLater(service.sync(sampleData()), completes);
      expect(gateway.updateCalls, 0);

      gateway.error = null;
      await service.sync(sampleData());
      expect(gateway.updateCalls, 1);
    });
  });

  group('slangWidgetTextResolver（D-15 文案走 i18n key）', () {
    test('zh：状态/到点/归属日文案', () {
      final t = AppLocale.zhCn.buildSync();
      final resolver = slangWidgetTextResolver(t);

      final fasting = resolver(
        FastingState.fasting,
        const LocalDate(2026, 7, 29),
        '12:00',
      );
      expect(fasting.statusLabel, '断食中');
      expect(fasting.dueLineLabel, '12:00 可进食');
      expect(fasting.attributionLabel, '本次断食计入 7月29日');

      final eating = resolver(FastingState.eating, null, '20:00');
      expect(eating.dueLineLabel, '20:00 进食截止');
    });

    test('en：到点文案语序本地化', () {
      final t = AppLocale.en.buildSync();
      final resolver = slangWidgetTextResolver(t);

      final fasting = resolver(
        FastingState.fasting,
        const LocalDate(2026, 7, 29),
        '12:00',
      );
      expect(fasting.dueLineLabel, 'Eat at 12:00');
      expect(fasting.attributionLabel, 'This fast counts toward Jul 29');
    });
  });

  group('WidgetDeepLinkService', () {
    late FakeHomeWidgetGateway gateway;
    late WidgetDeepLinkService deepLink;

    setUp(() {
      gateway = FakeHomeWidgetGateway();
      deepLink = WidgetDeepLinkService(gateway: gateway);
    });

    test('点击流 eatwise://widget/home → 回调；其他 URI 忽略', () async {
      var opened = 0;
      deepLink.start(onOpenHome: () => opened += 1);
      addTearDown(deepLink.dispose);

      gateway.clickController.add(Uri.parse('eatwise://widget/home'));
      gateway.clickController.add(Uri.parse('https://example.com'));
      await Future<void>.delayed(Duration.zero);

      expect(opened, 1);
    });

    test('冷启动由小组件拉起 → 回调一次', () async {
      gateway.initialUri = Uri.parse('eatwise://widget/home');
      var opened = 0;
      deepLink.start(onOpenHome: () => opened += 1);
      addTearDown(deepLink.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(opened, 1);
    });
  });
}
