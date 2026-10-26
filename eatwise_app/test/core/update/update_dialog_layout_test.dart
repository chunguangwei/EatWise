import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/update/update_dialog.dart';
import 'package:eatwise/core/update/update_downloader.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _notesEnd = 'END / 说明结束';

String _longNotes(bool isEn) => <String>[
  for (var index = 1; index <= 35; index++)
    isEn
        ? '$index. Improve food recording, nutrition details and community review. '
              'Keep your records available while switching between pages.'
        : '$index. 优化食物记录、营养详情和社区审核。切换页面后继续输入，'
              '同时保留记录内容和当前份量，改善小屏设备的显示效果。',
  _notesEnd,
].join('\n');

AppVersionInfo _info() => AppVersionInfo(
  latestVersion: '1.17.12',
  minSupportedVersion: '1.0.0',
  releaseNotesZh: _longNotes(false),
  releaseNotesEn: _longNotes(true),
  apkUrl: 'https://example.com/update.apk',
  publishedAt: null,
  source: 'github',
);

Future<void> _openDialog(
  WidgetTester tester, {
  required Size size,
  required AppLocale locale,
  required bool dark,
  UpdateDownloader? downloader,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  LocaleSettings.setLocaleSync(locale);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateDialog(
                context,
                UpdateCheckResult(
                  status: UpdateStatus.available,
                  info: _info(),
                ),
                downloader: downloader,
                platform: 'android',
              ),
              child: const Text('open-update'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-update'));
  await tester.pumpAndSettle();
}

Finder get _surface => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

void _expectContained(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.5));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.5));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.5));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.5));
}

void _expectActionsInDialog(
  WidgetTester tester,
  Size size, {
  required String primary,
  required String later,
}) {
  expect(tester.takeException(), isNull);
  expect(_surface, findsOneWidget);
  final bounds = tester.getRect(_surface);
  _expectContained(bounds, Offset.zero & size);
  final viewport = tester.getRect(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(SingleChildScrollView),
    ),
  );
  for (final label in [primary, later]) {
    // Match each concrete button without depending on AlertDialog's OverflowBar.
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(
      button.hitTestable(),
      findsOneWidget,
      reason: '$label must be tappable',
    );
    final buttonBounds = tester.getRect(button);
    _expectContained(buttonBounds, bounds);
    expect(
      viewport.bottom,
      lessThanOrEqualTo(buttonBounds.top + 0.5),
      reason: 'Scrollable content must end above $label',
    );
  }
}

