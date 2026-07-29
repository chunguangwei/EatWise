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
	late final Translations$home$zh_CN home = Translations$home$zh_CN.internal(_root);
	late final Translations$notification$zh_CN notification = Translations$notification$zh_CN.internal(_root);
	late final Translations$nutrition$zh_CN nutrition = Translations$nutrition$zh_CN.internal(_root);
	late final Translations$reports$zh_CN reports = Translations$reports$zh_CN.internal(_root);
	late final Translations$streak$zh_CN streak = Translations$streak$zh_CN.internal(_root);
	late final Translations$settings$zh_CN settings = Translations$settings$zh_CN.internal(_root);
	late final Translations$social$zh_CN social = Translations$social$zh_CN.internal(_root);
	late final Translations$auth$zh_CN auth = Translations$auth$zh_CN.internal(_root);
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
	late final Translations$record$photo$zh_CN photo = Translations$record$photo$zh_CN.internal(_root);
	late final Translations$record$voice$zh_CN voice = Translations$record$voice$zh_CN.internal(_root);
	late final Translations$record$frequent$zh_CN frequent = Translations$record$frequent$zh_CN.internal(_root);
	late final Translations$record$card$zh_CN card = Translations$record$card$zh_CN.internal(_root);
	late final Translations$record$water$zh_CN water = Translations$record$water$zh_CN.internal(_root);
	late final Translations$record$weight$zh_CN weight = Translations$record$weight$zh_CN.internal(_root);
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

// Path: home
class Translations$home$zh_CN {
	Translations$home$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$home$tab$zh_CN tab = Translations$home$tab$zh_CN.internal(_root);
	late final Translations$home$data$zh_CN data = Translations$home$data$zh_CN.internal(_root);
	late final Translations$home$community$zh_CN community = Translations$home$community$zh_CN.internal(_root);
	late final Translations$home$profile$zh_CN profile = Translations$home$profile$zh_CN.internal(_root);
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
	late final Translations$nutrition$data$zh_CN data = Translations$nutrition$data$zh_CN.internal(_root);
	late final Translations$nutrition$signalCard$zh_CN signalCard = Translations$nutrition$signalCard$zh_CN.internal(_root);
}

// Path: reports
class Translations$reports$zh_CN {
	Translations$reports$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '趋势与报告'
	String get title => '趋势与报告';

	/// zh-CN: '趋势与深度报告'
	String get entry => '趋势与深度报告';

	late final Translations$reports$trend$zh_CN trend = Translations$reports$trend$zh_CN.internal(_root);
	late final Translations$reports$growth$zh_CN growth = Translations$reports$growth$zh_CN.internal(_root);
	late final Translations$reports$weekly$zh_CN weekly = Translations$reports$weekly$zh_CN.internal(_root);
	late final Translations$reports$monthly$zh_CN monthly = Translations$reports$monthly$zh_CN.internal(_root);
}

// Path: streak
class Translations$streak$zh_CN {
	Translations$streak$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$streak$home$zh_CN home = Translations$streak$home$zh_CN.internal(_root);
	late final Translations$streak$milestone$zh_CN milestone = Translations$streak$milestone$zh_CN.internal(_root);
	late final Translations$streak$kBreak$zh_CN kBreak = Translations$streak$kBreak$zh_CN.internal(_root);
	late final Translations$streak$profile$zh_CN profile = Translations$streak$profile$zh_CN.internal(_root);
}

// Path: settings
class Translations$settings$zh_CN {
	Translations$settings$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$settings$language$zh_CN language = Translations$settings$language$zh_CN.internal(_root);
}

// Path: social
class Translations$social$zh_CN {
	Translations$social$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$social$feed$zh_CN feed = Translations$social$feed$zh_CN.internal(_root);
	late final Translations$social$compose$zh_CN compose = Translations$social$compose$zh_CN.internal(_root);
}

// Path: auth
class Translations$auth$zh_CN {
	Translations$auth$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$auth$login$zh_CN login = Translations$auth$login$zh_CN.internal(_root);

	/// zh-CN: '退出登录'
	String get logout => '退出登录';

	/// zh-CN: '确定退出登录吗？未同步的记录会保留在本机。'
	String get logoutConfirm => '确定退出登录吗？未同步的记录会保留在本机。';

	/// zh-CN: '已退出登录'
	String get loggedOut => '已退出登录';
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

// Path: record.photo
class Translations$record$photo$zh_CN {
	Translations$record$photo$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '拍照识别食物'
	String get pickTitle => '拍照识别食物';

	/// zh-CN: '拍照'
	String get takePhoto => '拍照';

	/// zh-CN: '从相册选择'
	String get fromGallery => '从相册选择';

	/// zh-CN: '识别中…'
	String get recognizing => '识别中…';

	/// zh-CN: '暂时识别不了，手动搜索一样快'
	String get unavailable => '暂时识别不了，手动搜索一样快';

	/// zh-CN: '相机未授权'
	String get deniedTitle => '相机未授权';

	/// zh-CN: '拍不了照也能记，手动搜一样快'
	String get deniedBody => '拍不了照也能记，手动搜一样快';

	/// zh-CN: '去开启'
	String get openSettings => '去开启';

