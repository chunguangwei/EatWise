import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/barcode/domain/barcode_rules.dart';
import 'package:eatwise/features/record/barcode/presentation/barcode_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 手动输码对话框（扫码页入口 + 权限降级入口共用）。
///
/// 仅接受数字输入；确认时按 8–14 位校验，非法则原地提示不关闭；
/// 合法返回 trim 后条码，取消返回 null。
Future<String?> showBarcodeManualInput(
  BuildContext context,
  BarcodeStrings bs,
) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _BarcodeManualInputDialog(bs: bs),
  );
}

class _BarcodeManualInputDialog extends StatefulWidget {
  const _BarcodeManualInputDialog({required this.bs});

  final BarcodeStrings bs;

  @override
  State<_BarcodeManualInputDialog> createState() =>
      _BarcodeManualInputDialogState();
}

class _BarcodeManualInputDialogState extends State<_BarcodeManualInputDialog> {
  final TextEditingController _controller = TextEditingController();

  /// 非法条码内联错误（不改弹层状态，只提示）。
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final code = _controller.text.trim();
    if (!isValidBarcode(code)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final bs = widget.bs;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return AlertDialog(
      title: Text(bs.manualTitle, style: textStyles.textLg),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(14),
            ],
            style: textStyles.textBase,
            decoration: InputDecoration(
              hintText: bs.manualHint,
              errorText: _invalid ? bs.invalid : null,
            ),
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            onSubmitted: (_) => _onConfirm(),
          ),
          const SizedBox(height: AppSpacing.s2),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(bs.cancelAction),
        ),
        FilledButton(onPressed: _onConfirm, child: Text(bs.manualConfirm)),
      ],
    );
  }
}
