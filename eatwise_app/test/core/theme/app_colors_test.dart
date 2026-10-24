import 'package:eatwise/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final colors in <AppColors>[AppColors.light, AppColors.dark]) {
    test('主按钮前景在 ${colors == AppColors.light ? '亮色' : '暗色'}主题达 AA', () {
      expect(
        contrastRatio(colors.actionPrimary, colors.onActionPrimary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('彩色状态格前景在 ${colors == AppColors.light ? '亮色' : '暗色'}主题达 AA', () {
      for (final background in <Color>[
        colors.ringExercise,
        colors.ringStand,
        colors.signalRed,
      ]) {
        expect(
          contrastRatio(background, readableForeground(background)),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  }
}