	/// zh-CN: '手动搜索'
	String get useManual => '手动搜索';
}

// Path: record.voice
class Translations$record$voice$zh_CN {
	Translations$record$voice$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '正在听… 说说吃了什么，如「一碗米饭」'
	String get listening => '正在听… 说说吃了什么，如「一碗米饭」';

	/// zh-CN: '点一下开始说话'
	String get tapToStart => '点一下开始说话';

	/// zh-CN: '完成'
	String get finish => '完成';

	/// zh-CN: '这台设备暂时用不了语音识别，打字搜一样快'
	String get unavailable => '这台设备暂时用不了语音识别，打字搜一样快';

	/// zh-CN: '麦克风未授权'
	String get deniedTitle => '麦克风未授权';

	/// zh-CN: '开不了语音也能记，打字搜一样快'
	String get deniedBody => '开不了语音也能记，打字搜一样快';

	/// zh-CN: '没听出是什么食物，换个说法或手动搜索'
	String get noMatch => '没听出是什么食物，换个说法或手动搜索';
}

// Path: record.frequent
class Translations$record$frequent$zh_CN {
	Translations$record$frequent$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '常吃的食物'
	String get title => '常吃的食物';

	/// zh-CN: '多记几笔，常吃榜就出来啦'
	String get empty => '多记几笔，常吃榜就出来啦';
}

// Path: record.card
class Translations$record$card$zh_CN {
	Translations$record$card$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '请确认'
	String get pleaseConfirm => '请确认';
}

// Path: record.water
class Translations$record$water$zh_CN {
	Translations$record$water$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '今日饮水'
	String get title => '今日饮水';

	/// zh-CN: '${total} / ${goal} 毫升'
	String progress({required Object total, required Object goal}) => '${total} / ${goal} 毫升';

	/// zh-CN: '加 ${ml} 毫升水'
	String quickAddLabel({required Object ml}) => '加 ${ml} 毫升水';
}

// Path: record.weight
class Translations$record$weight$zh_CN {
	Translations$record$weight$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '体重'
	String get title => '体重';

	/// zh-CN: '记一下'
	String get notLogged => '记一下';

	/// zh-CN: '${kg} 千克'
	String current({required Object kg}) => '${kg} 千克';

	/// zh-CN: '记录今日体重'
	String get dialogTitle => '记录今日体重';

	/// zh-CN: '体重（千克）'
	String get inputLabel => '体重（千克）';

	/// zh-CN: '请输入 20 到 300 之间的数'
	String get invalid => '请输入 20 到 300 之间的数';
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

	/// zh-CN: '单次最多延长 4 小时'
	String get extendLimit => '单次最多延长 4 小时';

	/// zh-CN: '${id} · 进食窗 ${start}–${end}'
	String planTag({required Object id, required Object start, required Object end}) => '${id} · 进食窗 ${start}–${end}';

	/// zh-CN: '3 个小问题，帮你找到最适合的断食节奏'
	String get noPlanSubtitle => '3 个小问题，帮你找到最适合的断食节奏';

	/// zh-CN: '断食完成！身体悄悄做了次大扫除 ✨'
	String get celebrationTitle => '断食完成！身体悄悄做了次大扫除 ✨';

	/// zh-CN: '断食完成 ✨'
	String get celebrationBadge => '断食完成 ✨';

	/// zh-CN: '今天还没记录，记一笔后信号灯会亮起来'
	String get signalEmpty => '今天还没记录，记一笔后信号灯会亮起来';

	late final Translations$fasting$home$greeting$zh_CN greeting = Translations$fasting$home$greeting$zh_CN.internal(_root);
}

// Path: home.tab
class Translations$home$tab$zh_CN {
	Translations$home$tab$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '首页'
	String get home => '首页';

	/// zh-CN: '记录'
	String get record => '记录';

	/// zh-CN: '数据'
	String get data => '数据';

	/// zh-CN: '社区'
	String get community => '社区';

	/// zh-CN: '我的'
	String get profile => '我的';
}

// Path: home.data
class Translations$home$data$zh_CN {
	Translations$home$data$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '数据曲线正在热身，多记几天它就跑起来啦。'
	String get emptyTitle => '数据曲线正在热身，多记几天它就跑起来啦。';

	/// zh-CN: '连续记录几天，趋势和信号灯就会跑起来。'
	String get emptySubtitle => '连续记录几天，趋势和信号灯就会跑起来。';

	/// zh-CN: '去记录'
	String get cta => '去记录';
}

// Path: home.community
class Translations$home$community$zh_CN {
	Translations$home$community$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '这里在等今天第一口美食登场。'
	String get emptyTitle => '这里在等今天第一口美食登场。';

	/// zh-CN: '打卡流与挑战赛正在筹备中。'
	String get emptySubtitle => '打卡流与挑战赛正在筹备中。';

	/// zh-CN: '发布打卡'
	String get cta => '发布打卡';

	/// zh-CN: '社区功能即将上线，敬请期待'
	String get comingSoon => '社区功能即将上线，敬请期待';
}

// Path: home.profile
class Translations$home$profile$zh_CN {
	Translations$home$profile$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '个人中心正在装修'
	String get emptyTitle => '个人中心正在装修';

