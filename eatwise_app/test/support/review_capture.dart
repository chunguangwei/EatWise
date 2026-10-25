import 'dart:io';
import 'dart:ui' as ui;

import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Optional local visual evidence. CI remains font/platform independent.
/// Pass --dart-define=REVIEW_FONT=/path/to/a/CJK/font to capture screenshots.
const _fontPath = String.fromEnvironment('REVIEW_FONT');
bool? _previousDisableShadows;

Future<void> loadReviewFont() async {
  if (_fontPath.isEmpty) return;
  final bytes = await File(_fontPath).readAsBytes();
  // Replace the test font only during explicit local visual review.
  final loader = FontLoader('Review')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
  final icons = await File(
    '../.tooling/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(icons)))).load();
}

ThemeData reviewTheme(ThemeData theme) {
  if (_fontPath.isEmpty) return theme;
  _previousDisableShadows = debugDisableShadows;
  debugDisableShadows = false;
  final styles = theme.extension<AppTextStyles>()!;
  return theme.copyWith(
    extensions: [
      ...theme.extensions.values.where((value) => value is! AppTextStyles),
      styles.copyWith(
        textXs: styles.textXs.copyWith(fontFamily: 'Review'),
        textSm: styles.textSm.copyWith(fontFamily: 'Review'),
        textBase: styles.textBase.copyWith(fontFamily: 'Review'),
        textLg: styles.textLg.copyWith(fontFamily: 'Review'),
        textXl: styles.textXl.copyWith(fontFamily: 'Review'),
        text2xl: styles.text2xl.copyWith(fontFamily: 'Review'),
        text3xl: styles.text3xl.copyWith(fontFamily: 'Review'),
        textH1: styles.textH1.copyWith(fontFamily: 'Review'),
        textDisplay: styles.textDisplay.copyWith(fontFamily: 'Review'),
      ),
    ],
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Review',
      ),
    ),
    textTheme: theme.textTheme.apply(fontFamily: 'Review'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Review'),
  );
}

Future<void> captureReview(
  WidgetTester tester,
  String name, {
  Finder? boundaryFinder,
}) async {
  if (_fontPath.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    boundaryFinder ?? find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('build/review-2026-10-25/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  debugDisableShadows = _previousDisableShadows ?? true;
}
