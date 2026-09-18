import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/update/update_checker.dart';
import 'package:eatwise/core/update/update_dialog.dart';
import 'package:eatwise/core/update/update_launcher.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_providers.dart';
import 'package:eatwise/core/update/update_throttle.dart';
import 'package:eatwise/core/update/version_compare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/fake_http_adapter.dart';

/// 应用内更新检查：版本比较边界、三态判定、节流、弹窗三态与跳转、双语。
void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  tearDown(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });

  group('版本比较（x.y.z[+build]）', () {
    test('解析：完整/前导 v/缺省段/build 元数据', () {
      expect(parseAppVersion('1.2.3+45').build, '45');
      expect(parseAppVersion('v2.0').minor, 0);
      expect(parseAppVersion('3').patch, 0);
    });

    test('非法版本号抛 FormatException', () {
      expect(() => parseAppVersion('abc'), throwsFormatException);
      expect(() => parseAppVersion('1.2.x'), throwsFormatException);
    });

    test('边界：相等/build 忽略/逐段比较', () {
      expect(compareAppVersions('1.0.0', '1.0.0'), 0);
      expect(compareAppVersions('1.0.0+1', '1.0.0+2'), 0); // build 不参与
      expect(compareAppVersions('v1.2.3', '1.2.3'), 0);
      expect(compareAppVersions('1.2.3', '1.2.10'), lessThan(0));
      expect(compareAppVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareAppVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareAppVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareAppVersions('1.0', '1.0.0'), 0);
    });
  });

  group('三态判定（decide 纯函数）', () {
    const info = AppVersionInfo(
      latestVersion: '1.2.0',
      minSupportedVersion: '1.0.0',
      releaseNotesZh: 'zh',
      releaseNotesEn: 'en',
      apkUrl: 'https://example.com/app.apk',
      publishedAt: null,
      source: 'github',
    );

    test('当前 >= latest → 已是最新', () {
      expect(UpdateChecker.decide('1.2.0', info), UpdateStatus.upToDate);
      expect(UpdateChecker.decide('1.3.0', info), UpdateStatus.upToDate);
    });

    test('min <= 当前 < latest → 可选更新', () {
      expect(UpdateChecker.decide('1.1.0', info), UpdateStatus.available);
      expect(UpdateChecker.decide('1.0.0', info), UpdateStatus.available);
    });

    test('当前 < minSupported → 强制更新（边界：等于 min 不强制）', () {
      const strict = AppVersionInfo(
        latestVersion: '1.2.0',
        minSupportedVersion: '1.1.0',
        releaseNotesZh: '',
        releaseNotesEn: '',
        apkUrl: null,
        publishedAt: null,
        source: 'github',
      );
      expect(UpdateChecker.decide('1.0.9', strict), UpdateStatus.forced);
      expect(UpdateChecker.decide('1.1.0', strict), UpdateStatus.available);
    });
  });

  group('UpdateChecker（走服务端 /app/version/latest）', () {
    late FakeHttpAdapter adapter;
    late Dio dio;

    setUp(() {
      adapter = FakeHttpAdapter();
      dio = createApiDio(config: ApiConfig());
      dio.httpClientAdapter = adapter;
    });

    Map<String, dynamic> versionPayload({
      String latest = '1.2.0',
      String min = '1.0.0',
    }) {
      return StubResponse.envelope(<String, dynamic>{
        'latestVersion': latest,
        'minSupportedVersion': min,
        'releaseNotes': <String, String>{'zh': '修复问题', 'en': 'Bug fixes'},
        'apkUrl': 'https://example.com/app.apk',
        'publishedAt': '2026-07-29T00:00:00Z',
        'source': 'github',
      });
    }

    test('携带 platform 查询参数并解包信封', () async {
      adapter.stub(
        '/app/version/latest',
        StubResponse.json(200, versionPayload()),
      );
      final checker = UpdateChecker(
        dio: dio,
        currentVersion: () async => '1.1.0',
        platform: 'android',
      );
      final result = await checker.check();
      expect(result.status, UpdateStatus.available);
      expect(result.info.latestVersion, '1.2.0');
      expect(result.info.releaseNotesFor('zh-CN'), '修复问题');
      expect(result.info.releaseNotesFor('en'), 'Bug fixes');
      expect(adapter.requests.single.queryParameters['platform'], 'android');
    });

    test('已是最新 / 强制更新两态', () async {
      adapter.stub(
        '/app/version/latest',
        StubResponse.json(200, versionPayload()),
      );
      final upToDate = await UpdateChecker(
        dio: dio,
        currentVersion: () async => '1.2.0',
        platform: 'android',
      ).check();
      expect(upToDate.status, UpdateStatus.upToDate);

      adapter.stub(
        '/app/version/latest',
        StubResponse.json(200, versionPayload(min: '1.1.0')),
      );
      final forced = await UpdateChecker(
        dio: dio,
        currentVersion: () async => '1.0.0',
        platform: 'android',
      ).check();
      expect(forced.status, UpdateStatus.forced);
    });

    test('服务端异常向上抛（由调用方决定静默或提示）', () async {
      adapter.stub('/app/version/latest', StubResponse.networkError('offline'));
      final checker = UpdateChecker(
        dio: dio,
        currentVersion: () async => '1.0.0',
        platform: 'android',
      );
      expect(checker.check(), throwsA(isA<DioException>()));
    });

    test('iOS 平台门：有更新也不发请求，直接报已是最新（不提示更新）', () async {
      adapter.stub(
        '/app/version/latest',
        StubResponse.json(200, versionPayload()),
      );
      final checker = UpdateChecker(
        dio: dio,
        currentVersion: () async => '1.0.0',
        platform: 'ios',
      );
      final result = await checker.check();
      expect(result.status, UpdateStatus.upToDate);
      expect(adapter.requests, isEmpty);
    });
  });

  group('节流（≥24h〔假设〕）与启动协调', () {
    test('首次应检查；记录后 24h 内跳过；超过后再次检查', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 7, 30, 12);
      final throttle = UpdateCheckThrottle(prefs, now: () => now);

      expect(throttle.shouldCheck(), isTrue);
      await throttle.markChecked();
      expect(throttle.shouldCheck(), isFalse);

      now = now.add(const Duration(hours: 23, minutes: 59));
      expect(throttle.shouldCheck(), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(throttle.shouldCheck(), isTrue);
    });

    test('自定义间隔生效（测试用小间隔）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 7, 30, 12);
      final throttle = UpdateCheckThrottle(
        prefs,
        interval: const Duration(minutes: 5),
        now: () => now,
      );
      await throttle.markChecked();
      now = now.add(const Duration(minutes: 6));
      expect(throttle.shouldCheck(), isTrue);
    });

    test('启动协调：有更新返回结果 → 节流内跳过；已是最新/异常静默', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final throttle = UpdateCheckThrottle(prefs);
      final adapter = FakeHttpAdapter();
      final dio = createApiDio(config: ApiConfig());
      dio.httpClientAdapter = adapter;
      UpdateChecker checker(String current) => UpdateChecker(
        dio: dio,
        currentVersion: () async => current,
        platform: 'android',
      );
      Map<String, dynamic> payload() => StubResponse.envelope(<String, dynamic>{
        'latestVersion': '1.2.0',
        'minSupportedVersion': '1.0.0',
        'releaseNotes': <String, String>{'zh': '', 'en': ''},
        'apkUrl': null,
        'publishedAt': null,
        'source': 'github',
      });

      // 有更新：返回结果并记录检查时间。
      adapter.stub('/app/version/latest', StubResponse.json(200, payload()));
      final coordinator = UpdateCheckCoordinator(
        checker: checker('1.0.0'),
        throttle: throttle,
      );
      final result = await coordinator.checkOnStartup();
      expect(result?.status, UpdateStatus.available);
      expect(throttle.shouldCheck(), isFalse);
      // 节流内：直接跳过，不再请求。
      expect(await coordinator.checkOnStartup(), isNull);
      expect(adapter.requestsTo('/app/version/latest'), 1);

      // 已是最新：返回 null。
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs2 = await SharedPreferences.getInstance();
      adapter.stub('/app/version/latest', StubResponse.json(200, payload()));
      final coordinator2 = UpdateCheckCoordinator(
        checker: checker('1.2.0'),
        throttle: UpdateCheckThrottle(prefs2),
      );
      expect(await coordinator2.checkOnStartup(), isNull);

      // 网络异常：静默 null，不阻断启动。
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs3 = await SharedPreferences.getInstance();
      adapter.stub('/app/version/latest', StubResponse.networkError('offline'));
      final coordinator3 = UpdateCheckCoordinator(
        checker: checker('1.0.0'),
        throttle: UpdateCheckThrottle(prefs3),
      );
      expect(await coordinator3.checkOnStartup(), isNull);
    });

    test('启动协调：iOS 平台有更新也静默（不请求、返回 null、不弹窗）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final adapter = FakeHttpAdapter();
      final dio = createApiDio(config: ApiConfig());
      dio.httpClientAdapter = adapter;
      adapter.stub(
        '/app/version/latest',
        StubResponse.json(
          200,
          StubResponse.envelope(<String, dynamic>{
            'latestVersion': '1.2.0',
            'minSupportedVersion': '1.0.0',
            'releaseNotes': <String, String>{'zh': '', 'en': ''},
            'apkUrl': null,
            'publishedAt': null,
            'source': 'github',
          }),
        ),
      );
      final coordinator = UpdateCheckCoordinator(
        checker: UpdateChecker(
          dio: dio,
          currentVersion: () async => '1.0.0',
          platform: 'ios',
        ),
        throttle: UpdateCheckThrottle(prefs),
      );
      expect(await coordinator.checkOnStartup(), isNull);
      expect(adapter.requests, isEmpty);
    });
  });

  group('UpdateLauncher', () {
    const info = AppVersionInfo(
      latestVersion: '1.2.0',
      minSupportedVersion: '1.0.0',
      releaseNotesZh: '',
      releaseNotesEn: '',
      apkUrl: 'https://example.com/app.apk',
      publishedAt: null,
      source: 'github',
    );

    test('Android 打开 apkUrl；iOS 打开 App Store 占位〔假设〕', () async {
      final opened = <Uri>[];
      final launcher = UpdateLauncher(
        launch: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      expect(await launcher.openUpdate(info, platform: 'android'), isTrue);
      expect(opened.single.toString(), 'https://example.com/app.apk');

      expect(await launcher.openUpdate(info, platform: 'ios'), isTrue);
      expect(opened.last.toString(), UpdateLauncher.iosAppStoreUrl);
    });

    test('Android 缺 apkUrl 返回 false', () async {
      const noApk = AppVersionInfo(
        latestVersion: '1.2.0',
        minSupportedVersion: '1.0.0',
        releaseNotesZh: '',
        releaseNotesEn: '',
        apkUrl: null,
        publishedAt: null,
        source: 'fallback',
      );
      const launcher = UpdateLauncher();
      expect(await launcher.openUpdate(noApk, platform: 'android'), isFalse);
    });
  });

  group('更新弹窗（双语三态）', () {
    const info = AppVersionInfo(
      latestVersion: '1.2.0',
      minSupportedVersion: '1.1.0',
      releaseNotesZh: '- 新增更新检查',
      releaseNotesEn: '- In-app update check',
      apkUrl: 'https://example.com/app.apk',
      publishedAt: null,
      source: 'github',
    );

    Widget harness(UpdateCheckResult result, {UpdateLauncher? launcher}) {
      return TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UpdateDialog(
              result: result,
              launcher: launcher ?? const UpdateLauncher(),
            ),
          ),
        ),
      );
    }

    testWidgets('可选更新：标题/版本号/中文 notes/两个按钮', (tester) async {
      await tester.pumpWidget(
        harness(
          const UpdateCheckResult(status: UpdateStatus.available, info: info),
        ),
      );
      await tester.pump();
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('最新版本：1.2.0'), findsOneWidget);
      expect(find.text('- 新增更新检查'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('以后再说'), findsOneWidget);
    });

    testWidgets('强制更新：无「以后再说」且返回被拦截', (tester) async {
      await tester.pumpWidget(
        harness(
          const UpdateCheckResult(status: UpdateStatus.forced, info: info),
        ),
      );
      await tester.pump();
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('以后再说'), findsNothing);
      // PopScope canPop=false：系统返回不关闭。
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('点「立即更新」调 launcher 并关闭弹窗（可选更新）', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showUpdateDialog(
                  context,
                  const UpdateCheckResult(
                    status: UpdateStatus.available,
                    info: info,
                  ),
                  launcher: UpdateLauncher(
                    launch: (uri) async {
                      opened.add(uri);
                      return true;
                    },
                  ),
                  platform: 'android',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);

      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://example.com/app.apk');
      expect(find.text('发现新版本'), findsNothing); // 已关闭
    });

    testWidgets('强制更新跳转后弹窗保持（未升级不放行）', (tester) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showUpdateDialog(
                  context,
                  const UpdateCheckResult(
                    status: UpdateStatus.forced,
                    info: info,
                  ),
                  launcher: UpdateLauncher(launch: (uri) async => true),
                  platform: 'android',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget); // 未关闭
    });

    testWidgets('英文语言：标题/按钮/notes 切英文（D-15）', (tester) async {
      await LocaleSettings.setLocale(AppLocale.en);
      await tester.pumpWidget(
        harness(
          const UpdateCheckResult(status: UpdateStatus.available, info: info),
        ),
      );
      await tester.pump();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Latest version: 1.2.0'), findsOneWidget);
      expect(find.text('- In-app update check'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });
  });
}
