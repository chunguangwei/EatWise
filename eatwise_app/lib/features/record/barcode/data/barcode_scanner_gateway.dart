import 'package:eatwise/features/record/barcode/presentation/barcode_scan_page.dart';
import 'package:flutter/material.dart';

/// 扫码页返回结果（sealed：条码 / 用户取消 / 相机权限拒绝）。
sealed class BarcodeScanResult {
  const BarcodeScanResult();
}

/// 识别（或手动输入）到一个条码。
final class BarcodeScanCode extends BarcodeScanResult {
  const BarcodeScanCode(this.code);

  /// 原始条码（未校验，交由查询流程统一校验）。
  final String code;
}

/// 用户主动退出扫码页（不丢已输入内容，静默返回）。
final class BarcodeScanCancelled extends BarcodeScanResult {
  const BarcodeScanCancelled();
}

/// 相机权限被拒绝（插件在扫码页内报出）。
final class BarcodeScanDenied extends BarcodeScanResult {
  const BarcodeScanDenied();
}

/// 相机权限拒绝异常（流程层据此弹降级说明卡，§4.3）。
final class BarcodePermissionDeniedException implements Exception {
  const BarcodePermissionDeniedException();
}

/// 扫码入口抽象（生产 mobile_scanner；测试 override 为 fake，
/// 与 PhotoPickerGateway 同一模式）。
abstract interface class BarcodeScannerGateway {
  /// 打开扫码流程，返回识别/手动输入的条码；取消返回 null；
  /// 权限拒绝抛 [BarcodePermissionDeniedException]。
  Future<String?> scan(BuildContext context);
}

/// mobile_scanner 实现：全屏推入扫码页（取景框 + 照明灯 + 手动输码）。
final class MobileScannerBarcodeGateway implements BarcodeScannerGateway {
  @override
  Future<String?> scan(BuildContext context) async {
    final result = await Navigator.of(context).push<BarcodeScanResult>(
      MaterialPageRoute<BarcodeScanResult>(
        builder: (_) => const BarcodeScanPage(),
      ),
    );
    return switch (result) {
      BarcodeScanCode(code: final code) => code,
      BarcodeScanDenied() => throw const BarcodePermissionDeniedException(),
      BarcodeScanCancelled() || null => null,
    };
  }
}
