import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:flutter/material.dart';

/// 份量（克）输入框统一装饰（真机走查：填充底+无边框的样式不像输入框，
/// 用户不知道份量可点改）。
///
/// 明确输入框形态：可见描边（[AppColors.border]）+「克/g」单位后缀 +
/// 标签上浮；点击即聚焦弹键盘（TextField 默认）。食物详情弹层 / 记录页
/// 结果卡 / 拍照明细行三处份量录入共用，校验语义（空/≤0 → 确认禁用 +
/// 行内提示）由调用方维持不变。
InputDecoration portionInputDecoration({
  required Translations t,
  required AppColors colors,
  required AppRadii radii,
  String? helperText,
  bool dense = false,
  Color? fillColor,
  bool showLabel = true,
}) {
  return InputDecoration(
    labelText: showLabel ? t.record.amount.label : null,
    // 份量必填行内引导（空/非法时提示，与确认禁用态联动）。
    helperText: helperText,
    suffixText: t.record.nutrition.gramUnit,
    isDense: dense,
    filled: true,
    fillColor: fillColor ?? colors.bgSecondary,
    border: OutlineInputBorder(
      borderRadius: radii.rMd,
      // 可见描边（不再 BorderSide.none）：输入框形态可感知。
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radii.rMd,
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radii.rMd,
      borderSide: BorderSide(color: colors.brandPrimary, width: 2),
    ),
  );
}
