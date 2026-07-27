///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsZhCn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zhCn,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh-CN>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$common$zh_CN common = Translations$common$zh_CN.internal(_root);
	late final Translations$fasting$zh_CN fasting = Translations$fasting$zh_CN.internal(_root);
	late final Translations$record$zh_CN record = Translations$record$zh_CN.internal(_root);
	late final Translations$notification$zh_CN notification = Translations$notification$zh_CN.internal(_root);
	late final Translations$nutrition$zh_CN nutrition = Translations$nutrition$zh_CN.internal(_root);
	late final Translations$settings$zh_CN settings = Translations$settings$zh_CN.internal(_root);
}

// Path: common
class Translations$common$zh_CN {
	Translations$common$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: 'EatWise'
	String get appName => 'EatWise';

	late final Translations$common$action$zh_CN action = Translations$common$action$zh_CN.internal(_root);
}

// Path: fasting
class Translations$fasting$zh_CN {
	Translations$fasting$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$fasting$home$zh_CN home = Translations$fasting$home$zh_CN.internal(_root);
}

// Path: record
class Translations$record$zh_CN {
	Translations$record$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$record$home$zh_CN home = Translations$record$home$zh_CN.internal(_root);
	late final Translations$record$empty$zh_CN empty = Translations$record$empty$zh_CN.internal(_root);
	late final Translations$record$toast$zh_CN toast = Translations$record$toast$zh_CN.internal(_root);
}

// Path: notification
class Translations$notification$zh_CN {
	Translations$notification$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$notification$fasting$zh_CN fasting = Translations$notification$fasting$zh_CN.internal(_root);
}

// Path: nutrition
class Translations$nutrition$zh_CN {
	Translations$nutrition$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$nutrition$signalCard$zh_CN signalCard = Translations$nutrition$signalCard$zh_CN.internal(_root);
}

// Path: settings
class Translations$settings$zh_CN {
	Translations$settings$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$settings$language$zh_CN language = Translations$settings$language$zh_CN.internal(_root);
}

// Path: common.action
class Translations$common$action$zh_CN {
	Translations$common$action$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '保存'
	String get save => '保存';

	/// zh-CN: '取消'
	String get cancel => '取消';

	/// zh-CN: '撤销'
	String get undo => '撤销';

	/// zh-CN: '重试'
	String get retry => '重试';
}

// Path: fasting.home
class Translations$fasting$home$zh_CN {
	Translations$fasting$home$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '断食计时'
	String get title => '断食计时';

	/// zh-CN: '结束断食'
	String get endFast => '结束断食';

	/// zh-CN: '延长'
	String get extend => '延长';

	/// zh-CN: '选择你的断食方案'
	String get startPlan => '选择你的断食方案';

	/// zh-CN: '进食窗口中'
	String get stateEating => '进食窗口中';

	/// zh-CN: '断食中'
	String get stateFasting => '断食中';

	/// zh-CN: '断食中 · 已延长'
	String get stateFastingExtended => '断食中 · 已延长';

	/// zh-CN: '还未开始断食方案'
	String get stateNoPlan => '还未开始断食方案';

	/// zh-CN: '本次断食计入 ${date}'
	String attribution({required Object date}) => '本次断食计入 ${date}';

	/// zh-CN: '已延长 +${minutes} 分钟'
	String extendedBadge({required Object minutes}) => '已延长 +${minutes} 分钟';
}

// Path: record.home
class Translations$record$home$zh_CN {
	Translations$record$home$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '记录'
	String get title => '记录';

	/// zh-CN: '记一笔'
	String get logMeal => '记一笔';
}

// Path: record.empty
class Translations$record$empty$zh_CN {
	Translations$record$empty$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '肚子的故事还没写呢，点橙色按钮记一笔？'
	String get title => '肚子的故事还没写呢，点橙色按钮记一笔？';
}

// Path: record.toast
class Translations$record$toast$zh_CN {
	Translations$record$toast$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '已记录'
	String get recorded => '已记录';
}

// Path: notification.fasting
class Translations$notification$fasting$zh_CN {
	Translations$notification$fasting$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '还有 15 分钟就可以进食啦'
	String get eatSoon => '还有 15 分钟就可以进食啦';

	/// zh-CN: '可以进食啦，本次断食计入 ${date} ✅'
	String eatStart({required Object date}) => '可以进食啦，本次断食计入 ${date} ✅';

