import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/features/record/barcode/data/barcode_food_service.dart';
import 'package:eatwise/features/record/barcode/data/barcode_scanner_gateway.dart';
import 'package:eatwise/features/record/barcode/domain/barcode_rules.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_providers.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_strings.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_sheet.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「扫码记」入口流程（食物库扩充第一层方案）。
///
/// 步骤：扫码（含手动输码）→ 服务端 /foods/barcode/{code}（OFF 代理）→
/// 命中预填记录结果卡（recordSelectedFoodProvider，EntrySource.barcode）；
/// 未收录（404）给「手动搜索 / 添加自定义食物」双动作（条码预填别名〔假设〕）；
/// 权限拒绝走 §4.3 降级说明卡（不阻断核心闭环，参考 photo_flow）。
Future<void> startBarcodeScan(BuildContext context, WidgetRef ref) async {
  final bs = BarcodeStrings.of(context);
  String? code;
  try {
    code = await ref.read(barcodeScannerGatewayProvider).scan(context);
  } on BarcodePermissionDeniedException {
    if (context.mounted) await showBarcodePermissionDeniedCard(context, bs);
    return;
  }
  // 用户主动退出扫码页：静默返回，不动任何已输入内容。
  if (code == null || !context.mounted) return;
  await applyBarcodeLookup(context, ref, code);
}

/// 条码 → 查询 → 结果承接（扫码命中与手动输码共用；手动输码测试直达此层）。
Future<void> applyBarcodeLookup(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  final bs = BarcodeStrings.of(context);
  final trimmed = code.trim();
  if (!isValidBarcode(trimmed)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(bs.invalid)));
    return;
  }
  final outcome = await ref.read(barcodeFoodServiceProvider).lookup(trimmed);
  if (!context.mounted) return;
  switch (outcome) {
    case BarcodeLookupHit(food: final food):
      // 命中：预填结果卡；份量必填留空（与手动搜索/自定义食物口径一致）。
      ref.read(recordSelectedFoodProvider.notifier).state = food;
      ref.read(recordAmountTextProvider.notifier).state = '';
      ref.read(recordEntrySourceProvider.notifier).state = EntrySource.barcode;
      ref.read(recordLowConfidenceProvider.notifier).state = false;
    case BarcodeLookupNotFound():
      await _showBarcodeNotFoundCard(context, ref, bs, trimmed);
    case BarcodeLookupUnavailable(message: final message):
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 未收录双动作卡：「手动搜索」（回搜索框）/「添加自定义食物」（预填条码别名）。
Future<void> _showBarcodeNotFoundCard(
  BuildContext context,
  WidgetRef ref,
  BarcodeStrings bs,
  String code,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(bs.notFoundTitle),
      content: Text(bs.notFoundBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(bs.notFoundSearch),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            if (context.mounted) {
              unawaited(startCustomFoodFlow(context, ref, barcodeAlias: code));
            }
          },
          child: Text(bs.notFoundCustom),
        ),
      ],
    ),
  );
}

/// 相机权限拒绝降级说明卡（§4.3：「去开启」/「手动搜索」双按钮，
/// 与拍照权限降级卡同构）。
Future<void> showBarcodePermissionDeniedCard(
  BuildContext context,
  BarcodeStrings bs,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(bs.deniedTitle),
      content: Text(bs.deniedBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(bs.useManual),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(AppSettings.openAppSettings());
          },
          child: Text(bs.openSettings),
        ),
      ],
    ),
  );
}
