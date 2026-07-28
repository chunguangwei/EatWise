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
	late final Translations$notify$zh_CN notify = Translations$notify$zh_CN.internal(_root);
	late final Translations$onboarding$zh_CN onboarding = Translations$onboarding$zh_CN.internal(_root);
	late final Translations$record$zh_CN record = Translations$record$zh_CN.internal(_root);
	late final Translations$common$zh_CN common = Translations$common$zh_CN.internal(_root);
	late final Translations$fasting$zh_CN fasting = Translations$fasting$zh_CN.internal(_root);
	late final Translations$notification$zh_CN notification = Translations$notification$zh_CN.internal(_root);
	late final Translations$nutrition$zh_CN nutrition = Translations$nutrition$zh_CN.internal(_root);
	late final Translations$settings$zh_CN settings = Translations$settings$zh_CN.internal(_root);
}

// Path: notify
class Translations$notify$zh_CN {
	Translations$notify$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$notify$channel$zh_CN channel = Translations$notify$channel$zh_CN.internal(_root);

	/// zh-CN: '开启通知，到点提醒你进食与断食'
	String get permissionBanner => '开启通知，到点提醒你进食与断食';

	/// zh-CN: '系统省电策略可能延迟提醒，建议允许精确闹钟'
	String get exactAlarmHint => '系统省电策略可能延迟提醒，建议允许精确闹钟';
}

// Path: onboarding
class Translations$onboarding$zh_CN {
	Translations$onboarding$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$onboarding$quiz$zh_CN quiz = Translations$onboarding$quiz$zh_CN.internal(_root);
	late final Translations$onboarding$plans$zh_CN plans = Translations$onboarding$plans$zh_CN.internal(_root);
	late final Translations$onboarding$recommendation$zh_CN recommendation = Translations$onboarding$recommendation$zh_CN.internal(_root);
	late final Translations$onboarding$science$zh_CN science = Translations$onboarding$science$zh_CN.internal(_root);
}

// Path: record
class Translations$record$zh_CN {
	Translations$record$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$record$page$zh_CN page = Translations$record$page$zh_CN.internal(_root);
	late final Translations$record$entries$zh_CN entries = Translations$record$entries$zh_CN.internal(_root);
	late final Translations$record$pending$zh_CN pending = Translations$record$pending$zh_CN.internal(_root);
	late final Translations$record$search$zh_CN search = Translations$record$search$zh_CN.internal(_root);
	late final Translations$record$amount$zh_CN amount = Translations$record$amount$zh_CN.internal(_root);
	late final Translations$record$nutrition$zh_CN nutrition = Translations$record$nutrition$zh_CN.internal(_root);
	late final Translations$record$toast$zh_CN toast = Translations$record$toast$zh_CN.internal(_root);
	late final Translations$record$home$zh_CN home = Translations$record$home$zh_CN.internal(_root);
	late final Translations$record$empty$zh_CN empty = Translations$record$empty$zh_CN.internal(_root);
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

// Path: notify.channel
class Translations$notify$channel$zh_CN {
	Translations$notify$channel$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$notify$channel$fastingReminders$zh_CN fastingReminders = Translations$notify$channel$fastingReminders$zh_CN.internal(_root);
}

// Path: onboarding.quiz
class Translations$onboarding$quiz$zh_CN {
	Translations$onboarding$quiz$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '3 个小问题，帮你找到最适合的断食节奏 🌱'
	String get title => '3 个小问题，帮你找到最适合的断食节奏 🌱';

	/// zh-CN: '第 ${step} 题，共 ${total} 题'
	String progress({required Object step, required Object total}) => '第 ${step} 题，共 ${total} 题';

	/// zh-CN: '跳过，先看看'
	String get skip => '跳过，先看看';

	/// zh-CN: '继续'
	String get next => '继续';

	/// zh-CN: '看看我的方案'
	String get finish => '看看我的方案';

	/// zh-CN: '上一题'
	String get back => '上一题';