	/// zh-CN: '断食窗口开始啦，今天也很棒，加油坚持～'
	String get fastStart => '断食窗口开始啦，今天也很棒，加油坚持～';
}

// Path: nutrition.signalCard
class Translations$nutrition$signalCard$zh_CN {
	Translations$nutrition$signalCard$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$nutrition$signalCard$advice$zh_CN advice = Translations$nutrition$signalCard$advice$zh_CN.internal(_root);
}

// Path: settings.language
class Translations$settings$language$zh_CN {
	Translations$settings$language$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '语言'
	String get title => '语言';

	/// zh-CN: '跟随系统'
	String get system => '跟随系统';

	/// zh-CN: '简体中文'
	String get zhCN => '简体中文';

	/// zh-CN: 'English'
	String get en => 'English';
}

// Path: nutrition.signalCard.advice
class Translations$nutrition$signalCard$advice$zh_CN {
	Translations$nutrition$signalCard$advice$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$nutrition$signalCard$advice$kcal$zh_CN kcal = Translations$nutrition$signalCard$advice$kcal$zh_CN.internal(_root);
	late final Translations$nutrition$signalCard$advice$protein$zh_CN protein = Translations$nutrition$signalCard$advice$protein$zh_CN.internal(_root);
	late final Translations$nutrition$signalCard$advice$carb$zh_CN carb = Translations$nutrition$signalCard$advice$carb$zh_CN.internal(_root);
	late final Translations$nutrition$signalCard$advice$fat$zh_CN fat = Translations$nutrition$signalCard$advice$fat$zh_CN.internal(_root);
	late final Translations$nutrition$signalCard$advice$meal$zh_CN meal = Translations$nutrition$signalCard$advice$meal$zh_CN.internal(_root);
}

// Path: nutrition.signalCard.advice.kcal
class Translations$nutrition$signalCard$advice$kcal$zh_CN {
	Translations$nutrition$signalCard$advice$kcal$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '今天热量刚刚好，节奏很稳，继续保持～ 🌱'
	String get green => '今天热量刚刚好，节奏很稳，继续保持～ 🌱';

	/// zh-CN: '今天吃得有点少，${meal_action}，身体会感谢你的。'
	String yellowLow({required Object meal_action}) => '今天吃得有点少，${meal_action}，身体会感谢你的。';

	/// zh-CN: '热量有一点点高，${meal_action}，就回来啦。'
	String yellowHigh({required Object meal_action}) => '热量有一点点高，${meal_action}，就回来啦。';

	/// zh-CN: '今天摄入太少了，断食之外也要好好吃饭哦，${meal_action}。'
	String redLow({required Object meal_action}) => '今天摄入太少了，断食之外也要好好吃饭哦，${meal_action}。';

	/// zh-CN: '热量小超啦，别焦虑，${meal_action}，明天又是新的一天。'
	String redHigh({required Object meal_action}) => '热量小超啦，别焦虑，${meal_action}，明天又是新的一天。';

	/// zh-CN: '好像还没记到今天的热量哦，是不是漏了一餐？'
	String get zero => '好像还没记到今天的热量哦，是不是漏了一餐？';
}

// Path: nutrition.signalCard.advice.protein
class Translations$nutrition$signalCard$advice$protein$zh_CN {
	Translations$nutrition$signalCard$advice$protein$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '蛋白质满分！肌肉群给你比心 💪'
	String get green => '蛋白质满分！肌肉群给你比心 💪';

	/// zh-CN: '蛋白质还差一点，${meal_action}，就够啦。'
	String yellowLow({required Object meal_action}) => '蛋白质还差一点，${meal_action}，就够啦。';

	/// zh-CN: '今天蛋白质有点少 🟡 ${meal_action}，给身体加点料。'
	String redLow({required Object meal_action}) => '今天蛋白质有点少 🟡 ${meal_action}，给身体加点料。';

	/// zh-CN: '蛋白质有点多啦，${meal_action}，均衡一点更舒服。'
	String redHigh({required Object meal_action}) => '蛋白质有点多啦，${meal_action}，均衡一点更舒服。';

	/// zh-CN: '好像还没记到蛋白质哦，是不是漏了一餐？'
	String get zero => '好像还没记到蛋白质哦，是不是漏了一餐？';
}

// Path: nutrition.signalCard.advice.carb
class Translations$nutrition$signalCard$advice$carb$zh_CN {
	Translations$nutrition$signalCard$advice$carb$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '碳水刚刚好，能量供应稳稳的。'
	String get green => '碳水刚刚好，能量供应稳稳的。';

