///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsEn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsEn _root = this; // ignore: unused_field

	@override 
	TranslationsEn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEn(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$notify$en notify = _Translations$notify$en._(_root);
	@override late final _Translations$onboarding$en onboarding = _Translations$onboarding$en._(_root);
	@override late final _Translations$record$en record = _Translations$record$en._(_root);
	@override late final _Translations$common$en common = _Translations$common$en._(_root);
	@override late final _Translations$fasting$en fasting = _Translations$fasting$en._(_root);
	@override late final _Translations$home$en home = _Translations$home$en._(_root);
	@override late final _Translations$notification$en notification = _Translations$notification$en._(_root);
	@override late final _Translations$nutrition$en nutrition = _Translations$nutrition$en._(_root);
	@override late final _Translations$reports$en reports = _Translations$reports$en._(_root);
	@override late final _Translations$streak$en streak = _Translations$streak$en._(_root);
	@override late final _Translations$settings$en settings = _Translations$settings$en._(_root);
	@override late final _Translations$legal$en legal = _Translations$legal$en._(_root);
	@override late final _Translations$social$en social = _Translations$social$en._(_root);
	@override late final _Translations$auth$en auth = _Translations$auth$en._(_root);
	@override late final _Translations$update$en update = _Translations$update$en._(_root);
}

// Path: notify
class _Translations$notify$en extends Translations$notify$zh_CN {
	_Translations$notify$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$notify$channel$en channel = _Translations$notify$channel$en._(_root);
	@override String get permissionBanner => 'Turn on notifications to get reminded when your eating and fasting windows start';
	@override String get exactAlarmHint => 'Battery-saving policies may delay reminders — allow exact alarms for on-time alerts';
}

// Path: onboarding
class _Translations$onboarding$en extends Translations$onboarding$zh_CN {
	_Translations$onboarding$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$onboarding$quiz$en quiz = _Translations$onboarding$quiz$en._(_root);
	@override late final _Translations$onboarding$plans$en plans = _Translations$onboarding$plans$en._(_root);
	@override late final _Translations$onboarding$recommendation$en recommendation = _Translations$onboarding$recommendation$en._(_root);
	@override late final _Translations$onboarding$science$en science = _Translations$onboarding$science$en._(_root);
}

// Path: record
class _Translations$record$en extends Translations$record$zh_CN {
	_Translations$record$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$record$page$en page = _Translations$record$page$en._(_root);
	@override late final _Translations$record$entries$en entries = _Translations$record$entries$en._(_root);
	@override late final _Translations$record$pending$en pending = _Translations$record$pending$en._(_root);
	@override late final _Translations$record$search$en search = _Translations$record$search$en._(_root);
	@override late final _Translations$record$amount$en amount = _Translations$record$amount$en._(_root);
	@override late final _Translations$record$nutrition$en nutrition = _Translations$record$nutrition$en._(_root);
	@override late final _Translations$record$toast$en toast = _Translations$record$toast$en._(_root);
	@override late final _Translations$record$photo$en photo = _Translations$record$photo$en._(_root);
	@override late final _Translations$record$barcode$en barcode = _Translations$record$barcode$en._(_root);
	@override late final _Translations$record$voice$en voice = _Translations$record$voice$en._(_root);
	@override late final _Translations$record$frequent$en frequent = _Translations$record$frequent$en._(_root);
	@override late final _Translations$record$card$en card = _Translations$record$card$en._(_root);
	@override late final _Translations$record$customFood$en customFood = _Translations$record$customFood$en._(_root);
	@override late final _Translations$record$water$en water = _Translations$record$water$en._(_root);
	@override late final _Translations$record$weight$en weight = _Translations$record$weight$en._(_root);
	@override late final _Translations$record$home$en home = _Translations$record$home$en._(_root);
	@override late final _Translations$record$empty$en empty = _Translations$record$empty$en._(_root);
}

// Path: common
class _Translations$common$en extends Translations$common$zh_CN {
	_Translations$common$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get appName => 'EatWise';
	@override late final _Translations$common$action$en action = _Translations$common$action$en._(_root);
}

// Path: fasting
class _Translations$fasting$en extends Translations$fasting$zh_CN {
	_Translations$fasting$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$fasting$home$en home = _Translations$fasting$home$en._(_root);
	@override late final _Translations$fasting$widget$en widget = _Translations$fasting$widget$en._(_root);
}

// Path: home
class _Translations$home$en extends Translations$home$zh_CN {
	_Translations$home$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$home$tab$en tab = _Translations$home$tab$en._(_root);
	@override late final _Translations$home$data$en data = _Translations$home$data$en._(_root);
	@override late final _Translations$home$community$en community = _Translations$home$community$en._(_root);
	@override late final _Translations$home$profile$en profile = _Translations$home$profile$en._(_root);
}

// Path: notification
class _Translations$notification$en extends Translations$notification$zh_CN {
	_Translations$notification$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$notification$fasting$en fasting = _Translations$notification$fasting$en._(_root);
}

// Path: nutrition
class _Translations$nutrition$en extends Translations$nutrition$zh_CN {
	_Translations$nutrition$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$nutrition$data$en data = _Translations$nutrition$data$en._(_root);
	@override late final _Translations$nutrition$signalCard$en signalCard = _Translations$nutrition$signalCard$en._(_root);
}

// Path: reports
class _Translations$reports$en extends Translations$reports$zh_CN {
	_Translations$reports$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Trends & reports';
	@override String get entry => 'Trends & deep reports';
	@override late final _Translations$reports$trend$en trend = _Translations$reports$trend$en._(_root);
	@override late final _Translations$reports$growth$en growth = _Translations$reports$growth$en._(_root);
	@override late final _Translations$reports$weekly$en weekly = _Translations$reports$weekly$en._(_root);
	@override late final _Translations$reports$monthly$en monthly = _Translations$reports$monthly$en._(_root);
}

// Path: streak
class _Translations$streak$en extends Translations$streak$zh_CN {
	_Translations$streak$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$streak$home$en home = _Translations$streak$home$en._(_root);
	@override late final _Translations$streak$milestone$en milestone = _Translations$streak$milestone$en._(_root);
	@override late final _Translations$streak$kBreak$en kBreak = _Translations$streak$kBreak$en._(_root);
	@override late final _Translations$streak$profile$en profile = _Translations$streak$profile$en._(_root);
}

// Path: settings
class _Translations$settings$en extends Translations$settings$zh_CN {
	_Translations$settings$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Settings';
	@override late final _Translations$settings$language$en language = _Translations$settings$language$en._(_root);
	@override late final _Translations$settings$group$en group = _Translations$settings$group$en._(_root);
	@override late final _Translations$settings$account$en account = _Translations$settings$account$en._(_root);
	@override late final _Translations$settings$privacy$en privacy = _Translations$settings$privacy$en._(_root);
	@override late final _Translations$settings$theme$en theme = _Translations$settings$theme$en._(_root);
	@override late final _Translations$settings$fastingPlan$en fastingPlan = _Translations$settings$fastingPlan$en._(_root);
	@override late final _Translations$settings$reminders$en reminders = _Translations$settings$reminders$en._(_root);
	@override late final _Translations$settings$about$en about = _Translations$settings$about$en._(_root);
	@override late final _Translations$settings$aiModel$en aiModel = _Translations$settings$aiModel$en._(_root);
	@override late final _Translations$settings$onDevice$en onDevice = _Translations$settings$onDevice$en._(_root);
	@override late final _Translations$settings$chain$en chain = _Translations$settings$chain$en._(_root);
}

// Path: legal
class _Translations$legal$en extends Translations$legal$zh_CN {
	_Translations$legal$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get draftNote => '[Pending external confirmation: final legal copy]';
	@override late final _Translations$legal$consent$en consent = _Translations$legal$consent$en._(_root);
	@override late final _Translations$legal$disclaimer$en disclaimer = _Translations$legal$disclaimer$en._(_root);
	@override late final _Translations$legal$privacyPolicy$en privacyPolicy = _Translations$legal$privacyPolicy$en._(_root);
	@override late final _Translations$legal$userAgreement$en userAgreement = _Translations$legal$userAgreement$en._(_root);
}

// Path: social
class _Translations$social$en extends Translations$social$zh_CN {
	_Translations$social$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$social$feed$en feed = _Translations$social$feed$en._(_root);
	@override late final _Translations$social$compose$en compose = _Translations$social$compose$en._(_root);
}

// Path: auth
class _Translations$auth$en extends Translations$auth$zh_CN {
	_Translations$auth$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$auth$login$en login = _Translations$auth$login$en._(_root);
	@override String get logout => 'Sign out';
	@override String get logoutConfirm => 'Sign out now? Unsynced records stay on this device.';
	@override String get loggedOut => 'Signed out';
	@override late final _Translations$auth$register$en register = _Translations$auth$register$en._(_root);
	@override late final _Translations$auth$changePassword$en changePassword = _Translations$auth$changePassword$en._(_root);
	@override late final _Translations$auth$error$en error = _Translations$auth$error$en._(_root);
}

// Path: update
class _Translations$update$en extends Translations$update$zh_CN {
	_Translations$update$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Update available';
	@override String newVersion({required Object version}) => 'Latest version: ${version}';
	@override String get updateNow => 'Update now';
	@override String get later => 'Later';
	@override String get upToDate => 'You\'re on the latest version';
	@override String get checkFailed => 'Couldn\'t check for updates. Try again later.';
	@override String get downloadFailed => 'Couldn\'t open the download link. Try again later.';
}

// Path: notify.channel
class _Translations$notify$channel$en extends Translations$notify$channel$zh_CN {
	_Translations$notify$channel$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$notify$channel$fastingReminders$en fastingReminders = _Translations$notify$channel$fastingReminders$en._(_root);
}

// Path: onboarding.quiz
class _Translations$onboarding$quiz$en extends Translations$onboarding$quiz$zh_CN {
	_Translations$onboarding$quiz$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => '3 quick questions to find your fasting rhythm 🌱';
	@override String progress({required Object step, required Object total}) => 'Question ${step} of ${total}';
	@override String get skip => 'Skip for now';
	@override String get next => 'Continue';
	@override String get finish => 'See my plan';
	@override String get back => 'Back';
	@override late final _Translations$onboarding$quiz$q1$en q1 = _Translations$onboarding$quiz$q1$en._(_root);
	@override late final _Translations$onboarding$quiz$q2$en q2 = _Translations$onboarding$quiz$q2$en._(_root);
	@override late final _Translations$onboarding$quiz$q3$en q3 = _Translations$onboarding$quiz$q3$en._(_root);
}

// Path: onboarding.plans
class _Translations$onboarding$plans$en extends Translations$onboarding$plans$zh_CN {
	_Translations$onboarding$plans$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$onboarding$plans$p14x10$en p14x10 = _Translations$onboarding$plans$p14x10$en._(_root);
	@override late final _Translations$onboarding$plans$p16x8$en p16x8 = _Translations$onboarding$plans$p16x8$en._(_root);
	@override late final _Translations$onboarding$plans$p18x6$en p18x6 = _Translations$onboarding$plans$p18x6$en._(_root);
	@override late final _Translations$onboarding$plans$p5x2$en p5x2 = _Translations$onboarding$plans$p5x2$en._(_root);
}

// Path: onboarding.recommendation
class _Translations$onboarding$recommendation$en extends Translations$onboarding$recommendation$zh_CN {
	_Translations$onboarding$recommendation$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Your recommended plan';
	@override String get mainBadge => 'Top pick';
	@override String get altTitle => 'Worth a try';
	@override String get select => 'Choose this';
	@override String get selected => 'Selected';
	@override String get startNow => 'Start now';
	@override String window({required Object start, required Object end}) => 'Eating window ${start}–${end}';
	@override String get scienceLink => 'How does fasting work?';
	@override String get comingSoon => 'Coming in a later version';
	@override late final _Translations$onboarding$recommendation$reason$en reason = _Translations$onboarding$recommendation$reason$en._(_root);
	@override String get flexibleHint => 'Your schedule isn\'t fixed, so feel free to shift your eating window around your life.';
	@override String fallbackNotice({required Object kcal}) => 'Your daily nutrition goal is estimated at ${kcal} kcal for now — add your height & weight in Profile for a precise target.';
	@override String get planChangeTitle => 'Change fasting plan';
	@override String planChangeConfirm({required Object date}) => 'The new plan takes effect at 00:00 on ${date}. Today still follows your current plan.';
}

// Path: onboarding.science
class _Translations$onboarding$science$en extends Translations$onboarding$science$zh_CN {
	_Translations$onboarding$science$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'How fasting works';
	@override String get card1Title => 'Give your body a break';
	@override String get card1Body => 'During a fast, your body gradually switches to fat-burning mode, running on stored energy.';
	@override String get card2Title => 'A rhythm, not a diet';
	@override String get card2Body => 'Fasting is about when you eat, not what you can\'t eat — eating well inside your window matters.';
	@override String get disclaimer => 'This content is general wellness information, not medical advice. If you are pregnant, breastfeeding, or managing a medical condition, please consult your doctor first.';
	@override String get back => 'Back';
}

// Path: record.page
class _Translations$record$page$en extends Translations$record$page$zh_CN {
	_Translations$record$page$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Records';
	@override String get confirm => 'Log it';
	@override String loggedToday({required Object count}) => '${count} logged today';
	@override String todayKcal({required Object kcal}) => '~${kcal} kcal today (to be calibrated)';
}

// Path: record.entries
class _Translations$record$entries$en extends Translations$record$entries$zh_CN {
	_Translations$record$entries$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get photo => 'Photo';
	@override String get voice => 'Voice';
	@override String get frequent => 'Usual';
	@override String get comingSoon => 'Coming soon — search manually to log for now';
}

// Path: record.pending
class _Translations$record$pending$en extends Translations$record$pending$zh_CN {
	_Translations$record$pending$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String banner({required Object count}) => '${count} record(s) still on the way — will sync when online';
}

// Path: record.search
class _Translations$record$search$en extends Translations$record$search$zh_CN {
	_Translations$record$search$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get hint => 'Search foods (Chinese or English)';
	@override String get empty => 'No match? Try another keyword';
}

// Path: record.amount
class _Translations$record$amount$en extends Translations$record$amount$zh_CN {
	_Translations$record$amount$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get label => 'Amount (g)';
	@override String get invalid => 'Enter an amount greater than 0';
}

// Path: record.nutrition
class _Translations$record$nutrition$en extends Translations$record$nutrition$zh_CN {
	_Translations$record$nutrition$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get kcal => 'Calories';
	@override String get protein => 'Protein';
	@override String get carb => 'Carbs';
	@override String get fat => 'Fat';
	@override String get kcalUnit => 'kcal';
	@override String get gramUnit => 'g';
}

