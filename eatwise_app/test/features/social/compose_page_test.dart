import 'dart:async';
import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/presentation/compose_page.dart';
import 'package:eatwise/features/streak/application/streak_controller.dart';
import 'package:eatwise/features/streak/data/streak_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'social_test_fakes.dart';

/// 打卡发布页 widget 测试：字数计数 / streak 徽章 / 空文校验 /
/// 发布被拒双语提示 / 失败提示 / 双语。
void main() {
  late FakeSocialApi api;
  late FakeUploadApi upload;
  late Uint8List? pickedPhoto;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    api = FakeSocialApi();
    upload = FakeUploadApi();
    pickedPhoto = null;
  });

  Future<void> pumpCompose(
    WidgetTester tester, {
    ServerStreakView? streakView,
    Object? streakError,
    Object? uploadError,
  }) async {
    if (uploadError != null) upload = FakeUploadApi(error: uploadError);
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('FEED')),
        ),
        GoRoute(
          path: '/compose',
          builder: (context, state) => const ComposePage(),
        ),
      ],
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: <Override>[
            socialApiProvider.overrideWithValue(api),
            uploadApiProvider.overrideWithValue(upload),
            composePhotoPickerProvider.overrideWithValue(
              FakePhotoPicker(pickedPhoto),
            ),
            streakApiProvider.overrideWithValue(
              FakeStreakApi(view: streakView, error: streakError),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    // push 返回的 Future 在 pop 时才完成，不能 await。
    unawaited(router.push('/compose')); // 从 / 进入，发布成功 pop 才合法
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 过渡动画跑完
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('字数计数：输入后实时更新 x/500', (tester) async {
    await pumpCompose(tester);
    expect(find.text('0/500'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '第一天打卡');
    await tester.pump();
    expect(find.text('5/500'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('streak 徽章：有连胜显示天数，无连胜显示引导文案（4.2）', (tester) async {
    await pumpCompose(
      tester,
      streakView: const ServerStreakView(
        currentStreak: 5,
        longestStreak: 9,
        lastQualifiedDate: '2026-07-28',
        mendCardStock: 2,
        mendCardGrantsThisMonth: 2,
        mendCardExpiresAt: '2026-07-31',
        mendCardUsableWindowDays: 7,
        mendCardStatus: 'available',
      ),
    );
    expect(find.text('当前连续 5 天 🔥'), findsOneWidget);
    await unmount(tester);

    await pumpCompose(tester); // 默认 view currentStreak = 0
    expect(find.text('完成今天的断食，打卡就会带上连胜徽章哦'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('空文本发布 → 提示「先写点什么吧」，不发请求', (tester) async {
    await pumpCompose(tester);
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('先写点什么吧'), findsOneWidget);
    expect(api.createCalls, 0);
    await unmount(tester);
  });

  testWidgets('发布被拒：服务端双语拒绝原因上屏，不返回', (tester) async {
    api.createError = rejectedException;
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '赌博广告');
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('内容未通过审核，无法发布'), findsOneWidget); // SnackBar
    expect(find.text('FEED'), findsNothing); // 未返回
    await unmount(tester);
  });

  testWidgets('发布网络失败：通用失败提示，不返回', (tester) async {
    api.createError = networkException;
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '正常打卡');
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('发布失败，请稍后重试'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('选图即上传：上传中禁用发布，成功后发布带服务端图片 URL', (tester) async {
    pickedPhoto = pngBytes;
    upload.gate = Completer<void>(); // 挂起上传，断言「上传中」态
    await pumpCompose(tester);
    await tester.tap(find.text('添加图片'));
    await tester.pump();
    // 上传在途：发布按钮禁用，避免发出无图帖。
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发布'))
          .onPressed,
      isNull,
    );
    upload.gate!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(upload.calls, 1);
    expect(upload.uploaded.single, pngBytes);

    // 上传完成：发布恢复，上行 imageUrls 为服务端 URL（非本地路径）。
    await tester.enterText(find.byType(TextField), '带图打卡');
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.lastImageUrls, <String>['/v1/uploads/srv-1.png']);
  });

  testWidgets('上传失败：错误上屏 + 就地重试；未重试前发布不带图', (tester) async {
    pickedPhoto = pngBytes;
    await pumpCompose(tester, uploadError: tooLargeException);
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('图片超过 5MB，请换一张或压缩后再传'), findsOneWidget);

    upload.error = null; // 重试成功（provider 持有的是同一实例）
    await tester.tap(find.text('重新上传'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(upload.calls, 2); // 首次失败 + 重试成功
    expect(find.text('图片超过 5MB，请换一张或压缩后再传'), findsNothing);
  });

  testWidgets('未选图发布不带 imageUrls（纯文字路径不受上传链路影响）', (tester) async {
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '纯文字');
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.lastImageUrls, isEmpty);
    expect(upload.calls, 0);
  });

  testWidgets('英文渲染：标题/计数/按钮双语', (tester) async {
    await LocaleSettings.setLocale(AppLocale.en);
    await pumpCompose(tester);
    expect(find.text('New check-in'), findsOneWidget);
    expect(find.text('0/500'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
    await unmount(tester);
    await LocaleSettings.setLocale(AppLocale.zhCn);
  });
}
