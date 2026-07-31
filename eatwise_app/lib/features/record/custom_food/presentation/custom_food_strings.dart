import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// K2 自定义食物文案（i18n key：`record.customFood.*`，slang 生成产物薄封装，
/// 与 RecordStrings 同法）。
final class CustomFoodStrings {
  const CustomFoodStrings._(this._t);

  final Translations _t;

  /// 按当前 slang 语言取文案（D-15：跟随 LocaleSettings 即时切换）。
  static CustomFoodStrings of(BuildContext context) {
    return CustomFoodStrings._(Translations.of(context));
  }

  /// record.customFood.cta
  String get cta => _t.record.customFood.cta;

  /// record.customFood.badge
  String get badge => _t.record.customFood.badge;

  /// record.customFood.title
  String get title => _t.record.customFood.title;

  /// record.customFood.nameLabel
  String get nameLabel => _t.record.customFood.nameLabel;

  /// record.customFood.nameRequired
  String get nameRequired => _t.record.customFood.nameRequired;

  /// record.customFood.aliasLabel
  String get aliasLabel => _t.record.customFood.aliasLabel;

  /// record.customFood.estimate
  String get estimate => _t.record.customFood.estimate;

  /// record.customFood.estimating
  String get estimating => _t.record.customFood.estimating;

  /// record.customFood.estimateBadge
  String get estimateBadge => _t.record.customFood.estimateBadge;

  /// record.customFood.estimateLow
  String get estimateLow => _t.record.customFood.estimateLow;

  /// record.customFood.estimateUnavailable
  String get estimateUnavailable => _t.record.customFood.estimateUnavailable;

  /// record.customFood.kcalLabel
  String get kcalLabel => _t.record.customFood.kcalLabel;

  /// record.customFood.proteinLabel
  String get proteinLabel => _t.record.customFood.proteinLabel;

  /// record.customFood.carbLabel
  String get carbLabel => _t.record.customFood.carbLabel;

  /// record.customFood.fatLabel
  String get fatLabel => _t.record.customFood.fatLabel;

  /// record.customFood.nutritionRequired
  String get nutritionRequired => _t.record.customFood.nutritionRequired;

  /// record.customFood.kcalRange
  String get kcalRange => _t.record.customFood.kcalRange;

  /// record.customFood.macroRange
  String get macroRange => _t.record.customFood.macroRange;

  /// record.customFood.savedOffline
  String get savedOffline => _t.record.customFood.savedOffline;

  /// common.action.save
  String get saveAction => _t.common.action.save;
}
