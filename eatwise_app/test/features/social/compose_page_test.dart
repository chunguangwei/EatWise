import 'dart:async';
import 'dart:typed_data';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/widgets/busy_filled_button.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:eatwise/features/social/application/post_polish_providers.dart';
import 'package:eatwise/features/social/application/post_polish_service.dart';
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
    PostPolishService? polishService,
  }) async {
    if (uploadError != null) upload = FakeUploadApi(error: uploadError);
    // 放大视口：带图 + 上传失败行时发布按钮会跌出默认 800x600 的懒构建区。
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
            postPolishServiceProvider.overrideWithValue(polishService),
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

  testWidgets('图片审核：选图后说明可见，移除图片恢复纯文字发布', (tester) async {
    pickedPhoto = pngBytes;
    await pumpCompose(tester);
    expect(find.text('图片帖需人工审核，通过后才会公开。'), findsNothing);
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('图片帖需人工审核，通过后才会公开。'), findsOneWidget);
    expect(find.text('提交审核'), findsOneWidget);
    await tester.tap(find.byTooltip('移除图片'));
    await tester.pump();
    expect(find.text('图片帖需人工审核，通过后才会公开。'), findsNothing);
    expect(find.text('发布'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('图片审核：服务端 pending 回执返回列表并确认仅自己可见', (tester) async {
    pickedPhoto = pngBytes;
    api.createAuditStatus = 'pending';
    await pumpCompose(tester);
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), '待审图片打卡');
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('FEED'), findsOneWidget);
    expect(find.text('已提交审核，暂时仅自己可见'), findsOneWidget);
    expect(api.createCalls, 1);
    await unmount(tester);
  });

  testWidgets('photo review: English hint, action and pending confirmation', (
    tester,
  ) async {
    await LocaleSettings.setLocale(AppLocale.en);
    pickedPhoto = pngBytes;
    api.createAuditStatus = 'pending';
    await pumpCompose(tester);
    await tester.tap(find.text('Add photo'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Photo posts are reviewed before they become public.'),
      findsOneWidget,
    );
    expect(find.text('Submit for review'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Photo check-in');
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('FEED'), findsOneWidget);
    expect(
      find.text('Submitted for review. Only you can see it for now.'),
      findsOneWidget,
    );
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

  testWidgets('发布提交中：BusyFilledButton 保持可读并防重复提交', (tester) async {
    api.createGate = Completer<void>();
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '提交中的打卡');
    await tester.tap(find.text('发布'));
    await tester.pump();

    final busy = tester.widget<BusyFilledButton>(find.byType(BusyFilledButton));
    expect(busy.busy, isTrue);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(BusyFilledButton),
        matching: find.byType(FilledButton),
      ),
    );
    const disabled = <WidgetState>{WidgetState.disabled};
    expect(button.onPressed, isNull);
    expect(
      button.style!.backgroundColor!.resolve(disabled),
      AppColors.light.actionPrimary,
    );
    expect(
      button.style!.foregroundColor!.resolve(disabled),
      AppColors.light.onActionPrimary,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(api.createCalls, 1);

    api.createGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FEED'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('发布中冻结文字图片匿名头像，失败后恢复完整草稿', (tester) async {
    pickedPhoto = pngBytes;
    api.createGate = Completer<void>();
    api.createError = networkException;
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '冻结稿件');
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.ensureVisible(find.byType(BusyFilledButton));
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly || field.enabled == false, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byTooltip('移除图片'),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    // Native back must not discard the only frozen draft during publication.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ComposePage), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(ComposePage)))!.isCurrent,
      isTrue,
    );
    expect(api.createCalls, 1);
    expect(api.lastAnonymous, isTrue);
    expect(api.lastImageUrls, isNotEmpty);
    for (final avatar in find.byType(CircleAvatar).evaluate()) {
      final ink = find.ancestor(
        of: find.byWidget(avatar.widget),
        matching: find.byType(InkWell),
      );
      if (ink.evaluate().isNotEmpty) {
        expect(tester.widget<InkWell>(ink.first).onTap, isNull);
      }
    }
    api.createGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final restored = tester.widget<TextField>(find.byType(TextField));
    expect(restored.readOnly, isFalse);
    expect(restored.controller!.text, '冻结稿件');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byTooltip('移除图片'),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('发布失败，请稍后重试'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('提交首帧双击只发送一次发布请求', (tester) async {
    api.createGate = Completer<void>();
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '一次发布');
    await tester.tap(find.byType(BusyFilledButton));
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    expect(api.createCalls, 1);
    api.createGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await unmount(tester);
  });

  testWidgets('无图发布确认等待期间冻结草稿，取消后恢复', (tester) async {
    pickedPhoto = pngBytes;
    await pumpCompose(tester, uploadError: networkException);
    await tester.enterText(find.byType(TextField), '仍保留原稿');
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.byType(BusyFilledButton));
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump(const Duration(milliseconds: 350));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly || field.enabled == false, isTrue);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(api.createCalls, 0);
    final restored = tester.widget<TextField>(find.byType(TextField));
    expect(restored.readOnly, isFalse);
    expect(restored.controller!.text, '仍保留原稿');
    expect(find.byTooltip('移除图片'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('不带图发布失败仍保留原图片与上传重试草稿', (tester) async {
    pickedPhoto = pngBytes;
    api.createError = networkException;
    await pumpCompose(tester, uploadError: networkException);
    await tester.enterText(find.byType(TextField), '保留图文稿');
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.byType(BusyFilledButton));
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('不带图发布'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.lastImageUrls, isEmpty);
    expect(find.byTooltip('移除图片'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留图文稿',
    );
    expect(find.text('发布失败，请稍后重试'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('发布遇到非API异常也恢复草稿和操作', (tester) async {
    api.createError = StateError('unexpected transport failure');
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '异常后保留稿件');
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('发布失败，请稍后重试'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '异常后保留稿件',
    );
    expect(
      tester.widget<BusyFilledButton>(find.byType(BusyFilledButton)).busy,
      isFalse,
    );
    await unmount(tester);
  });

  testWidgets('发布中打开新页面：旧完成回调不得将其关闭', (tester) async {
    final gate = Completer<void>();
    api.createGate = gate;
    await pumpCompose(tester);
    await tester.enterText(find.byType(TextField), '提交中的打卡');
    await tester.tap(find.text('发布'));
    await tester.pump();
    final composeContext = tester.element(find.byType(ComposePage));
    unawaited(
      Navigator.of(composeContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('NEXT')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('NEXT'), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('NEXT'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
          .widget<FilledButton>(find.widgetWithText(FilledButton, '提交审核'))
          .onPressed,
      isNull,
    );
    upload.gate!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(upload.calls, 1);
    expect(upload.uploaded.single, pngBytes);

    // 上传完成：发布恢复，上行 imageUrls 为服务端 URL（非本地路径）。
    await tester.enterText(find.byType(TextField), '带图打卡');
    await tester.tap(find.byType(BusyFilledButton));
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
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.lastImageUrls, isEmpty);
    expect(upload.calls, 0);
  });

  testWidgets('上传失败后点发布：失败语义弹窗，选「不带图发布」按纯文字发出', (tester) async {
    pickedPhoto = pngBytes;
    await pumpCompose(tester, uploadError: tooLargeException);
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('图片超过 5MB，请换一张或压缩后再传'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '图挂了也要打卡');
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 失败语义提示（不再是「上传中」），给出不带图发布选择。
    expect(find.text('图片上传失败：可以不带图发布，或取消后重新上传。'), findsOneWidget);
    expect(api.createCalls, 0);

    await tester.tap(find.text('不带图发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.createCalls, 1);
    expect(api.lastImageUrls, isEmpty); // 丢弃失败配图，纯文字上行
    await unmount(tester);
  });

  testWidgets('上传失败后点发布：取消则保留配图与重试入口，不发请求', (tester) async {
    pickedPhoto = pngBytes;
    await pumpCompose(tester, uploadError: tooLargeException);
    await tester.tap(find.text('添加图片'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), '再想想');
    await tester.tap(find.byType(BusyFilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('图片上传失败：可以不带图发布，或取消后重新上传。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.createCalls, 0);
    // 配图与就地重试入口保留，可修正后再发。
    expect(find.text('重新上传'), findsOneWidget);
    expect(find.text('图片超过 5MB，请换一张或压缩后再传'), findsOneWidget);
    await unmount(tester);
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

  group('AI 润色', () {
    testWidgets('服务为 null（开关关/模型未就绪）→ 入口隐藏', (tester) async {
      await pumpCompose(tester); // polishService 默认 null
      expect(find.text('AI 润色'), findsNothing);
      await unmount(tester);
    });

    testWidgets('空文本禁用；成功回填输入框，snackbar 撤销恢复原文', (tester) async {
      final polish = FakePostPolishService(const PostPolishOk('润色后的文案'));
      await pumpCompose(tester, polishService: polish);
      final button = find.widgetWithText(TextButton, 'AI 润色');
      expect(
        tester.widget<TextButton>(button).onPressed,
        isNull,
        reason: '空文本不可润色',
      );
      await tester.enterText(find.byType(TextField), '原始文案');
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(polish.lastText, '原始文案');
      expect(find.text('润色后的文案'), findsOneWidget); // 已回填输入框

      // snackbar「撤销润色」→ 回填原文。
      await tester.tap(find.text('撤销润色'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '原始文案',
      );
      await unmount(tester);
    });

    testWidgets('带配图润色把图片字节传给服务；失败提示且不改写原文', (tester) async {
      pickedPhoto = pngBytes;
      final polish = FakePostPolishService(
        const PostPolishUnavailable('model_missing'),
      );
      await pumpCompose(tester, polishService: polish);
      await tester.tap(find.text('添加图片'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '带图打卡');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'AI 润色'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(polish.lastImage, pngBytes);
      expect(find.text('润色失败，请稍后重试'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '带图打卡',
      ); // 原文未被改写
      await unmount(tester);
    });

    testWidgets('润色等待期间继续编辑：旧结果不得覆盖新文字', (tester) async {
      final polish = FakePostPolishService(const PostPolishOk('过期润色结果'));
      final gate = Completer<PostPolishResult>();
      polish.gate = gate;
      await pumpCompose(tester, polishService: polish);
      await tester.enterText(find.byType(TextField), '原始文案');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'AI 润色'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '用户继续编辑的新文案');
      await tester.pump();

      gate.complete(const PostPolishOk('过期润色结果'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '用户继续编辑的新文案',
      );
      expect(find.text('已完成润色'), findsNothing);
      expect(find.text('撤销润色'), findsNothing);
      await unmount(tester);
    });
  });

  group('匿名发布', () {
    testWidgets('默认关闭：无头像选择；开启后展开预设头像，选中后发布透传', (tester) async {
      await pumpCompose(tester);
      expect(find.text('匿名发布'), findsOneWidget);
      expect(find.text('选择头像'), findsNothing); // 关闭态整段收起

      await tester.tap(find.text('匿名发布'));
      await tester.pump();
      expect(find.text('选择头像'), findsOneWidget);

      // 选第 4 个头像（下标 3 = 静坐）
      await tester.tap(find.byIcon(Icons.self_improvement));
      await tester.pump();
      final avatar = tester.widget<CircleAvatar>(
        find
            .ancestor(
              of: find.byIcon(Icons.self_improvement),
              matching: find.byType(CircleAvatar),
            )
            .first,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.self_improvement)).color,
        readableForeground(avatar.backgroundColor!),
      );
      await tester.enterText(find.byType(TextField), '匿名打卡');
      await tester.tap(find.text('发布'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastAnonymous, isTrue);
      expect(api.lastAvatarId, 3);
      await unmount(tester);
    });

    testWidgets('不开匿名直接发布：anonymous=false、avatarId=null', (tester) async {
      await pumpCompose(tester);
      await tester.enterText(find.byType(TextField), '实名打卡');
      await tester.tap(find.text('发布'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.lastAnonymous, isFalse);
      expect(api.lastAvatarId, isNull);
      await unmount(tester);
    });
  });
}