	/// zh-CN: '碳水略少，${meal_action}，下午不容易犯困哦。'
	String yellowLow({required Object meal_action}) => '碳水略少，${meal_action}，下午不容易犯困哦。';

	/// zh-CN: '碳水略高，${meal_action}，让血糖稳一点。'
	String yellowHigh({required Object meal_action}) => '碳水略高，${meal_action}，让血糖稳一点。';

	/// zh-CN: '今天碳水太少了，${meal_action}，别亏待身体。'
	String redLow({required Object meal_action}) => '今天碳水太少了，${meal_action}，别亏待身体。';

	/// zh-CN: '碳水超得有点多，${meal_action}，让血糖稳一点。'
	String redHigh({required Object meal_action}) => '碳水超得有点多，${meal_action}，让血糖稳一点。';

	/// zh-CN: '好像还没记到碳水哦，是不是漏了一餐？'
	String get zero => '好像还没记到碳水哦，是不是漏了一餐？';
}

// Path: nutrition.signalCard.advice.fat
class Translations$nutrition$signalCard$advice$fat$zh_CN {
	Translations$nutrition$signalCard$advice$fat$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '脂肪摄入很健康，皮肤和气色都会喜欢。'
	String get green => '脂肪摄入很健康，皮肤和气色都会喜欢。';

	/// zh-CN: '好脂肪有点少，${meal_action}，帮助吸收维生素。'
	String yellowLow({required Object meal_action}) => '好脂肪有点少，${meal_action}，帮助吸收维生素。';

	/// zh-CN: '脂肪略高，${meal_action}，清淡一点更轻盈。'
	String yellowHigh({required Object meal_action}) => '脂肪略高，${meal_action}，清淡一点更轻盈。';

	/// zh-CN: '好脂肪太少了，${meal_action}，身体需要它们帮忙吸收维生素。'
	String redLow({required Object meal_action}) => '好脂肪太少了，${meal_action}，身体需要它们帮忙吸收维生素。';

	/// zh-CN: '脂肪有点高了，${meal_action}，清淡一点更轻盈。'
	String redHigh({required Object meal_action}) => '脂肪有点高了，${meal_action}，清淡一点更轻盈。';

	/// zh-CN: '好像还没记到脂肪哦，是不是漏了一餐？'
	String get zero => '好像还没记到脂肪哦，是不是漏了一餐？';
}

// Path: nutrition.signalCard.advice.meal
class Translations$nutrition$signalCard$advice$meal$zh_CN {
	Translations$nutrition$signalCard$advice$meal$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '早餐加个鸡蛋或一杯豆浆'
	String get breakfast => '早餐加个鸡蛋或一杯豆浆';

	/// zh-CN: '午餐来份掌心大的瘦肉或豆腐'
	String get lunch => '午餐来份掌心大的瘦肉或豆腐';

	/// zh-CN: '晚餐选清蒸/白灼，七分饱就好'
	String get dinner => '晚餐选清蒸/白灼，七分饱就好';

	/// zh-CN: '加餐来把坚果或一杯酸奶'
	String get snack => '加餐来把坚果或一杯酸奶';
}

