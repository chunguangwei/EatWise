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

  /// record.page.calibrationBadge
  String get calibrationBadge => _t.record.page.calibrationBadge;

  /// record.entries.photo
  String get entryPhoto => _t.record.entries.photo;

  /// record.entries.voice
  String get entryVoice => _t.record.entries.voice;

  /// record.entries.frequent
  String get entryFrequent => _t.record.entries.frequent;

  /// record.entries.exercise
  String get entryExercise => _t.record.entries.exercise;

  /// record.entries.comingSoon
  String get comingSoon => _t.record.entries.comingSoon;

  /// record.pending.banner
  String pendingBanner(int count) => _t.record.pending.banner(count: count);

  /// record.search.hint
  String get searchHint => _t.record.search.hint;

  /// record.search.empty
  String get searchEmpty => _t.record.search.empty;

  /// record.search.clear
  String get searchClear => _t.record.search.clear;

  /// record.search.addRow
  String searchAddRow(String query) => _t.record.search.addRow(query: query);

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

  /// record.photo.pickTitle
  String get photoPickTitle => _t.record.photo.pickTitle;

  /// record.photo.takePhoto
  String get photoTakePhoto => _t.record.photo.takePhoto;

  /// record.photo.fromGallery
  String get photoFromGallery => _t.record.photo.fromGallery;

  /// record.photo.recognizing
  String get photoRecognizing => _t.record.photo.recognizing;

  /// record.photo.unavailable
  String get photoUnavailable => _t.record.photo.unavailable;

  /// record.photo.deniedTitle
  String get photoDeniedTitle => _t.record.photo.deniedTitle;

  /// record.photo.deniedBody
  String get photoDeniedBody => _t.record.photo.deniedBody;

  /// record.photo.openSettings
  String get photoOpenSettings => _t.record.photo.openSettings;

  /// record.photo.useManual
  String get photoUseManual => _t.record.photo.useManual;

  /// record.photo.noFoodTitle
  String get photoNoFoodTitle => _t.record.photo.noFoodTitle;

  /// record.photo.noFoodHint
  String get photoNoFoodHint => _t.record.photo.noFoodHint;

  /// record.photo.gotIt
  String get photoGotIt => _t.record.photo.gotIt;

  /// record.photo.retake
  String get photoRetake => _t.record.photo.retake;

  /// record.photo.recognizingHint
  String get photoRecognizingHint => _t.record.photo.recognizingHint;

  /// record.photo.loadingModel
  String get photoLoadingModel => _t.record.photo.loadingModel;

  /// record.photo.mealConfirmTitle
  String get photoMealConfirmTitle => _t.record.photo.mealConfirmTitle;

  /// record.photo.logAll
  String get photoLogAll => _t.record.photo.logAll;

  /// record.photo.loggedItems
  String photoLoggedItems(int count) =>
      _t.record.photo.loggedItems(count: count);

  /// record.photo.unmatchedItemTag
  String get photoUnmatchedItemTag => _t.record.photo.unmatchedItemTag;

  /// record.photo.labelValueTag
  String get photoLabelValueTag => _t.record.photo.labelValueTag;

  /// record.photo.similarFoodsTitle
  String get photoSimilarFoodsTitle => _t.record.photo.similarFoodsTitle;

  /// record.photo.useThisFood
  String get photoUseThisFood => _t.record.photo.useThisFood;

  /// record.photo.loggedWithPending
  String photoLoggedWithPending(int count, int pending) =>
      _t.record.photo.loggedWithPending(count: count, pending: pending);

  /// record.photo.engineGuideTitle
  String get engineGuideTitle => _t.record.photo.engineGuideTitle;

  /// record.photo.engineGuideBody
  String get engineGuideBody => _t.record.photo.engineGuideBody;

  /// record.photo.engineGuideDownload
  String get engineGuideDownload => _t.record.photo.engineGuideDownload;

  /// record.photo.engineGuideConfigApi
  String get engineGuideConfigApi => _t.record.photo.engineGuideConfigApi;

  /// record.photo.engineGuideManual
  String get engineGuideManual => _t.record.photo.engineGuideManual;

  /// record.voice.listening
  String get voiceListening => _t.record.voice.listening;

  /// record.voice.tapToStart
  String get voiceTapToStart => _t.record.voice.tapToStart;

  /// record.voice.finish
  String get voiceFinish => _t.record.voice.finish;

  /// record.voice.unavailable
  String get voiceUnavailable => _t.record.voice.unavailable;

  /// record.voice.deniedTitle
  String get voiceDeniedTitle => _t.record.voice.deniedTitle;

  /// record.voice.deniedBody
  String get voiceDeniedBody => _t.record.voice.deniedBody;

  /// record.voice.noMatch
  String get voiceNoMatch => _t.record.voice.noMatch;

  /// record.voice.noMatchTyped
  String get voiceNoMatchTyped => _t.record.voice.noMatchTyped;

  /// record.voice.typeInput
  String get voiceTypeInput => _t.record.voice.typeInput;

  /// record.voice.typeHint
  String get voiceTypeHint => _t.record.voice.typeHint;

  /// record.voice.understanding
  String get voiceUnderstanding => _t.record.voice.understanding;

  /// record.voice.recordingNow
  String get voiceRecordingNow => _t.record.voice.recordingNow;

  /// record.voice.transcribingNow
  String get voiceTranscribingNow => _t.record.voice.transcribingNow;

  /// record.voice.transcribeFailed
  String get voiceTranscribeFailed => _t.record.voice.transcribeFailed;

  /// record.voice.retry
  String get voiceRetry => _t.record.voice.retry;

  /// record.voice.useOnDeviceAsr
  String get voiceUseOnDeviceAsr => _t.record.voice.useOnDeviceAsr;

  /// record.voice.loadingModel
  String get voiceLoadingModel => _t.record.voice.loadingModel;

  /// record.voice.downloadTitle
  String get voiceDownloadTitle => _t.record.voice.downloadTitle;

  /// record.voice.noSpeechHint
  String get voiceNoSpeechHint => _t.record.voice.noSpeechHint;

  /// record.voice.errorGeneric
  String get voiceErrorGeneric => _t.record.voice.errorGeneric;

  /// record.frequent.title
  String get frequentTitle => _t.record.frequent.title;

  /// record.frequent.empty
  String get frequentEmpty => _t.record.frequent.empty;

  /// record.frequent.emptyCta
  String get frequentEmptyCta => _t.record.frequent.emptyCta;

  /// record.card.pleaseConfirm
  String get cardPleaseConfirm => _t.record.card.pleaseConfirm;

  /// record.water.title
  String get waterTitle => _t.record.water.title;

  /// record.water.progress
  String waterProgress(int total, int goal) =>
      _t.record.water.progress(total: total, goal: goal);

  /// record.water.quickAddLabel
  String waterQuickAddLabel(int ml) => _t.record.water.quickAddLabel(ml: ml);

  /// record.weight.title
  String get weightTitle => _t.record.weight.title;

  /// record.weight.notLogged
  String get weightNotLogged => _t.record.weight.notLogged;

  /// record.weight.current
  String weightCurrent(String kg) => _t.record.weight.current(kg: kg);

  /// record.weight.tapToEdit
  String get weightTapToEdit => _t.record.weight.tapToEdit;

  /// record.weight.dialogTitle
  String get weightDialogTitle => _t.record.weight.dialogTitle;

  /// record.weight.inputLabel
  String get weightInputLabel => _t.record.weight.inputLabel;

  /// record.weight.inputLabelJin
  String get weightInputLabelJin => _t.record.weight.inputLabelJin;

  /// record.weight.invalid
  String get weightInvalid => _t.record.weight.invalid;

  /// record.weight.invalidJin
  String get weightInvalidJin => _t.record.weight.invalidJin;

  /// record.weight.unitKg
  String get weightUnitKg => _t.record.weight.unitKg;

  /// record.weight.unitJin
  String get weightUnitJin => _t.record.weight.unitJin;

  /// record.weight.bodyFatLabel
  String get bodyFatLabel => _t.record.weight.bodyFatLabel;

  /// record.weight.bodyFatInvalid
  String get bodyFatInvalid => _t.record.weight.bodyFatInvalid;

  /// record.duringFast.badge
  String get duringFastBadge => _t.record.duringFast.badge;

  /// common.action.cancel
  String get cancelAction => _t.common.action.cancel;
}
