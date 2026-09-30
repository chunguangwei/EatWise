import 'package:eatwise/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 真机 UI 走查（iPhone，flutter drive）：五 tab 全覆盖 + 关键交互，
/// 逐站打印 `@@SHOT:<name>@@` 标记供宿主脚本对齐 devicectl 截屏。
///
/// 运行（项目根 eatwise_app/ 下，设备已解锁）：
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/ui_walkthrough_test.dart \
///   -d <device-udid> --dart-define=API_BASE_URL=https://wcg.polin.tech:8443/v1
/// ```
///
/// 演示账号（App Store 审核号）：appreview / Review#2026EatWise。
/// 前置：中国区「无线数据」系统弹窗需由宿主侧 XCUITest 并发关闭
/// （见 /tmp/wt_run3.sh 与 /tmp/alertdismiss）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 每站收尾：画面稳定 → 打标记 → 给宿主截屏留窗；tapAt 注入一次
  /// 空白触控防自动锁屏（真机走查曾在中途锁屏，后续站全部拍成锁屏页）。
  Future<void> station(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 1500));
    debugPrint('@@SHOT:$name@@');
    await tester.tapAt(const Offset(8, 200));
    await tester.pump(const Duration(milliseconds: 1800));
  }

  /// 文案出现才点（800ms 轮询重试至超时；.first/.last finder 在空集合上
  /// evaluate 会抛 StateError，必须先对基础 finder 判空）。
  Future<bool> tapIfVisible(
    WidgetTester tester,
    String text, {
    bool last = false,
    bool contains = false,
    int retries = 12,
  }) async {
    for (var i = 0; i <= retries; i++) {
      final base = contains ? find.textContaining(text) : find.text(text);
      if (base.evaluate().isNotEmpty) {
        await tester.tap(last ? base.last : base.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 1200));
        return true;
      }
      await tester.pump(const Duration(milliseconds: 800));
    }
    debugPrint('@@MISS:$text@@');
    return false;
  }

  /// ValueKey 精确点按（轮询等待；引导链路关键按钮专用，防文案歧义）。
  Future<bool> tapByKeyIfVisible(
    WidgetTester tester,
    String key, {
    int retries = 12,
  }) async {
    for (var i = 0; i <= retries; i++) {
      final base = find.byKey(ValueKey<String>(key));
      if (base.evaluate().isNotEmpty) {
        await tester.tap(base.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 1200));
        return true;
      }
      await tester.pump(const Duration(milliseconds: 800));
    }
    debugPrint('@@MISS_KEY:$key@@');
    return false;
  }

  /// 当前页面上所有 Text 数据（诊断用）。
  void dumpTexts(WidgetTester tester, String tag) {
    final shown = <String>[];
    for (final e in find.byType(Text).evaluate().take(14)) {
      final w = e.widget;
      if (w is Text && w.data != null && w.data!.isNotEmpty) shown.add(w.data!);
    }
    debugPrint('@@TEXTS[$tag]: $shown@@');
  }

  testWidgets('ui walkthrough', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 8));

    // ① 隐私同意（首启门禁：必勾主同意 CheckboxListTile（点标题行即翻转
    // 勾选，按钮才可用）→ 同意并继续。反复点直到按钮可用，而非盲点一次。
    var agreed = false;
    for (var i = 0; i < 60 && !agreed; i++) {
      final consentText = find.text('同意并继续');
      if (consentText.evaluate().isNotEmpty) {
        final btnFinder = find.ancestor(
          of: consentText.first,
          matching: find.byType(FilledButton),
        );
        if (btnFinder.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(btnFinder.first).onPressed != null) {
          agreed = true;
          continue;
        }
      }
      await tapIfVisible(tester, '我已阅读并同意《用户协议》与《隐私政策》', retries: 0);
      await tester.pump(const Duration(milliseconds: 800));
    }
    await tapIfVisible(tester, '同意并继续', retries: 10);
    await tester.pump(const Duration(seconds: 2));

    // ② 登录页处理（演示账号；年龄确认后一键启动也可能落登录页）。
    Future<bool> loginIfVisible() async {
      if (find.byType(TextField).evaluate().length >= 2 &&
          find.text('登录').evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField).at(0), 'appreview');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(
          find.byType(TextField).at(1),
          'Review#2026EatWise',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tapIfVisible(tester, '登录', last: true);
        // 等待登录结果：进首页（底栏「首页」）或出错误文案。
        for (var i = 0; i < 45; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.text('首页').evaluate().isNotEmpty) return true;
        }
        dumpTexts(tester, 'login-failed');
        return false;
      }
      return false;
    }

    // ③ 引导（ValueKey 精确链路：问卷跳过 → 推荐页一键启动 → 年龄确认
    // 勾选 → 确认；首装食物库灌库耗时较长，全部轮询等待）。
    await tapByKeyIfVisible(tester, 'onboarding.quiz.skip', retries: 40);
    if (await tapByKeyIfVisible(
      tester,
      'onboarding.recommendation.start',
      retries: 10,
    )) {
      await tapByKeyIfVisible(tester, 'onboarding.ageConfirm.checkbox');
      await tapByKeyIfVisible(tester, 'onboarding.ageConfirm.confirm');
      await tester.pump(const Duration(seconds: 3));
    }
    // 年龄确认后未登录会被路由强制送登录页（app_router redirect：
    // !loggedIn → /login）：必须登录成功才能进首页。
    await loginIfVisible();
    // 若被弹回推荐页（年龄已确认不再弹窗）再点一次启动并补登录。
    await tapByKeyIfVisible(
      tester,
      'onboarding.recommendation.start',
      retries: 3,
    );
    await loginIfVisible();

    // ── 首页 ──────────────────────────────────────────────
    await tapIfVisible(tester, '首页');
    await station(tester, '01_home_fasting');

    // ── 记录页 ────────────────────────────────────────────
    await tapIfVisible(tester, '记录');
    await station(tester, '02_record_entries');
    // 搜索 → 结果列表。
    final searchBase = find.byType(TextField);
    if (searchBase.evaluate().isNotEmpty) {
      await tester.enterText(searchBase.first, '米饭');
      await tester.pump(const Duration(milliseconds: 1600));
    }
    await station(tester, '03_record_search');
    // 食物详情弹层（份量输入框新形态）。
    await tapIfVisible(tester, '白米饭');
    await station(tester, '04_record_food_detail');
    // 份量入账 → 今日记录列表。
    final amountBase = find.byType(TextField);
    if (amountBase.evaluate().isNotEmpty) {
      await tester.enterText(amountBase.last, '200');
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tapIfVisible(tester, '确认记录');
    await station(tester, '05_record_today_list');
    // 饮水快捷 +200。
    await tapIfVisible(tester, '+200');
    await station(tester, '06_record_water');

    // ── 数据页 ────────────────────────────────────────────
    await tapIfVisible(tester, '数据');
    await station(tester, '07_data_trend');
    await tapIfVisible(tester, '断食时长');
    await station(tester, '08_data_fasting_trend');
    // 日期切换（前一天）。
    final prevBase = find.byIcon(Icons.chevron_left);
    if (prevBase.evaluate().isNotEmpty) {
      await tester.tap(prevBase.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 1200));
    }
    await station(tester, '09_data_prev_day');
    // 报告区（滚到底部）。
    final dataScrollBase = find.byType(Scrollable);
    if (dataScrollBase.evaluate().isNotEmpty) {
      try {
        await tester.drag(
          dataScrollBase.first,
          const Offset(0, -500),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 1200));
      } on Object {
        // 数据不足一屏时不可拖，忽略。
      }
    }
    await station(tester, '10_data_reports');

    // ── 社区 ──────────────────────────────────────────────
    await tapIfVisible(tester, '社区');
    await station(tester, '11_community_feed');

    // ── 我的 ──────────────────────────────────────────────
    await tapIfVisible(tester, '我的');
    await station(tester, '12_profile_top');
    // 滚到底（关于与法务组全可见）。
    final settingsScrollBase = find.byType(Scrollable);
    if (settingsScrollBase.evaluate().isNotEmpty) {
      try {
        await tester.drag(
          settingsScrollBase.first,
          const Offset(0, -600),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 1000));
      } on Object {
        // 忽略不可拖场景。
      }
    }
    await station(tester, '13_profile_bottom');
    // 协议 Hub 弹层。
    await tapIfVisible(tester, '协议与说明');
    await station(tester, '14_profile_legal_hub');
    // 关弹层。
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 800));

    // ── 深色模式一轮 ──────────────────────────────────────
    await tapIfVisible(tester, '主题');
    await tapIfVisible(tester, '深色');
    await tapIfVisible(tester, '首页');
    await station(tester, '15_dark_home');
    await tapIfVisible(tester, '记录');
    await station(tester, '16_dark_record');
    await tapIfVisible(tester, '我的');
    await station(tester, '17_dark_profile');

    // ── 英文一轮 ──────────────────────────────────────────
    await tapIfVisible(tester, '主题');
    await tapIfVisible(tester, '浅色');
    final settingsScrollBase2 = find.byType(Scrollable);
    if (settingsScrollBase2.evaluate().isNotEmpty) {
      try {
        await tester.drag(
          settingsScrollBase2.first,
          const Offset(0, -400),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 800));
      } on Object {
        // 忽略。
      }
    }
    await tapIfVisible(tester, '语言');
    await tapIfVisible(tester, 'English');
    await tapIfVisible(tester, 'Home');
    await station(tester, '18_en_home');
    await tapIfVisible(tester, 'Me');
    await station(tester, '19_en_profile');

    // ── 还原中文（设备状态留给用户）────────────────────────
    await tapIfVisible(tester, 'Language');
    await tapIfVisible(tester, '简体中文');
    await station(tester, '20_restore_zh');
  });
}