	late final Translations$onboarding$quiz$q1$zh_CN q1 = Translations$onboarding$quiz$q1$zh_CN.internal(_root);
	late final Translations$onboarding$quiz$q2$zh_CN q2 = Translations$onboarding$quiz$q2$zh_CN.internal(_root);
	late final Translations$onboarding$quiz$q3$zh_CN q3 = Translations$onboarding$quiz$q3$zh_CN.internal(_root);
}

// Path: onboarding.plans
class Translations$onboarding$plans$zh_CN {
	Translations$onboarding$plans$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$onboarding$plans$p14x10$zh_CN p14x10 = Translations$onboarding$plans$p14x10$zh_CN.internal(_root);
	late final Translations$onboarding$plans$p16x8$zh_CN p16x8 = Translations$onboarding$plans$p16x8$zh_CN.internal(_root);
	late final Translations$onboarding$plans$p18x6$zh_CN p18x6 = Translations$onboarding$plans$p18x6$zh_CN.internal(_root);
	late final Translations$onboarding$plans$p5x2$zh_CN p5x2 = Translations$onboarding$plans$p5x2$zh_CN.internal(_root);
}

// Path: onboarding.recommendation
class Translations$onboarding$recommendation$zh_CN {
	Translations$onboarding$recommendation$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '为你推荐的方案'
	String get title => '为你推荐的方案';

	/// zh-CN: '主推荐'
	String get mainBadge => '主推荐';

	/// zh-CN: '也可以试试'
	String get altTitle => '也可以试试';

	/// zh-CN: '选这个'
	String get select => '选这个';

	/// zh-CN: '已选择'
	String get selected => '已选择';

	/// zh-CN: '一键启动'
	String get startNow => '一键启动';

	/// zh-CN: '进食窗口 ${start}–${end}'
	String window({required Object start, required Object end}) => '进食窗口 ${start}–${end}';

	/// zh-CN: '断食是什么原理？'
	String get scienceLink => '断食是什么原理？';

	/// zh-CN: '后续版本提供'
	String get comingSoon => '后续版本提供';

	late final Translations$onboarding$recommendation$reason$zh_CN reason = Translations$onboarding$recommendation$reason$zh_CN.internal(_root);

	/// zh-CN: '你的作息不太固定，进食窗口可以随时自由调整，跟着生活节奏走就好。'
	String get flexibleHint => '你的作息不太固定，进食窗口可以随时自由调整，跟着生活节奏走就好。';

	/// zh-CN: '每日营养目标先按 ${kcal} kcal 估算，去「我的」补全身高体重后会更准哦。'
	String fallbackNotice({required Object kcal}) => '每日营养目标先按 ${kcal} kcal 估算，去「我的」补全身高体重后会更准哦。';
}

// Path: onboarding.science
class Translations$onboarding$science$zh_CN {
	Translations$onboarding$science$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '断食原理小科普'
	String get title => '断食原理小科普';

	/// zh-CN: '给身体一点休息时间'
	String get card1Title => '给身体一点休息时间';

	/// zh-CN: '断食期间，身体会慢慢切换到燃脂模式，用储存的能量供能。'
	String get card1Body => '断食期间，身体会慢慢切换到燃脂模式，用储存的能量供能。';

	/// zh-CN: '不是节食，是节奏'
	String get card2Title => '不是节食，是节奏';

	/// zh-CN: '轻断食关注「什么时候吃」，而不是「这不能吃那不能吃」，进食窗口里好好吃饭很重要。'
	String get card2Body => '轻断食关注「什么时候吃」，而不是「这不能吃那不能吃」，进食窗口里好好吃饭很重要。';

	/// zh-CN: '本内容仅为健康科普，非医疗建议。如有基础疾病，或在孕期、哺乳期等特殊情况，请先咨询医生。'
	String get disclaimer => '本内容仅为健康科普，非医疗建议。如有基础疾病，或在孕期、哺乳期等特殊情况，请先咨询医生。';

	/// zh-CN: '返回'
	String get back => '返回';
}

// Path: record.page
class Translations$record$page$zh_CN {
	Translations$record$page$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '记录'
	String get title => '记录';

	/// zh-CN: '确认记录'
	String get confirm => '确认记录';

	/// zh-CN: '今日已记 ${count} 笔'
	String loggedToday({required Object count}) => '今日已记 ${count} 笔';

	/// zh-CN: '今日约 ${kcal} 千卡（待云端校准）'
	String todayKcal({required Object kcal}) => '今日约 ${kcal} 千卡（待云端校准）';
}

// Path: record.entries
class Translations$record$entries$zh_CN {
	Translations$record$entries$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '拍照记'
	String get photo => '拍照记';

	/// zh-CN: '语音记'
	String get voice => '语音记';

	/// zh-CN: '常吃'
	String get frequent => '常吃';

	/// zh-CN: '即将上线，先用手动搜索记一笔吧'
	String get comingSoon => '即将上线，先用手动搜索记一笔吧';
}

// Path: record.pending
class Translations$record$pending$zh_CN {
	Translations$record$pending$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '还有 ${count} 条记录在路上，联网后自动同步'
	String banner({required Object count}) => '还有 ${count} 条记录在路上，联网后自动同步';
}

// Path: record.search
class Translations$record$search$zh_CN {
	Translations$record$search$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '搜索食物（中文或英文）'
	String get hint => '搜索食物（中文或英文）';