// Path: record.toast
class _Translations$record$toast$en extends Translations$record$toast$zh_CN {
	_Translations$record$toast$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get recorded => 'Logged';
	@override String get undo => 'Undo';
	@override String get undone => 'Undone';
	@override String get syncFailed => 'This record wasn\'t saved — please submit again';
}

// Path: record.photo
class _Translations$record$photo$en extends Translations$record$photo$zh_CN {
	_Translations$record$photo$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get pickTitle => 'Snap to recognize';
	@override String get takePhoto => 'Take photo';
	@override String get fromGallery => 'Choose from album';
	@override String get recognizing => 'Recognizing…';
	@override String get unavailable => 'Recognition isn\'t available right now — a quick manual search works just as well';
	@override String get deniedTitle => 'Camera not allowed';
	@override String get deniedBody => 'No camera? No problem — searching manually is just as fast';
	@override String get openSettings => 'Open Settings';
	@override String get useManual => 'Search manually';
}

// Path: record.barcode
class _Translations$record$barcode$en extends Translations$record$barcode$zh_CN {
	_Translations$record$barcode$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get entry => 'Scan';
	@override String get title => 'Scan product barcode';
	@override String get torch => 'Torch';
	@override String get manualInput => 'Enter manually';
	@override String get manualTitle => 'Enter barcode';
	@override String get manualHint => 'Enter the 8–14 digit code on the package';
	@override String get manualConfirm => 'Look up';
	@override String get invalid => 'Invalid barcode — should be 8–14 digits';
	@override String get looking => 'Looking up…';
	@override String get notFoundTitle => 'Product not found';
	@override String get notFoundBody => 'This product isn\'t in the food library yet. Add its info (snap the nutrition label for review — everyone can scan it once approved), search manually, or add a custom food.';
	@override String get notFoundSearch => 'Search manually';
	@override String get notFoundCustom => 'Add custom food';
	@override String get notFoundContribute => 'Add product info';
	@override String get unavailable => 'Lookup failed. Check your connection and try again';
	@override String get deniedTitle => 'Camera not authorized';
	@override String get deniedBody => 'You can still log by searching or entering the code manually';
	@override String get openSettings => 'Open settings';
	@override String get useManual => 'Search manually';
	@override late final _Translations$record$barcode$contribute$en contribute = _Translations$record$barcode$contribute$en._(_root);
}

// Path: record.voice
class _Translations$record$voice$en extends Translations$record$voice$zh_CN {
	_Translations$record$voice$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get listening => 'Listening… say what you ate, e.g. "a bowl of rice"';
	@override String get tapToStart => 'Tap to start speaking';
	@override String get finish => 'Done';
	@override String get unavailable => 'Speech recognition isn\'t available on this device — typing works just as well';
	@override String get deniedTitle => 'Microphone not allowed';
	@override String get deniedBody => 'No voice? No problem — typing a search is just as fast';
	@override String get noMatch => 'Couldn\'t catch the food — try rephrasing or search manually';
}

// Path: record.frequent
class _Translations$record$frequent$en extends Translations$record$frequent$zh_CN {
	_Translations$record$frequent$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Frequently logged';
	@override String get empty => 'Log a few more meals and your usuals will show up here';
}

// Path: record.card
class _Translations$record$card$en extends Translations$record$card$zh_CN {
	_Translations$record$card$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get pleaseConfirm => 'Please confirm';
}

// Path: record.customFood
class _Translations$record$customFood$en extends Translations$record$customFood$zh_CN {
	_Translations$record$customFood$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get cta => 'Can\'t find it? Add a custom food';
	@override String get badge => 'Custom';
	@override String get title => 'Add custom food';
	@override String get nameLabel => 'Food name';
	@override String get nameRequired => 'Please enter a name';
	@override String get aliasLabel => 'Aliases (optional, comma-separated)';
	@override String get estimate => 'AI estimate';
	@override String get estimating => 'Estimating…';
	@override String get estimateLow => 'Low confidence — please double-check the values';
	@override String get estimateUnavailable => 'Estimate unavailable — please enter values manually';
	@override String get estimateBadgeOnDevice => 'On-device estimate — please confirm';
	@override String get estimateBadgeUserApi => 'Custom API estimate — please confirm';
	@override String get estimateDubious => 'Estimate looks off — please double-check the values';
	@override String get kcalLabel => 'Calories (kcal / 100 g)';
	@override String get proteinLabel => 'Protein (g / 100 g)';
	@override String get carbLabel => 'Carbs (g / 100 g)';
	@override String get fatLabel => 'Fat (g / 100 g)';
	@override String get nutritionRequired => 'Enter a number greater than 0';
	@override String get kcalRange => 'Calories must be between 0 and 900 kcal';
	@override String get macroRange => 'Must be between 0 and 100 g';
	@override String get savedOffline => 'Saved on this device — will sync when online';
	@override String get savedOnline => 'Saved';
	@override String get shareOptIn => 'Share with all users (everyone can find it once approved)';
	@override String get shareAction => 'Share with all users';
	@override String get submittedReview => 'Submitted for review';
	@override String get badgePending => 'In review';
	@override String get badgeApproved => 'Shared';
	@override String get badgeRejected => 'Not approved';
	@override String get badgeCommunity => 'Community';
	@override late final _Translations$record$customFood$contributions$en contributions = _Translations$record$customFood$contributions$en._(_root);
}

// Path: record.water
class _Translations$record$water$en extends Translations$record$water$zh_CN {
	_Translations$record$water$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Water today';
	@override String progress({required Object total, required Object goal}) => '${total} / ${goal} ml';
	@override String quickAddLabel({required Object ml}) => 'Add ${ml} ml of water';
}

// Path: record.weight
class _Translations$record$weight$en extends Translations$record$weight$zh_CN {
	_Translations$record$weight$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Weight';
	@override String get notLogged => 'Log it';
	@override String current({required Object kg}) => '${kg} kg';
	@override String get dialogTitle => 'Log today\'s weight';
	@override String get inputLabel => 'Weight (kg)';
	@override String get invalid => 'Enter a value between 20 and 300';
}

// Path: record.home
class _Translations$record$home$en extends Translations$record$home$zh_CN {
	_Translations$record$home$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Log';
	@override String get logMeal => 'Log a bite';
}

// Path: record.empty
class _Translations$record$empty$en extends Translations$record$empty$zh_CN {
	_Translations$record$empty$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'No food stories yet — tap the orange button to log your first bite?';
}

// Path: common.action
class _Translations$common$action$en extends Translations$common$action$zh_CN {
	_Translations$common$action$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get save => 'Save';
	@override String get cancel => 'Cancel';
	@override String get undo => 'Undo';
	@override String get retry => 'Retry';
	@override String get confirm => 'OK';
}

// Path: fasting.home
class _Translations$fasting$home$en extends Translations$fasting$home$zh_CN {
	_Translations$fasting$home$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Fasting Timer';
	@override String get endFast => 'End fast';
	@override String get extend => 'Extend';
	@override String get startPlan => 'Choose your fasting plan';
	@override String get stateEating => 'Eating window';
	@override String get stateFasting => 'Fasting';
	@override String get stateFastingExtended => 'Fasting · Extended';
	@override String get stateNoPlan => 'No fasting plan yet';
	@override String attribution({required Object date}) => 'This fast counts toward ${date}';
	@override String extendedBadge({required Object minutes}) => 'Extended +${minutes} min';
	@override String get extendLimit => 'You can extend by up to 4 hours per fast';
	@override String planTag({required Object id, required Object start, required Object end}) => '${id} · Eating window ${start}–${end}';
	@override String get noPlanSubtitle => 'Answer 3 quick questions to find your fasting rhythm';
	@override String get celebrationTitle => 'Fast complete! Your body just did a quiet deep-clean ✨';
	@override String get celebrationBadge => 'Fast complete ✨';
	@override String get signalEmpty => 'Nothing logged today — log a bite and your signal lights will show up';
	@override late final _Translations$fasting$home$greeting$en greeting = _Translations$fasting$home$greeting$en._(_root);
	@override late final _Translations$fasting$home$endFastDialog$en endFastDialog = _Translations$fasting$home$endFastDialog$en._(_root);
}

// Path: fasting.widget
class _Translations$fasting$widget$en extends Translations$fasting$widget$zh_CN {
	_Translations$fasting$widget$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String dueEat({required Object time}) => 'Eat at ${time}';
	@override String dueEatEnd({required Object time}) => 'Window ends ${time}';
}

// Path: home.tab
class _Translations$home$tab$en extends Translations$home$tab$zh_CN {
	_Translations$home$tab$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get home => 'Home';
	@override String get record => 'Log';
	@override String get data => 'Stats';
	@override String get community => 'Community';
	@override String get profile => 'Me';
}

// Path: home.data
class _Translations$home$data$en extends Translations$home$data$zh_CN {
	_Translations$home$data$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get emptyTitle => 'Your trends are warming up — log a few days to get them moving.';
	@override String get emptySubtitle => 'Keep logging for a few days and your trends and signal lights will come alive.';
	@override String get cta => 'Log a bite';
}

// Path: home.community
class _Translations$home$community$en extends Translations$home$community$zh_CN {
	_Translations$home$community$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get emptyTitle => 'Waiting for today\'s first check-in to show up.';
	@override String get emptySubtitle => 'Check-ins and challenges are on the way.';
	@override String get cta => 'Check in';
	@override String get comingSoon => 'Community is coming soon — stay tuned';
}

// Path: home.profile
class _Translations$home$profile$en extends Translations$home$profile$zh_CN {
	_Translations$home$profile$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get emptyTitle => 'Your profile is under construction';
	@override String get emptySubtitle => 'Plans, goals and more settings are moving in soon.';
}

// Path: notification.fasting
class _Translations$notification$fasting$en extends Translations$notification$fasting$zh_CN {
	_Translations$notification$fasting$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get eatSoon => 'Eating window opens in 15 min';
	@override String eatStart({required Object date}) => 'Time to eat! This fast counts toward ${date} ✅';
	@override String get fastStart => 'Your fasting window has started — you\'re doing great, keep it up!';
}

// Path: nutrition.data
class _Translations$nutrition$data$en extends Translations$nutrition$data$zh_CN {
	_Translations$nutrition$data$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$nutrition$data$dateSwitcher$en dateSwitcher = _Translations$nutrition$data$dateSwitcher$en._(_root);
	@override late final _Translations$nutrition$data$summary$en summary = _Translations$nutrition$data$summary$en._(_root);
	@override String get localEstimate => 'Local estimate — the cloud fine-tunes it once you\'re online';
	@override late final _Translations$nutrition$data$proDetails$en proDetails = _Translations$nutrition$data$proDetails$en._(_root);
	@override late final _Translations$nutrition$data$trend$en trend = _Translations$nutrition$data$trend$en._(_root);
}

// Path: nutrition.signalCard
class _Translations$nutrition$signalCard$en extends Translations$nutrition$signalCard$zh_CN {
	_Translations$nutrition$signalCard$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$nutrition$signalCard$zone$en zone = _Translations$nutrition$signalCard$zone$en._(_root);
	@override late final _Translations$nutrition$signalCard$advice$en advice = _Translations$nutrition$signalCard$advice$en._(_root);
}

// Path: reports.trend
class _Translations$reports$trend$en extends Translations$reports$trend$zh_CN {
	_Translations$reports$trend$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Growth trends';
	@override late final _Translations$reports$trend$dim$en dim = _Translations$reports$trend$dim$en._(_root);
	@override late final _Translations$reports$trend$range$en range = _Translations$reports$trend$range$en._(_root);
	@override late final _Translations$reports$trend$unit$en unit = _Translations$reports$trend$unit$en._(_root);
	@override String get empty => 'Your trends are warming up — log a few days to get them moving.';
	@override String get ctaRecord => 'Log now';
	@override String get ctaFast => 'Start fasting';
	@override String get ctaWeight => 'Log weight';
}

// Path: reports.growth
class _Translations$reports$growth$en extends Translations$reports$growth$zh_CN {
	_Translations$reports$growth$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String title({required Object days}) => '${days}-day journey';
	@override String get qualifiedDays => 'Fasting goals hit';
	@override String get recordedDays => 'Days logged';
	@override String get avgFasting => 'Avg. fast';
	@override String get weightDelta => 'Weight change';
	@override String get daysUnit => 'd';
	@override String get hourUnit => 'h';
	@override String get kgUnit => 'kg';
	@override String get noValue => '—';
	@override String get empty => 'No footprints yet — log a meal or finish a fast to start.';
}

// Path: reports.weekly
class _Translations$reports$weekly$en extends Translations$reports$weekly$zh_CN {
	_Translations$reports$weekly$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'This week';
	@override String range({required Object start, required Object end}) => '${start} – ${end}';
	@override String qualified({required Object days}) => '${days} days on target';
	@override String entries({required Object count}) => '${count} entries logged';
	@override String greenRatio({required Object percent}) => '${percent}% green lights';
	@override late final _Translations$reports$weekly$cheer$en cheer = _Translations$reports$weekly$cheer$en._(_root);
	@override String get empty => 'Almost there — log a meal or finish a fast to unlock your weekly report.';
}

// Path: reports.monthly
class _Translations$reports$monthly$en extends Translations$reports$monthly$zh_CN {
	_Translations$reports$monthly$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get prevMonth => 'Previous month';
	@override String get nextMonth => 'Next month';
	@override String qualified({required Object days}) => '${days} fasting days on target';
	@override String recordedDays({required Object days}) => '${days} days logged';
	@override String avgFastingHours({required Object hours}) => 'Avg. fast ${hours} h';
	@override String avgFastingHoursMinutes({required Object hours, required Object minutes}) => 'Avg. fast ${hours} h ${minutes} m';
	@override String kcalAvg({required Object kcal, required Object target}) => 'Avg ${kcal} kcal · goal ${target} kcal';
	@override String macros({required Object protein, required Object carbs, required Object fat}) => 'Protein ${protein}g · Carbs ${carbs}g · Fat ${fat}g';
	@override String weightChange({required Object value}) => 'Weight change ${value}';
	@override String get empty => 'No records this month yet';
	@override String get emptyHint => 'Log a meal or finish a fast and your monthly report will bloom.';
}

// Path: streak.home
class _Translations$streak$home$en extends Translations$streak$home$zh_CN {
	_Translations$streak$home$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String streakDays({required Object days}) => '${days}-day streak 🔥';
	@override String get startHint => 'Finish today\'s fast to start day 1';
}

// Path: streak.milestone
class _Translations$streak$milestone$en extends Translations$streak$milestone$zh_CN {
	_Translations$streak$milestone$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String title({required Object days}) => '${days}-day streak! You\'ve outlasted 80% of the community 🎉';
	@override String badgeLabel({required Object days}) => '${days}-day streak';
	@override String get share => 'Share';
	@override String get accept => 'Keep it';
	@override late final _Translations$streak$milestone$shareCard$en shareCard = _Translations$streak$milestone$shareCard$en._(_root);
}