	/// zh-CN: '方案、目标与更多设置会陆续搬进来。'
	String get emptySubtitle => '方案、目标与更多设置会陆续搬进来。';
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

// Path: nutrition.data
class Translations$nutrition$data$zh_CN {
	Translations$nutrition$data$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$nutrition$data$dateSwitcher$zh_CN dateSwitcher = Translations$nutrition$data$dateSwitcher$zh_CN.internal(_root);
	late final Translations$nutrition$data$summary$zh_CN summary = Translations$nutrition$data$summary$zh_CN.internal(_root);

	/// zh-CN: '本地预估，联网后云端自动校准'
	String get localEstimate => '本地预估，联网后云端自动校准';

	late final Translations$nutrition$data$proDetails$zh_CN proDetails = Translations$nutrition$data$proDetails$zh_CN.internal(_root);
	late final Translations$nutrition$data$trend$zh_CN trend = Translations$nutrition$data$trend$zh_CN.internal(_root);
}

// Path: nutrition.signalCard
class Translations$nutrition$signalCard$zh_CN {
	Translations$nutrition$signalCard$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$nutrition$signalCard$zone$zh_CN zone = Translations$nutrition$signalCard$zone$zh_CN.internal(_root);
	late final Translations$nutrition$signalCard$advice$zh_CN advice = Translations$nutrition$signalCard$advice$zh_CN.internal(_root);
}

// Path: reports.trend
class Translations$reports$trend$zh_CN {
	Translations$reports$trend$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '成长趋势'
	String get title => '成长趋势';

	late final Translations$reports$trend$dim$zh_CN dim = Translations$reports$trend$dim$zh_CN.internal(_root);
	late final Translations$reports$trend$range$zh_CN range = Translations$reports$trend$range$zh_CN.internal(_root);
	late final Translations$reports$trend$unit$zh_CN unit = Translations$reports$trend$unit$zh_CN.internal(_root);

	/// zh-CN: '数据曲线正在热身，多记几天它就跑起来啦'
	String get empty => '数据曲线正在热身，多记几天它就跑起来啦';

	/// zh-CN: '去记录'
	String get ctaRecord => '去记录';

	/// zh-CN: '去断食'
	String get ctaFast => '去断食';

	/// zh-CN: '记体重'
	String get ctaWeight => '记体重';
}

// Path: reports.growth
class Translations$reports$growth$zh_CN {
	Translations$reports$growth$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '${days} 天成长轨迹'
	String title({required Object days}) => '${days} 天成长轨迹';

	/// zh-CN: '断食达标'
	String get qualifiedDays => '断食达标';

	/// zh-CN: '记录天数'
	String get recordedDays => '记录天数';

	/// zh-CN: '平均断食'
	String get avgFasting => '平均断食';

	/// zh-CN: '体重变化'
	String get weightDelta => '体重变化';

	/// zh-CN: '天'
	String get daysUnit => '天';

	/// zh-CN: '小时'
	String get hourUnit => '小时';

	/// zh-CN: '公斤'
	String get kgUnit => '公斤';

	/// zh-CN: '—'
	String get noValue => '—';

	/// zh-CN: '还没有足迹，先记一笔或完成一次断食吧'
	String get empty => '还没有足迹，先记一笔或完成一次断食吧';
}

// Path: reports.weekly
class Translations$reports$weekly$zh_CN {
	Translations$reports$weekly$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '本周报告'
	String get title => '本周报告';

	/// zh-CN: '${start} – ${end}'
	String range({required Object start, required Object end}) => '${start} – ${end}';

	/// zh-CN: '达标 ${days} 天'
	String qualified({required Object days}) => '达标 ${days} 天';

	/// zh-CN: '记录 ${count} 条'
	String entries({required Object count}) => '记录 ${count} 条';

	/// zh-CN: '绿灯占比 ${percent}%'
	String greenRatio({required Object percent}) => '绿灯占比 ${percent}%';

	late final Translations$reports$weekly$cheer$zh_CN cheer = Translations$reports$weekly$cheer$zh_CN.internal(_root);

	/// zh-CN: '周报还差一点点数据，记一笔或完成一次断食就生成啦'
	String get empty => '周报还差一点点数据，记一笔或完成一次断食就生成啦';
}

// Path: reports.monthly
class Translations$reports$monthly$zh_CN {
	Translations$reports$monthly$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '本月报告'
	String get title => '本月报告';

	/// zh-CN: '月报完整版将于 V1.2 提供，先把周报跑起来～'
	String get placeholder => '月报完整版将于 V1.2 提供，先把周报跑起来～';
}

// Path: streak.home
class Translations$streak$home$zh_CN {
	Translations$streak$home$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '连续 ${days} 天 🔥'
	String streakDays({required Object days}) => '连续 ${days} 天 🔥';

	/// zh-CN: '完成今天断食，开启第 1 天'
	String get startHint => '完成今天断食，开启第 1 天';
}

// Path: streak.milestone
class Translations$streak$milestone$zh_CN {
	Translations$streak$milestone$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '连续 ${days} 天！你已经超过了 80% 的伙伴 🎉'
	String title({required Object days}) => '连续 ${days} 天！你已经超过了 80% 的伙伴 🎉';

	/// zh-CN: '${days} 天连胜'
	String badgeLabel({required Object days}) => '${days} 天连胜';

	/// zh-CN: '分享'
	String get share => '分享';

	/// zh-CN: '收下啦'
	String get accept => '收下啦';

