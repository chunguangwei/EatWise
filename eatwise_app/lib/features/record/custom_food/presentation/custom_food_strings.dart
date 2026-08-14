import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/storage/database.dart';
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

  /// record.customFood.estimateFallbackNotice
  String get estimateFallbackNotice =>
      _t.record.customFood.estimateFallbackNotice;

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

  /// record.customFood.savedOnline
  String get savedOnline => _t.record.customFood.savedOnline;

  /// record.customFood.shareOptIn
  String get shareOptIn => _t.record.customFood.shareOptIn;

  /// record.customFood.shareAction
  String get shareAction => _t.record.customFood.shareAction;

  /// record.customFood.submittedReview
  String get submittedReview => _t.record.customFood.submittedReview;

  /// record.customFood.badgePending
  String get badgePending => _t.record.customFood.badgePending;

  /// record.customFood.badgeApproved
  String get badgeApproved => _t.record.customFood.badgeApproved;

  /// record.customFood.badgeRejected
  String get badgeRejected => _t.record.customFood.badgeRejected;

  /// record.customFood.badgeCommunity
  String get badgeCommunity => _t.record.customFood.badgeCommunity;

  /// 搜索结果行状态标签（K2 众包；null = 不显示标签）：
  /// 自定义食物按贡献状态分「自定义/审核中/已共享/未通过」；
  /// 非自定义但下行标记 approved 的为他人贡献的社区食物（「社区」）。
  String? badgeFor(Food food) {
    if (food.isCustom) {
      return switch (food.contributionStatus) {
        'pending' => badgePending,
        'approved' => badgeApproved,
        'rejected' => badgeRejected,
        _ => badge,
      };
    }
    if (food.contributionStatus == 'approved') return badgeCommunity;
    return null;
  }

  /// common.action.save
  String get saveAction => _t.common.action.save;
}
