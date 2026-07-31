import 'dart:async';

import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/barcode/data/barcode_scanner_gateway.dart';
import 'package:eatwise/features/record/barcode/domain/barcode_rules.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_manual_input.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_strings.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 条码扫码页（mobile_scanner）：取景框 + 照明灯开关 + 手动输码入口。
///
/// 识别到合法条码即 `pop(BarcodeScanCode)`；相机权限被拒绝时
/// `pop(BarcodeScanDenied)`，由流程层弹 §4.3 降级说明卡；
/// 用户主动退出 `pop(BarcodeScanCancelled)`（不丢已输入内容）。
/// 相机权限声明（NSCameraUsageDescription / CAMERA）已在原生工程配置（合规 §3）。
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    // 只识别商品一维码（EAN/UPC/Code128），降低误识别。
    formats: const <BarcodeFormat>[
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
  );

  /// 已出结果（防 onDetect 高频回调重复 pop）。
  bool _resolved = false;

  /// 照明灯开关状态。
  bool _torchOn = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_resolved) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && isValidBarcode(raw)) {
        _resolved = true;
        Navigator.of(context).pop(BarcodeScanCode(raw.trim()));
        return;
      }
    }
  }

  /// 手动输码：返回合法条码即作为扫码结果上抛。
  Future<void> _onManualInput() async {
    final bs = BarcodeStrings.of(context);
    final code = await showBarcodeManualInput(context, bs);
    if (code == null || !mounted || _resolved) return;
    _resolved = true;
    Navigator.of(context).pop(BarcodeScanCode(code));
  }

  @override
  Widget build(BuildContext context) {
    final bs = BarcodeStrings.of(context);
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(bs.title, style: textStyles.textLg),
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              // 相机权限被拒/相机不可用：交给流程层走 §4.3 降级说明卡。
              if (!_resolved) {
                _resolved = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    Navigator.of(context).pop(const BarcodeScanDenied());
                  }
                });
              }
              return const SizedBox.shrink();
            },
          ),
          // 底部操作条：照明灯 + 手动输码（≥44px 触控区）。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          minimumSize: const Size.fromHeight(AppSpacing.s12),
                        ),
                        onPressed: () {
                          unawaited(_controller.toggleTorch());
                          setState(() => _torchOn = !_torchOn);
                        },
                        icon: Icon(
                          _torchOn ? Icons.flash_on : Icons.flash_off_outlined,
                        ),
                        label: Text(bs.torch, style: textStyles.textBase),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(AppSpacing.s12),
                        ),
                        onPressed: () => unawaited(_onManualInput()),
                        icon: const Icon(Icons.keyboard_outlined),
                        label: Text(bs.manualInput, style: textStyles.textBase),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