	/// zh-CN: '分享图卡即将上线，先把这份坚持记在心里'
	String get shareComingSoon => '分享图卡即将上线，先把这份坚持记在心里';
}

// Path: streak.kBreak
class Translations$streak$kBreak$zh_CN {
	Translations$streak$kBreak$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '哎呀，连胜中断了'
	String get title => '哎呀，连胜中断了';

	/// zh-CN: '连胜只按「断食打卡达标」累计：每天按计划完成断食窗口（提前不超过 15 分钟也算达标）即连胜 +1；饮食记录天数单独统计，不影响连胜。中断后连胜归零，7 天内可用补签卡恢复。'
	String get howItWorks => '连胜只按「断食打卡达标」累计：每天按计划完成断食窗口（提前不超过 15 分钟也算达标）即连胜 +1；饮食记录天数单独统计，不影响连胜。中断后连胜归零，7 天内可用补签卡恢复。';

	/// zh-CN: '本月剩余补签卡：${n} 张'
	String cardsLeft({required Object n}) => '本月剩余补签卡：${n} 张';

	/// zh-CN: '使用补签卡，恢复 ${days} 天连胜'
	String mendCta({required Object days}) => '使用补签卡，恢复 ${days} 天连胜';

	/// zh-CN: '已恢复 ${days} 天连胜 🎉'
	String mendSuccess({required Object days}) => '已恢复 ${days} 天连胜 🎉';

	/// zh-CN: '补签失败，请稍后重试'
	String get mendFailed => '补签失败，请稍后重试';

	/// zh-CN: '本月补签卡已用完，下月 1 日将发放 2 张新卡'
	String get exhausted => '本月补签卡已用完，下月 1 日将发放 2 张新卡';

	/// zh-CN: '断签已超过 7 天，补签窗口已关闭。从今天开始新的连胜吧！'
	String get unmendable => '断签已超过 7 天，补签窗口已关闭。从今天开始新的连胜吧！';

	/// zh-CN: '知道了，重新开始'
	String get dismiss => '知道了，重新开始';
}

// Path: streak.profile
class Translations$streak$profile$zh_CN {
	Translations$streak$profile$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '连胜'
	String get title => '连胜';

	/// zh-CN: '当前连胜'
	String get current => '当前连胜';

	/// zh-CN: '历史最长'
	String get longest => '历史最长';

	/// zh-CN: '天'
	String get daysUnit => '天';

	/// zh-CN: '补签卡'
	String get mendCards => '补签卡';

	/// zh-CN: '${n} 张'
	String mendCardsValue({required Object n}) => '${n} 张';

	/// zh-CN: '去补签'
	String get mendEntry => '去补签';
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

// Path: social.feed
class Translations$social$feed$zh_CN {
	Translations$social$feed$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '社区'
	String get title => '社区';

	/// zh-CN: '这里在等今天第一口美食登场。'
	String get emptyTitle => '这里在等今天第一口美食登场。';

	/// zh-CN: '发布你的第一条打卡，给同样在坚持的人一点光。'
	String get emptySubtitle => '发布你的第一条打卡，给同样在坚持的人一点光。';

	/// zh-CN: '发布打卡'
	String get emptyCta => '发布打卡';

	/// zh-CN: '打卡流加载失败，请稍后重试'
	String get errorTitle => '打卡流加载失败，请稍后重试';

	/// zh-CN: '内容审核中，仅自己可见'
	String get pendingBadge => '内容审核中，仅自己可见';

	/// zh-CN: '连续 ${days} 天'
	String streakBadge({required Object days}) => '连续 ${days} 天';

	/// zh-CN: '点赞'
	String get like => '点赞';

	/// zh-CN: '举报'
	String get report => '举报';

	/// zh-CN: '确定举报这条打卡吗？举报后内容将下架并提交人工复核。'
	String get reportConfirm => '确定举报这条打卡吗？举报后内容将下架并提交人工复核。';

	/// zh-CN: '已举报，感谢反馈'
	String get reported => '已举报，感谢反馈';

	/// zh-CN: '举报失败，请稍后重试'
	String get reportFailed => '举报失败，请稍后重试';

	/// zh-CN: '展开'
	String get expand => '展开';

	/// zh-CN: '收起'
	String get collapse => '收起';

	/// zh-CN: '刚刚'
	String get justNow => '刚刚';

	/// zh-CN: '${n} 分钟前'
	String minutesAgo({required Object n}) => '${n} 分钟前';

	/// zh-CN: '${n} 小时前'
	String hoursAgo({required Object n}) => '${n} 小时前';

	/// zh-CN: '${n} 天前'
	String daysAgo({required Object n}) => '${n} 天前';

	/// zh-CN: 'EatWise 伙伴'
	String get anonymous => 'EatWise 伙伴';
}

// Path: social.compose
class Translations$social$compose$zh_CN {
	Translations$social$compose$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '发布打卡'
	String get title => '发布打卡';

	/// zh-CN: '记录这一刻的坚持…'
	String get hint => '记录这一刻的坚持…';

	/// zh-CN: '${n}/500'
	String charCount({required Object n}) => '${n}/500';

	/// zh-CN: '添加图片'
	String get addPhoto => '添加图片';

	/// zh-CN: '移除图片'
	String get removePhoto => '移除图片';