// Path: streak.kBreak
class _Translations$streak$kBreak$en extends Translations$streak$kBreak$zh_CN {
	_Translations$streak$kBreak$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Your streak was interrupted';
	@override String get howItWorks => 'Your streak counts only days you complete your fasting plan (ending up to 15 min early still counts). Meal-log days are tracked separately and don\'t affect your streak. A missed day resets it to 0 — use a Mend Card within 7 days to restore it.';
	@override String cardsLeft({required Object n}) => 'Mend Cards left this month: ${n}';
	@override String mendCta({required Object days}) => 'Use a Mend Card to restore your ${days}-day streak';
	@override String mendSuccess({required Object days}) => 'Streak restored to ${days} days 🎉';
	@override String get mendFailed => 'Couldn\'t use the Mend Card. Please try again later.';
	@override String get exhausted => 'No Mend Cards left this month. You\'ll get 2 new ones on the 1st.';
	@override String get unmendable => 'This miss is over 7 days old and can no longer be mended. Start a fresh streak today!';
	@override String get dismiss => 'Got it, start fresh';
}

// Path: streak.profile
class _Translations$streak$profile$en extends Translations$streak$profile$zh_CN {
	_Translations$streak$profile$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Streak';
	@override String get current => 'Current streak';
	@override String get longest => 'Longest streak';
	@override String get daysUnit => 'days';
	@override String get mendCards => 'Mend Cards';
	@override String mendCardsValue({required Object n}) => '${n} left';
	@override String get mendEntry => 'Mend now';
}

// Path: settings.language
class _Translations$settings$language$en extends Translations$settings$language$zh_CN {
	_Translations$settings$language$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Language';
	@override String get system => 'System';
	@override String get zhCN => '简体中文';
	@override String get en => 'English';
}

// Path: settings.group
class _Translations$settings$group$en extends Translations$settings$group$zh_CN {
	_Translations$settings$group$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get account => 'Account';
	@override String get privacy => 'Privacy';
	@override String get preferences => 'Preferences';
	@override String get reminders => 'Reminders';
	@override String get about => 'About';
}

// Path: settings.account
class _Translations$settings$account$en extends Translations$settings$account$zh_CN {
	_Translations$settings$account$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get cancelDeletion => 'Cancel deletion';
	@override String get changePassword => 'Change password';
	@override String get contributions => 'My contributions';
	@override String get deleteAccount => 'Delete account';
	@override String get deleteConfirmAction => 'Confirm deletion';
	@override String get deleteConfirmBody => 'After deletion, your phone number, profile, and all meal/fasting records will be permanently erased and cannot be recovered. Your request starts a 7-day cooling-off period: signing in during this period cancels the deletion, and your data is erased on day 7.';
	@override String get deleteConfirmTitle => 'Delete your account?';
	@override String get deleteRequested => 'Deletion requested — your account enters a 7-day cooling-off period';
	@override String deleteScheduledBody({required Object date}) => 'Deletion requested. Your account will be erased on ${date}; sign in before then to cancel.';
	@override String get deletionCancelled => 'Deletion cancelled — your account is back to normal';
	@override String deletionScheduled({required Object days}) => 'Deletion scheduled in ${days} day(s) — you can cancel before then';
	@override String get logout => 'Sign out';
	@override String get notLoggedIn => 'Not signed in';
	@override String get phone => 'Phone number';
}

// Path: settings.privacy
class _Translations$settings$privacy$en extends Translations$settings$privacy$zh_CN {
	_Translations$settings$privacy$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get privacyPolicy => 'Privacy Policy';
	@override String get userAgreement => 'Terms of Service';
	@override String get exportData => 'Export my data';
	@override String exportSuccess({required Object path}) => 'Data exported: ${path}';
	@override String get healthData => 'Health data consent';
	@override String get healthDataSubtitle => 'Processing of sensitive personal info such as height/weight and meal/fasting records';
	@override String get healthDataRevoked => 'Health data consent withdrawn — nutrition targets will use defaults';
	@override String get analytics => 'Analytics consent';
	@override String get analyticsSubtitle => 'Anonymous usage stats that help us improve — no health data included';
	@override String get exportFailed => 'Export failed. Check your connection and try again.';
}

// Path: settings.theme
class _Translations$settings$theme$en extends Translations$settings$theme$zh_CN {
	_Translations$settings$theme$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Theme';
	@override String get system => 'System';
	@override String get light => 'Light';
	@override String get dark => 'Dark';
}

// Path: settings.fastingPlan
class _Translations$settings$fastingPlan$en extends Translations$settings$fastingPlan$zh_CN {
	_Translations$settings$fastingPlan$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Fasting plan';
	@override String get subtitle => 'View or change your fasting plan — changes take effect at 00:00 the next day';
}

// Path: settings.reminders
class _Translations$settings$reminders$en extends Translations$settings$reminders$zh_CN {
	_Translations$settings$reminders$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get notifications => 'Notification settings';
	@override String get notificationsSubtitle => 'Manage notification permission in system settings';
}

// Path: settings.about
class _Translations$settings$about$en extends Translations$settings$about$zh_CN {
	_Translations$settings$about$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get version => 'Version';
	@override String get disclaimer => 'Disclaimer & special groups';
	@override String get checkUpdate => 'Check for updates';
}

// Path: settings.aiModel
class _Translations$settings$aiModel$en extends Translations$settings$aiModel$zh_CN {
	_Translations$settings$aiModel$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'AI Model';
	@override String get provider => 'Provider';
	@override late final _Translations$settings$aiModel$providers$en providers = _Translations$settings$aiModel$providers$en._(_root);
	@override String get baseUrl => 'Base URL';
	@override String get model => 'Model';
	@override String get apiKey => 'API Key';
	@override String get apiKeyHint => 'Leave blank to keep unchanged';
	@override String get baseUrlRequired => 'Custom provider requires a Base URL';
	@override String get modelRequired => 'Custom provider requires a model name';
	@override String get save => 'Save';
	@override String get saved => 'AI model configuration saved';
	@override String get test => 'Test connection';
	@override String get testing => 'Testing…';
	@override String get testOk => 'Connection successful — model service is reachable';
	@override String testFail({required Object reason}) => 'Connection failed: ${reason}';
	@override String get testFailNetwork => 'Connection failed: server unreachable — check the Base URL and your network';
	@override String get testFailTimeout => 'Connection failed: timed out — check your network and try again';
	@override String get testFailAuth => 'Connection failed: invalid API Key or insufficient permission';
	@override String get clear => 'Clear configuration';
	@override String get clearConfirmTitle => 'Clear AI model configuration?';
	@override String get clearConfirmBody => 'After clearing, custom food estimates will be unavailable (enable the on-device model or configure again).';
	@override String get clearConfirmAction => 'Clear';
	@override String get cleared => 'AI model configuration cleared';
}

// Path: settings.onDevice
class _Translations$settings$onDevice$en extends Translations$settings$onDevice$zh_CN {
	_Translations$settings$onDevice$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'On-device model';
	@override String get desc => 'Estimate nutrition offline on this device — your data never leaves it';
	@override String get size => 'Model size: ~2.41 GB';
	@override String get wifiHint => 'Large file — Wi-Fi recommended';
	@override String get download => 'Download model';
	@override String downloading({required Object percent}) => 'Downloading ${percent}%';
	@override String get cancel => 'Cancel';
	@override String paused({required Object percent}) => 'Paused (${percent}% downloaded)';
	@override String get resume => 'Resume';
	@override String get delete => 'Delete model';
	@override String get deleteConfirmTitle => 'Delete on-device model?';
	@override String get deleteConfirmBody => 'You\'ll need to re-download the ~2.41 GB model to use on-device estimates again.';
	@override String get deleteConfirmAction => 'Delete';
	@override String get deleted => 'On-device model deleted';
	@override String get ready => 'Model ready';
	@override String get coldLoadHint => 'The first estimate loads the model and may take a few seconds';
	@override String get enabled => 'Prefer on-device estimates';
	@override String get errorDownload => 'Download failed — check your connection and retry';
	@override String get errorStorage => 'Not enough free storage (~6 GB needed) — free up space and retry';
	@override String get errorMemory => 'Not enough device memory for the on-device model';
	@override String get retry => 'Retry';
	@override String get oomDisabled => 'On-device estimates disabled — not enough device memory';
	@override String get statusFailed => 'Failed to read model status';
}

// Path: settings.chain
class _Translations$settings$chain$en extends Translations$settings$chain$zh_CN {
	_Translations$settings$chain$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Estimate routing';
	@override String get onDevice => 'On-device model';
	@override String get userApi => 'Custom API';
	@override String get statusEnabled => 'Enabled';
	@override String get statusDisabled => 'Disabled';
	@override String get statusNotDownloaded => 'Not downloaded';
	@override String get statusDownloading => 'Downloading';
	@override String get statusPaused => 'Paused';
	@override String get statusError => 'Download failed';
	@override String get statusUnknown => 'Not ready';
	@override String get statusConfigured => 'Configured';
	@override String get statusNotConfigured => 'Not configured';
	@override String get current => 'Active';
}

// Path: legal.consent
class _Translations$legal$consent$en extends Translations$legal$consent$zh_CN {
	_Translations$legal$consent$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Welcome to EatWise';
	@override String get summary => 'We collect and use your information as described in the Privacy Policy to provide core features like fasting timers, meal logging, and nutrition feedback. Your data is stored securely in mainland China. Please review and confirm:';
	@override String get agreeMain => 'I have read and agree to the Terms of Service and Privacy Policy';
	@override String get healthTitle => 'Separate consent for health data (optional)';
	@override String get healthBody => 'Your height, weight, age, gender, and meal/fasting records are sensitive personal information. With your separate consent, we use them to calculate personalized nutrition targets and feedback, stored encrypted in mainland China. You may decline (targets will use default values) or withdraw anytime in Settings > Privacy.';
	@override String get disclaimerSummary => 'Note: EatWise content is general healthy-lifestyle reference only — not medical advice, diagnosis, or treatment.';
	@override String get specialGroupsEntry => 'See who should not fast';
	@override String get viewPrivacyPolicy => 'Read the full Privacy Policy';
	@override String get viewUserAgreement => 'Read the full Terms of Service';
	@override String get agreeAndContinue => 'Agree and continue';
	@override String get decline => 'Decline and exit';
}

// Path: legal.disclaimer
class _Translations$legal$disclaimer$en extends Translations$legal$disclaimer$zh_CN {
	_Translations$legal$disclaimer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Disclaimer';
	@override String get notMedicalTitle => 'Not Medical Advice';
	@override String get notMedicalBody => 'EatWise provides content (including fasting plans, nutrition targets, signal-light feedback and suggestions) for general healthy-lifestyle reference only. It is not medical advice, diagnosis, or treatment, and is no substitute for guidance from a physician, registered dietitian, or other qualified professional. Your nutrition targets are estimated from general formulas and may not fit your individual condition. If you have any health condition, take medication, or have a disease, consult a qualified healthcare professional before fasting or changing your diet. EatWise assumes no medical liability for consequences arising from use of this information.';
	@override String get specialGroupsTitle => 'Special Groups Notice';
	@override String get specialGroupsBody => '⚠️ Intermittent fasting is not recommended for the following groups, or should only be done under medical supervision: pregnant or breastfeeding women; minors (under 18); people with a history of or at risk for eating disorders (e.g., anorexia, bulimia); people with diabetes (especially those using insulin or glucose-lowering medication); people with hypoglycemia or hypotension; people who are underweight (BMI < 18.5); people with chronic conditions such as gout, kidney or liver disease; people recovering from recent surgery or illness; and frail older adults. If you fall into any of these categories, do not start a fasting plan and consult your doctor first.';
	@override String get short => 'EatWise content is not medical advice';
}

// Path: legal.privacyPolicy
class _Translations$legal$privacyPolicy$en extends Translations$legal$privacyPolicy$zh_CN {
	_Translations$legal$privacyPolicy$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Privacy Policy';
	@override String get body => 'Effective: 2026-07-27 | Version 1.0.0 [Pending external confirmation: final legal copy]\n\nEatWise ("we") provides services in mainland China only. This policy explains how we collect, use, store, and protect your personal information, and the rights you have.\n\n1. Information We Collect\n1) Phone number: for registration, sign-in, and account recovery; stored encrypted in mainland China.\n2) Height, weight, age, gender: used to compute daily nutrition targets; sensitive personal information requiring your separate consent.\n3) Meal and fasting records: required for core features; sensitive personal information.\n4) Goal, schedule, and fasting experience (3-question quiz): used for plan recommendation.\n5) Nickname and avatar: optional, for personalization and community display.\n6) Device info and push token: for notification delivery and crash analysis; we never collect IMEI/IMSI/MAC.\n7) Crash and performance logs: de-identified, retained for 6 months.\n8) Analytics events: event-level usage stats only; can be turned off in Settings > Privacy.\nWe do NOT collect: location, contacts, Bluetooth, or HealthKit/Health Connect data.\n\n2. Separate Consent for Sensitive Personal Information\nHealth-related data (height/weight, meal/fasting records) is processed only with your separate consent under PIPL Article 29. Declining does not affect account features — nutrition targets fall back to defaults — and you may withdraw anytime in Settings > Privacy.\n\n3. Storage and Security\nAll data is stored on servers in mainland China; transmission uses TLS 1.2+; phone numbers and health data use field-level encryption; the local database is fully encrypted. No data crosses borders.\n\n4. Third-Party SDKs\nWe use WeChat Login, Sign in with Apple, aggregated push, content safety, and crash monitoring SDKs, all operating within mainland China. No SDK ever receives your raw health data.\n\n5. Your Rights\n1) Access & copy: request a full export of your personal data (JSON+CSV) in Settings > Privacy > Export my data.\n2) Deletion: Settings > Account > Delete account starts a 7-day cooling-off period; signing in during this period cancels the deletion.\n3) Withdraw consent: you may withdraw health data consent and analytics consent anytime in Settings > Privacy.\n\n6. Minors\nThis product is not intended for children under 14.\n\n7. Policy Updates\nIf this policy changes materially, we will ask for your consent again.\n\n8. Contact Us\nFor questions about this policy, reach us via Settings > About in the app.';
}

