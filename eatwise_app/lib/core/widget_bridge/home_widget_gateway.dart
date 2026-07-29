import 'package:home_widget/home_widget.dart';

/// home_widget 插件网关（《技术选型与双端架构》§3：home_widget + MethodChannel）。
///
/// 抽象为接口便于测试替身；生产实现 [HomeWidgetPluginGateway] 薄封装
/// home_widget 静态 API。数据经 App Group（iOS）/ SharedPreferences
/// （Android `HomeWidgetPreferences`）共享容器传递（D-17）。
abstract interface class HomeWidgetGateway {
  /// iOS：设置 App Group（共享容器 id），Android 为 no-op。
  Future<void> setAppGroupId(String groupId);

  /// 写入共享键值（null = 删除该键）。
  Future<void> saveData(String key, Object? value);

  /// 触发双端小组件重渲染（iOS `reloadAllTimelines` /
  /// Android `ACTION_APPWIDGET_UPDATE` 广播）。
  Future<void> updateWidget({
    required String qualifiedAndroidName,
    required String iOSName,
  });

  /// 小组件点击深链流（home_widget `widgetClicked`）。
  Stream<Uri?> get clickStream;

  /// 冷启动由小组件拉起时的深链（home_widget
  /// `initiallyLaunchedFromHomeWidget`）。
  Future<Uri?> initialClickUri();
}

/// home_widget 插件生产实现。
final class HomeWidgetPluginGateway implements HomeWidgetGateway {
  const HomeWidgetPluginGateway();

  @override
  Future<void> setAppGroupId(String groupId) async {
    await HomeWidget.setAppGroupId(groupId);
  }

  @override
  Future<void> saveData(String key, Object? value) async {
    await HomeWidget.saveWidgetData<Object>(key, value);
  }

  @override
  Future<void> updateWidget({
    required String qualifiedAndroidName,
    required String iOSName,
  }) async {
    await HomeWidget.updateWidget(
      qualifiedAndroidName: qualifiedAndroidName,
      iOSName: iOSName,
    );
  }

  @override
  Stream<Uri?> get clickStream => HomeWidget.widgetClicked;

  @override
  Future<Uri?> initialClickUri() {
    return HomeWidget.initiallyLaunchedFromHomeWidget();
  }
}