	/// zh-CN: '图片上传即将支持，本次先发布文字'
	String get photoUploadTodo => '图片上传即将支持，本次先发布文字';

	/// zh-CN: '当前连续 ${days} 天 🔥'
	String streakBadge({required Object days}) => '当前连续 ${days} 天 🔥';

	/// zh-CN: '完成今天的断食，打卡就会带上连胜徽章哦'
	String get noStreak => '完成今天的断食，打卡就会带上连胜徽章哦';

	/// zh-CN: '发布'
	String get publish => '发布';

	/// zh-CN: '发布失败，请稍后重试'
	String get publishFailed => '发布失败，请稍后重试';

	/// zh-CN: '先写点什么吧'
	String get emptyText => '先写点什么吧';
}

// Path: auth.login
class Translations$auth$login$zh_CN {
	Translations$auth$login$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '手机号登录'
	String get title => '手机号登录';

	/// zh-CN: '未注册的手机号验证后将自动注册'
	String get subtitle => '未注册的手机号验证后将自动注册';

	/// zh-CN: '手机号'
	String get phoneLabel => '手机号';

	/// zh-CN: '请输入 11 位手机号'
	String get phoneHint => '请输入 11 位手机号';

	/// zh-CN: '验证码'
	String get codeLabel => '验证码';

	/// zh-CN: '6 位验证码'
	String get codeHint => '6 位验证码';

	/// zh-CN: '获取验证码'
	String get sendCode => '获取验证码';

	/// zh-CN: '${seconds}s 后重新发送'
	String resendIn({required Object seconds}) => '${seconds}s 后重新发送';

	/// zh-CN: '登录'
	String get login => '登录';

	/// zh-CN: '登录中…'
	String get loggingIn => '登录中…';

	/// zh-CN: '验证码已发送，请查收'
	String get codeSent => '验证码已发送，请查收';

	/// zh-CN: '请输入正确的手机号'
	String get invalidPhone => '请输入正确的手机号';

	/// zh-CN: '请输入 6 位数字验证码'
	String get invalidCode => '请输入 6 位数字验证码';

	/// zh-CN: '本地联调环境验证码固定为 123456'
	String get mockHint => '本地联调环境验证码固定为 123456';
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

// Path: fasting.home.greeting
class Translations$fasting$home$greeting$zh_CN {
	Translations$fasting$home$greeting$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '早上好'
	String get morning => '早上好';

	/// zh-CN: '中午好'
	String get noon => '中午好';

	/// zh-CN: '下午好'
	String get afternoon => '下午好';

	/// zh-CN: '晚上好'
	String get evening => '晚上好';

	/// zh-CN: '这么晚还醒着？喝口水早点睡也是养生哦'
	String get night => '这么晚还醒着？喝口水早点睡也是养生哦';
}

// Path: nutrition.data.dateSwitcher
class Translations$nutrition$data$dateSwitcher$zh_CN {
	Translations$nutrition$data$dateSwitcher$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '前一天'
	String get prevDay => '前一天';

	/// zh-CN: '后一天'
	String get nextDay => '后一天';

	/// zh-CN: '回到今天'
	String get backToToday => '回到今天';

	/// zh-CN: '今天'
	String get today => '今天';
}

// Path: nutrition.data.summary
class Translations$nutrition$data$summary$zh_CN {
	Translations$nutrition$data$summary$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '今天的营养节奏很稳，给你点个赞 🌱'
	String get allGreen => '今天的营养节奏很稳，给你点个赞 🌱';

	/// zh-CN: '今天总体不错，个别营养素还差一点点'
	String get hasYellow => '今天总体不错，个别营养素还差一点点';

	/// zh-CN: '有几盏小红灯，别急，跟着下面的建议慢慢调'
	String get hasRed => '有几盏小红灯，别急，跟着下面的建议慢慢调';

	/// zh-CN: '这一天还没有记录，记一笔信号灯就会亮起来'
	String get empty => '这一天还没有记录，记一笔信号灯就会亮起来';

	/// zh-CN: '当前按默认目标估算，补全身体资料后会更准哦'
	String get fallbackGoal => '当前按默认目标估算，补全身体资料后会更准哦';
}

// Path: nutrition.data.proDetails
class Translations$nutrition$data$proDetails$zh_CN {
	Translations$nutrition$data$proDetails$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '专业数据'
	String get title => '专业数据';

	/// zh-CN: '查看详情'
	String get expand => '查看详情';

	/// zh-CN: '收起'
	String get collapse => '收起';

	/// zh-CN: '目标'
	String get target => '目标';

	/// zh-CN: '已摄入'
	String get actual => '已摄入';

	/// zh-CN: '占比'
	String get percent => '占比';

	/// zh-CN: 'RDA 参考'
	String get rda => 'RDA 参考';

	/// zh-CN: 'RDA 为成人通用膳食参考值〔待营养专业背书〕，个人目标以你的方案为准'
	String get rdaNote => 'RDA 为成人通用膳食参考值〔待营养专业背书〕，个人目标以你的方案为准';
}

// Path: nutrition.data.trend
class Translations$nutrition$data$trend$zh_CN {
	Translations$nutrition$data$trend$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '近 7 日趋势'
	String get title => '近 7 日趋势';

	/// zh-CN: '热量'
	String get kcal => '热量';

