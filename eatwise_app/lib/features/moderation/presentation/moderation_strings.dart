import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:flutter/widgets.dart';

/// 审批中心文案（i18n key：`moderation.*`，slang 生成产物薄封装，
/// 与 CustomFoodStrings 同法）。
final class ModerationStrings {
  const ModerationStrings._(this._t);

  final Translations _t;

  /// 按当前 slang 语言取文案（D-15：跟随 LocaleSettings 即时切换）。
  static ModerationStrings of(BuildContext context) {
    return ModerationStrings._(Translations.of(context));
  }

  /// moderation.title
  String get title => _t.moderation.title;

  /// moderation.subtitle
  String get subtitle => _t.moderation.subtitle;

  /// moderation.empty
  String get empty => _t.moderation.empty;

  /// moderation.approve
  String get approve => _t.moderation.approve;

  /// moderation.reject
  String get reject => _t.moderation.reject;

  /// moderation.approveConfirm
  String get approveConfirm => _t.moderation.approveConfirm;

  /// moderation.rejectConfirmTitle
  String get rejectConfirmTitle => _t.moderation.rejectConfirmTitle;

  /// moderation.rejectConfirmBody
  String get rejectConfirmBody => _t.moderation.rejectConfirmBody;

  /// moderation.reasonHint
  String get reasonHint => _t.moderation.reasonHint;

  /// moderation.approved
  String get approved => _t.moderation.approved;

  /// moderation.rejected
  String get rejected => _t.moderation.rejected;

  /// moderation.delete
  String get delete => _t.moderation.delete;

  /// moderation.deleteConfirm
  String get deleteConfirm => _t.moderation.deleteConfirm;

  /// moderation.deleted
  String get deleted => _t.moderation.deleted;

  /// moderation.loadFailed
  String get loadFailed => _t.moderation.loadFailed;

  /// moderation.suggestionTitle
  String get suggestionTitle => _t.moderation.suggestionTitle;

  /// moderation.currentTitle
  String get currentTitle => _t.moderation.currentTitle;

  /// moderation.barcodeLabel
  String barcodeLabel(String code) => _t.moderation.barcodeLabel(code: code);

  /// moderation.submittedAt
  String submittedAt(String date) => _t.moderation.submittedAt(date: date);

  /// moderation.per100gSummary
  String per100gSummary({
    required String kcal,
    required String protein,
    required String carb,
    required String fat,
  }) => _t.moderation.per100gSummary(
    kcal: kcal,
    protein: protein,
    carb: carb,
    fat: fat,
  );

  /// 候选类型标签（custom/barcode/correction）。
  String kindLabel(FoodContributionKind kind) => switch (kind) {
    FoodContributionKind.custom => _t.moderation.kindCustom,
    FoodContributionKind.barcode => _t.moderation.kindBarcode,
    FoodContributionKind.correction => _t.moderation.kindCorrection,
  };
}
