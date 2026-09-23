import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真机状态栏视口模拟与顶部重叠断言（真机走查「内容与状态栏重叠」回归防线）。
///
/// 背景：widget 测试默认 `viewPadding` 全 0（无状态栏），且部分旧 harness 用
/// `MediaQuery(data: MediaQueryData(textScaler: ...))` 整包覆盖，会把视图
/// padding 一并清零——两类写法都让「缺 SafeArea / AppBar 顶进状态栏」在测试
/// 里永远隐身。本 helper 从平台通道注入（`tester.view.viewPadding` +
/// `platformDispatcher.textScaleFactorTestValue`），与真机渲染路径一致。

/// 走查基线小屏：360x640 逻辑分辨率（华为系小屏）。
const Size kSmallScreenLogicalSize = Size(360, 640);

/// 安卓常见状态栏高度（逻辑 pt）。
const double kStatusBarHeight = 24;

/// 把测试视口设为 360x640@dpr2 + 顶部 24pt 状态栏 + 系统大字体 1.3，
/// 并注册 tearDown 还原。
///
/// 注意：`tester.view.viewPadding`/`padding` 的单位是**物理像素**
/// （框架内 `MediaQueryData.fromView` 会除以 devicePixelRatio），所以这里
/// 乘回 dpr，保证逻辑态栏高恰为 [statusBarHeight]。
void simulateStatusBarViewport(
  WidgetTester tester, {
  double statusBarHeight = kStatusBarHeight,
  double textScale = 1.3,
  Size logicalSize = kSmallScreenLogicalSize,
}) {
  const dpr = 2.0;
  tester.view.physicalSize = logicalSize * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.viewPadding = FakeViewPadding(top: statusBarHeight * dpr);
  tester.view.padding = FakeViewPadding(top: statusBarHeight * dpr);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// 断言 [finder] 命中控件的顶边不侵入状态栏区（[0, statusBarHeight)）。
/// finder 必须至少命中一个可见控件（skipOffstage 默认生效）。
void expectBelowStatusBar(
  WidgetTester tester,
  Finder finder, {
  double statusBarHeight = kStatusBarHeight,
}) {
  expect(finder, findsWidgets);
  expect(
    tester.getTopLeft(finder.first).dy,
    greaterThanOrEqualTo(statusBarHeight),
    reason: '内容顶边侵入状态栏区（<$statusBarHeight）',
  );
}

/// AppBar 标题查找器：限定在 AppBar 子树内，避开底部导航同名标签。
Finder appBarTitle(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));
