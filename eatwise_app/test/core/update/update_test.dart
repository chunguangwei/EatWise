import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/network/api_client.dart';
import 'package:eatwise/core/network/api_config.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/update/update_checker.dart';
import 'package:eatwise/core/update/update_dialog.dart';
import 'package:eatwise/core/update/update_downloader.dart';
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
        'apkUrlFallback': 'https://fallback.example.com/app.apk',
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
      expect(result.info.apkUrl, 'https://example.com/app.apk');
      expect(
        result.info.apkUrlFallback,
        'https://fallback.example.com/app.apk',
      );
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

  group('UpdateDownloader（App 内下载 + 续传/重试/兜底/保活）', () {
    const apkUrl = 'https://example.com/app.apk';
    const fallbackUrl = 'https://fallback.example.com/app.apk';
    final apkBytes = List<int>.generate(64, (i) => i);

    late FakeHttpAdapter adapter;
    late Dio dio;
    late Directory tempDir;
    late List<String> wakelockEvents;
    late List<Duration> sleeps;

    String partPath() =>
        '${tempDir.path}/${UpdateDownloader.apkFileName}${UpdateDownloader.partFileSuffix}';
    String finalPath() => '${tempDir.path}/${UpdateDownloader.apkFileName}';

    setUp(() {
      adapter = FakeHttpAdapter();
      dio = Dio();
      dio.httpClientAdapter = adapter;
      tempDir = Directory.systemTemp.createTempSync('update_dl_test');
      wakelockEvents = <String>[];
      sleeps = <Duration>[];
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    UpdateDownloader downloader({
      required Future<bool> Function(String) open,
    }) => UpdateDownloader(
      dio: dio,
      openApk: open,
      tempDir: () async => tempDir,
      acquireWakelock: () async => wakelockEvents.add('acquire'),
      releaseWakelock: () async => wakelockEvents.add('release'),
      sleep: (d) async => sleeps.add(d),
    );

    test('成功：流式下载到临时目录、进度回调递增且末次满量、调起 open', () async {
      adapter.stub(apkUrl, StubResponse.rawBytes(200, apkBytes));
      final progress = <(int, int)>[];
      final opened = <String>[];
      final ok =
          await downloader(
            open: (path) async {
              opened.add(path);
              return true;
            },
          ).downloadAndInstall(
            apkUrl,
            onProgress: (received, total) => progress.add((received, total)),
          );
      expect(ok, isTrue);
      expect(opened.single, endsWith(UpdateDownloader.apkFileName));
      expect(progress, isNotEmpty);
      expect(progress.last, (apkBytes.length, apkBytes.length));
      expect(File(finalPath()).readAsBytesSync(), apkBytes);
      // 保活：下载期间 acquire，结束必 release。
      expect(wakelockEvents, <String>['acquire', 'release']);
    });

    test('下载失败（网络错误重试耗尽）：返回 false 且不调起 open；保活仍释放', () async {
      adapter.stub(apkUrl, StubResponse.networkError('offline'));
      var openCalled = false;
      final ok = await downloader(
        open: (path) async {
          openCalled = true;
          return true;
        },
      ).downloadAndInstall(apkUrl);
      expect(ok, isFalse);
      expect(openCalled, isFalse);
      // 3 次尝试 = 首次 + 2 次退避重试（1s/2s）
      expect(sleeps, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(adapter.requestsTo(apkUrl), 3);
      expect(wakelockEvents, <String>['acquire', 'release']);
    });

    test('调起安装器失败（用户取消/无权限）：返回 false', () async {
      adapter.stub(apkUrl, StubResponse.rawBytes(200, apkBytes));
      final ok = await downloader(
        open: (path) async => false,
      ).downloadAndInstall(apkUrl);
      expect(ok, isFalse);
    });

    test('断点续传：.part 已存在带 Range 请求，206 追加写、进度累计不回退', () async {
      File(partPath()).writeAsBytesSync(apkBytes.sublist(0, 4));
      adapter.stub(
        apkUrl,
        StubResponse.rawBytes(
          206,
          apkBytes.sublist(4),
          extraHeaders: <String, List<String>>{
            'content-range': <String>['bytes 4-63/64'],
          },
        ),
      );
      final progress = <(int, int)>[];
      final ok = await downloader(open: (path) async => true)
          .downloadAndInstall(
            apkUrl,
            onProgress: (received, total) => progress.add((received, total)),
          );
      expect(ok, isTrue);
      expect(adapter.requests.single.headers['range'], 'bytes=4-');
      expect(File(finalPath()).readAsBytesSync(), apkBytes);
      expect(progress, isNotEmpty);
      expect(progress.first.$1, greaterThan(4)); // 累计：已收 4 + 本次
      expect(progress.last, (64, 64));
    });

    test('服务端不认 Range（回 200）：截断重下整文件', () async {
      File(partPath()).writeAsBytesSync(<int>[9, 9, 9, 9]);
      adapter.stub(apkUrl, StubResponse.rawBytes(200, apkBytes));
      final progress = <(int, int)>[];
      final ok = await downloader(open: (path) async => true)
          .downloadAndInstall(
            apkUrl,
            onProgress: (received, total) => progress.add((received, total)),
          );
      expect(ok, isTrue);
      expect(File(finalPath()).readAsBytesSync(), apkBytes);
      expect(progress.last, (64, 64)); // 从 0 重计仍收满
    });

    test('416（.part 已完整）：不写数据直接大小校验通过并 rename', () async {
      File(partPath()).writeAsBytesSync(apkBytes);
      adapter.stub(
        apkUrl,
        StubResponse.rawBytes(
          416,
          <int>[],
          extraHeaders: <String, List<String>>{
            'content-range': <String>['bytes */64'],
          },
        ),
      );
      final ok = await downloader(
        open: (path) async => true,
      ).downloadAndInstall(apkUrl);
      expect(ok, isTrue);
      expect(File(finalPath()).readAsBytesSync(), apkBytes);
    });

    test('中断后自动重试：前两次网络错误、第三次成功（指数退避 1s/2s）', () async {
      adapter
        ..stub(apkUrl, StubResponse.networkError('offline'))
        ..stub(apkUrl, StubResponse.networkError('offline'))
        ..stub(apkUrl, StubResponse.rawBytes(200, apkBytes));
      final ok = await downloader(
        open: (path) async => true,
      ).downloadAndInstall(apkUrl);
      expect(ok, isTrue);
      expect(sleeps, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(adapter.requestsTo(apkUrl), 3);
      expect(File(finalPath()).readAsBytesSync(), apkBytes);
    });

    test('主链连续失败切兜底 URL：.part 续传跨 URL 成立', () async {
      // 主链：先收到 4 字节后中断（声明总长 64 但流只有 4 字节）→ 重试全失败。
      adapter
        ..stub(
          apkUrl,
          StubResponse.rawBytes(
            200,
            apkBytes.sublist(0, 4),
            extraHeaders: <String, List<String>>{
              Headers.contentLengthHeader: <String>['64'],
            },
          ),
        )
        ..stub(apkUrl, StubResponse.networkError('offline'))
        ..stub(apkUrl, StubResponse.networkError('offline'));
      // 兜底：带 Range 续传（.part 已收 4 字节）。
      adapter.stub(
        fallbackUrl,
        StubResponse.rawBytes(
          206,
          apkBytes.sublist(4),
          extraHeaders: <String, List<String>>{
            'content-range': <String>['bytes 4-63/64'],
          },
        ),
      );
      final ok = await downloader(
        open: (path) async => true,
      ).downloadAndInstall(apkUrl, fallbackUrl: fallbackUrl);
      expect(ok, isTrue);
      expect(adapter.requestsTo(apkUrl), 3);
      expect(adapter.requestsTo(fallbackUrl), 1);
      expect(adapter.requests.last.headers['range'], 'bytes=4-');
      expect(File(finalPath()).readAsBytesSync(), apkBytes);
    });

    test('切兜底后总长度不一致：清 .part 重下', () async {
      File(partPath()).writeAsBytesSync(<int>[9, 9, 9, 9]);
      // 主链：首轮 206 声明总长 64（记下 expectedTotal）但流不完整，
      // 后续重试 5xx 耗尽。
      adapter
        ..stub(
          apkUrl,
          StubResponse.rawBytes(
            206,
            apkBytes.sublist(4, 6),
            extraHeaders: <String, List<String>>{
              'content-range': <String>['bytes 4-5/64'],
            },
          ),
        )
        ..stub(apkUrl, StubResponse.rawBytes(500, <int>[]))
        ..stub(apkUrl, StubResponse.rawBytes(500, <int>[]));
      // 兜底为另一个文件（总长 100 ≠ 64）：首轮 206 声明不一致 → 清 .part，
      // 下一轮从 0 重下。
      final otherBytes = List<int>.generate(100, (i) => 255 - i);
      adapter
        ..stub(
          fallbackUrl,
          StubResponse.rawBytes(
            206,
            otherBytes.sublist(6),
            extraHeaders: <String, List<String>>{
              'content-range': <String>['bytes 6-99/100'],
            },
          ),
        )
        ..stub(fallbackUrl, StubResponse.rawBytes(200, otherBytes));
      final ok = await downloader(
        open: (path) async => true,
      ).downloadAndInstall(apkUrl, fallbackUrl: fallbackUrl);
      expect(ok, isTrue);
      expect(File(finalPath()).readAsBytesSync(), otherBytes);
      expect(adapter.requestsTo(fallbackUrl), 2);
      // 第二轮从头下：不带 Range。
      expect(adapter.requests.last.headers['range'], isNull);
    });

    test('完整性校验：流短于声明总长视为失败，保留 .part 供重试续传', () async {
      adapter.stub(
        apkUrl,
        StubResponse.rawBytes(
          200,
          apkBytes.sublist(0, 10),
          extraHeaders: <String, List<String>>{
            Headers.contentLengthHeader: <String>['64'],
          },
        ),
      );
      var openCalled = false;
      final ok = await downloader(
        open: (path) async {
          openCalled = true;
          return true;
        },
      ).downloadAndInstall(apkUrl);
      expect(ok, isFalse);
      expect(openCalled, isFalse);
      expect(File(finalPath()).existsSync(), isFalse); // 未 rename
      expect(
        File(partPath()).readAsBytesSync(),
        apkBytes.sublist(0, 10),
      ); // .part 保留
    });

    test('parseContentRangeTotal（纯函数）：正常/416 星号/缺失/非法', () {
      expect(parseContentRangeTotal('bytes 4-63/64'), 64);
      expect(parseContentRangeTotal('bytes */128'), 128);
      expect(parseContentRangeTotal(null), isNull);
      expect(parseContentRangeTotal('bytes 0-3/*'), isNull);
      expect(parseContentRangeTotal('garbage'), isNull);
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

    Widget harness(
      UpdateCheckResult result, {
      UpdateLauncher? launcher,
      UpdateDownloader? downloader,
    }) {
      return TranslationProvider(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: UpdateDialog(
              result: result,
              launcher: launcher ?? const UpdateLauncher(),
              downloader: downloader,
            ),
          ),
        ),
      );
    }

    /// 假下载器：dio 走 FakeHttpAdapter（stub apkUrl），openApk 记录调起；
    /// sleep/保亮注入假实现（失败路径的退避重试不耗真实时间）。
    UpdateDownloader fakeDownloader({
      required FakeHttpAdapter adapter,
      required Directory tempDir,
      required Future<bool> Function(String path) open,
    }) {
      final dio = Dio()..httpClientAdapter = adapter;
      return UpdateDownloader(
        dio: dio,
        openApk: open,
        tempDir: () async => tempDir,
        acquireWakelock: () async {},
        releaseWakelock: () async {},
        sleep: (_) async {},
      );
    }

    Directory makeTempDir() {
      final dir = Directory.systemTemp.createTempSync('update_dialog_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    /// 点击按钮触发下载并等下载结束：下载含真实文件 IO，整个触发 + 等待
    /// 放 runAsync（真实事件循环）内——fake 时钟区内注册的 IO 回调不会触发。
    Future<void> tapAndWaitDownload(WidgetTester tester, String label) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle(); // 收尾：结果帧 + 关窗动画
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

    testWidgets('点「立即更新」App 内下载完成调起安装并关闭弹窗（可选更新）', (tester) async {
      final adapter = FakeHttpAdapter()
        ..stub(
          'https://example.com/app.apk',
          StubResponse.rawBytes(200, <int>[1, 2, 3, 4]),
        );
      final opened = <String>[];
      final downloader = fakeDownloader(
        adapter: adapter,
        tempDir: makeTempDir(),
        open: (path) async {
          opened.add(path);
          return true;
        },
      );
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
                  downloader: downloader,
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

      await tapAndWaitDownload(tester, '立即更新');
      expect(opened.single, endsWith(UpdateDownloader.apkFileName));
      expect(find.text('发现新版本'), findsNothing); // 已关闭
    });

    testWidgets('下载失败给重试：错误提示 + 「重试」，重试成功后调起安装', (tester) async {
      final adapter = FakeHttpAdapter()
        // 首轮把每 URL 3 次尝试全部耗尽（下载器内部自动重试），
        // 第二轮（点「重试」）才成功。
        ..stub(
          'https://example.com/app.apk',
          StubResponse.networkError('offline'),
        )
        ..stub(
          'https://example.com/app.apk',
          StubResponse.networkError('offline'),
        )
        ..stub(
          'https://example.com/app.apk',
          StubResponse.networkError('offline'),
        )
        ..stub(
          'https://example.com/app.apk',
          StubResponse.rawBytes(200, <int>[1, 2, 3, 4]),
        );
      final opened = <String>[];
      final downloader = fakeDownloader(
        adapter: adapter,
        tempDir: makeTempDir(),
        open: (path) async {
          opened.add(path);
          return true;
        },
      );
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
                  downloader: downloader,
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

      // 首次下载失败：错误提示 + 「重试」按钮，弹窗保持。
      await tapAndWaitDownload(tester, '立即更新');
      expect(find.text('下载失败，请检查网络后重试'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(opened, isEmpty);

      // 重试成功：调起安装并关闭弹窗。
      await tapAndWaitDownload(tester, '重试');
      expect(opened.single, endsWith(UpdateDownloader.apkFileName));
      expect(find.text('发现新版本'), findsNothing);
    });

    testWidgets('强制更新调起安装后弹窗保持（未升级不放行）', (tester) async {
      final adapter = FakeHttpAdapter()
        ..stub(
          'https://example.com/app.apk',
          StubResponse.rawBytes(200, <int>[1, 2, 3, 4]),
        );
      final downloader = fakeDownloader(
        adapter: adapter,
        tempDir: makeTempDir(),
        open: (path) async => true,
      );
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
                  downloader: downloader,
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
      await tapAndWaitDownload(tester, '立即更新');
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