Future<void> _scrollToNotesEnd(
  WidgetTester tester, {
  required String notes,
}) async {
  final scrollView = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(SingleChildScrollView),
  );
  expect(scrollView, findsOneWidget);
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: scrollView, matching: find.byType(Scrollable)),
  );
  expect(scrollable.position.maxScrollExtent, greaterThan(0));
  for (
    var attempt = 0;
    attempt < 12 && scrollable.position.extentAfter > 0.5;
    attempt++
  ) {
    await tester.drag(scrollView, const Offset(0, -5000));
    await tester.pumpAndSettle();
  }
  expect(scrollable.position.extentAfter, lessThanOrEqualTo(0.5));

  // The complete Text has a tall render box by design. Check the actual glyph
  // boxes of the last line, after a real drag, against the clipped viewport.
  final paragraph = tester.renderObject<RenderParagraph>(find.text(notes));
  final lastLine = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: notes.lastIndexOf(_notesEnd),
      extentOffset: notes.length,
    ),
  );
  expect(lastLine, isNotEmpty);
  final viewport = tester.getRect(scrollView);
  for (final box in lastLine) {
    final local = box.toRect();
    final visibleLine = paragraph.localToGlobal(local.topLeft) & local.size;
    _expectContained(visibleLine, viewport);
    _expectContained(visibleLine, tester.getRect(_surface));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.zhCn));

  for (final locale in [AppLocale.zhCn, AppLocale.en]) {
    final isEn = locale == AppLocale.en;
    final updateNow = isEn ? 'Update now' : '立即更新';
    final later = isEn ? 'Later' : '以后再说';
    for (final dark in [false, true]) {
      for (final size in [
        const Size(360, 640),
        const Size(320, 568),
        const Size(640, 360),
      ]) {
        testWidgets('长更新说明可滚动且按钮不重叠 ${locale.name} dark=$dark $size 2倍字', (
          tester,
        ) async {
          await _openDialog(tester, size: size, locale: locale, dark: dark);
          _expectActionsInDialog(
            tester,
            size,
            primary: updateNow,
            later: later,
          );
          await _scrollToNotesEnd(tester, notes: _longNotes(isEn));
          _expectActionsInDialog(
            tester,
            size,
            primary: updateNow,
            later: later,
          );
          await tester.tap(find.text(later));
          await tester.pumpAndSettle();
          expect(find.byType(UpdateDialog), findsNothing);
        });
      }

      for (final atEnd in [false, true]) {
        testWidgets(
          '长说明${atEnd ? '末尾' : '顶部'}开始下载与失败状态可见，下载期禁止关闭 ${locale.name} dark=$dark',
          (tester) async {
            final directory = Completer<Directory>();
            // The injected directory operation holds the real final downloader in
            // flight without any HTTP or filesystem activity.
            directory.future.ignore();
            addTearDown(() {
              if (!directory.isCompleted) {
                directory.completeError(StateError('test disposed'));
              }
            });
            final downloader = UpdateDownloader(
              dio: Dio(),
              tempDir: () => directory.future,
              acquireWakelock: () async {},
              releaseWakelock: () async {},
            );
            const size = Size(360, 640);
            await _openDialog(
              tester,
              size: size,
              locale: locale,
              dark: dark,
              downloader: downloader,
            );
            if (atEnd) {
              await _scrollToNotesEnd(tester, notes: _longNotes(isEn));
            }
            await tester.tap(find.text(updateNow));
            await tester.pump();
            final strings = LocaleSettings.currentLocale.translations.update;
            expect(
              find.text(strings.downloadingNoProgress).hitTestable(),
              findsOneWidget,
            );
            expect(
              find.byType(LinearProgressIndicator).hitTestable(),
              findsOneWidget,
            );
            expect(find.text(updateNow), findsNothing);
            expect(tester.takeException(), isNull);

            await tester.tapAt(const Offset(4, 4));
            await tester.pump();
            expect(find.byType(UpdateDialog), findsOneWidget);
            expect(
              ModalRoute.of(
                tester.element(find.byType(UpdateDialog)),
              )?.isCurrent,
              isTrue,
            );
            await tester.binding.handlePopRoute();
            await tester.pump();
            expect(find.byType(UpdateDialog), findsOneWidget);
            expect(
              ModalRoute.of(
                tester.element(find.byType(UpdateDialog)),
              )?.isCurrent,
              isTrue,
            );

            directory.completeError(StateError('controlled download failure'));
            await tester.pumpAndSettle();
            expect(
              find.text(strings.downloadFailed).hitTestable(),
              findsOneWidget,
            );
            _expectActionsInDialog(
              tester,
              size,
              primary: strings.retry,
              later: later,
            );
            await tester.tapAt(const Offset(4, 4));
            await tester.pumpAndSettle();
            expect(find.byType(UpdateDialog), findsNothing);
          },
        );
      }
    }
  }

  testWidgets('下载保活初始化抛异常后显示失败并恢复重试与关闭', (tester) async {
    final downloader = UpdateDownloader(
      dio: Dio(),
      acquireWakelock: () async => throw StateError('wakelock unavailable'),
      releaseWakelock: () async {},
    );
    const size = Size(360, 640);
    await _openDialog(
      tester,
      size: size,
      locale: AppLocale.zhCn,
      dark: false,
      downloader: downloader,
    );
    await tester.tap(find.text('立即更新'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find
          .text(LocaleSettings.currentLocale.translations.update.downloadFailed)
          .hitTestable(),
      findsOneWidget,
    );
    _expectActionsInDialog(tester, size, primary: '重试', later: '以后再说');
    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
  });
}