	/// zh-CN: '没找到？换个关键词试试'
	String get empty => '没找到？换个关键词试试';
}

// Path: record.amount
class Translations$record$amount$zh_CN {
	Translations$record$amount$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '份量（克）'
	String get label => '份量（克）';

	/// zh-CN: '请输入大于 0 的份量'
	String get invalid => '请输入大于 0 的份量';
}

// Path: record.nutrition
class Translations$record$nutrition$zh_CN {
	Translations$record$nutrition$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '热量'
	String get kcal => '热量';

	/// zh-CN: '蛋白质'
	String get protein => '蛋白质';

	/// zh-CN: '碳水'
	String get carb => '碳水';

	/// zh-CN: '脂肪'
	String get fat => '脂肪';

	/// zh-CN: '千卡'
	String get kcalUnit => '千卡';

	/// zh-CN: '克'
	String get gramUnit => '克';
}

// Path: record.toast
class Translations$record$toast$zh_CN {
	Translations$record$toast$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '已记录'
	String get recorded => '已记录';

	/// zh-CN: '撤销'
	String get undo => '撤销';

	/// zh-CN: '已撤销'
	String get undone => '已撤销';

	/// zh-CN: '这条记录没被保存，请重新提交'
	String get syncFailed => '这条记录没被保存，请重新提交';
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

// Path: notify.channel.fastingReminders
class Translations$notify$channel$fastingReminders$zh_CN {
	Translations$notify$channel$fastingReminders$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '断食提醒'
	String get name => '断食提醒';

	/// zh-CN: '进食窗口与断食窗口的到点提醒'
	String get description => '进食窗口与断食窗口的到点提醒';
}

// Path: onboarding.quiz.q1
class Translations$onboarding$quiz$q1$zh_CN {
	Translations$onboarding$quiz$q1$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '你的小目标是？'
	String get title => '你的小目标是？';

	late final Translations$onboarding$quiz$q1$options$zh_CN options = Translations$onboarding$quiz$q1$options$zh_CN.internal(_root);
}

// Path: onboarding.quiz.q2
class Translations$onboarding$quiz$q2$zh_CN {
	Translations$onboarding$quiz$q2$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '你现在的作息是？'
	String get title => '你现在的作息是？';

	late final Translations$onboarding$quiz$q2$options$zh_CN options = Translations$onboarding$quiz$q2$options$zh_CN.internal(_root);
}

// Path: onboarding.quiz.q3
class Translations$onboarding$quiz$q3$zh_CN {
	Translations$onboarding$quiz$q3$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '之前试过轻断食吗？'
	String get title => '之前试过轻断食吗？';

	late final Translations$onboarding$quiz$q3$options$zh_CN options = Translations$onboarding$quiz$q3$options$zh_CN.internal(_root);
}

// Path: onboarding.plans.p14x10
class Translations$onboarding$plans$p14x10$zh_CN {
	Translations$onboarding$plans$p14x10$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '14:10 温和入门'
	String get name => '14:10 温和入门';

	/// zh-CN: '每天断食 14 小时、进食窗口 10 小时，身体几乎无感，最容易坚持。'
	String get desc => '每天断食 14 小时、进食窗口 10 小时，身体几乎无感，最容易坚持。';
}

// Path: onboarding.plans.p16x8
class Translations$onboarding$plans$p16x8$zh_CN {
	Translations$onboarding$plans$p16x8$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '16:8 经典节奏'
	String get name => '16:8 经典节奏';

	/// zh-CN: '每天断食 16 小时、进食窗口 8 小时，人气最高的经典方案。'
	String get desc => '每天断食 16 小时、进食窗口 8 小时，人气最高的经典方案。';
}

// Path: onboarding.plans.p18x6
class Translations$onboarding$plans$p18x6$zh_CN {
	Translations$onboarding$plans$p18x6$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '18:6 进阶挑战'
	String get name => '18:6 进阶挑战';

	/// zh-CN: '每天断食 18 小时，适合已有经验、想更进一步的你。'
	String get desc => '每天断食 18 小时，适合已有经验、想更进一步的你。';
}

// Path: onboarding.plans.p5x2
class Translations$onboarding$plans$p5x2$zh_CN {
	Translations$onboarding$plans$p5x2$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '5:2 轻断食'
	String get name => '5:2 轻断食';

