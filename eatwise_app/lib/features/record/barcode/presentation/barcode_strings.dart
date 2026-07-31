import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// 条码扫码文案（i18n key：`record.barcode.*`，slang 生成产物薄封装，
/// 与 RecordStrings 同法）。
final class BarcodeStrings {
  const BarcodeStrings._(this._t);

  final Translations _t;

  /// 按当前 slang 语言取文案（D-15：跟随 LocaleSettings 即时切换）。
  static BarcodeStrings of(BuildContext context) {
    return BarcodeStrings._(Translations.of(context));
  }

  /// record.barcode.entry（记录页第四入口标签）
  String get entry => _t.record.barcode.entry;

  /// record.barcode.title
  String get title => _t.record.barcode.title;

  /// record.barcode.torch
  String get torch => _t.record.barcode.torch;

  /// record.barcode.manualInput
  String get manualInput => _t.record.barcode.manualInput;

  /// record.barcode.manualTitle
  String get manualTitle => _t.record.barcode.manualTitle;

  /// record.barcode.manualHint
  String get manualHint => _t.record.barcode.manualHint;

  /// record.barcode.manualConfirm
  String get manualConfirm => _t.record.barcode.manualConfirm;

  /// record.barcode.invalid
  String get invalid => _t.record.barcode.invalid;

  /// record.barcode.notFoundTitle
  String get notFoundTitle => _t.record.barcode.notFoundTitle;

  /// record.barcode.notFoundBody
  String get notFoundBody => _t.record.barcode.notFoundBody;

  /// record.barcode.notFoundSearch
  String get notFoundSearch => _t.record.barcode.notFoundSearch;

  /// record.barcode.notFoundCustom
  String get notFoundCustom => _t.record.barcode.notFoundCustom;

  /// record.barcode.unavailable
  String get unavailable => _t.record.barcode.unavailable;

  /// record.barcode.deniedTitle
  String get deniedTitle => _t.record.barcode.deniedTitle;

  /// record.barcode.deniedBody
  String get deniedBody => _t.record.barcode.deniedBody;

  /// record.barcode.openSettings
  String get openSettings => _t.record.barcode.openSettings;

  /// record.barcode.useManual
  String get useManual => _t.record.barcode.useManual;

  /// common.action.cancel（D-15 统一动作词）
  String get cancelAction => _t.common.action.cancel;
}
