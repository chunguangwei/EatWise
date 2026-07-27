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
	@override late final _Translations$common$en common = _Translations$common$en._(_root);
	@override late final _Translations$fasting$en fasting = _Translations$fasting$en._(_root);
	@override late final _Translations$record$en record = _Translations$record$en._(_root);
	@override late final _Translations$notification$en notification = _Translations$notification$en._(_root);
	@override late final _Translations$nutrition$en nutrition = _Translations$nutrition$en._(_root);
	@override late final _Translations$settings$en settings = _Translations$settings$en._(_root);
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

// Path: record
class _Translations$record$en extends Translations$record$zh_CN {
	_Translations$record$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$record$home$en home = _Translations$record$home$en._(_root);
	@override late final _Translations$record$empty$en empty = _Translations$record$empty$en._(_root);
	@override late final _Translations$record$toast$en toast = _Translations$record$toast$en._(_root);
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

// Path: record.toast
class _Translations$record$toast$en extends Translations$record$toast$zh_CN {
	_Translations$record$toast$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get recorded => 'Logged';
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
			'record.home.title' => 'Log',
			'record.home.logMeal' => 'Log a bite',
			'record.empty.title' => 'No food stories yet — tap the orange button to log your first bite?',
			'record.toast.recorded' => 'Logged',
			'notification.fasting.eatSoon' => 'Eating window opens in 15 min',
			'notification.fasting.eatStart' => ({required Object date}) => 'Time to eat! This fast counts toward ${date} ✅',
			'notification.fasting.fastStart' => 'Your fasting window has started — you\'re doing great, keep it up!',
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
			_ => null,
		};
	}
}
