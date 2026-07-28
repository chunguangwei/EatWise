import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// M3 记录页文案（i18n key：`record.*`，slang 生成产物的薄封装）。
///
/// 集成说明：`i18n/strings_*.i18n.json` 已深合并全部命名空间 key（namespaces:
/// false，代码生成走 `dart run slang`），本类仅代理生成的 `t.record.*`，
/// 保留原桥接 API 形态以不变更调用点。
final class RecordStrings {
  const RecordStrings._(this._t);

  final Translations _t;

  /// 按当前 slang 语言取记录页文案（D-15：跟随 LocaleSettings 即时切换）。
  static RecordStrings of(BuildContext context) {
    return RecordStrings._(Translations.of(context));
  }

  /// record.page.title
  String get pageTitle => _t.record.page.title;

  /// record.page.confirm
  String get confirm => _t.record.page.confirm;

  /// record.page.loggedToday
  String loggedToday(int count) => _t.record.page.loggedToday(count: count);

  /// record.page.todayKcal
  String todayKcal(int kcal) => _t.record.page.todayKcal(kcal: kcal);

  /// record.entries.photo
  String get entryPhoto => _t.record.entries.photo;

  /// record.entries.voice
  String get entryVoice => _t.record.entries.voice;

  /// record.entries.frequent
  String get entryFrequent => _t.record.entries.frequent;

  /// record.entries.comingSoon
  String get comingSoon => _t.record.entries.comingSoon;

  /// record.pending.banner
  String pendingBanner(int count) => _t.record.pending.banner(count: count);

  /// record.search.hint
  String get searchHint => _t.record.search.hint;

  /// record.search.empty
  String get searchEmpty => _t.record.search.empty;

  /// record.amount.label
  String get amountLabel => _t.record.amount.label;

  /// record.amount.invalid
  String get amountInvalid => _t.record.amount.invalid;

  /// record.nutrition.kcal
  String get nutritionKcal => _t.record.nutrition.kcal;

  /// record.nutrition.protein
  String get nutritionProtein => _t.record.nutrition.protein;

  /// record.nutrition.carb
  String get nutritionCarb => _t.record.nutrition.carb;

  /// record.nutrition.fat
  String get nutritionFat => _t.record.nutrition.fat;

  /// record.nutrition.kcalUnit
  String get kcalUnit => _t.record.nutrition.kcalUnit;

  /// record.nutrition.gramUnit
  String get gramUnit => _t.record.nutrition.gramUnit;

  /// record.toast.recorded
  String get toastRecorded => _t.record.toast.recorded;

  /// record.toast.undo
  String get toastUndo => _t.record.toast.undo;

  /// record.toast.undone
  String get toastUndone => _t.record.toast.undone;

  /// record.toast.syncFailed
  String get toastSyncFailed => _t.record.toast.syncFailed;
}