	/// zh-CN: '断食时长'
	String get fasting => '断食时长';

	/// zh-CN: '记满几天，趋势曲线就跑起来啦'
	String get empty => '记满几天，趋势曲线就跑起来啦';

	/// zh-CN: '小时'
	String get hourUnit => '小时';
}

// Path: nutrition.signalCard.zone
class Translations$nutrition$signalCard$zone$zh_CN {
	Translations$nutrition$signalCard$zone$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '达标'
	String get green => '达标';

	/// zh-CN: '适量提醒'
	String get yellow => '适量提醒';

	/// zh-CN: '警示'
	String get red => '警示';
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

// Path: reports.trend.dim
class Translations$reports$trend$dim$zh_CN {
	Translations$reports$trend$dim$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '体重'
	String get weight => '体重';

	/// zh-CN: '热量'
	String get kcal => '热量';

	/// zh-CN: '断食时长'
	String get fasting => '断食时长';
}

// Path: reports.trend.range
class Translations$reports$trend$range$zh_CN {
	Translations$reports$trend$range$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '7 天'
	String get d7 => '7 天';

	/// zh-CN: '30 天'
	String get d30 => '30 天';
}

// Path: reports.trend.unit
class Translations$reports$trend$unit$zh_CN {
	Translations$reports$trend$unit$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '公斤'
	String get kg => '公斤';

	/// zh-CN: '千卡'
	String get kcal => '千卡';

	/// zh-CN: '小时'
	String get hour => '小时';
}

// Path: reports.weekly.cheer
class Translations$reports$weekly$cheer$zh_CN {
	Translations$reports$weekly$cheer$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '这一周节奏超稳，给自己点个大大的赞 🌱'
	String get great => '这一周节奏超稳，给自己点个大大的赞 🌱';

	/// zh-CN: '有起有落很正常，稳住节奏，下周继续～'
	String get mixed => '有起有落很正常，稳住节奏，下周继续～';