// Path: legal.userAgreement
class _Translations$legal$userAgreement$en extends Translations$legal$userAgreement$zh_CN {
	_Translations$legal$userAgreement$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Terms of Service';
	@override String get body => 'Effective: 2026-07-27 | Version 1.0.0 [Pending external confirmation: final legal copy]\n\nWelcome to EatWise (the "App"). Please read these terms carefully before using the App.\n\n1. Services\nThe App provides healthy-lifestyle tools including intermittent fasting timers, meal logging, nutrition target estimates with signal-light feedback, trend reports, and community check-ins.\n\n2. Account\nYou may register and sign in via phone verification code, WeChat, or Sign in with Apple. Keep your account secure; you are responsible for activity under it.\n\n3. Not Medical Advice\nAll content in the App is general healthy-lifestyle reference only and is not medical advice, diagnosis, or treatment. See the Disclaimer for details.\n\n4. User Conduct\nYou agree that content you post complies with applicable laws and does not infringe others\' rights. Violating content may be removed and account features restricted.\n\n5. Intellectual Property\nThe App\'s content and software are owned by us; you receive a personal, non-commercial license to use them.\n\n6. Limitation of Liability\nWe assume no medical liability for health consequences arising from use of the App\'s information, and no liability for service interruptions caused by force majeure or third parties.\n\n7. Changes and Termination\nWe will notify you of changes to these terms via in-app notices. You may stop using the App at any time by deleting your account.\n\n8. Governing Law\nThese terms are governed by the laws of the People\'s Republic of China.';
}

// Path: social.feed
class _Translations$social$feed$en extends Translations$social$feed$zh_CN {
	_Translations$social$feed$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Community';
	@override String get emptyTitle => 'Waiting for today\'s first check-in to show up.';
	@override String get emptySubtitle => 'Post your first check-in and light the way for others.';
	@override String get emptyCta => 'Check in';
	@override String get errorTitle => 'Couldn\'t load the feed. Please try again.';
	@override String get pendingBadge => 'Under review — visible only to you';
	@override String streakBadge({required Object days}) => '${days}-day streak';
	@override String get like => 'Like';
	@override String get report => 'Report';
	@override String get reportConfirm => 'Report this check-in? It will be taken down and sent for manual review.';
	@override String get reported => 'Reported. Thanks for the heads-up.';
	@override String get reportFailed => 'Couldn\'t report. Please try again later.';
	@override String get expand => 'Expand';
	@override String get collapse => 'Collapse';
	@override String get justNow => 'Just now';
	@override String minutesAgo({required Object n}) => '${n} min ago';
	@override String hoursAgo({required Object n}) => '${n} hr ago';
	@override String daysAgo({required Object n}) => '${n} d ago';
	@override String get anonymous => 'EatWise buddy';
}

// Path: social.compose
class _Translations$social$compose$en extends Translations$social$compose$zh_CN {
	_Translations$social$compose$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'New check-in';
	@override String get hint => 'Capture this moment of persistence…';
	@override String charCount({required Object n}) => '${n}/500';
	@override String get addPhoto => 'Add photo';
	@override String get removePhoto => 'Remove photo';
	@override String get photoUploading => 'Uploading photo…';
	@override String get photoUploadFailed => 'Photo upload failed';
	@override String get photoUploadFailedBody => 'The photo failed to upload. You can post without it, or cancel and retry the upload.';
	@override String get publishWithoutPhoto => 'Post without photo';
	@override String get retryUpload => 'Try uploading again';
	@override String streakBadge({required Object days}) => 'Current streak: ${days} days 🔥';
	@override String get noStreak => 'Finish today\'s fast and your check-in will carry the streak badge';
	@override String get publish => 'Post';
	@override String get publishFailed => 'Couldn\'t post. Please try again.';
	@override String get emptyText => 'Write something first';
}

// Path: auth.login
class _Translations$auth$login$en extends Translations$auth$login$zh_CN {
	_Translations$auth$login$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sign in';
	@override String get subtitle => 'Sign in with your username and password';
	@override String get phoneLabel => 'Phone number';
	@override String get phoneHint => 'Enter your 11-digit phone number';
	@override String get codeLabel => 'Verification code';
	@override String get codeHint => '6-digit code';
	@override String get sendCode => 'Send code';
	@override String resendIn({required Object seconds}) => 'Resend in ${seconds}s';
	@override String get login => 'Sign in';
	@override String get loggingIn => 'Signing in…';
	@override String get codeSent => 'Verification code sent';
	@override String get invalidPhone => 'Please enter a valid phone number';
	@override String get invalidCode => 'Please enter the 6-digit code';
	@override String get mockHint => 'In local dev the code is always 123456';
	@override String get usernameLabel => 'Username';
	@override String get usernameHint => '3-20 letters, digits or underscores';
	@override String get passwordLabel => 'Password';
	@override String get passwordHint => 'Enter your password';
	@override String get invalidUsername => 'Username must be 3-20 letters, digits or underscores';
	@override String get invalidPassword => 'Password must be 8-64 characters';
	@override String get noAccount => 'No account?';
	@override String get toRegister => 'Sign up';
	@override String get otherLoginMethods => 'Other sign-in methods';
}

// Path: auth.register
class _Translations$auth$register$en extends Translations$auth$register$zh_CN {
	_Translations$auth$register$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sign up';
	@override String get subtitle => 'Create an account to get started';
	@override String get usernameLabel => 'Username';
	@override String get usernameHint => '3-20 letters, digits or underscores';
	@override String get passwordLabel => 'Password';
	@override String get passwordHint => '8-64 characters with letters and digits';
	@override String get confirmPasswordLabel => 'Confirm password';
	@override String get confirmPasswordHint => 'Re-enter your password';
	@override String get register => 'Sign up';
	@override String get registering => 'Signing up…';
	@override String get passwordMismatch => 'Passwords do not match';
	@override String get agreePrefix => 'I have read and agree to the ';
	@override String get agreeAnd => ' and ';
	@override String get agreeRequired => 'Please agree to the Privacy Policy and Terms of Service first';
	@override String get strengthWeak => 'Strength: weak';
	@override String get strengthMedium => 'Strength: medium';
	@override String get strengthStrong => 'Strength: strong';
	@override String get strengthTooShort => 'Password must be at least 8 characters';
	@override String get invalidUsername => 'Username must be 3-20 letters, digits or underscores';
}

// Path: auth.changePassword
class _Translations$auth$changePassword$en extends Translations$auth$changePassword$zh_CN {
	_Translations$auth$changePassword$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Change password';
	@override String get oldLabel => 'Current password';
	@override String get oldHint => 'Enter your current password';
	@override String get oldRequired => 'Enter your current password';
	@override String get newLabel => 'New password';
	@override String get newHint => '8-64 characters with letters and digits';
	@override String get confirmLabel => 'Confirm new password';
	@override String get confirmHint => 'Re-enter your new password';
	@override String get submit => 'Confirm change';
	@override String get submitting => 'Submitting…';
	@override String get success => 'Password changed — please sign in again';
	@override String get passwordMismatch => 'New passwords do not match';
}

// Path: auth.error
class _Translations$auth$error$en extends Translations$auth$error$zh_CN {
	_Translations$auth$error$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get usernameTaken => 'Username already taken';
	@override String get invalidCredentials => 'Incorrect username or password';
	@override String get passwordTooWeak => 'Password must be 8-64 characters with letters and digits';
}

// Path: notify.channel.fastingReminders
class _Translations$notify$channel$fastingReminders$en extends Translations$notify$channel$fastingReminders$zh_CN {
	_Translations$notify$channel$fastingReminders$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => 'Fasting reminders';
	@override String get description => 'Reminders for when your eating and fasting windows start';
}

// Path: onboarding.quiz.q1
class _Translations$onboarding$quiz$q1$en extends Translations$onboarding$quiz$q1$zh_CN {
	_Translations$onboarding$quiz$q1$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'What\'s your goal?';
	@override late final _Translations$onboarding$quiz$q1$options$en options = _Translations$onboarding$quiz$q1$options$en._(_root);
}

// Path: onboarding.quiz.q2
class _Translations$onboarding$quiz$q2$en extends Translations$onboarding$quiz$q2$zh_CN {
	_Translations$onboarding$quiz$q2$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'What\'s your daily schedule like?';
	@override late final _Translations$onboarding$quiz$q2$options$en options = _Translations$onboarding$quiz$q2$options$en._(_root);
}

// Path: onboarding.quiz.q3
class _Translations$onboarding$quiz$q3$en extends Translations$onboarding$quiz$q3$zh_CN {
	_Translations$onboarding$quiz$q3$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Have you tried intermittent fasting?';
	@override late final _Translations$onboarding$quiz$q3$options$en options = _Translations$onboarding$quiz$q3$options$en._(_root);
}

// Path: onboarding.plans.p14x10
class _Translations$onboarding$plans$p14x10$en extends Translations$onboarding$plans$p14x10$zh_CN {
	_Translations$onboarding$plans$p14x10$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => '14:10 Gentle Start';
	@override String get desc => 'Fast 14 hours a day with a 10-hour eating window — barely feels like fasting, and it\'s the easiest to keep.';
}

// Path: onboarding.plans.p16x8
class _Translations$onboarding$plans$p16x8$en extends Translations$onboarding$plans$p16x8$zh_CN {
	_Translations$onboarding$plans$p16x8$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => '16:8 Classic Rhythm';
	@override String get desc => 'Fast 16 hours with an 8-hour eating window — the most popular classic.';
}

// Path: onboarding.plans.p18x6
class _Translations$onboarding$plans$p18x6$en extends Translations$onboarding$plans$p18x6$zh_CN {
	_Translations$onboarding$plans$p18x6$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => '18:6 Advanced';
	@override String get desc => 'An 18-hour daily fast, for experienced fasters ready for the next step.';
}

// Path: onboarding.plans.p5x2
class _Translations$onboarding$plans$p5x2$en extends Translations$onboarding$plans$p5x2$zh_CN {
	_Translations$onboarding$plans$p5x2$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => '5:2 Fasting';
	@override String get desc => 'Eat normally 5 days a week and fast lightly on 2. The full timer flow comes in a later version — get to know it first.';
}

// Path: onboarding.recommendation.reason
class _Translations$onboarding$recommendation$reason$en extends Translations$onboarding$recommendation$reason$zh_CN {
	_Translations$onboarding$recommendation$reason$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get beginner => 'New to fasting? 14:10 is the gentlest way to ease your body into the rhythm.';
	@override String get triedButStopped => 'Tried before and it didn\'t stick? 16:8 with a flexible window makes this round feel easy.';
	@override String get experienced => 'With your experience, 16:8 is a steady default — and 18:6 is there when you want more.';
	@override String get healthUpgrade => 'With experience and health-check goals, 18:6 suits you better. Ease into it.';
	@override String get fallback => 'Let\'s start with the crowd favorite 16:8 — you can adjust it anytime in Profile.';
}

// Path: record.barcode.contribute
class _Translations$record$barcode$contribute$en extends Translations$record$barcode$contribute$zh_CN {
	_Translations$record$barcode$contribute$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Add product info';
	@override String barcodeLabel({required Object code}) => 'Barcode: ${code}';
	@override String get nameLabel => 'Product name';
	@override String get nameRequired => 'Please enter the product name';
	@override String get photoLabel => 'Nutrition label photo (required)';
	@override String get photoAdd => 'Take / choose a photo';
	@override String get photoRequired => 'Please take or choose a photo of the nutrition label on the package';
	@override String get photoUploading => 'Uploading photo…';
	@override String get photoUploadRetry => 'Try uploading again';
	@override String get submitAction => 'Submit';
	@override String get submitted => 'Submitted — everyone can scan it once approved';
	@override String get alreadyListed => 'This product is already listed — prefilled for you';
	@override String get offlineNotice => 'Submitting needs a connection: the product is saved on this device for logging — resubmit when online';
}

// Path: record.customFood.contributions
class _Translations$record$customFood$contributions$en extends Translations$record$customFood$contributions$zh_CN {
	_Translations$record$customFood$contributions$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'My contributions';
	@override String get filterAll => 'All';
	@override String get empty => 'No contributions yet';
	@override String get statusPending => 'In review';
	@override String get statusApproved => 'Approved';
	@override String get statusRejected => 'Rejected';
	@override String reasonLabel({required Object reason}) => 'Reason: ${reason}';
	@override String submittedAt({required Object date}) => 'Submitted on ${date}';
	@override String get loadFailed => 'Failed to load — please try again later';
	@override String get kindBarcode => 'Barcode product';
	@override String barcodeLabel({required Object code}) => 'Barcode ${code}';
}

// Path: fasting.home.greeting
class _Translations$fasting$home$greeting$en extends Translations$fasting$home$greeting$zh_CN {
	_Translations$fasting$home$greeting$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get morning => 'Good morning';
	@override String get noon => 'Good noon';
	@override String get afternoon => 'Good afternoon';
	@override String get evening => 'Good evening';
	@override String get night => 'Still up? A glass of water and an early night is self-care too';
}

// Path: fasting.home.endFastDialog
class _Translations$fasting$home$endFastDialog$en extends Translations$fasting$home$endFastDialog$zh_CN {
	_Translations$fasting$home$endFastDialog$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'End fast';
	@override String elapsed({required Object hours, required Object minutes}) => 'Fasted for ${hours} h ${minutes} min';
	@override String plannedHours({required Object hours}) => 'Planned ${hours} h';
	@override String plannedHoursMinutes({required Object hours, required Object minutes}) => 'Planned ${hours} h ${minutes} min';
	@override String get earlyWarning => 'Ending more than 15 minutes early counts as not qualified';
	@override String get cancel => 'Keep fasting';
	@override String get confirm => 'End fast';
}

// Path: nutrition.data.dateSwitcher
class _Translations$nutrition$data$dateSwitcher$en extends Translations$nutrition$data$dateSwitcher$zh_CN {
	_Translations$nutrition$data$dateSwitcher$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get prevDay => 'Previous day';
	@override String get nextDay => 'Next day';
	@override String get backToToday => 'Back to today';
	@override String get today => 'Today';
}

// Path: nutrition.data.summary
class _Translations$nutrition$data$summary$en extends Translations$nutrition$data$summary$zh_CN {
	_Translations$nutrition$data$summary$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get allGreen => 'Nice and steady today — give yourself a pat on the back 🌱';
	@override String get hasYellow => 'Solid day overall — a nutrient or two needs a small top-up';
	@override String get hasRed => 'A couple of red flags today — no stress, just follow the tips below';
	@override String get empty => 'Nothing logged this day — log a meal and the signal lights come on';
	@override String get fallbackGoal => 'Using default goals for now — complete your profile for sharper targets';
}

// Path: nutrition.data.proDetails
class _Translations$nutrition$data$proDetails$en extends Translations$nutrition$data$proDetails$zh_CN {
	_Translations$nutrition$data$proDetails$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Pro data';
	@override String get expand => 'View details';
	@override String get collapse => 'Collapse';
	@override String get target => 'Target';
	@override String get actual => 'Intake';
	@override String get percent => '% of goal';
	@override String get rda => 'RDA ref.';
	@override String get rdaNote => 'RDA values are general adult dietary references (pending nutritionist sign-off) — your personal goals follow your plan';
}

