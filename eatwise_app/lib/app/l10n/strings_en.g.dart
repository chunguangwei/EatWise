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
	@override late final _Translations$settings$en settings = _Translations$settings$en._(_root);
	@override late final _Translations$auth$en auth = _Translations$auth$en._(_root);
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
	@override late final _Translations$record$voice$en voice = _Translations$record$voice$en._(_root);
	@override late final _Translations$record$frequent$en frequent = _Translations$record$frequent$en._(_root);
	@override late final _Translations$record$card$en card = _Translations$record$card$en._(_root);
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
	@override late final _Translations$nutrition$signalCard$en signalCard = _Translations$nutrition$signalCard$en._(_root);
}

// Path: settings
class _Translations$settings$en extends Translations$settings$zh_CN {
	_Translations$settings$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$language$en language = _Translations$settings$language$en._(_root);
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

// Path: nutrition.signalCard
class _Translations$nutrition$signalCard$en extends Translations$nutrition$signalCard$zh_CN {
	_Translations$nutrition$signalCard$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$nutrition$signalCard$zone$en zone = _Translations$nutrition$signalCard$zone$en._(_root);
	@override late final _Translations$nutrition$signalCard$advice$en advice = _Translations$nutrition$signalCard$advice$en._(_root);
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

// Path: auth.login
class _Translations$auth$login$en extends Translations$auth$login$zh_CN {
	_Translations$auth$login$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sign in with phone';
	@override String get subtitle => 'New numbers are registered automatically after verification';
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
			'record.home.title' => 'Log',
			'record.home.logMeal' => 'Log a bite',
			'record.empty.title' => 'No food stories yet — tap the orange button to log your first bite?',
			'common.appName' => 'EatWise',
			'common.action.save' => 'Save',
			'common.action.cancel' => 'Cancel',
			'common.action.undo' => 'Undo',
			'common.action.retry' => 'Retry',
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
			'settings.language.title' => 'Language',
			'settings.language.system' => 'System',
			'settings.language.zhCN' => '简体中文',
			'settings.language.en' => 'English',
			'auth.login.title' => 'Sign in with phone',
			'auth.login.subtitle' => 'New numbers are registered automatically after verification',
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
			'auth.logout' => 'Sign out',
			'auth.logoutConfirm' => 'Sign out now? Unsynced records stay on this device.',
			'auth.loggedOut' => 'Signed out',
			_ => null,
		};
	}
}
