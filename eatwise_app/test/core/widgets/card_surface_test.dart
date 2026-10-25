import 'dart:ui' as ui;
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_shadows.dart';
import 'package:eatwise/core/theme/app_theme.dart';
import 'package:eatwise/core/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('Material卡片阴影不覆盖卡片内容底色 $dark', (tester) async {
      final theme = dark ? AppTheme.dark() : AppTheme.light();
      final colors = theme.extension<AppColors>()!;
      final shadows = theme.extension<AppShadows>()!;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 200,
                height: 120,
                child: Material(
                  color: colors.bgSecondary,
                  child: Container(
                    decoration: AppSurfaces.card(
                      colors,
                      shadows,
                      onMaterial: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (60 * image.width + 100) * 4;
        final actual = Color.fromARGB(
          pixels.getUint8(offset + 3),
          pixels.getUint8(offset),
          pixels.getUint8(offset + 1),
          pixels.getUint8(offset + 2),
        );
        expect(actual, colors.bgSecondary);
        image.dispose();
      });
    });
  }
}