	/// zh-CN: '每周 5 天正常吃、2 天轻断食。完整计时流将在后续版本提供，先了解为主。'
	String get desc => '每周 5 天正常吃、2 天轻断食。完整计时流将在后续版本提供，先了解为主。';
}

// Path: onboarding.recommendation.reason
class Translations$onboarding$recommendation$reason$zh_CN {
	Translations$onboarding$recommendation$reason$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '零基础起步，14:10 最温和，先让身体慢慢习惯节奏。'
	String get beginner => '零基础起步，14:10 最温和，先让身体慢慢习惯节奏。';

	/// zh-CN: '之前试过没坚持？16:8 配上灵活的窗口，这次轻轻松松来。'
	String get triedButStopped => '之前试过没坚持？16:8 配上灵活的窗口，这次轻轻松松来。';

	/// zh-CN: '有经验的你，16:8 稳定输出，状态好还能进阶 18:6。'
	String get experienced => '有经验的你，16:8 稳定输出，状态好还能进阶 18:6。';

	/// zh-CN: '想改善体检指标又有经验，18:6 更适合你，记得循序渐进哦。'
	String get healthUpgrade => '想改善体检指标又有经验，18:6 更适合你，记得循序渐进哦。';

	/// zh-CN: '先按人气最高的 16:8 开始，随时可以在「我的」里调整。'
	String get fallback => '先按人气最高的 16:8 开始，随时可以在「我的」里调整。';
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

// Path: onboarding.quiz.q1.options
class Translations$onboarding$quiz$q1$options$zh_CN {
	Translations$onboarding$quiz$q1$options$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '减脂塑形'
	String get loseWeight => '减脂塑形';

	/// zh-CN: '改善体检指标'
	String get improveHealth => '改善体检指标';

	/// zh-CN: '调整作息'
	String get adjustSchedule => '调整作息';

	/// zh-CN: '先试试看'
	String get justTrying => '先试试看';
}

// Path: onboarding.quiz.q2.options
class Translations$onboarding$quiz$q2$options$zh_CN {
	Translations$onboarding$quiz$q2$options$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '规律（朝九晚五）'
	String get regular => '规律（朝九晚五）';

	/// zh-CN: '轮班或夜班'
	String get shiftWork => '轮班或夜班';

	/// zh-CN: '自由职业·不规律'
	String get flexible => '自由职业·不规律';
}

// Path: onboarding.quiz.q3.options
class Translations$onboarding$quiz$q3$options$zh_CN {
	Translations$onboarding$quiz$q3$options$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '零基础'
	String get beginner => '零基础';

	/// zh-CN: '试过但没坚持'
	String get triedButStopped => '试过但没坚持';