// Path: nutrition.data.trend
class _Translations$nutrition$data$trend$en extends Translations$nutrition$data$trend$zh_CN {
	_Translations$nutrition$data$trend$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Last 7 days';
	@override String get kcal => 'Calories';
	@override String get fasting => 'Fasting';
	@override String get empty => 'Log a few more days and your trend line starts moving';
	@override String get hourUnit => 'h';
}

// Path: nutrition.signalCard.zone
class _Translations$nutrition$signalCard$zone$en extends Translations$nutrition$signalCard$zone$zh_CN {
	_Translations$nutrition$signalCard$zone$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get green => 'On track';
	@override String get yellow => 'Heads-up';
	@override String get red => 'Warning';
}

// Path: nutrition.signalCard.advice
class _Translations$nutrition$signalCard$advice$en extends Translations$nutrition$signalCard$advice$zh_CN {
	_Translations$nutrition$signalCard$advice$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$nutrition$signalCard$advice$kcal$en kcal = _Translations$nutrition$signalCard$advice$kcal$en._(_root);
	@override late final _Translations$nutrition$signalCard$advice$protein$en protein = _Translations$nutrition$signalCard$advice$protein$en._(_root);
	@override late final _Translations$nutrition$signalCard$advice$carb$en carb = _Translations$nutrition$signalCard$advice$carb$en._(_root);
	@override late final _Translations$nutrition$signalCard$advice$fat$en fat = _Translations$nutrition$signalCard$advice$fat$en._(_root);
	@override late final _Translations$nutrition$signalCard$advice$meal$en meal = _Translations$nutrition$signalCard$advice$meal$en._(_root);
}

// Path: reports.trend.dim
class _Translations$reports$trend$dim$en extends Translations$reports$trend$dim$zh_CN {
	_Translations$reports$trend$dim$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get weight => 'Weight';
	@override String get kcal => 'Calories';
	@override String get fasting => 'Fasting';
}

// Path: reports.trend.range
class _Translations$reports$trend$range$en extends Translations$reports$trend$range$zh_CN {
	_Translations$reports$trend$range$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get d7 => '7D';
	@override String get d30 => '30D';
}

// Path: reports.trend.unit
class _Translations$reports$trend$unit$en extends Translations$reports$trend$unit$zh_CN {
	_Translations$reports$trend$unit$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get kg => 'kg';
	@override String get kcal => 'kcal';
	@override String get hour => 'h';
}

// Path: reports.weekly.cheer
class _Translations$reports$weekly$cheer$en extends Translations$reports$weekly$cheer$zh_CN {
	_Translations$reports$weekly$cheer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get great => 'Rock-steady week — give yourself a big thumbs-up 🌱';
	@override String get mixed => 'Ups and downs are normal. Keep the rhythm next week~';
	@override String get start => 'Starting is what counts — your data will grow with you.';
}

// Path: streak.milestone.shareCard
class _Translations$streak$milestone$shareCard$en extends Translations$streak$milestone$shareCard$zh_CN {
	_Translations$streak$milestone$shareCard$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get sheetTitle => 'Milestone unlocked · Share card';
	@override String get daysUnit => 'days';
	@override String get appName => 'EatWise';
	@override String get tagline => 'Gentle fasting, mindful living';
	@override String get saveToAlbum => 'Save to Photos';
	@override String get shareSystem => 'Share';
	@override String get saveSuccess => 'Saved to Photos';
	@override String get saveFailed => 'Couldn\'t save. Check the photo permission and try again.';
	@override String get shareFailed => 'Couldn\'t share right now. Please try again later.';
}

// Path: settings.aiModel.providers
class _Translations$settings$aiModel$providers$en extends Translations$settings$aiModel$providers$zh_CN {
	_Translations$settings$aiModel$providers$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get custom => 'Custom';
	@override String get deepseek => 'DeepSeek';
	@override String get qwen => 'Qwen';
	@override String get kimi => 'Kimi';
}

// Path: onboarding.quiz.q1.options
class _Translations$onboarding$quiz$q1$options$en extends Translations$onboarding$quiz$q1$options$zh_CN {
	_Translations$onboarding$quiz$q1$options$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get loseWeight => 'Lose weight & tone up';
	@override String get improveHealth => 'Improve health check results';
	@override String get adjustSchedule => 'Fix my daily routine';
	@override String get justTrying => 'Just curious';
}

// Path: onboarding.quiz.q2.options
class _Translations$onboarding$quiz$q2$options$en extends Translations$onboarding$quiz$q2$options$zh_CN {
	_Translations$onboarding$quiz$q2$options$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get regular => 'Regular (9 to 5)';
	@override String get shiftWork => 'Shift or night work';
	@override String get flexible => 'Freelance & flexible';
}

// Path: onboarding.quiz.q3.options
class _Translations$onboarding$quiz$q3$options$en extends Translations$onboarding$quiz$q3$options$zh_CN {
	_Translations$onboarding$quiz$q3$options$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get beginner => 'Brand new';
	@override String get triedButStopped => 'Tried, but it didn\'t stick';
	@override String get experienced => 'Experienced';
}

// Path: nutrition.signalCard.advice.kcal
class _Translations$nutrition$signalCard$advice$kcal$en extends Translations$nutrition$signalCard$advice$kcal$zh_CN {
	_Translations$nutrition$signalCard$advice$kcal$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get green => 'Your calories are right on track today — nice and steady, keep it up! 🌱';
	@override String yellowLow({required Object meal_action}) => 'You\'re a bit under on calories — ${meal_action}. Your body will thank you.';
	@override String yellowHigh({required Object meal_action}) => 'Calories are a touch high — ${meal_action} and you\'re right back on track.';
	@override String redLow({required Object meal_action}) => 'You\'re well under today — outside your fasting window, do eat well: ${meal_action}.';
	@override String redHigh({required Object meal_action}) => 'A bit over on calories — no stress! ${meal_action}. Tomorrow\'s a fresh day.';
	@override String get zero => 'No calories logged yet — did a meal slip by?';
}

// Path: nutrition.signalCard.advice.protein
class _Translations$nutrition$signalCard$advice$protein$en extends Translations$nutrition$signalCard$advice$protein$zh_CN {
	_Translations$nutrition$signalCard$advice$protein$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get green => 'Protein nailed it! Your muscles are sending you a heart 💪';
	@override String yellowLow({required Object meal_action}) => 'Protein is almost there — ${meal_action} and you\'ve got it.';
	@override String redLow({required Object meal_action}) => 'Protein\'s on the low side today — ${meal_action} to give your body a boost.';
	@override String redHigh({required Object meal_action}) => 'A little much protein today — ${meal_action} for a comfier balance.';
	@override String get zero => 'No protein logged yet — did a meal slip by?';
}

// Path: nutrition.signalCard.advice.carb
class _Translations$nutrition$signalCard$advice$carb$en extends Translations$nutrition$signalCard$advice$carb$zh_CN {
	_Translations$nutrition$signalCard$advice$carb$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get green => 'Carbs are just right — steady energy all the way.';
	@override String yellowLow({required Object meal_action}) => 'Carbs are a bit low — ${meal_action} to keep the afternoon slump away.';
	@override String yellowHigh({required Object meal_action}) => 'Carbs are a touch high — ${meal_action} to keep your blood sugar steady.';
	@override String redLow({required Object meal_action}) => 'Carbs are well under today — ${meal_action}. Don\'t shortchange your body.';
	@override String redHigh({required Object meal_action}) => 'Carbs ran quite high — ${meal_action} to keep your blood sugar steadier.';
	@override String get zero => 'No carbs logged yet — did a meal slip by?';
}

// Path: nutrition.signalCard.advice.fat
class _Translations$nutrition$signalCard$advice$fat$en extends Translations$nutrition$signalCard$advice$fat$zh_CN {
	_Translations$nutrition$signalCard$advice$fat$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get green => 'Healthy fat intake — your skin and glow will love it.';
	@override String yellowLow({required Object meal_action}) => 'Good fats are a bit low — ${meal_action}; they help absorb vitamins.';
	@override String yellowHigh({required Object meal_action}) => 'Fat\'s a touch high — ${meal_action} for a lighter feel.';
	@override String redLow({required Object meal_action}) => 'Good fats are well under today — ${meal_action}; your body needs them to absorb vitamins.';
	@override String redHigh({required Object meal_action}) => 'Fat\'s on the high side — ${meal_action} for a lighter feel.';
	@override String get zero => 'No fat logged yet — did a meal slip by?';
}