	/// zh-CN: '先动起来就很棒，数据会陪你一起进步。'
	String get start => '先动起来就很棒，数据会陪你一起进步。';
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
			'record.photo.pickTitle' => '拍照识别食物',
			'record.photo.takePhoto' => '拍照',
			'record.photo.fromGallery' => '从相册选择',
			'record.photo.recognizing' => '识别中…',
			'record.photo.unavailable' => '暂时识别不了，手动搜索一样快',
			'record.photo.deniedTitle' => '相机未授权',
			'record.photo.deniedBody' => '拍不了照也能记，手动搜一样快',
			'record.photo.openSettings' => '去开启',
			'record.photo.useManual' => '手动搜索',
			'record.voice.listening' => '正在听… 说说吃了什么，如「一碗米饭」',
			'record.voice.tapToStart' => '点一下开始说话',
			'record.voice.finish' => '完成',
			'record.voice.unavailable' => '这台设备暂时用不了语音识别，打字搜一样快',
			'record.voice.deniedTitle' => '麦克风未授权',
			'record.voice.deniedBody' => '开不了语音也能记，打字搜一样快',
			'record.voice.noMatch' => '没听出是什么食物，换个说法或手动搜索',
			'record.frequent.title' => '常吃的食物',
			'record.frequent.empty' => '多记几笔，常吃榜就出来啦',
			'record.card.pleaseConfirm' => '请确认',
			'record.water.title' => '今日饮水',
			'record.water.progress' => ({required Object total, required Object goal}) => '${total} / ${goal} 毫升',
			'record.water.quickAddLabel' => ({required Object ml}) => '加 ${ml} 毫升水',
			'record.weight.title' => '体重',
			'record.weight.notLogged' => '记一下',
			'record.weight.current' => ({required Object kg}) => '${kg} 千克',
			'record.weight.dialogTitle' => '记录今日体重',
			'record.weight.inputLabel' => '体重（千克）',
			'record.weight.invalid' => '请输入 20 到 300 之间的数',
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
			'fasting.home.extendLimit' => '单次最多延长 4 小时',
			'fasting.home.planTag' => ({required Object id, required Object start, required Object end}) => '${id} · 进食窗 ${start}–${end}',
			'fasting.home.noPlanSubtitle' => '3 个小问题，帮你找到最适合的断食节奏',
			'fasting.home.celebrationTitle' => '断食完成！身体悄悄做了次大扫除 ✨',
			'fasting.home.celebrationBadge' => '断食完成 ✨',
			'fasting.home.signalEmpty' => '今天还没记录，记一笔后信号灯会亮起来',
			'fasting.home.greeting.morning' => '早上好',
			'fasting.home.greeting.noon' => '中午好',
			'fasting.home.greeting.afternoon' => '下午好',
			'fasting.home.greeting.evening' => '晚上好',
			'fasting.home.greeting.night' => '这么晚还醒着？喝口水早点睡也是养生哦',
			'home.tab.home' => '首页',
			'home.tab.record' => '记录',
			'home.tab.data' => '数据',
			'home.tab.community' => '社区',
			'home.tab.profile' => '我的',
			'home.data.emptyTitle' => '数据曲线正在热身，多记几天它就跑起来啦。',
			'home.data.emptySubtitle' => '连续记录几天，趋势和信号灯就会跑起来。',
			'home.data.cta' => '去记录',
			'home.community.emptyTitle' => '这里在等今天第一口美食登场。',
			'home.community.emptySubtitle' => '打卡流与挑战赛正在筹备中。',
			'home.community.cta' => '发布打卡',
			'home.community.comingSoon' => '社区功能即将上线，敬请期待',
			'home.profile.emptyTitle' => '个人中心正在装修',
			'home.profile.emptySubtitle' => '方案、目标与更多设置会陆续搬进来。',
			'notification.fasting.eatSoon' => '还有 15 分钟就可以进食啦',
			'notification.fasting.eatStart' => ({required Object date}) => '可以进食啦，本次断食计入 ${date} ✅',
			'notification.fasting.fastStart' => '断食窗口开始啦，今天也很棒，加油坚持～',
			'nutrition.data.dateSwitcher.prevDay' => '前一天',
			'nutrition.data.dateSwitcher.nextDay' => '后一天',
			'nutrition.data.dateSwitcher.backToToday' => '回到今天',
			'nutrition.data.dateSwitcher.today' => '今天',
			'nutrition.data.summary.allGreen' => '今天的营养节奏很稳，给你点个赞 🌱',
			'nutrition.data.summary.hasYellow' => '今天总体不错，个别营养素还差一点点',
			'nutrition.data.summary.hasRed' => '有几盏小红灯，别急，跟着下面的建议慢慢调',
			'nutrition.data.summary.empty' => '这一天还没有记录，记一笔信号灯就会亮起来',
			'nutrition.data.summary.fallbackGoal' => '当前按默认目标估算，补全身体资料后会更准哦',
			'nutrition.data.localEstimate' => '本地预估，联网后云端自动校准',
			'nutrition.data.proDetails.title' => '专业数据',
			'nutrition.data.proDetails.expand' => '查看详情',
			'nutrition.data.proDetails.collapse' => '收起',
			'nutrition.data.proDetails.target' => '目标',
			'nutrition.data.proDetails.actual' => '已摄入',
			'nutrition.data.proDetails.percent' => '占比',
			'nutrition.data.proDetails.rda' => 'RDA 参考',
			'nutrition.data.proDetails.rdaNote' => 'RDA 为成人通用膳食参考值〔待营养专业背书〕，个人目标以你的方案为准',
			'nutrition.data.trend.title' => '近 7 日趋势',
			'nutrition.data.trend.kcal' => '热量',
			'nutrition.data.trend.fasting' => '断食时长',
			'nutrition.data.trend.empty' => '记满几天，趋势曲线就跑起来啦',
			'nutrition.data.trend.hourUnit' => '小时',
			'nutrition.signalCard.zone.green' => '达标',
			'nutrition.signalCard.zone.yellow' => '适量提醒',
			'nutrition.signalCard.zone.red' => '警示',
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
			'reports.title' => '趋势与报告',
			'reports.entry' => '趋势与深度报告',
			'reports.trend.title' => '成长趋势',
			'reports.trend.dim.weight' => '体重',
			'reports.trend.dim.kcal' => '热量',
			'reports.trend.dim.fasting' => '断食时长',
			'reports.trend.range.d7' => '7 天',
			'reports.trend.range.d30' => '30 天',
			'reports.trend.unit.kg' => '公斤',
			'reports.trend.unit.kcal' => '千卡',
			'reports.trend.unit.hour' => '小时',
			'reports.trend.empty' => '数据曲线正在热身，多记几天它就跑起来啦',
			'reports.trend.ctaRecord' => '去记录',
			'reports.trend.ctaFast' => '去断食',
			'reports.trend.ctaWeight' => '记体重',
			'reports.growth.title' => ({required Object days}) => '${days} 天成长轨迹',
			'reports.growth.qualifiedDays' => '断食达标',
			'reports.growth.recordedDays' => '记录天数',
			'reports.growth.avgFasting' => '平均断食',
			'reports.growth.weightDelta' => '体重变化',
			'reports.growth.daysUnit' => '天',
			'reports.growth.hourUnit' => '小时',
			'reports.growth.kgUnit' => '公斤',
			'reports.growth.noValue' => '—',
			'reports.growth.empty' => '还没有足迹，先记一笔或完成一次断食吧',
			'reports.weekly.title' => '本周报告',
			'reports.weekly.range' => ({required Object start, required Object end}) => '${start} – ${end}',
			'reports.weekly.qualified' => ({required Object days}) => '达标 ${days} 天',
			'reports.weekly.entries' => ({required Object count}) => '记录 ${count} 条',
			'reports.weekly.greenRatio' => ({required Object percent}) => '绿灯占比 ${percent}%',
			'reports.weekly.cheer.great' => '这一周节奏超稳，给自己点个大大的赞 🌱',
			'reports.weekly.cheer.mixed' => '有起有落很正常，稳住节奏，下周继续～',
			'reports.weekly.cheer.start' => '先动起来就很棒，数据会陪你一起进步。',
			'reports.weekly.empty' => '周报还差一点点数据，记一笔或完成一次断食就生成啦',
			'reports.monthly.title' => '本月报告',
			'reports.monthly.placeholder' => '月报完整版将于 V1.2 提供，先把周报跑起来～',
			'streak.home.streakDays' => ({required Object days}) => '连续 ${days} 天 🔥',
			'streak.home.startHint' => '完成今天断食，开启第 1 天',
			'streak.milestone.title' => ({required Object days}) => '连续 ${days} 天！你已经超过了 80% 的伙伴 🎉',
			'streak.milestone.badgeLabel' => ({required Object days}) => '${days} 天连胜',
			'streak.milestone.share' => '分享',
			'streak.milestone.accept' => '收下啦',
			'streak.milestone.shareComingSoon' => '分享图卡即将上线，先把这份坚持记在心里',
			'streak.kBreak.title' => '哎呀，连胜中断了',
			'streak.kBreak.howItWorks' => '连胜只按「断食打卡达标」累计：每天按计划完成断食窗口（提前不超过 15 分钟也算达标）即连胜 +1；饮食记录天数单独统计，不影响连胜。中断后连胜归零，7 天内可用补签卡恢复。',
			'streak.kBreak.cardsLeft' => ({required Object n}) => '本月剩余补签卡：${n} 张',
			'streak.kBreak.mendCta' => ({required Object days}) => '使用补签卡，恢复 ${days} 天连胜',
			'streak.kBreak.mendSuccess' => ({required Object days}) => '已恢复 ${days} 天连胜 🎉',
			'streak.kBreak.mendFailed' => '补签失败，请稍后重试',
			'streak.kBreak.exhausted' => '本月补签卡已用完，下月 1 日将发放 2 张新卡',
			'streak.kBreak.unmendable' => '断签已超过 7 天，补签窗口已关闭。从今天开始新的连胜吧！',
			'streak.kBreak.dismiss' => '知道了，重新开始',
			'streak.profile.title' => '连胜',
			'streak.profile.current' => '当前连胜',
			'streak.profile.longest' => '历史最长',
			'streak.profile.daysUnit' => '天',
			'streak.profile.mendCards' => '补签卡',
			'streak.profile.mendCardsValue' => ({required Object n}) => '${n} 张',
			'streak.profile.mendEntry' => '去补签',
			'settings.language.title' => '语言',
			'settings.language.system' => '跟随系统',
			'settings.language.zhCN' => '简体中文',
			'settings.language.en' => 'English',
			'social.feed.title' => '社区',
			'social.feed.emptyTitle' => '这里在等今天第一口美食登场。',
			'social.feed.emptySubtitle' => '发布你的第一条打卡，给同样在坚持的人一点光。',
			'social.feed.emptyCta' => '发布打卡',
			'social.feed.errorTitle' => '打卡流加载失败，请稍后重试',
			'social.feed.pendingBadge' => '内容审核中，仅自己可见',
			'social.feed.streakBadge' => ({required Object days}) => '连续 ${days} 天',
			'social.feed.like' => '点赞',
			'social.feed.report' => '举报',
			'social.feed.reportConfirm' => '确定举报这条打卡吗？举报后内容将下架并提交人工复核。',
			'social.feed.reported' => '已举报，感谢反馈',
			'social.feed.reportFailed' => '举报失败，请稍后重试',
			'social.feed.expand' => '展开',
			'social.feed.collapse' => '收起',
			'social.feed.justNow' => '刚刚',
			'social.feed.minutesAgo' => ({required Object n}) => '${n} 分钟前',
			'social.feed.hoursAgo' => ({required Object n}) => '${n} 小时前',
			'social.feed.daysAgo' => ({required Object n}) => '${n} 天前',
			'social.feed.anonymous' => 'EatWise 伙伴',
			'social.compose.title' => '发布打卡',
			'social.compose.hint' => '记录这一刻的坚持…',
			'social.compose.charCount' => ({required Object n}) => '${n}/500',
			'social.compose.addPhoto' => '添加图片',
			'social.compose.removePhoto' => '移除图片',
			'social.compose.photoUploadTodo' => '图片上传即将支持，本次先发布文字',
			'social.compose.streakBadge' => ({required Object days}) => '当前连续 ${days} 天 🔥',
			'social.compose.noStreak' => '完成今天的断食，打卡就会带上连胜徽章哦',
			'social.compose.publish' => '发布',
			'social.compose.publishFailed' => '发布失败，请稍后重试',
			'social.compose.emptyText' => '先写点什么吧',
			'auth.login.title' => '手机号登录',
			'auth.login.subtitle' => '未注册的手机号验证后将自动注册',
			'auth.login.phoneLabel' => '手机号',
			'auth.login.phoneHint' => '请输入 11 位手机号',
			'auth.login.codeLabel' => '验证码',
			'auth.login.codeHint' => '6 位验证码',
			'auth.login.sendCode' => '获取验证码',
			'auth.login.resendIn' => ({required Object seconds}) => '${seconds}s 后重新发送',
			'auth.login.login' => '登录',
			'auth.login.loggingIn' => '登录中…',
			'auth.login.codeSent' => '验证码已发送，请查收',
			'auth.login.invalidPhone' => '请输入正确的手机号',
			'auth.login.invalidCode' => '请输入 6 位数字验证码',
			'auth.login.mockHint' => '本地联调环境验证码固定为 123456',
			'auth.logout' => '退出登录',
			'auth.logoutConfirm' => '确定退出登录吗？未同步的记录会保留在本机。',
			'auth.loggedOut' => '已退出登录',
			_ => null,
		};
	}
}