/// The flat map containing all translations for locale <zh-CN>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'common.appName' => 'EatWise',
			'common.action.save' => '保存',
			'common.action.cancel' => '取消',
			'common.action.undo' => '撤销',
			'common.action.retry' => '重试',
			'fasting.home.title' => '断食计时',
			'fasting.home.endFast' => '结束断食',
			'fasting.home.extend' => '延长',
			'fasting.home.startPlan' => '选择你的断食方案',
			'fasting.home.stateEating' => '进食窗口中',
			'fasting.home.stateFasting' => '断食中',
			'fasting.home.stateFastingExtended' => '断食中 · 已延长',
			'fasting.home.stateNoPlan' => '还未开始断食方案',
			'fasting.home.attribution' => ({required Object date}) => '本次断食计入 ${date}',
			'fasting.home.extendedBadge' => ({required Object minutes}) => '已延长 +${minutes} 分钟',
			'record.home.title' => '记录',
			'record.home.logMeal' => '记一笔',
			'record.empty.title' => '肚子的故事还没写呢，点橙色按钮记一笔？',
			'record.toast.recorded' => '已记录',
			'notification.fasting.eatSoon' => '还有 15 分钟就可以进食啦',
			'notification.fasting.eatStart' => ({required Object date}) => '可以进食啦，本次断食计入 ${date} ✅',
			'notification.fasting.fastStart' => '断食窗口开始啦，今天也很棒，加油坚持～',
			'nutrition.signalCard.advice.kcal.green' => '今天热量刚刚好，节奏很稳，继续保持～ 🌱',
			'nutrition.signalCard.advice.kcal.yellowLow' => ({required Object meal_action}) => '今天吃得有点少，${meal_action}，身体会感谢你的。',
			'nutrition.signalCard.advice.kcal.yellowHigh' => ({required Object meal_action}) => '热量有一点点高，${meal_action}，就回来啦。',
			'nutrition.signalCard.advice.kcal.redLow' => ({required Object meal_action}) => '今天摄入太少了，断食之外也要好好吃饭哦，${meal_action}。',
			'nutrition.signalCard.advice.kcal.redHigh' => ({required Object meal_action}) => '热量小超啦，别焦虑，${meal_action}，明天又是新的一天。',
			'nutrition.signalCard.advice.kcal.zero' => '好像还没记到今天的热量哦，是不是漏了一餐？',
			'nutrition.signalCard.advice.protein.green' => '蛋白质满分！肌肉群给你比心 💪',
			'nutrition.signalCard.advice.protein.yellowLow' => ({required Object meal_action}) => '蛋白质还差一点，${meal_action}，就够啦。',
			'nutrition.signalCard.advice.protein.redLow' => ({required Object meal_action}) => '今天蛋白质有点少 🟡 ${meal_action}，给身体加点料。',
			'nutrition.signalCard.advice.protein.redHigh' => ({required Object meal_action}) => '蛋白质有点多啦，${meal_action}，均衡一点更舒服。',
			'nutrition.signalCard.advice.protein.zero' => '好像还没记到蛋白质哦，是不是漏了一餐？',
			'nutrition.signalCard.advice.carb.green' => '碳水刚刚好，能量供应稳稳的。',
			'nutrition.signalCard.advice.carb.yellowLow' => ({required Object meal_action}) => '碳水略少，${meal_action}，下午不容易犯困哦。',
			'nutrition.signalCard.advice.carb.yellowHigh' => ({required Object meal_action}) => '碳水略高，${meal_action}，让血糖稳一点。',
			'nutrition.signalCard.advice.carb.redLow' => ({required Object meal_action}) => '今天碳水太少了，${meal_action}，别亏待身体。',
			'nutrition.signalCard.advice.carb.redHigh' => ({required Object meal_action}) => '碳水超得有点多，${meal_action}，让血糖稳一点。',
			'nutrition.signalCard.advice.carb.zero' => '好像还没记到碳水哦，是不是漏了一餐？',
			'nutrition.signalCard.advice.fat.green' => '脂肪摄入很健康，皮肤和气色都会喜欢。',
			'nutrition.signalCard.advice.fat.yellowLow' => ({required Object meal_action}) => '好脂肪有点少，${meal_action}，帮助吸收维生素。',
			'nutrition.signalCard.advice.fat.yellowHigh' => ({required Object meal_action}) => '脂肪略高，${meal_action}，清淡一点更轻盈。',
			'nutrition.signalCard.advice.fat.redLow' => ({required Object meal_action}) => '好脂肪太少了，${meal_action}，身体需要它们帮忙吸收维生素。',
			'nutrition.signalCard.advice.fat.redHigh' => ({required Object meal_action}) => '脂肪有点高了，${meal_action}，清淡一点更轻盈。',
			'nutrition.signalCard.advice.fat.zero' => '好像还没记到脂肪哦，是不是漏了一餐？',
			'nutrition.signalCard.advice.meal.breakfast' => '早餐加个鸡蛋或一杯豆浆',
			'nutrition.signalCard.advice.meal.lunch' => '午餐来份掌心大的瘦肉或豆腐',
			'nutrition.signalCard.advice.meal.dinner' => '晚餐选清蒸/白灼，七分饱就好',
			'nutrition.signalCard.advice.meal.snack' => '加餐来把坚果或一杯酸奶',
			'settings.language.title' => '语言',
			'settings.language.system' => '跟随系统',
			'settings.language.zhCN' => '简体中文',
			'settings.language.en' => 'English',
			_ => null,
		};
	}
}