// Path: nutrition.signalCard.advice.meal
class _Translations$nutrition$signalCard$advice$meal$en extends Translations$nutrition$signalCard$advice$meal$zh_CN {
	_Translations$nutrition$signalCard$advice$meal$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get breakfast => 'add an egg or a glass of soy milk at breakfast';
	@override String get lunch => 'go for a palm-size portion of lean meat or tofu at lunch';
	@override String get dinner => 'pick something steamed or lightly poached for dinner, and stop at 80% full';
	@override String get snack => 'grab a handful of nuts or a yogurt as a snack';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEn {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'notify.channel.fastingReminders.name' => 'Fasting reminders',
			'notify.channel.fastingReminders.description' => 'Reminders for when your eating and fasting windows start',
			'notify.permissionBanner' => 'Turn on notifications to get reminded when your eating and fasting windows start',
			'notify.exactAlarmHint' => 'Battery-saving policies may delay reminders — allow exact alarms for on-time alerts',
			'onboarding.quiz.title' => '3 quick questions to find your fasting rhythm 🌱',
			'onboarding.quiz.progress' => ({required Object step, required Object total}) => 'Question ${step} of ${total}',
			'onboarding.quiz.skip' => 'Skip for now',
			'onboarding.quiz.next' => 'Continue',
			'onboarding.quiz.finish' => 'See my plan',
			'onboarding.quiz.back' => 'Back',
			'onboarding.quiz.q1.title' => 'What\'s your goal?',
			'onboarding.quiz.q1.options.loseWeight' => 'Lose weight & tone up',
			'onboarding.quiz.q1.options.improveHealth' => 'Improve health check results',
			'onboarding.quiz.q1.options.adjustSchedule' => 'Fix my daily routine',
			'onboarding.quiz.q1.options.justTrying' => 'Just curious',
			'onboarding.quiz.q2.title' => 'What\'s your daily schedule like?',
			'onboarding.quiz.q2.options.regular' => 'Regular (9 to 5)',
			'onboarding.quiz.q2.options.shiftWork' => 'Shift or night work',
			'onboarding.quiz.q2.options.flexible' => 'Freelance & flexible',
			'onboarding.quiz.q3.title' => 'Have you tried intermittent fasting?',
			'onboarding.quiz.q3.options.beginner' => 'Brand new',
			'onboarding.quiz.q3.options.triedButStopped' => 'Tried, but it didn\'t stick',
			'onboarding.quiz.q3.options.experienced' => 'Experienced',
			'onboarding.plans.p14x10.name' => '14:10 Gentle Start',
			'onboarding.plans.p14x10.desc' => 'Fast 14 hours a day with a 10-hour eating window — barely feels like fasting, and it\'s the easiest to keep.',
			'onboarding.plans.p16x8.name' => '16:8 Classic Rhythm',
			'onboarding.plans.p16x8.desc' => 'Fast 16 hours with an 8-hour eating window — the most popular classic.',
			'onboarding.plans.p18x6.name' => '18:6 Advanced',
			'onboarding.plans.p18x6.desc' => 'An 18-hour daily fast, for experienced fasters ready for the next step.',
			'onboarding.plans.p5x2.name' => '5:2 Fasting',
			'onboarding.plans.p5x2.desc' => 'Eat normally 5 days a week and fast lightly on 2. The full timer flow comes in a later version — get to know it first.',
			'onboarding.recommendation.title' => 'Your recommended plan',
			'onboarding.recommendation.mainBadge' => 'Top pick',
			'onboarding.recommendation.altTitle' => 'Worth a try',
			'onboarding.recommendation.select' => 'Choose this',
			'onboarding.recommendation.selected' => 'Selected',
			'onboarding.recommendation.startNow' => 'Start now',
			'onboarding.recommendation.window' => ({required Object start, required Object end}) => 'Eating window ${start}–${end}',
			'onboarding.recommendation.scienceLink' => 'How does fasting work?',
			'onboarding.recommendation.comingSoon' => 'Coming in a later version',
			'onboarding.recommendation.reason.beginner' => 'New to fasting? 14:10 is the gentlest way to ease your body into the rhythm.',
			'onboarding.recommendation.reason.triedButStopped' => 'Tried before and it didn\'t stick? 16:8 with a flexible window makes this round feel easy.',
			'onboarding.recommendation.reason.experienced' => 'With your experience, 16:8 is a steady default — and 18:6 is there when you want more.',
			'onboarding.recommendation.reason.healthUpgrade' => 'With experience and health-check goals, 18:6 suits you better. Ease into it.',
			'onboarding.recommendation.reason.fallback' => 'Let\'s start with the crowd favorite 16:8 — you can adjust it anytime in Profile.',
			'onboarding.recommendation.flexibleHint' => 'Your schedule isn\'t fixed, so feel free to shift your eating window around your life.',
			'onboarding.recommendation.fallbackNotice' => ({required Object kcal}) => 'Your daily nutrition goal is estimated at ${kcal} kcal for now — add your height & weight in Profile for a precise target.',
			'onboarding.recommendation.planChangeTitle' => 'Change fasting plan',
			'onboarding.recommendation.planChangeConfirm' => ({required Object date}) => 'The new plan takes effect at 00:00 on ${date}. Today still follows your current plan.',
			'onboarding.science.title' => 'How fasting works',
			'onboarding.science.card1Title' => 'Give your body a break',
			'onboarding.science.card1Body' => 'During a fast, your body gradually switches to fat-burning mode, running on stored energy.',
			'onboarding.science.card2Title' => 'A rhythm, not a diet',
			'onboarding.science.card2Body' => 'Fasting is about when you eat, not what you can\'t eat — eating well inside your window matters.',
			'onboarding.science.disclaimer' => 'This content is general wellness information, not medical advice. If you are pregnant, breastfeeding, or managing a medical condition, please consult your doctor first.',
			'onboarding.science.back' => 'Back',
			'record.page.title' => 'Records',
			'record.page.confirm' => 'Log it',
			'record.page.loggedToday' => ({required Object count}) => '${count} logged today',
			'record.page.todayKcal' => ({required Object kcal}) => '~${kcal} kcal today (to be calibrated)',
			'record.entries.photo' => 'Photo',
			'record.entries.voice' => 'Voice',
			'record.entries.frequent' => 'Usual',
			'record.entries.comingSoon' => 'Coming soon — search manually to log for now',
			'record.pending.banner' => ({required Object count}) => '${count} record(s) still on the way — will sync when online',
			'record.search.hint' => 'Search foods (Chinese or English)',
			'record.search.empty' => 'No match? Try another keyword',
			'record.amount.label' => 'Amount (g)',
			'record.amount.invalid' => 'Enter an amount greater than 0',
			'record.nutrition.kcal' => 'Calories',
			'record.nutrition.protein' => 'Protein',
			'record.nutrition.carb' => 'Carbs',
			'record.nutrition.fat' => 'Fat',
			'record.nutrition.kcalUnit' => 'kcal',
			'record.nutrition.gramUnit' => 'g',
			'record.toast.recorded' => 'Logged',
			'record.toast.undo' => 'Undo',
			'record.toast.undone' => 'Undone',
			'record.toast.syncFailed' => 'This record wasn\'t saved — please submit again',
			'record.photo.pickTitle' => 'Snap to recognize',
			'record.photo.takePhoto' => 'Take photo',
			'record.photo.fromGallery' => 'Choose from album',
			'record.photo.recognizing' => 'Recognizing…',
			'record.photo.unavailable' => 'Recognition isn\'t available right now — a quick manual search works just as well',
			'record.photo.deniedTitle' => 'Camera not allowed',
			'record.photo.deniedBody' => 'No camera? No problem — searching manually is just as fast',
			'record.photo.openSettings' => 'Open Settings',
			'record.photo.useManual' => 'Search manually',
			'record.barcode.entry' => 'Scan',
			'record.barcode.title' => 'Scan product barcode',
			'record.barcode.torch' => 'Torch',
			'record.barcode.manualInput' => 'Enter manually',
			'record.barcode.manualTitle' => 'Enter barcode',
			'record.barcode.manualHint' => 'Enter the 8–14 digit code on the package',
			'record.barcode.manualConfirm' => 'Look up',
			'record.barcode.invalid' => 'Invalid barcode — should be 8–14 digits',
			'record.barcode.looking' => 'Looking up…',
			'record.barcode.notFoundTitle' => 'Product not found',
			'record.barcode.notFoundBody' => 'This product isn\'t in the food library yet. Add its info (snap the nutrition label for review — everyone can scan it once approved), search manually, or add a custom food.',
			'record.barcode.notFoundSearch' => 'Search manually',
			'record.barcode.notFoundCustom' => 'Add custom food',
			'record.barcode.notFoundContribute' => 'Add product info',
			'record.barcode.unavailable' => 'Lookup failed. Check your connection and try again',
			'record.barcode.deniedTitle' => 'Camera not authorized',
			'record.barcode.deniedBody' => 'You can still log by searching or entering the code manually',
			'record.barcode.openSettings' => 'Open settings',
			'record.barcode.useManual' => 'Search manually',
			'record.barcode.contribute.title' => 'Add product info',
			'record.barcode.contribute.barcodeLabel' => ({required Object code}) => 'Barcode: ${code}',
			'record.barcode.contribute.nameLabel' => 'Product name',
			'record.barcode.contribute.nameRequired' => 'Please enter the product name',
			'record.barcode.contribute.photoLabel' => 'Nutrition label photo (required)',
			'record.barcode.contribute.photoAdd' => 'Take / choose a photo',
			'record.barcode.contribute.photoRequired' => 'Please take or choose a photo of the nutrition label on the package',
			'record.barcode.contribute.photoUploading' => 'Uploading photo…',
			'record.barcode.contribute.photoUploadRetry' => 'Try uploading again',
			'record.barcode.contribute.submitAction' => 'Submit',
			'record.barcode.contribute.submitted' => 'Submitted — everyone can scan it once approved',
			'record.barcode.contribute.alreadyListed' => 'This product is already listed — prefilled for you',
			'record.barcode.contribute.offlineNotice' => 'Submitting needs a connection: the product is saved on this device for logging — resubmit when online',
			'record.voice.listening' => 'Listening… say what you ate, e.g. "a bowl of rice"',
			'record.voice.tapToStart' => 'Tap to start speaking',
			'record.voice.finish' => 'Done',
			'record.voice.unavailable' => 'Speech recognition isn\'t available on this device — typing works just as well',
			'record.voice.deniedTitle' => 'Microphone not allowed',
			'record.voice.deniedBody' => 'No voice? No problem — typing a search is just as fast',
			'record.voice.noMatch' => 'Couldn\'t catch the food — try rephrasing or search manually',
			'record.frequent.title' => 'Frequently logged',
			'record.frequent.empty' => 'Log a few more meals and your usuals will show up here',
			'record.card.pleaseConfirm' => 'Please confirm',
			'record.customFood.cta' => 'Can\'t find it? Add a custom food',
			'record.customFood.badge' => 'Custom',
			'record.customFood.title' => 'Add custom food',
			'record.customFood.nameLabel' => 'Food name',
			'record.customFood.nameRequired' => 'Please enter a name',
			'record.customFood.aliasLabel' => 'Aliases (optional, comma-separated)',
			'record.customFood.estimate' => 'AI estimate',
			'record.customFood.estimating' => 'Estimating…',
			'record.customFood.estimateLow' => 'Low confidence — please double-check the values',
			'record.customFood.estimateUnavailable' => 'Estimate unavailable — please enter values manually',
			'record.customFood.estimateBadgeOnDevice' => 'On-device estimate — please confirm',
			'record.customFood.estimateBadgeUserApi' => 'Custom API estimate — please confirm',
			'record.customFood.estimateDubious' => 'Estimate looks off — please double-check the values',
			'record.customFood.kcalLabel' => 'Calories (kcal / 100 g)',
			'record.customFood.proteinLabel' => 'Protein (g / 100 g)',
			'record.customFood.carbLabel' => 'Carbs (g / 100 g)',
			'record.customFood.fatLabel' => 'Fat (g / 100 g)',
			'record.customFood.nutritionRequired' => 'Enter a number greater than 0',
			'record.customFood.kcalRange' => 'Calories must be between 0 and 900 kcal',
			'record.customFood.macroRange' => 'Must be between 0 and 100 g',
			'record.customFood.savedOffline' => 'Saved on this device — will sync when online',
			'record.customFood.savedOnline' => 'Saved',
			'record.customFood.shareOptIn' => 'Share with all users (everyone can find it once approved)',
			'record.customFood.shareAction' => 'Share with all users',
			'record.customFood.submittedReview' => 'Submitted for review',
			'record.customFood.badgePending' => 'In review',
			'record.customFood.badgeApproved' => 'Shared',
			'record.customFood.badgeRejected' => 'Not approved',
			'record.customFood.badgeCommunity' => 'Community',
			'record.customFood.contributions.title' => 'My contributions',
			'record.customFood.contributions.filterAll' => 'All',
			'record.customFood.contributions.empty' => 'No contributions yet',
			'record.customFood.contributions.statusPending' => 'In review',
			'record.customFood.contributions.statusApproved' => 'Approved',
			'record.customFood.contributions.statusRejected' => 'Rejected',
			'record.customFood.contributions.reasonLabel' => ({required Object reason}) => 'Reason: ${reason}',
			'record.customFood.contributions.submittedAt' => ({required Object date}) => 'Submitted on ${date}',
			'record.customFood.contributions.loadFailed' => 'Failed to load — please try again later',
			'record.customFood.contributions.kindBarcode' => 'Barcode product',
			'record.customFood.contributions.barcodeLabel' => ({required Object code}) => 'Barcode ${code}',
			'record.water.title' => 'Water today',
			'record.water.progress' => ({required Object total, required Object goal}) => '${total} / ${goal} ml',
			'record.water.quickAddLabel' => ({required Object ml}) => 'Add ${ml} ml of water',
			'record.weight.title' => 'Weight',
			'record.weight.notLogged' => 'Log it',
			'record.weight.current' => ({required Object kg}) => '${kg} kg',
			'record.weight.dialogTitle' => 'Log today\'s weight',
			'record.weight.inputLabel' => 'Weight (kg)',
			'record.weight.invalid' => 'Enter a value between 20 and 300',
			'record.home.title' => 'Log',
			'record.home.logMeal' => 'Log a bite',
			'record.empty.title' => 'No food stories yet — tap the orange button to log your first bite?',
			'common.appName' => 'EatWise',
			'common.action.save' => 'Save',
			'common.action.cancel' => 'Cancel',
			'common.action.undo' => 'Undo',
			'common.action.retry' => 'Retry',
			'common.action.confirm' => 'OK',
			'fasting.home.title' => 'Fasting Timer',
			'fasting.home.endFast' => 'End fast',
			'fasting.home.extend' => 'Extend',
			'fasting.home.startPlan' => 'Choose your fasting plan',
			'fasting.home.stateEating' => 'Eating window',
			'fasting.home.stateFasting' => 'Fasting',
			'fasting.home.stateFastingExtended' => 'Fasting · Extended',
			'fasting.home.stateNoPlan' => 'No fasting plan yet',
			'fasting.home.attribution' => ({required Object date}) => 'This fast counts toward ${date}',
			'fasting.home.extendedBadge' => ({required Object minutes}) => 'Extended +${minutes} min',
			'fasting.home.extendLimit' => 'You can extend by up to 4 hours per fast',
			'fasting.home.planTag' => ({required Object id, required Object start, required Object end}) => '${id} · Eating window ${start}–${end}',
			'fasting.home.noPlanSubtitle' => 'Answer 3 quick questions to find your fasting rhythm',
			'fasting.home.celebrationTitle' => 'Fast complete! Your body just did a quiet deep-clean ✨',
			'fasting.home.celebrationBadge' => 'Fast complete ✨',
			'fasting.home.signalEmpty' => 'Nothing logged today — log a bite and your signal lights will show up',
			'fasting.home.greeting.morning' => 'Good morning',
			'fasting.home.greeting.noon' => 'Good noon',
			'fasting.home.greeting.afternoon' => 'Good afternoon',
			'fasting.home.greeting.evening' => 'Good evening',
			'fasting.home.greeting.night' => 'Still up? A glass of water and an early night is self-care too',
			'fasting.home.endFastDialog.title' => 'End fast',
			'fasting.home.endFastDialog.elapsed' => ({required Object hours, required Object minutes}) => 'Fasted for ${hours} h ${minutes} min',
			'fasting.home.endFastDialog.plannedHours' => ({required Object hours}) => 'Planned ${hours} h',
			'fasting.home.endFastDialog.plannedHoursMinutes' => ({required Object hours, required Object minutes}) => 'Planned ${hours} h ${minutes} min',
			'fasting.home.endFastDialog.earlyWarning' => 'Ending more than 15 minutes early counts as not qualified',
			'fasting.home.endFastDialog.cancel' => 'Keep fasting',
			'fasting.home.endFastDialog.confirm' => 'End fast',
			'fasting.widget.dueEat' => ({required Object time}) => 'Eat at ${time}',
			'fasting.widget.dueEatEnd' => ({required Object time}) => 'Window ends ${time}',
			'home.tab.home' => 'Home',
			'home.tab.record' => 'Log',
			'home.tab.data' => 'Stats',
			'home.tab.community' => 'Community',
			'home.tab.profile' => 'Me',
			'home.data.emptyTitle' => 'Your trends are warming up — log a few days to get them moving.',
			'home.data.emptySubtitle' => 'Keep logging for a few days and your trends and signal lights will come alive.',
			'home.data.cta' => 'Log a bite',
			'home.community.emptyTitle' => 'Waiting for today\'s first check-in to show up.',
			'home.community.emptySubtitle' => 'Check-ins and challenges are on the way.',
			'home.community.cta' => 'Check in',
			'home.community.comingSoon' => 'Community is coming soon — stay tuned',
			'home.profile.emptyTitle' => 'Your profile is under construction',
			'home.profile.emptySubtitle' => 'Plans, goals and more settings are moving in soon.',
			'notification.fasting.eatSoon' => 'Eating window opens in 15 min',
			'notification.fasting.eatStart' => ({required Object date}) => 'Time to eat! This fast counts toward ${date} ✅',
			'notification.fasting.fastStart' => 'Your fasting window has started — you\'re doing great, keep it up!',
			'nutrition.data.dateSwitcher.prevDay' => 'Previous day',
			'nutrition.data.dateSwitcher.nextDay' => 'Next day',
			'nutrition.data.dateSwitcher.backToToday' => 'Back to today',
			'nutrition.data.dateSwitcher.today' => 'Today',
			'nutrition.data.summary.allGreen' => 'Nice and steady today — give yourself a pat on the back 🌱',
			'nutrition.data.summary.hasYellow' => 'Solid day overall — a nutrient or two needs a small top-up',
			'nutrition.data.summary.hasRed' => 'A couple of red flags today — no stress, just follow the tips below',
			'nutrition.data.summary.empty' => 'Nothing logged this day — log a meal and the signal lights come on',
			'nutrition.data.summary.fallbackGoal' => 'Using default goals for now — complete your profile for sharper targets',
			'nutrition.data.localEstimate' => 'Local estimate — the cloud fine-tunes it once you\'re online',
			'nutrition.data.proDetails.title' => 'Pro data',
			'nutrition.data.proDetails.expand' => 'View details',
			'nutrition.data.proDetails.collapse' => 'Collapse',
			'nutrition.data.proDetails.target' => 'Target',
			'nutrition.data.proDetails.actual' => 'Intake',
			'nutrition.data.proDetails.percent' => '% of goal',
			'nutrition.data.proDetails.rda' => 'RDA ref.',
			'nutrition.data.proDetails.rdaNote' => 'RDA values are general adult dietary references (pending nutritionist sign-off) — your personal goals follow your plan',
			'nutrition.data.trend.title' => 'Last 7 days',
			'nutrition.data.trend.kcal' => 'Calories',
			'nutrition.data.trend.fasting' => 'Fasting',
			'nutrition.data.trend.empty' => 'Log a few more days and your trend line starts moving',
			'nutrition.data.trend.hourUnit' => 'h',
			'nutrition.signalCard.zone.green' => 'On track',
			'nutrition.signalCard.zone.yellow' => 'Heads-up',
			'nutrition.signalCard.zone.red' => 'Warning',
			'nutrition.signalCard.advice.kcal.green' => 'Your calories are right on track today — nice and steady, keep it up! 🌱',
			'nutrition.signalCard.advice.kcal.yellowLow' => ({required Object meal_action}) => 'You\'re a bit under on calories — ${meal_action}. Your body will thank you.',
			'nutrition.signalCard.advice.kcal.yellowHigh' => ({required Object meal_action}) => 'Calories are a touch high — ${meal_action} and you\'re right back on track.',
			'nutrition.signalCard.advice.kcal.redLow' => ({required Object meal_action}) => 'You\'re well under today — outside your fasting window, do eat well: ${meal_action}.',
			'nutrition.signalCard.advice.kcal.redHigh' => ({required Object meal_action}) => 'A bit over on calories — no stress! ${meal_action}. Tomorrow\'s a fresh day.',
			'nutrition.signalCard.advice.kcal.zero' => 'No calories logged yet — did a meal slip by?',
			'nutrition.signalCard.advice.protein.green' => 'Protein nailed it! Your muscles are sending you a heart 💪',
			'nutrition.signalCard.advice.protein.yellowLow' => ({required Object meal_action}) => 'Protein is almost there — ${meal_action} and you\'ve got it.',
			'nutrition.signalCard.advice.protein.redLow' => ({required Object meal_action}) => 'Protein\'s on the low side today — ${meal_action} to give your body a boost.',
			'nutrition.signalCard.advice.protein.redHigh' => ({required Object meal_action}) => 'A little much protein today — ${meal_action} for a comfier balance.',
			'nutrition.signalCard.advice.protein.zero' => 'No protein logged yet — did a meal slip by?',
			'nutrition.signalCard.advice.carb.green' => 'Carbs are just right — steady energy all the way.',
			'nutrition.signalCard.advice.carb.yellowLow' => ({required Object meal_action}) => 'Carbs are a bit low — ${meal_action} to keep the afternoon slump away.',
			'nutrition.signalCard.advice.carb.yellowHigh' => ({required Object meal_action}) => 'Carbs are a touch high — ${meal_action} to keep your blood sugar steady.',
			'nutrition.signalCard.advice.carb.redLow' => ({required Object meal_action}) => 'Carbs are well under today — ${meal_action}. Don\'t shortchange your body.',
			'nutrition.signalCard.advice.carb.redHigh' => ({required Object meal_action}) => 'Carbs ran quite high — ${meal_action} to keep your blood sugar steadier.',
			'nutrition.signalCard.advice.carb.zero' => 'No carbs logged yet — did a meal slip by?',
			'nutrition.signalCard.advice.fat.green' => 'Healthy fat intake — your skin and glow will love it.',
			'nutrition.signalCard.advice.fat.yellowLow' => ({required Object meal_action}) => 'Good fats are a bit low — ${meal_action}; they help absorb vitamins.',
			'nutrition.signalCard.advice.fat.yellowHigh' => ({required Object meal_action}) => 'Fat\'s a touch high — ${meal_action} for a lighter feel.',
			'nutrition.signalCard.advice.fat.redLow' => ({required Object meal_action}) => 'Good fats are well under today — ${meal_action}; your body needs them to absorb vitamins.',
			'nutrition.signalCard.advice.fat.redHigh' => ({required Object meal_action}) => 'Fat\'s on the high side — ${meal_action} for a lighter feel.',
			'nutrition.signalCard.advice.fat.zero' => 'No fat logged yet — did a meal slip by?',
			'nutrition.signalCard.advice.meal.breakfast' => 'add an egg or a glass of soy milk at breakfast',
			'nutrition.signalCard.advice.meal.lunch' => 'go for a palm-size portion of lean meat or tofu at lunch',
			'nutrition.signalCard.advice.meal.dinner' => 'pick something steamed or lightly poached for dinner, and stop at 80% full',
			'nutrition.signalCard.advice.meal.snack' => 'grab a handful of nuts or a yogurt as a snack',
			'reports.title' => 'Trends & reports',
			'reports.entry' => 'Trends & deep reports',
			'reports.trend.title' => 'Growth trends',
			'reports.trend.dim.weight' => 'Weight',
			'reports.trend.dim.kcal' => 'Calories',
			'reports.trend.dim.fasting' => 'Fasting',
			'reports.trend.range.d7' => '7D',
			'reports.trend.range.d30' => '30D',
			'reports.trend.unit.kg' => 'kg',
			'reports.trend.unit.kcal' => 'kcal',
			'reports.trend.unit.hour' => 'h',
			'reports.trend.empty' => 'Your trends are warming up — log a few days to get them moving.',
			'reports.trend.ctaRecord' => 'Log now',
			'reports.trend.ctaFast' => 'Start fasting',
			'reports.trend.ctaWeight' => 'Log weight',
			'reports.growth.title' => ({required Object days}) => '${days}-day journey',
			'reports.growth.qualifiedDays' => 'Fasting goals hit',
			'reports.growth.recordedDays' => 'Days logged',
			'reports.growth.avgFasting' => 'Avg. fast',
			'reports.growth.weightDelta' => 'Weight change',
			'reports.growth.daysUnit' => 'd',
			'reports.growth.hourUnit' => 'h',
			'reports.growth.kgUnit' => 'kg',
			'reports.growth.noValue' => '—',
			'reports.growth.empty' => 'No footprints yet — log a meal or finish a fast to start.',
			'reports.weekly.title' => 'This week',
			'reports.weekly.range' => ({required Object start, required Object end}) => '${start} – ${end}',
			'reports.weekly.qualified' => ({required Object days}) => '${days} days on target',
			'reports.weekly.entries' => ({required Object count}) => '${count} entries logged',
			'reports.weekly.greenRatio' => ({required Object percent}) => '${percent}% green lights',
			'reports.weekly.cheer.great' => 'Rock-steady week — give yourself a big thumbs-up 🌱',
			'reports.weekly.cheer.mixed' => 'Ups and downs are normal. Keep the rhythm next week~',
			'reports.weekly.cheer.start' => 'Starting is what counts — your data will grow with you.',
			'reports.weekly.empty' => 'Almost there — log a meal or finish a fast to unlock your weekly report.',
			'reports.monthly.prevMonth' => 'Previous month',
			'reports.monthly.nextMonth' => 'Next month',
			'reports.monthly.qualified' => ({required Object days}) => '${days} fasting days on target',
			'reports.monthly.recordedDays' => ({required Object days}) => '${days} days logged',
			'reports.monthly.avgFastingHours' => ({required Object hours}) => 'Avg. fast ${hours} h',
			'reports.monthly.avgFastingHoursMinutes' => ({required Object hours, required Object minutes}) => 'Avg. fast ${hours} h ${minutes} m',
			'reports.monthly.kcalAvg' => ({required Object kcal, required Object target}) => 'Avg ${kcal} kcal · goal ${target} kcal',
			'reports.monthly.macros' => ({required Object protein, required Object carbs, required Object fat}) => 'Protein ${protein}g · Carbs ${carbs}g · Fat ${fat}g',
			'reports.monthly.weightChange' => ({required Object value}) => 'Weight change ${value}',
			'reports.monthly.empty' => 'No records this month yet',
			'reports.monthly.emptyHint' => 'Log a meal or finish a fast and your monthly report will bloom.',
			'streak.home.streakDays' => ({required Object days}) => '${days}-day streak 🔥',
			'streak.home.startHint' => 'Finish today\'s fast to start day 1',
			'streak.milestone.title' => ({required Object days}) => '${days}-day streak! You\'ve outlasted 80% of the community 🎉',
			'streak.milestone.badgeLabel' => ({required Object days}) => '${days}-day streak',
			'streak.milestone.share' => 'Share',
			'streak.milestone.accept' => 'Keep it',
			'streak.milestone.shareCard.sheetTitle' => 'Milestone unlocked · Share card',
			'streak.milestone.shareCard.daysUnit' => 'days',
			'streak.milestone.shareCard.appName' => 'EatWise',
			'streak.milestone.shareCard.tagline' => 'Gentle fasting, mindful living',
			'streak.milestone.shareCard.saveToAlbum' => 'Save to Photos',
			'streak.milestone.shareCard.shareSystem' => 'Share',
			'streak.milestone.shareCard.saveSuccess' => 'Saved to Photos',
			'streak.milestone.shareCard.saveFailed' => 'Couldn\'t save. Check the photo permission and try again.',
			'streak.milestone.shareCard.shareFailed' => 'Couldn\'t share right now. Please try again later.',
			'streak.kBreak.title' => 'Your streak was interrupted',
			'streak.kBreak.howItWorks' => 'Your streak counts only days you complete your fasting plan (ending up to 15 min early still counts). Meal-log days are tracked separately and don\'t affect your streak. A missed day resets it to 0 — use a Mend Card within 7 days to restore it.',
			'streak.kBreak.cardsLeft' => ({required Object n}) => 'Mend Cards left this month: ${n}',
			'streak.kBreak.mendCta' => ({required Object days}) => 'Use a Mend Card to restore your ${days}-day streak',
			'streak.kBreak.mendSuccess' => ({required Object days}) => 'Streak restored to ${days} days 🎉',
			'streak.kBreak.mendFailed' => 'Couldn\'t use the Mend Card. Please try again later.',
			'streak.kBreak.exhausted' => 'No Mend Cards left this month. You\'ll get 2 new ones on the 1st.',
			'streak.kBreak.unmendable' => 'This miss is over 7 days old and can no longer be mended. Start a fresh streak today!',
			'streak.kBreak.dismiss' => 'Got it, start fresh',
			'streak.profile.title' => 'Streak',
			'streak.profile.current' => 'Current streak',
			'streak.profile.longest' => 'Longest streak',
			'streak.profile.daysUnit' => 'days',
			'streak.profile.mendCards' => 'Mend Cards',
			'streak.profile.mendCardsValue' => ({required Object n}) => '${n} left',
			'streak.profile.mendEntry' => 'Mend now',
			'settings.title' => 'Settings',
			'settings.language.title' => 'Language',
			'settings.language.system' => 'System',
			'settings.language.zhCN' => '简体中文',
			'settings.language.en' => 'English',
			'settings.group.account' => 'Account',
			'settings.group.privacy' => 'Privacy',
			'settings.group.preferences' => 'Preferences',
			'settings.group.reminders' => 'Reminders',
			'settings.group.about' => 'About',
			'settings.account.cancelDeletion' => 'Cancel deletion',
			'settings.account.changePassword' => 'Change password',
			'settings.account.contributions' => 'My contributions',
			'settings.account.deleteAccount' => 'Delete account',
			'settings.account.deleteConfirmAction' => 'Confirm deletion',
			'settings.account.deleteConfirmBody' => 'After deletion, your phone number, profile, and all meal/fasting records will be permanently erased and cannot be recovered. Your request starts a 7-day cooling-off period: signing in during this period cancels the deletion, and your data is erased on day 7.',
			'settings.account.deleteConfirmTitle' => 'Delete your account?',
			'settings.account.deleteRequested' => 'Deletion requested — your account enters a 7-day cooling-off period',
			'settings.account.deleteScheduledBody' => ({required Object date}) => 'Deletion requested. Your account will be erased on ${date}; sign in before then to cancel.',
			'settings.account.deletionCancelled' => 'Deletion cancelled — your account is back to normal',
			'settings.account.deletionScheduled' => ({required Object days}) => 'Deletion scheduled in ${days} day(s) — you can cancel before then',
			'settings.account.logout' => 'Sign out',
			'settings.account.notLoggedIn' => 'Not signed in',
			'settings.account.phone' => 'Phone number',
			'settings.privacy.privacyPolicy' => 'Privacy Policy',
			'settings.privacy.userAgreement' => 'Terms of Service',
			'settings.privacy.exportData' => 'Export my data',
			'settings.privacy.exportSuccess' => ({required Object path}) => 'Data exported: ${path}',
			'settings.privacy.healthData' => 'Health data consent',
			'settings.privacy.healthDataSubtitle' => 'Processing of sensitive personal info such as height/weight and meal/fasting records',
			'settings.privacy.healthDataRevoked' => 'Health data consent withdrawn — nutrition targets will use defaults',
			'settings.privacy.analytics' => 'Analytics consent',
			'settings.privacy.analyticsSubtitle' => 'Anonymous usage stats that help us improve — no health data included',
			'settings.privacy.exportFailed' => 'Export failed. Check your connection and try again.',
			'settings.theme.title' => 'Theme',
			'settings.theme.system' => 'System',
			'settings.theme.light' => 'Light',
			'settings.theme.dark' => 'Dark',
			'settings.fastingPlan.title' => 'Fasting plan',
			'settings.fastingPlan.subtitle' => 'View or change your fasting plan — changes take effect at 00:00 the next day',
			'settings.reminders.notifications' => 'Notification settings',
			'settings.reminders.notificationsSubtitle' => 'Manage notification permission in system settings',
			'settings.about.version' => 'Version',
			'settings.about.disclaimer' => 'Disclaimer & special groups',
			'settings.about.checkUpdate' => 'Check for updates',
			'settings.aiModel.title' => 'AI Model',
			'settings.aiModel.provider' => 'Provider',
			'settings.aiModel.providers.custom' => 'Custom',
			'settings.aiModel.providers.deepseek' => 'DeepSeek',
			'settings.aiModel.providers.qwen' => 'Qwen',
			'settings.aiModel.providers.kimi' => 'Kimi',
			'settings.aiModel.baseUrl' => 'Base URL',
			'settings.aiModel.model' => 'Model',
			'settings.aiModel.apiKey' => 'API Key',
			'settings.aiModel.apiKeyHint' => 'Leave blank to keep unchanged',
			'settings.aiModel.baseUrlRequired' => 'Custom provider requires a Base URL',
			'settings.aiModel.modelRequired' => 'Custom provider requires a model name',
			'settings.aiModel.save' => 'Save',
			'settings.aiModel.saved' => 'AI model configuration saved',
			'settings.aiModel.test' => 'Test connection',
			'settings.aiModel.testing' => 'Testing…',
			'settings.aiModel.testOk' => 'Connection successful — model service is reachable',
			'settings.aiModel.testFail' => ({required Object reason}) => 'Connection failed: ${reason}',
			'settings.aiModel.testFailNetwork' => 'Connection failed: server unreachable — check the Base URL and your network',
			'settings.aiModel.testFailTimeout' => 'Connection failed: timed out — check your network and try again',
			'settings.aiModel.testFailAuth' => 'Connection failed: invalid API Key or insufficient permission',
			'settings.aiModel.clear' => 'Clear configuration',
			'settings.aiModel.clearConfirmTitle' => 'Clear AI model configuration?',
			'settings.aiModel.clearConfirmBody' => 'After clearing, custom food estimates will be unavailable (enable the on-device model or configure again).',
			'settings.aiModel.clearConfirmAction' => 'Clear',
			'settings.aiModel.cleared' => 'AI model configuration cleared',
			'settings.onDevice.title' => 'On-device model',
			'settings.onDevice.desc' => 'Estimate nutrition offline on this device — your data never leaves it',
			'settings.onDevice.size' => 'Model size: ~2.41 GB',
			'settings.onDevice.wifiHint' => 'Large file — Wi-Fi recommended',
			'settings.onDevice.download' => 'Download model',
			'settings.onDevice.downloading' => ({required Object percent}) => 'Downloading ${percent}%',
			'settings.onDevice.cancel' => 'Cancel',
			'settings.onDevice.paused' => ({required Object percent}) => 'Paused (${percent}% downloaded)',
			'settings.onDevice.resume' => 'Resume',
			'settings.onDevice.delete' => 'Delete model',
			'settings.onDevice.deleteConfirmTitle' => 'Delete on-device model?',
			'settings.onDevice.deleteConfirmBody' => 'You\'ll need to re-download the ~2.41 GB model to use on-device estimates again.',
			'settings.onDevice.deleteConfirmAction' => 'Delete',
			'settings.onDevice.deleted' => 'On-device model deleted',
			'settings.onDevice.ready' => 'Model ready',
			'settings.onDevice.coldLoadHint' => 'The first estimate loads the model and may take a few seconds',
			'settings.onDevice.enabled' => 'Prefer on-device estimates',
			'settings.onDevice.errorDownload' => 'Download failed — check your connection and retry',
			'settings.onDevice.errorStorage' => 'Not enough free storage (~6 GB needed) — free up space and retry',
			'settings.onDevice.errorMemory' => 'Not enough device memory for the on-device model',
			'settings.onDevice.retry' => 'Retry',
			'settings.onDevice.oomDisabled' => 'On-device estimates disabled — not enough device memory',
			'settings.onDevice.statusFailed' => 'Failed to read model status',
			'settings.chain.title' => 'Estimate routing',
			'settings.chain.onDevice' => 'On-device model',
			'settings.chain.userApi' => 'Custom API',
			'settings.chain.statusEnabled' => 'Enabled',
			'settings.chain.statusDisabled' => 'Disabled',
			'settings.chain.statusNotDownloaded' => 'Not downloaded',
			'settings.chain.statusDownloading' => 'Downloading',
			'settings.chain.statusPaused' => 'Paused',
			'settings.chain.statusError' => 'Download failed',
			'settings.chain.statusUnknown' => 'Not ready',
			'settings.chain.statusConfigured' => 'Configured',
			'settings.chain.statusNotConfigured' => 'Not configured',
			'settings.chain.current' => 'Active',
			'legal.draftNote' => '[Pending external confirmation: final legal copy]',
			'legal.consent.title' => 'Welcome to EatWise',
			'legal.consent.summary' => 'We collect and use your information as described in the Privacy Policy to provide core features like fasting timers, meal logging, and nutrition feedback. Your data is stored securely in mainland China. Please review and confirm:',
			'legal.consent.agreeMain' => 'I have read and agree to the Terms of Service and Privacy Policy',
			'legal.consent.healthTitle' => 'Separate consent for health data (optional)',
			'legal.consent.healthBody' => 'Your height, weight, age, gender, and meal/fasting records are sensitive personal information. With your separate consent, we use them to calculate personalized nutrition targets and feedback, stored encrypted in mainland China. You may decline (targets will use default values) or withdraw anytime in Settings > Privacy.',
			'legal.consent.disclaimerSummary' => 'Note: EatWise content is general healthy-lifestyle reference only — not medical advice, diagnosis, or treatment.',
			'legal.consent.specialGroupsEntry' => 'See who should not fast',
			'legal.consent.viewPrivacyPolicy' => 'Read the full Privacy Policy',
			'legal.consent.viewUserAgreement' => 'Read the full Terms of Service',
			'legal.consent.agreeAndContinue' => 'Agree and continue',
			'legal.consent.decline' => 'Decline and exit',
			'legal.disclaimer.title' => 'Disclaimer',
			'legal.disclaimer.notMedicalTitle' => 'Not Medical Advice',
			'legal.disclaimer.notMedicalBody' => 'EatWise provides content (including fasting plans, nutrition targets, signal-light feedback and suggestions) for general healthy-lifestyle reference only. It is not medical advice, diagnosis, or treatment, and is no substitute for guidance from a physician, registered dietitian, or other qualified professional. Your nutrition targets are estimated from general formulas and may not fit your individual condition. If you have any health condition, take medication, or have a disease, consult a qualified healthcare professional before fasting or changing your diet. EatWise assumes no medical liability for consequences arising from use of this information.',
			'legal.disclaimer.specialGroupsTitle' => 'Special Groups Notice',
			'legal.disclaimer.specialGroupsBody' => '⚠️ Intermittent fasting is not recommended for the following groups, or should only be done under medical supervision: pregnant or breastfeeding women; minors (under 18); people with a history of or at risk for eating disorders (e.g., anorexia, bulimia); people with diabetes (especially those using insulin or glucose-lowering medication); people with hypoglycemia or hypotension; people who are underweight (BMI < 18.5); people with chronic conditions such as gout, kidney or liver disease; people recovering from recent surgery or illness; and frail older adults. If you fall into any of these categories, do not start a fasting plan and consult your doctor first.',
			'legal.disclaimer.short' => 'EatWise content is not medical advice',
			'legal.privacyPolicy.title' => 'Privacy Policy',
			'legal.privacyPolicy.body' => 'Effective: 2026-07-27 | Version 1.0.0 [Pending external confirmation: final legal copy]\n\nEatWise ("we") provides services in mainland China only. This policy explains how we collect, use, store, and protect your personal information, and the rights you have.\n\n1. Information We Collect\n1) Phone number: for registration, sign-in, and account recovery; stored encrypted in mainland China.\n2) Height, weight, age, gender: used to compute daily nutrition targets; sensitive personal information requiring your separate consent.\n3) Meal and fasting records: required for core features; sensitive personal information.\n4) Goal, schedule, and fasting experience (3-question quiz): used for plan recommendation.\n5) Nickname and avatar: optional, for personalization and community display.\n6) Device info and push token: for notification delivery and crash analysis; we never collect IMEI/IMSI/MAC.\n7) Crash and performance logs: de-identified, retained for 6 months.\n8) Analytics events: event-level usage stats only; can be turned off in Settings > Privacy.\nWe do NOT collect: location, contacts, Bluetooth, or HealthKit/Health Connect data.\n\n2. Separate Consent for Sensitive Personal Information\nHealth-related data (height/weight, meal/fasting records) is processed only with your separate consent under PIPL Article 29. Declining does not affect account features — nutrition targets fall back to defaults — and you may withdraw anytime in Settings > Privacy.\n\n3. Storage and Security\nAll data is stored on servers in mainland China; transmission uses TLS 1.2+; phone numbers and health data use field-level encryption; the local database is fully encrypted. No data crosses borders.\n\n4. Third-Party SDKs\nWe use WeChat Login, Sign in with Apple, aggregated push, content safety, and crash monitoring SDKs, all operating within mainland China. No SDK ever receives your raw health data.\n\n5. Your Rights\n1) Access & copy: request a full export of your personal data (JSON+CSV) in Settings > Privacy > Export my data.\n2) Deletion: Settings > Account > Delete account starts a 7-day cooling-off period; signing in during this period cancels the deletion.\n3) Withdraw consent: you may withdraw health data consent and analytics consent anytime in Settings > Privacy.\n\n6. Minors\nThis product is not intended for children under 14.\n\n7. Policy Updates\nIf this policy changes materially, we will ask for your consent again.\n\n8. Contact Us\nFor questions about this policy, reach us via Settings > About in the app.',
			'legal.userAgreement.title' => 'Terms of Service',
			'legal.userAgreement.body' => 'Effective: 2026-07-27 | Version 1.0.0 [Pending external confirmation: final legal copy]\n\nWelcome to EatWise (the "App"). Please read these terms carefully before using the App.\n\n1. Services\nThe App provides healthy-lifestyle tools including intermittent fasting timers, meal logging, nutrition target estimates with signal-light feedback, trend reports, and community check-ins.\n\n2. Account\nYou may register and sign in via phone verification code, WeChat, or Sign in with Apple. Keep your account secure; you are responsible for activity under it.\n\n3. Not Medical Advice\nAll content in the App is general healthy-lifestyle reference only and is not medical advice, diagnosis, or treatment. See the Disclaimer for details.\n\n4. User Conduct\nYou agree that content you post complies with applicable laws and does not infringe others\' rights. Violating content may be removed and account features restricted.\n\n5. Intellectual Property\nThe App\'s content and software are owned by us; you receive a personal, non-commercial license to use them.\n\n6. Limitation of Liability\nWe assume no medical liability for health consequences arising from use of the App\'s information, and no liability for service interruptions caused by force majeure or third parties.\n\n7. Changes and Termination\nWe will notify you of changes to these terms via in-app notices. You may stop using the App at any time by deleting your account.\n\n8. Governing Law\nThese terms are governed by the laws of the People\'s Republic of China.',
			'social.feed.title' => 'Community',
			'social.feed.emptyTitle' => 'Waiting for today\'s first check-in to show up.',
			'social.feed.emptySubtitle' => 'Post your first check-in and light the way for others.',
			'social.feed.emptyCta' => 'Check in',
			'social.feed.errorTitle' => 'Couldn\'t load the feed. Please try again.',
			'social.feed.pendingBadge' => 'Under review — visible only to you',
			'social.feed.streakBadge' => ({required Object days}) => '${days}-day streak',
			'social.feed.like' => 'Like',
			'social.feed.report' => 'Report',
			'social.feed.reportConfirm' => 'Report this check-in? It will be taken down and sent for manual review.',
			'social.feed.reported' => 'Reported. Thanks for the heads-up.',
			'social.feed.reportFailed' => 'Couldn\'t report. Please try again later.',
			'social.feed.expand' => 'Expand',
			'social.feed.collapse' => 'Collapse',
			'social.feed.justNow' => 'Just now',
			'social.feed.minutesAgo' => ({required Object n}) => '${n} min ago',
			'social.feed.hoursAgo' => ({required Object n}) => '${n} hr ago',
			'social.feed.daysAgo' => ({required Object n}) => '${n} d ago',
			'social.feed.anonymous' => 'EatWise buddy',
			_ => null,
		} ?? switch (path) {
			'social.compose.title' => 'New check-in',
			'social.compose.hint' => 'Capture this moment of persistence…',
			'social.compose.charCount' => ({required Object n}) => '${n}/500',
			'social.compose.addPhoto' => 'Add photo',
			'social.compose.removePhoto' => 'Remove photo',
			'social.compose.photoUploading' => 'Uploading photo…',
			'social.compose.photoUploadFailed' => 'Photo upload failed',
			'social.compose.photoUploadFailedBody' => 'The photo failed to upload. You can post without it, or cancel and retry the upload.',
			'social.compose.publishWithoutPhoto' => 'Post without photo',
			'social.compose.retryUpload' => 'Try uploading again',
			'social.compose.streakBadge' => ({required Object days}) => 'Current streak: ${days} days 🔥',
			'social.compose.noStreak' => 'Finish today\'s fast and your check-in will carry the streak badge',
			'social.compose.publish' => 'Post',
			'social.compose.publishFailed' => 'Couldn\'t post. Please try again.',
			'social.compose.emptyText' => 'Write something first',
			'auth.login.title' => 'Sign in',
			'auth.login.subtitle' => 'Sign in with your username and password',
			'auth.login.phoneLabel' => 'Phone number',
			'auth.login.phoneHint' => 'Enter your 11-digit phone number',
			'auth.login.codeLabel' => 'Verification code',
			'auth.login.codeHint' => '6-digit code',
			'auth.login.sendCode' => 'Send code',
			'auth.login.resendIn' => ({required Object seconds}) => 'Resend in ${seconds}s',
			'auth.login.login' => 'Sign in',
			'auth.login.loggingIn' => 'Signing in…',
			'auth.login.codeSent' => 'Verification code sent',
			'auth.login.invalidPhone' => 'Please enter a valid phone number',
			'auth.login.invalidCode' => 'Please enter the 6-digit code',
			'auth.login.mockHint' => 'In local dev the code is always 123456',
			'auth.login.usernameLabel' => 'Username',
			'auth.login.usernameHint' => '3-20 letters, digits or underscores',
			'auth.login.passwordLabel' => 'Password',
			'auth.login.passwordHint' => 'Enter your password',
			'auth.login.invalidUsername' => 'Username must be 3-20 letters, digits or underscores',
			'auth.login.invalidPassword' => 'Password must be 8-64 characters',
			'auth.login.noAccount' => 'No account?',
			'auth.login.toRegister' => 'Sign up',
			'auth.login.otherLoginMethods' => 'Other sign-in methods',
			'auth.logout' => 'Sign out',
			'auth.logoutConfirm' => 'Sign out now? Unsynced records stay on this device.',
			'auth.loggedOut' => 'Signed out',
			'auth.register.title' => 'Sign up',
			'auth.register.subtitle' => 'Create an account to get started',
			'auth.register.usernameLabel' => 'Username',
			'auth.register.usernameHint' => '3-20 letters, digits or underscores',
			'auth.register.passwordLabel' => 'Password',
			'auth.register.passwordHint' => '8-64 characters with letters and digits',
			'auth.register.confirmPasswordLabel' => 'Confirm password',
			'auth.register.confirmPasswordHint' => 'Re-enter your password',
			'auth.register.register' => 'Sign up',
			'auth.register.registering' => 'Signing up…',
			'auth.register.passwordMismatch' => 'Passwords do not match',
			'auth.register.agreePrefix' => 'I have read and agree to the ',
			'auth.register.agreeAnd' => ' and ',
			'auth.register.agreeRequired' => 'Please agree to the Privacy Policy and Terms of Service first',
			'auth.register.strengthWeak' => 'Strength: weak',
			'auth.register.strengthMedium' => 'Strength: medium',
			'auth.register.strengthStrong' => 'Strength: strong',
			'auth.register.strengthTooShort' => 'Password must be at least 8 characters',
			'auth.register.invalidUsername' => 'Username must be 3-20 letters, digits or underscores',
			'auth.changePassword.title' => 'Change password',
			'auth.changePassword.oldLabel' => 'Current password',
			'auth.changePassword.oldHint' => 'Enter your current password',
			'auth.changePassword.oldRequired' => 'Enter your current password',
			'auth.changePassword.newLabel' => 'New password',
			'auth.changePassword.newHint' => '8-64 characters with letters and digits',
			'auth.changePassword.confirmLabel' => 'Confirm new password',
			'auth.changePassword.confirmHint' => 'Re-enter your new password',
			'auth.changePassword.submit' => 'Confirm change',
			'auth.changePassword.submitting' => 'Submitting…',
			'auth.changePassword.success' => 'Password changed — please sign in again',
			'auth.changePassword.passwordMismatch' => 'New passwords do not match',
			'auth.error.usernameTaken' => 'Username already taken',
			'auth.error.invalidCredentials' => 'Incorrect username or password',
			'auth.error.passwordTooWeak' => 'Password must be 8-64 characters with letters and digits',
			'update.title' => 'Update available',
			'update.newVersion' => ({required Object version}) => 'Latest version: ${version}',
			'update.updateNow' => 'Update now',
			'update.later' => 'Later',
			'update.upToDate' => 'You\'re on the latest version',
			'update.checkFailed' => 'Couldn\'t check for updates. Try again later.',
			'update.downloadFailed' => 'Couldn\'t open the download link. Try again later.',
			_ => null,
		};
	}
}