	/// zh-CN: '有断食经验'
	String get experienced => '有断食经验';
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
			'notify.channel.fastingReminders.name' => '断食提醒',
			'notify.channel.fastingReminders.description' => '进食窗口与断食窗口的到点提醒',
			'notify.permissionBanner' => '开启通知，到点提醒你进食与断食',
			'notify.exactAlarmHint' => '系统省电策略可能延迟提醒，建议允许精确闹钟',
			'onboarding.quiz.title' => '3 个小问题，帮你找到最适合的断食节奏 🌱',
			'onboarding.quiz.progress' => ({required Object step, required Object total}) => '第 ${step} 题，共 ${total} 题',
			'onboarding.quiz.skip' => '跳过，先看看',
			'onboarding.quiz.next' => '继续',
			'onboarding.quiz.finish' => '看看我的方案',
			'onboarding.quiz.back' => '上一题',
			'onboarding.quiz.q1.title' => '你的小目标是？',
			'onboarding.quiz.q1.options.loseWeight' => '减脂塑形',
			'onboarding.quiz.q1.options.improveHealth' => '改善体检指标',
			'onboarding.quiz.q1.options.adjustSchedule' => '调整作息',
			'onboarding.quiz.q1.options.justTrying' => '先试试看',
			'onboarding.quiz.q2.title' => '你现在的作息是？',
			'onboarding.quiz.q2.options.regular' => '规律（朝九晚五）',
			'onboarding.quiz.q2.options.shiftWork' => '轮班或夜班',
			'onboarding.quiz.q2.options.flexible' => '自由职业·不规律',
			'onboarding.quiz.q3.title' => '之前试过轻断食吗？',
			'onboarding.quiz.q3.options.beginner' => '零基础',
			'onboarding.quiz.q3.options.triedButStopped' => '试过但没坚持',
			'onboarding.quiz.q3.options.experienced' => '有断食经验',
			'onboarding.plans.p14x10.name' => '14:10 温和入门',
			'onboarding.plans.p14x10.desc' => '每天断食 14 小时、进食窗口 10 小时，身体几乎无感，最容易坚持。',
			'onboarding.plans.p16x8.name' => '16:8 经典节奏',
			'onboarding.plans.p16x8.desc' => '每天断食 16 小时、进食窗口 8 小时，人气最高的经典方案。',
			'onboarding.plans.p18x6.name' => '18:6 进阶挑战',
			'onboarding.plans.p18x6.desc' => '每天断食 18 小时，适合已有经验、想更进一步的你。',
			'onboarding.plans.p5x2.name' => '5:2 轻断食',
			'onboarding.plans.p5x2.desc' => '每周 5 天正常吃、2 天轻断食。完整计时流将在后续版本提供，先了解为主。',
			'onboarding.recommendation.title' => '为你推荐的方案',
			'onboarding.recommendation.mainBadge' => '主推荐',
			'onboarding.recommendation.altTitle' => '也可以试试',
			'onboarding.recommendation.select' => '选这个',
			'onboarding.recommendation.selected' => '已选择',
			'onboarding.recommendation.startNow' => '一键启动',
			'onboarding.recommendation.window' => ({required Object start, required Object end}) => '进食窗口 ${start}–${end}',
			'onboarding.recommendation.scienceLink' => '断食是什么原理？',
			'onboarding.recommendation.comingSoon' => '后续版本提供',
			'onboarding.recommendation.reason.beginner' => '零基础起步，14:10 最温和，先让身体慢慢习惯节奏。',
			'onboarding.recommendation.reason.triedButStopped' => '之前试过没坚持？16:8 配上灵活的窗口，这次轻轻松松来。',
			'onboarding.recommendation.reason.experienced' => '有经验的你，16:8 稳定输出，状态好还能进阶 18:6。',
			'onboarding.recommendation.reason.healthUpgrade' => '想改善体检指标又有经验，18:6 更适合你，记得循序渐进哦。',
			'onboarding.recommendation.reason.fallback' => '先按人气最高的 16:8 开始，随时可以在「我的」里调整。',
			'onboarding.recommendation.flexibleHint' => '你的作息不太固定，进食窗口可以随时自由调整，跟着生活节奏走就好。',
			'onboarding.recommendation.fallbackNotice' => ({required Object kcal}) => '每日营养目标先按 ${kcal} kcal 估算，去「我的」补全身高体重后会更准哦。',
			'onboarding.science.title' => '断食原理小科普',
			'onboarding.science.card1Title' => '给身体一点休息时间',
			'onboarding.science.card1Body' => '断食期间，身体会慢慢切换到燃脂模式，用储存的能量供能。',
			'onboarding.science.card2Title' => '不是节食，是节奏',
			'onboarding.science.card2Body' => '轻断食关注「什么时候吃」，而不是「这不能吃那不能吃」，进食窗口里好好吃饭很重要。',
			'onboarding.science.disclaimer' => '本内容仅为健康科普，非医疗建议。如有基础疾病，或在孕期、哺乳期等特殊情况，请先咨询医生。',
			'onboarding.science.back' => '返回',
			'record.page.title' => '记录',
			'record.page.confirm' => '确认记录',
			'record.page.loggedToday' => ({required Object count}) => '今日已记 ${count} 笔',
			'record.page.todayKcal' => ({required Object kcal}) => '今日约 ${kcal} 千卡（待云端校准）',
			'record.entries.photo' => '拍照记',
			'record.entries.voice' => '语音记',
			'record.entries.frequent' => '常吃',
			'record.entries.comingSoon' => '即将上线，先用手动搜索记一笔吧',
			'record.pending.banner' => ({required Object count}) => '还有 ${count} 条记录在路上，联网后自动同步',
			'record.search.hint' => '搜索食物（中文或英文）',
			'record.search.empty' => '没找到？换个关键词试试',
			'record.amount.label' => '份量（克）',
			'record.amount.invalid' => '请输入大于 0 的份量',
			'record.nutrition.kcal' => '热量',
			'record.nutrition.protein' => '蛋白质',
			'record.nutrition.carb' => '碳水',
			'record.nutrition.fat' => '脂肪',
			'record.nutrition.kcalUnit' => '千卡',
			'record.nutrition.gramUnit' => '克',
			'record.toast.recorded' => '已记录',
			'record.toast.undo' => '撤销',
			'record.toast.undone' => '已撤销',
			'record.toast.syncFailed' => '这条记录没被保存，请重新提交',
			'record.home.title' => '记录',
			'record.home.logMeal' => '记一笔',
			'record.empty.title' => '肚子的故事还没写呢，点橙色按钮记一笔？',
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
