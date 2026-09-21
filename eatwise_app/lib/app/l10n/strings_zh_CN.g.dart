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
	late final Translations$legal$zh_CN legal = Translations$legal$zh_CN.internal(_root);
	late final Translations$social$zh_CN social = Translations$social$zh_CN.internal(_root);
	late final Translations$auth$zh_CN auth = Translations$auth$zh_CN.internal(_root);
	late final Translations$update$zh_CN update = Translations$update$zh_CN.internal(_root);
	late final Translations$moderation$zh_CN moderation = Translations$moderation$zh_CN.internal(_root);
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
	late final Translations$onboarding$profile$zh_CN profile = Translations$onboarding$profile$zh_CN.internal(_root);
	late final Translations$onboarding$goal$zh_CN goal = Translations$onboarding$goal$zh_CN.internal(_root);
}

// Path: record
class Translations$record$zh_CN {
	Translations$record$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$record$page$zh_CN page = Translations$record$page$zh_CN.internal(_root);
	late final Translations$record$meal$zh_CN meal = Translations$record$meal$zh_CN.internal(_root);
	late final Translations$record$today$zh_CN today = Translations$record$today$zh_CN.internal(_root);
	late final Translations$record$entries$zh_CN entries = Translations$record$entries$zh_CN.internal(_root);
	late final Translations$record$pending$zh_CN pending = Translations$record$pending$zh_CN.internal(_root);
	late final Translations$record$search$zh_CN search = Translations$record$search$zh_CN.internal(_root);
	late final Translations$record$amount$zh_CN amount = Translations$record$amount$zh_CN.internal(_root);
	late final Translations$record$nutrition$zh_CN nutrition = Translations$record$nutrition$zh_CN.internal(_root);
	late final Translations$record$toast$zh_CN toast = Translations$record$toast$zh_CN.internal(_root);
	late final Translations$record$photo$zh_CN photo = Translations$record$photo$zh_CN.internal(_root);
	late final Translations$record$barcode$zh_CN barcode = Translations$record$barcode$zh_CN.internal(_root);
	late final Translations$record$voice$zh_CN voice = Translations$record$voice$zh_CN.internal(_root);
	late final Translations$record$frequent$zh_CN frequent = Translations$record$frequent$zh_CN.internal(_root);
	late final Translations$record$card$zh_CN card = Translations$record$card$zh_CN.internal(_root);
	late final Translations$record$customFood$zh_CN customFood = Translations$record$customFood$zh_CN.internal(_root);
	late final Translations$record$water$zh_CN water = Translations$record$water$zh_CN.internal(_root);
	late final Translations$record$weight$zh_CN weight = Translations$record$weight$zh_CN.internal(_root);
	late final Translations$record$exercise$zh_CN exercise = Translations$record$exercise$zh_CN.internal(_root);
	late final Translations$record$home$zh_CN home = Translations$record$home$zh_CN.internal(_root);
	late final Translations$record$empty$zh_CN empty = Translations$record$empty$zh_CN.internal(_root);
	late final Translations$record$duringFast$zh_CN duringFast = Translations$record$duringFast$zh_CN.internal(_root);
	late final Translations$record$foodDetail$zh_CN foodDetail = Translations$record$foodDetail$zh_CN.internal(_root);
}

// Path: common
class Translations$common$zh_CN {
	Translations$common$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: 'EatWise'
	String get appName => 'EatWise';

	late final Translations$common$action$zh_CN action = Translations$common$action$zh_CN.internal(_root);
	late final Translations$common$error$zh_CN error = Translations$common$error$zh_CN.internal(_root);
}

// Path: fasting
class Translations$fasting$zh_CN {
	Translations$fasting$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$fasting$home$zh_CN home = Translations$fasting$home$zh_CN.internal(_root);
	late final Translations$fasting$window$zh_CN window = Translations$fasting$window$zh_CN.internal(_root);
	late final Translations$fasting$widget$zh_CN widget = Translations$fasting$widget$zh_CN.internal(_root);
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
	late final Translations$notification$water$zh_CN water = Translations$notification$water$zh_CN.internal(_root);
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
	late final Translations$reports$weeklySummary$zh_CN weeklySummary = Translations$reports$weeklySummary$zh_CN.internal(_root);
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

	/// zh-CN: '设置'
	String get title => '设置';

	late final Translations$settings$language$zh_CN language = Translations$settings$language$zh_CN.internal(_root);
	late final Translations$settings$group$zh_CN group = Translations$settings$group$zh_CN.internal(_root);
	late final Translations$settings$account$zh_CN account = Translations$settings$account$zh_CN.internal(_root);
	late final Translations$settings$privacy$zh_CN privacy = Translations$settings$privacy$zh_CN.internal(_root);
	late final Translations$settings$health$zh_CN health = Translations$settings$health$zh_CN.internal(_root);
	late final Translations$settings$theme$zh_CN theme = Translations$settings$theme$zh_CN.internal(_root);
	late final Translations$settings$fastingPlan$zh_CN fastingPlan = Translations$settings$fastingPlan$zh_CN.internal(_root);
	late final Translations$settings$bodyProfile$zh_CN bodyProfile = Translations$settings$bodyProfile$zh_CN.internal(_root);
	late final Translations$settings$reminders$zh_CN reminders = Translations$settings$reminders$zh_CN.internal(_root);
	late final Translations$settings$about$zh_CN about = Translations$settings$about$zh_CN.internal(_root);
	late final Translations$settings$aiModel$zh_CN aiModel = Translations$settings$aiModel$zh_CN.internal(_root);
	late final Translations$settings$onDevice$zh_CN onDevice = Translations$settings$onDevice$zh_CN.internal(_root);
	late final Translations$settings$chain$zh_CN chain = Translations$settings$chain$zh_CN.internal(_root);
}

// Path: legal
class Translations$legal$zh_CN {
	Translations$legal$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '〔待外部确认：法务终稿〕'
	String get draftNote => '〔待外部确认：法务终稿〕';

	late final Translations$legal$consent$zh_CN consent = Translations$legal$consent$zh_CN.internal(_root);
	late final Translations$legal$disclaimer$zh_CN disclaimer = Translations$legal$disclaimer$zh_CN.internal(_root);
	late final Translations$legal$privacyPolicy$zh_CN privacyPolicy = Translations$legal$privacyPolicy$zh_CN.internal(_root);
	late final Translations$legal$userAgreement$zh_CN userAgreement = Translations$legal$userAgreement$zh_CN.internal(_root);
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

	late final Translations$auth$register$zh_CN register = Translations$auth$register$zh_CN.internal(_root);
	late final Translations$auth$changePassword$zh_CN changePassword = Translations$auth$changePassword$zh_CN.internal(_root);
	late final Translations$auth$error$zh_CN error = Translations$auth$error$zh_CN.internal(_root);
}

// Path: update
class Translations$update$zh_CN {
	Translations$update$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '发现新版本'
	String get title => '发现新版本';

	/// zh-CN: '最新版本：${version}'
	String newVersion({required Object version}) => '最新版本：${version}';

	/// zh-CN: '立即更新'
	String get updateNow => '立即更新';

	/// zh-CN: '以后再说'
	String get later => '以后再说';

	/// zh-CN: '当前已是最新版本'
	String get upToDate => '当前已是最新版本';

	/// zh-CN: '检查更新失败，请稍后重试'
	String get checkFailed => '检查更新失败，请稍后重试';

	/// zh-CN: '下载中 ${percent}%'
	String downloading({required Object percent}) => '下载中 ${percent}%';

	/// zh-CN: '下载中…'
	String get downloadingNoProgress => '下载中…';

	/// zh-CN: '下载失败，请检查网络后重试'
	String get downloadFailed => '下载失败，请检查网络后重试';

	/// zh-CN: '重试'
	String get retry => '重试';
}

// Path: moderation
class Translations$moderation$zh_CN {
	Translations$moderation$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '审批中心'
	String get title => '审批中心';

	/// zh-CN: '审核用户贡献的食品'
	String get subtitle => '审核用户贡献的食品';

	/// zh-CN: '暂无待审批的食品候选'
	String get empty => '暂无待审批的食品候选';

	/// zh-CN: '通过'
	String get approve => '通过';

	/// zh-CN: '驳回'
	String get reject => '驳回';

	/// zh-CN: '通过后该食品将进入共享食物库，所有用户都能搜到。确认通过？'
	String get approveConfirm => '通过后该食品将进入共享食物库，所有用户都能搜到。确认通过？';

	/// zh-CN: '驳回该候选'
	String get rejectConfirmTitle => '驳回该候选';

	/// zh-CN: '驳回后提交者的相关记录将被移除。'
	String get rejectConfirmBody => '驳回后提交者的相关记录将被移除。';

	/// zh-CN: '驳回原因（可选）'
	String get reasonHint => '驳回原因（可选）';

	/// zh-CN: '已通过'
	String get approved => '已通过';

	/// zh-CN: '已驳回'
	String get rejected => '已驳回';

	/// zh-CN: '自定义食品'
	String get kindCustom => '自定义食品';

	/// zh-CN: '条码商品'
	String get kindBarcode => '条码商品';

	/// zh-CN: '数据纠错'
	String get kindCorrection => '数据纠错';

	/// zh-CN: '条码：${code}'
	String barcodeLabel({required Object code}) => '条码：${code}';

	/// zh-CN: '提交于 ${date}'
	String submittedAt({required Object date}) => '提交于 ${date}';

	/// zh-CN: '建议值'
	String get suggestionTitle => '建议值';

	/// zh-CN: '当前值'
	String get currentTitle => '当前值';

	/// zh-CN: '每100克：${kcal} 千卡 · 蛋白 ${protein}g · 碳水 ${carb}g · 脂肪 ${fat}g'
	String per100gSummary({required Object kcal, required Object protein, required Object carb, required Object fat}) => '每100克：${kcal} 千卡 · 蛋白 ${protein}g · 碳水 ${carb}g · 脂肪 ${fat}g';

	/// zh-CN: '加载失败，下拉重试'
	String get loadFailed => '加载失败，下拉重试';
}

// Path: notify.channel
class Translations$notify$channel$zh_CN {
	Translations$notify$channel$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$notify$channel$fastingReminders$zh_CN fastingReminders = Translations$notify$channel$fastingReminders$zh_CN.internal(_root);
	late final Translations$notify$channel$general$zh_CN general = Translations$notify$channel$general$zh_CN.internal(_root);
	late final Translations$notify$channel$waterReminders$zh_CN waterReminders = Translations$notify$channel$waterReminders$zh_CN.internal(_root);
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

	/// zh-CN: '更换断食方案'
	String get planChangeTitle => '更换断食方案';

	/// zh-CN: '新方案将于 ${date} 00:00 生效，今天仍按当前方案计时。'
	String planChangeConfirm({required Object date}) => '新方案将于 ${date} 00:00 生效，今天仍按当前方案计时。';

	/// zh-CN: '预计每周减 ${rate} kg · 约 ${date} 达成'
	String weightLossPlan({required Object rate, required Object date}) => '预计每周减 ${rate} kg · 约 ${date} 达成';

	/// zh-CN: '每日热量目标约 ${kcal} kcal'
	String dailyKcalTarget({required Object kcal}) => '每日热量目标约 ${kcal} kcal';

	/// zh-CN: '你的目标节奏偏快，已按安全上限调整为每周最多减 1 kg。'
	String get clampedNotice => '你的目标节奏偏快，已按安全上限调整为每周最多减 1 kg。';

	/// zh-CN: '已为你按温和节奏安排，每周最多减 0.5 kg。'
	String get gentleNotice => '已为你按温和节奏安排，每周最多减 0.5 kg。';

	/// zh-CN: '你提到有进食障碍相关经历：减重目标已按温和节奏调整。本应用不提供医疗建议，建议同步咨询专业医生或营养师。'
	String get edNotice => '你提到有进食障碍相关经历：减重目标已按温和节奏调整。本应用不提供医疗建议，建议同步咨询专业医生或营养师。';
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

// Path: onboarding.profile
class Translations$onboarding$profile$zh_CN {
	Translations$onboarding$profile$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '了解你的身体，目标更精准'
	String get title => '了解你的身体，目标更精准';

	/// zh-CN: '以下信息仅用于计算每日营养目标，属敏感个人信息：可以整页跳过，也可以只填部分；留空项将使用默认估算。'
	String get subtitle => '以下信息仅用于计算每日营养目标，属敏感个人信息：可以整页跳过，也可以只填部分；留空项将使用默认估算。';

	/// zh-CN: '生理性别（用于热量公式）'
	String get genderLabel => '生理性别（用于热量公式）';

	late final Translations$onboarding$profile$gender$zh_CN gender = Translations$onboarding$profile$gender$zh_CN.internal(_root);

	/// zh-CN: '出生年份'
	String get birthYearLabel => '出生年份';

	/// zh-CN: '如 1995'
	String get birthYearHint => '如 1995';

	/// zh-CN: '请输入 ${min}–${max} 之间的年份'
	String birthYearInvalid({required Object min, required Object max}) => '请输入 ${min}–${max} 之间的年份';

	/// zh-CN: '身高（cm）'
	String get heightLabel => '身高（cm）';

	/// zh-CN: '如 168'
	String get heightHint => '如 168';

	/// zh-CN: '请输入 100–250 之间的身高'
	String get heightInvalid => '请输入 100–250 之间的身高';

	/// zh-CN: '体重（kg）'
	String get weightLabel => '体重（kg）';

	/// zh-CN: '体重（斤）'
	String get weightLabelJin => '体重（斤）';

	/// zh-CN: '如 60'
	String get weightHint => '如 60';

	/// zh-CN: '如 120'
	String get weightHintJin => '如 120';

	/// zh-CN: '请输入 25–300 之间的体重'
	String get weightInvalid => '请输入 25–300 之间的体重';

	/// zh-CN: '请输入 50–600 之间的体重（斤）'
	String get weightInvalidJin => '请输入 50–600 之间的体重（斤）';

	/// zh-CN: '公斤'
	String get weightUnitKg => '公斤';

	/// zh-CN: '斤'
	String get weightUnitJin => '斤';

	/// zh-CN: '日常活动量'
	String get activityLabel => '日常活动量';

	late final Translations$onboarding$profile$activity$zh_CN activity = Translations$onboarding$profile$activity$zh_CN.internal(_root);

	/// zh-CN: '保存并继续'
	String get save => '保存并继续';

	/// zh-CN: '跳过，使用默认估算'
	String get skip => '跳过，使用默认估算';

	late final Translations$onboarding$profile$screening$zh_CN screening = Translations$onboarding$profile$screening$zh_CN.internal(_root);
}

// Path: onboarding.goal
class Translations$onboarding$goal$zh_CN {
	Translations$onboarding$goal$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '定个减重小目标'
	String get title => '定个减重小目标';

	/// zh-CN: '填上目标体重和日期，就能按安全节奏算出每天的热量目标；也可以跳过，先按默认折算。'
	String get subtitle => '填上目标体重和日期，就能按安全节奏算出每天的热量目标；也可以跳过，先按默认折算。';

	/// zh-CN: '目标体重（kg）'
	String get targetWeightLabel => '目标体重（kg）';

	/// zh-CN: '目标体重（斤）'
	String get targetWeightLabelJin => '目标体重（斤）';

	/// zh-CN: '如 55'
	String get targetWeightHint => '如 55';

	/// zh-CN: '如 110'
	String get targetWeightHintJin => '如 110';

	/// zh-CN: '请输入 25–300 之间的体重'
	String get targetWeightInvalid => '请输入 25–300 之间的体重';

	/// zh-CN: '请输入 50–600 之间的体重（斤）'
	String get targetWeightInvalidJin => '请输入 50–600 之间的体重（斤）';

	/// zh-CN: '希望在哪天达成？'
	String get targetDateLabel => '希望在哪天达成？';

	/// zh-CN: '${weeks} 周后'
	String quickWeeks({required Object weeks}) => '${weeks} 周后';

	/// zh-CN: '自选日期'
	String get customDate => '自选日期';

	/// zh-CN: '清除日期'
	String get clearDate => '清除日期';

	/// zh-CN: '保存并继续'
	String get save => '保存并继续';

	/// zh-CN: '跳过'
	String get skip => '跳过';
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

// Path: record.meal
class Translations$record$meal$zh_CN {
	Translations$record$meal$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '餐次'
	String get label => '餐次';

	/// zh-CN: '早餐'
	String get breakfast => '早餐';

	/// zh-CN: '午餐'
	String get lunch => '午餐';

	/// zh-CN: '晚餐'
	String get dinner => '晚餐';

	/// zh-CN: '加餐'
	String get snack => '加餐';

	/// zh-CN: '其他'
	String get other => '其他';
}

// Path: record.today
class Translations$record$today$zh_CN {
	Translations$record$today$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '今日记录'
	String get title => '今日记录';

	/// zh-CN: '删除这条记录？'
	String get deleteEntry => '删除这条记录？';

	/// zh-CN: '删除'
	String get deleteConfirmAction => '删除';

	/// zh-CN: '已删除'
	String get deleted => '已删除';
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

	/// zh-CN: '记运动'
	String get exercise => '记运动';

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

	/// zh-CN: '清空搜索'
	String get clear => '清空搜索';

	/// zh-CN: '添加「${query}」为自定义食物'
	String addRow({required Object query}) => '添加「${query}」为自定义食物';
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

	/// zh-CN: '钠'
	String get sodium => '钠';

	/// zh-CN: '千卡'
	String get kcalUnit => '千卡';

	/// zh-CN: '千焦'
	String get kjUnit => '千焦';

	/// zh-CN: '克'
	String get gramUnit => '克';

	/// zh-CN: '毫克'
	String get mgUnit => '毫克';
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

	/// zh-CN: '未识别到食物'
	String get noFoodTitle => '未识别到食物';

	/// zh-CN: '换个角度拍，或手动搜索试试'
	String get noFoodHint => '换个角度拍，或手动搜索试试';

	/// zh-CN: '知道了'
	String get gotIt => '知道了';

	/// zh-CN: '重新拍摄'
	String get retake => '重新拍摄';

	/// zh-CN: '首次识别需要加载视觉引擎，可能需要几秒'
	String get recognizingHint => '首次识别需要加载视觉引擎，可能需要几秒';

	/// zh-CN: '正在加载视觉模型…'
	String get loadingModel => '正在加载视觉模型…';

	/// zh-CN: '确认这餐明细'
	String get mealConfirmTitle => '确认这餐明细';

	/// zh-CN: '全部记录'
	String get logAll => '全部记录';

	/// zh-CN: '已记录 ${count} 条'
	String loggedItems({required Object count}) => '已记录 ${count} 条';

	/// zh-CN: '库未收录，将自动新建'
	String get unmatchedItemTag => '库未收录，将自动新建';

	/// zh-CN: '标签值'
	String get labelValueTag => '标签值';

	/// zh-CN: 'AI 识别需要一个模型'
	String get engineGuideTitle => 'AI 识别需要一个模型';

	/// zh-CN: '下载本地模型（离线可用，约 2.4GB，下载后无需联网），或配置云端 API 使用你的模型服务。'
	String get engineGuideBody => '下载本地模型（离线可用，约 2.4GB，下载后无需联网），或配置云端 API 使用你的模型服务。';

	/// zh-CN: '下载本地模型（推荐）'
	String get engineGuideDownload => '下载本地模型（推荐）';

	/// zh-CN: '配置云端 API'
	String get engineGuideConfigApi => '配置云端 API';

	/// zh-CN: '先手动搜索'
	String get engineGuideManual => '先手动搜索';

	/// zh-CN: '库中已有相似食物：'
	String get similarFoodsTitle => '库中已有相似食物：';

	/// zh-CN: '用这个'
	String get useThisFood => '用这个';

	/// zh-CN: '已记录 ${count} 条（${pending} 条待审核）'
	String loggedWithPending({required Object count, required Object pending}) => '已记录 ${count} 条（${pending} 条待审核）';
}

// Path: record.barcode
class Translations$record$barcode$zh_CN {
	Translations$record$barcode$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '扫码记'
	String get entry => '扫码记';

	/// zh-CN: '扫描商品条码'
	String get title => '扫描商品条码';

	/// zh-CN: '照明灯'
	String get torch => '照明灯';

	/// zh-CN: '手动输码'
	String get manualInput => '手动输码';

	/// zh-CN: '输入条码'
	String get manualTitle => '输入条码';

	/// zh-CN: '请输入包装上的 8–14 位数字条码'
	String get manualHint => '请输入包装上的 8–14 位数字条码';

	/// zh-CN: '查询'
	String get manualConfirm => '查询';

	/// zh-CN: '条码格式不正确，应为 8–14 位数字'
	String get invalid => '条码格式不正确，应为 8–14 位数字';

	/// zh-CN: '查询中…'
	String get looking => '查询中…';

	/// zh-CN: '未收录该商品'
	String get notFoundTitle => '未收录该商品';

	/// zh-CN: '食物库里还没有这个商品，你可以补充商品信息（拍营养表提交审核，通过后大家都能扫到），或手动搜索、添加自定义食物。'
	String get notFoundBody => '食物库里还没有这个商品，你可以补充商品信息（拍营养表提交审核，通过后大家都能扫到），或手动搜索、添加自定义食物。';

	/// zh-CN: '手动搜索'
	String get notFoundSearch => '手动搜索';

	/// zh-CN: '添加自定义食物'
	String get notFoundCustom => '添加自定义食物';

	/// zh-CN: '补充商品信息'
	String get notFoundContribute => '补充商品信息';

	/// zh-CN: '查询失败，请检查网络后重试'
	String get unavailable => '查询失败，请检查网络后重试';

	/// zh-CN: '相机未授权'
	String get deniedTitle => '相机未授权';

	/// zh-CN: '扫不了码也能记，手动搜索或输码一样快'
	String get deniedBody => '扫不了码也能记，手动搜索或输码一样快';

	/// zh-CN: '去开启'
	String get openSettings => '去开启';

	/// zh-CN: '手动搜索'
	String get useManual => '手动搜索';

	late final Translations$record$barcode$contribute$zh_CN contribute = Translations$record$barcode$contribute$zh_CN.internal(_root);
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

	/// zh-CN: '没找到匹配的食物，换个说法搜索或添加自定义食物'
	String get noMatchTyped => '没找到匹配的食物，换个说法搜索或添加自定义食物';

	/// zh-CN: '键盘输入'
	String get typeInput => '键盘输入';

	/// zh-CN: '说一句，比如「中午吃了一碗牛肉面加个蛋」'
	String get typeHint => '说一句，比如「中午吃了一碗牛肉面加个蛋」';

	/// zh-CN: '理解中…'
	String get understanding => '理解中…';

	/// zh-CN: '没听清，请再说一次，或点右边键盘图标打字'
	String get noSpeechHint => '没听清，请再说一次，或点右边键盘图标打字';

	/// zh-CN: '语音识别不可用，点右边键盘图标打字输入'
	String get errorGeneric => '语音识别不可用，点右边键盘图标打字输入';

	/// zh-CN: '正在录音… 再点一下停止'
	String get recordingNow => '正在录音… 再点一下停止';

	/// zh-CN: '转写中…'
	String get transcribingNow => '转写中…';

	/// zh-CN: '没转写出来，再录一次，或点右边键盘图标打字'
	String get transcribeFailed => '没转写出来，再录一次，或点右边键盘图标打字';

	/// zh-CN: '再说一次'
	String get retry => '再说一次';

	/// zh-CN: '用离线小模型识别'
	String get useOnDeviceAsr => '用离线小模型识别';

	/// zh-CN: '正在加载离线模型，首次较慢…'
	String get loadingModel => '正在加载离线模型，首次较慢…';

	/// zh-CN: '下载离线模型'
	String get downloadTitle => '下载离线模型';
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

	/// zh-CN: '去搜一搜'
	String get emptyCta => '去搜一搜';
}

// Path: record.card
class Translations$record$card$zh_CN {
	Translations$record$card$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '请确认'
	String get pleaseConfirm => '请确认';
}

// Path: record.customFood
class Translations$record$customFood$zh_CN {
	Translations$record$customFood$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '找不到？添加自定义食物'
	String get cta => '找不到？添加自定义食物';

	/// zh-CN: '自定义'
	String get badge => '自定义';

	/// zh-CN: '添加自定义食物'
	String get title => '添加自定义食物';

	/// zh-CN: '菜名'
	String get nameLabel => '菜名';

	/// zh-CN: '请输入菜名'
	String get nameRequired => '请输入菜名';

	/// zh-CN: '别名（可选，逗号分隔）'
	String get aliasLabel => '别名（可选，逗号分隔）';

	/// zh-CN: 'AI 估算'
	String get estimate => 'AI 估算';

	/// zh-CN: '估算中…'
	String get estimating => '估算中…';

	/// zh-CN: '置信度较低，请仔细核对数值'
	String get estimateLow => '置信度较低，请仔细核对数值';

	/// zh-CN: '估算暂不可用，请手动填写'
	String get estimateUnavailable => '估算暂不可用，请手动填写';

	/// zh-CN: '端侧估算，请确认'
	String get estimateBadgeOnDevice => '端侧估算，请确认';

	/// zh-CN: '自定义 API 估算，请确认'
	String get estimateBadgeUserApi => '自定义 API 估算，请确认';

	/// zh-CN: '估算存疑，请核对数值'
	String get estimateDubious => '估算存疑，请核对数值';

	/// zh-CN: '热量（千卡 / 100 克）'
	String get kcalLabel => '热量（千卡 / 100 克）';

	/// zh-CN: '蛋白质（克 / 100 克）'
	String get proteinLabel => '蛋白质（克 / 100 克）';

	/// zh-CN: '碳水（克 / 100 克）'
	String get carbLabel => '碳水（克 / 100 克）';

	/// zh-CN: '脂肪（克 / 100 克）'
	String get fatLabel => '脂肪（克 / 100 克）';

	/// zh-CN: '请填写大于 0 的数值'
	String get nutritionRequired => '请填写大于 0 的数值';

	/// zh-CN: '热量需在 0–900 千卡之间'
	String get kcalRange => '热量需在 0–900 千卡之间';

	/// zh-CN: '需在 0–100 克之间'
	String get macroRange => '需在 0–100 克之间';

	/// zh-CN: '已保存到本机，联网后自动同步'
	String get savedOffline => '已保存到本机，联网后自动同步';

	/// zh-CN: '已保存'
	String get savedOnline => '已保存';

	/// zh-CN: '分享给所有用户（审核通过后大家都能搜到）'
	String get shareOptIn => '分享给所有用户（审核通过后大家都能搜到）';

	/// zh-CN: '分享给所有用户'
	String get shareAction => '分享给所有用户';

	/// zh-CN: '已提交审核'
	String get submittedReview => '已提交审核';

	/// zh-CN: '审核中'
	String get badgePending => '审核中';

	/// zh-CN: '已共享'
	String get badgeApproved => '已共享';

	/// zh-CN: '未通过'
	String get badgeRejected => '未通过';

	/// zh-CN: '社区'
	String get badgeCommunity => '社区';

	/// zh-CN: '你提交的食品「${name}」未通过审核，相关记录已移除'
	String reviewRejectedNotice({required Object name}) => '你提交的食品「${name}」未通过审核，相关记录已移除';

	/// zh-CN: '编辑自定义食物'
	String get editTitle => '编辑自定义食物';

	/// zh-CN: '编辑'
	String get editAction => '编辑';

	/// zh-CN: '保存修改'
	String get editSave => '保存修改';

	/// zh-CN: '删除'
	String get deleteAction => '删除';

	/// zh-CN: '删除这个自定义食物？'
	String get deleteConfirmTitle => '删除这个自定义食物？';

	/// zh-CN: '(one) {将同时删除 ${n} 条相关历史记录，此操作不可撤销} (other) {将同时删除 ${n} 条相关历史记录，此操作不可撤销}'
	String deleteConfirmBody({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '将同时删除 ${n} 条相关历史记录，此操作不可撤销',
		other: '将同时删除 ${n} 条相关历史记录，此操作不可撤销',
	);

	/// zh-CN: '(one) {已删除（含 ${n} 条记录）} (other) {已删除（含 ${n} 条记录）}'
	String deleteDone({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '已删除（含 ${n} 条记录）',
		other: '已删除（含 ${n} 条记录）',
	);

	/// zh-CN: '该食物正在审核中，暂时无法删除，请先等待审核完成'
	String get underReviewDeleteBlocked => '该食物正在审核中，暂时无法删除，请先等待审核完成';

	late final Translations$record$customFood$contributions$zh_CN contributions = Translations$record$customFood$contributions$zh_CN.internal(_root);
	late final Translations$record$customFood$correction$zh_CN correction = Translations$record$customFood$correction$zh_CN.internal(_root);

	/// zh-CN: '拍营养表'
	String get photoOcr => '拍营养表';

	/// zh-CN: '读表中…'
	String get photoOcrReading => '读表中…';

	/// zh-CN: '没读出来，换个角度拍或手动填写'
	String get photoOcrFailed => '没读出来，换个角度拍或手动填写';

	/// zh-CN: 'AI 读表，请核对'
	String get estimateBadgeOcr => 'AI 读表，请核对';
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

	/// zh-CN: '体重（斤）'
	String get inputLabelJin => '体重（斤）';

	/// zh-CN: '请输入 20 到 300 之间的数'
	String get invalid => '请输入 20 到 300 之间的数';

	/// zh-CN: '请输入 40 到 600 之间的数（斤）'
	String get invalidJin => '请输入 40 到 600 之间的数（斤）';

	/// zh-CN: '千克'
	String get unitKg => '千克';

	/// zh-CN: '斤'
	String get unitJin => '斤';

	/// zh-CN: '体脂率（%，可不填）'
	String get bodyFatLabel => '体脂率（%，可不填）';

	/// zh-CN: '体脂率需在 1–70% 之间'
	String get bodyFatInvalid => '体脂率需在 1–70% 之间';
}

// Path: record.exercise
class Translations$record$exercise$zh_CN {
	Translations$record$exercise$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '记运动'
	String get title => '记运动';

	/// zh-CN: '运动类型'
	String get typeLabel => '运动类型';

	/// zh-CN: '时长（分钟）'
	String get durationLabel => '时长（分钟）';

	/// zh-CN: '消耗（千卡）'
	String get kcalLabel => '消耗（千卡）';

	/// zh-CN: '未填体重，按 60 千克估算'
	String get estimatedWeightHint => '未填体重，按 60 千克估算';

	/// zh-CN: '请输入大于 0 的分钟数'
	String get durationInvalid => '请输入大于 0 的分钟数';

	/// zh-CN: '请输入大于 0 的千卡数'
	String get kcalInvalid => '请输入大于 0 的千卡数';

	/// zh-CN: '今日运动'
	String get todayList => '今日运动';

	/// zh-CN: '${min} 分钟'
	String minutesValue({required Object min}) => '${min} 分钟';

	/// zh-CN: '${kcal} 千卡'
	String kcalValue({required Object kcal}) => '${kcal} 千卡';

	/// zh-CN: '步数（步）'
	String get stepsLabel => '步数（步）';

	/// zh-CN: '填步数则按步数自动估算距离与热量，时长可留空'
	String get stepsEstimateHint => '填步数则按步数自动估算距离与热量，时长可留空';

	/// zh-CN: '${steps} 步'
	String stepsValue({required Object steps}) => '${steps} 步';

	late final Translations$record$exercise$conflict$zh_CN conflict = Translations$record$exercise$conflict$zh_CN.internal(_root);

	/// zh-CN: '删除该条运动记录'
	String get deleteLabel => '删除该条运动记录';

	/// zh-CN: '已删除'
	String get deleted => '已删除';

	late final Translations$record$exercise$screenshot$zh_CN screenshot = Translations$record$exercise$screenshot$zh_CN.internal(_root);
	late final Translations$record$exercise$types$zh_CN types = Translations$record$exercise$types$zh_CN.internal(_root);
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

// Path: record.duringFast
class Translations$record$duringFast$zh_CN {
	Translations$record$duringFast$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '断食期用餐'
	String get badge => '断食期用餐';
}

// Path: record.foodDetail
class Translations$record$foodDetail$zh_CN {
	Translations$record$foodDetail$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '每 100 克'
	String get per100g => '每 100 克';

	/// zh-CN: '千卡 / ${kj} 千焦 · 每 100 克'
	String kcalKj({required Object kj}) => '千卡 / ${kj} 千焦 · 每 100 克';

	/// zh-CN: '大约需走 ${steps} 步'
	String walkSteps({required Object steps}) => '大约需走 ${steps} 步';

	/// zh-CN: '营养素'
	String get nutrientColumn => '营养素';

	/// zh-CN: 'NRV%'
	String get nrvColumn => 'NRV%';

	/// zh-CN: '三大营养素供能比例'
	String get macrosTitle => '三大营养素供能比例';

	/// zh-CN: '圆环按供能占比绘制：1 克脂肪供能 9 千卡，是碳水和蛋白质（各 4 千卡）的 2.25 倍'
	String get energyShareNote => '圆环按供能占比绘制：1 克脂肪供能 9 千卡，是碳水和蛋白质（各 4 千卡）的 2.25 倍';

	/// zh-CN: '每 100 克营养明细'
	String get moreTitle => '每 100 克营养明细';

	/// zh-CN: '供能 ${kcal} 千卡'
	String supplyKcal({required Object kcal}) => '供能 ${kcal} 千卡';

	/// zh-CN: '别名：${names}'
	String aliases({required Object names}) => '别名：${names}';

	/// zh-CN: '绿灯 · 放心吃'
	String get badgeGreen => '绿灯 · 放心吃';

	/// zh-CN: '黄灯 · 适量少吃'
	String get badgeYellow => '黄灯 · 适量少吃';

	/// zh-CN: '红灯 · 尽量别吃'
	String get badgeRed => '红灯 · 尽量别吃';

	/// zh-CN: '按每 100 克对照你的每日营养目标判定'
	String get badgeBasis => '按每 100 克对照你的每日营养目标判定';

	/// zh-CN: '数据有误？告诉我们'
	String get reportIssue => '数据有误？告诉我们';
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

	/// zh-CN: '确定'
	String get confirm => '确定';
}

// Path: common.error
class Translations$common$error$zh_CN {
	Translations$common$error$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '网络连接失败，请检查网络后重试'
	String get network => '网络连接失败，请检查网络后重试';

	/// zh-CN: '请求超时，请稍后重试'
	String get timeout => '请求超时，请稍后重试';
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

	/// zh-CN: '下一段断食将计入 ${date}'
	String attributionEating({required Object date}) => '下一段断食将计入 ${date}';

	/// zh-CN: '已延长 +${minutes} 分钟'
	String extendedBadge({required Object minutes}) => '已延长 +${minutes} 分钟';

	/// zh-CN: '单次最多延长 4 小时'
	String get extendLimit => '单次最多延长 4 小时';

	/// zh-CN: '断食 ${fast} 小时 · 进食窗口 ${start}–${end}'
	String planTag({required Object fast, required Object start, required Object end}) => '断食 ${fast} 小时 · 进食窗口 ${start}–${end}';

	/// zh-CN: '修改'
	String get pendingPlanEdit => '修改';

	/// zh-CN: '立即应用'
	String get pendingPlanApply => '立即应用';

	/// zh-CN: '新方案已立即生效'
	String get pendingPlanApplied => '新方案已立即生效';

	/// zh-CN: '新方案已更新，将按原定时间生效'
	String get pendingPlanRescheduled => '新方案已更新，将按原定时间生效';

	/// zh-CN: '待生效方案'
	String get pendingPlanBadge => '待生效方案';

	/// zh-CN: '将于 ${date} 0:00 自动生效'
	String pendingPlanEffective({required Object date}) => '将于 ${date} 0:00 自动生效';

	/// zh-CN: '取消后将继续使用当前方案，本次换方案不再生效。'
	String get pendingPlanCancelBody => '取消后将继续使用当前方案，本次换方案不再生效。';

	/// zh-CN: '已取消新方案，当前方案保持不变'
	String get pendingPlanCancelled => '已取消新方案，当前方案保持不变';

	/// zh-CN: '3 个小问题，帮你找到最适合的断食节奏'
	String get noPlanSubtitle => '3 个小问题，帮你找到最适合的断食节奏';

	/// zh-CN: '断食完成！身体悄悄做了次大扫除 ✨'
	String get celebrationTitle => '断食完成！身体悄悄做了次大扫除 ✨';

	/// zh-CN: '断食完成 ✨'
	String get celebrationBadge => '断食完成 ✨';

	/// zh-CN: '今天还没记录，记一笔后信号灯会亮起来'
	String get signalEmpty => '今天还没记录，记一笔后信号灯会亮起来';

	/// zh-CN: '今日还未记录 · 目标 ${kcal} 千卡'
	String budgetEmpty({required Object kcal}) => '今日还未记录 · 目标 ${kcal} 千卡';

	/// zh-CN: '已吃 ${eaten} 千卡 · 还可吃 ${left} 千卡'
	String budgetNormal({required Object eaten, required Object left}) => '已吃 ${eaten} 千卡 · 还可吃 ${left} 千卡';

	/// zh-CN: '已吃 ${eaten} 千卡 · 已超 ${over} 千卡'
	String budgetOver({required Object eaten, required Object over}) => '已吃 ${eaten} 千卡 · 已超 ${over} 千卡';

	/// zh-CN: ' · 运动 +${kcal}'
	String budgetExercise({required Object kcal}) => ' · 运动 +${kcal}';

	/// zh-CN: '第 ${week} 周 · 已减 ${lost} kg / 目标 ${goal} kg'
	String planProgress({required Object week, required Object lost, required Object goal}) => '第 ${week} 周 · 已减 ${lost} kg / 目标 ${goal} kg';

	/// zh-CN: '第 ${week} 周 · 距目标还差 ${gap} kg'
	String planProgressBehind({required Object week, required Object gap}) => '第 ${week} 周 · 距目标还差 ${gap} kg';

	late final Translations$fasting$home$greeting$zh_CN greeting = Translations$fasting$home$greeting$zh_CN.internal(_root);
	late final Translations$fasting$home$endFastDialog$zh_CN endFastDialog = Translations$fasting$home$endFastDialog$zh_CN.internal(_root);
}

// Path: fasting.window
class Translations$fasting$window$zh_CN {
	Translations$fasting$window$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '自定义进食窗口'
	String get entry => '自定义进食窗口';

	/// zh-CN: '自定义进食窗口'
	String get title => '自定义进食窗口';

	/// zh-CN: '进食时长'
	String get duration => '进食时长';

	/// zh-CN: '${hours} 小时'
	String hoursOption({required Object hours}) => '${hours} 小时';

	/// zh-CN: '开始时间'
	String get start => '开始时间';

	/// zh-CN: '进食 ${window} · 禁食 ${hours} 小时'
	String preview({required Object window, required Object hours}) => '进食 ${window} · 禁食 ${hours} 小时';

	/// zh-CN: '重置为推荐窗口'
	String get resetRecommended => '重置为推荐窗口';

	/// zh-CN: '确定'
	String get confirm => '确定';
}

// Path: fasting.widget
class Translations$fasting$widget$zh_CN {
	Translations$fasting$widget$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '${time} 可进食'
	String dueEat({required Object time}) => '${time} 可进食';

	/// zh-CN: '${time} 进食截止'
	String dueEatEnd({required Object time}) => '${time} 进食截止';
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

// Path: notification.water
class Translations$notification$water$zh_CN {
	Translations$notification$water$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '该喝水啦～建议喝 ${ml} 毫升，今天还差 ${remaining} 毫升'
	String hourly({required Object ml, required Object remaining}) => '该喝水啦～建议喝 ${ml} 毫升，今天还差 ${remaining} 毫升';
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
	late final Translations$nutrition$data$burn$zh_CN burn = Translations$nutrition$data$burn$zh_CN.internal(_root);
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

	/// zh-CN: '目标 ${kg} 公斤'
	String targetLine({required Object kg}) => '目标 ${kg} 公斤';

	/// zh-CN: '距目标还有 ${kg} 公斤'
	String toGoal({required Object kg}) => '距目标还有 ${kg} 公斤';

	/// zh-CN: '已达到目标体重'
	String get goalReached => '已达到目标体重';

	/// zh-CN: '再记录 ${count} 次体重，解锁完整曲线'
	String weightUnlock({required Object count}) => '再记录 ${count} 次体重，解锁完整曲线';
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

	/// zh-CN: '(other) {记录 ${n} 条}'
	String entries({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		other: '记录 ${n} 条',
	);

	/// zh-CN: '绿灯占比 ${percent}%'
	String greenRatio({required Object percent}) => '绿灯占比 ${percent}%';

	late final Translations$reports$weekly$cheer$zh_CN cheer = Translations$reports$weekly$cheer$zh_CN.internal(_root);

	/// zh-CN: '周报还差一点点数据，记一笔或完成一次断食就生成啦'
	String get empty => '周报还差一点点数据，记一笔或完成一次断食就生成啦';
}

// Path: reports.weeklySummary
class Translations$reports$weeklySummary$zh_CN {
	Translations$reports$weeklySummary$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '上周小结'
	String get title => '上周小结';

	/// zh-CN: '达标 ${days} 天'
	String chipQualified({required Object days}) => '达标 ${days} 天';

	/// zh-CN: '记录 ${days} 天'
	String chipRecorded({required Object days}) => '记录 ${days} 天';

	/// zh-CN: '平均 ${kcal} · 目标 ${target} 千卡'
	String chipAvgKcal({required Object kcal, required Object target}) => '平均 ${kcal} · 目标 ${target} 千卡';

	/// zh-CN: '体重 ${kg} 公斤'
	String chipWeight({required Object kg}) => '体重 ${kg} 公斤';

	/// zh-CN: '上周断食达标 ${days} 天'
	String fastingPlain({required Object days}) => '上周断食达标 ${days} 天';

	/// zh-CN: '上周断食达标 ${days} 天，比前周多 ${delta} 天'
	String fastingMore({required Object days, required Object delta}) => '上周断食达标 ${days} 天，比前周多 ${delta} 天';

	/// zh-CN: '上周断食达标 ${days} 天，比前周少 ${delta} 天'
	String fastingLess({required Object days, required Object delta}) => '上周断食达标 ${days} 天，比前周少 ${delta} 天';

	/// zh-CN: '上周断食达标 ${days} 天，与前周持平'
	String fastingSame({required Object days}) => '上周断食达标 ${days} 天，与前周持平';

	/// zh-CN: '平均每日摄入 ${kcal} 千卡，在目标范围内'
	String intakeWithin({required Object kcal}) => '平均每日摄入 ${kcal} 千卡，在目标范围内';

	/// zh-CN: '平均每日摄入 ${kcal} 千卡，比目标高 ${percent}%'
	String intakeAbove({required Object kcal, required Object percent}) => '平均每日摄入 ${kcal} 千卡，比目标高 ${percent}%';

	/// zh-CN: '平均每日摄入 ${kcal} 千卡，比目标低 ${percent}%'
	String intakeBelow({required Object kcal, required Object percent}) => '平均每日摄入 ${kcal} 千卡，比目标低 ${percent}%';

	/// zh-CN: '体重上升 ${kg} 公斤'
	String weightUp({required Object kg}) => '体重上升 ${kg} 公斤';

	/// zh-CN: '体重下降 ${kg} 公斤'
	String weightDown({required Object kg}) => '体重下降 ${kg} 公斤';

	/// zh-CN: '体重基本持平'
	String get weightSame => '体重基本持平';

	/// zh-CN: '仅供健康生活方式参考'
	String get disclaimer => '仅供健康生活方式参考';

	/// zh-CN: '先记录几天，下周这时见'
	String get empty => '先记录几天，下周这时见';
}

// Path: reports.monthly
class Translations$reports$monthly$zh_CN {
	Translations$reports$monthly$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '上一月'
	String get prevMonth => '上一月';

	/// zh-CN: '下一月'
	String get nextMonth => '下一月';

	/// zh-CN: '断食达标 ${days} 天'
	String qualified({required Object days}) => '断食达标 ${days} 天';

	/// zh-CN: '记录 ${days} 天'
	String recordedDays({required Object days}) => '记录 ${days} 天';

	/// zh-CN: '平均断食 ${hours} 小时'
	String avgFastingHours({required Object hours}) => '平均断食 ${hours} 小时';

	/// zh-CN: '平均断食 ${hours} 小时 ${minutes} 分钟'
	String avgFastingHoursMinutes({required Object hours, required Object minutes}) => '平均断食 ${hours} 小时 ${minutes} 分钟';

	/// zh-CN: '月均热量 ${kcal} 千卡 · 目标 ${target} 千卡'
	String kcalAvg({required Object kcal, required Object target}) => '月均热量 ${kcal} 千卡 · 目标 ${target} 千卡';

	/// zh-CN: '蛋白质 ${protein}g · 碳水 ${carbs}g · 脂肪 ${fat}g'
	String macros({required Object protein, required Object carbs, required Object fat}) => '蛋白质 ${protein}g · 碳水 ${carbs}g · 脂肪 ${fat}g';

	/// zh-CN: '体重变化 ${value}'
	String weightChange({required Object value}) => '体重变化 ${value}';

	/// zh-CN: '本月暂无记录'
	String get empty => '本月暂无记录';

	/// zh-CN: '记一笔饮食或完成一次断食，月报就会长出来～'
	String get emptyHint => '记一笔饮食或完成一次断食，月报就会长出来～';
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

	/// zh-CN: '连续 ${days} 天！这个节奏太稳了，继续保持 🎉'
	String title({required Object days}) => '连续 ${days} 天！这个节奏太稳了，继续保持 🎉';

	/// zh-CN: '${days} 天连胜'
	String badgeLabel({required Object days}) => '${days} 天连胜';

	/// zh-CN: '分享'
	String get share => '分享';

	/// zh-CN: '收下啦'
	String get accept => '收下啦';

	late final Translations$streak$milestone$shareCard$zh_CN shareCard = Translations$streak$milestone$shareCard$zh_CN.internal(_root);
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

// Path: settings.group
class Translations$settings$group$zh_CN {
	Translations$settings$group$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '账号'
	String get account => '账号';

	/// zh-CN: '隐私'
	String get privacy => '隐私';

	/// zh-CN: '偏好'
	String get preferences => '偏好';

	/// zh-CN: '提醒'
	String get reminders => '提醒';

	/// zh-CN: '关于'
	String get about => '关于';
}

// Path: settings.account
class Translations$settings$account$zh_CN {
	Translations$settings$account$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '账号'
	String get account => '账号';

	/// zh-CN: '撤销删除'
	String get cancelDeletion => '撤销删除';

	/// zh-CN: '修改密码'
	String get changePassword => '修改密码';

	/// zh-CN: '我的贡献'
	String get contributions => '我的贡献';

	/// zh-CN: '审批中心'
	String get moderation => '审批中心';

	/// zh-CN: '删除账号'
	String get deleteAccount => '删除账号';

	/// zh-CN: '确认删除'
	String get deleteConfirmAction => '确认删除';

	/// zh-CN: '删除后，你的手机号、基础资料、全部饮食/断食记录等个人数据将被物理删除，且不可恢复。申请后进入 7 天冷静期：冷静期内登录即视为撤销删除，第 7 天执行删除。'
	String get deleteConfirmBody => '删除后，你的手机号、基础资料、全部饮食/断食记录等个人数据将被物理删除，且不可恢复。申请后进入 7 天冷静期：冷静期内登录即视为撤销删除，第 7 天执行删除。';

	/// zh-CN: '删除账号？'
	String get deleteConfirmTitle => '删除账号？';

	/// zh-CN: '删除申请已提交，账号进入 7 天冷静期'
	String get deleteRequested => '删除申请已提交，账号进入 7 天冷静期';

	/// zh-CN: '删除申请已提交。账号将于 ${date} 删除，此日期前重新登录即可撤销。'
	String deleteScheduledBody({required Object date}) => '删除申请已提交。账号将于 ${date} 删除，此日期前重新登录即可撤销。';

	/// zh-CN: '已撤销删除申请，账号恢复正常'
	String get deletionCancelled => '已撤销删除申请，账号恢复正常';

	/// zh-CN: '删除已预约，${days} 日后执行，到期前可撤销'
	String deletionScheduled({required Object days}) => '删除已预约，${days} 日后执行，到期前可撤销';

	/// zh-CN: '登出'
	String get logout => '登出';

	/// zh-CN: '未登录'
	String get notLoggedIn => '未登录';
}

// Path: settings.privacy
class Translations$settings$privacy$zh_CN {
	Translations$settings$privacy$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '隐私政策'
	String get privacyPolicy => '隐私政策';

	/// zh-CN: '用户协议'
	String get userAgreement => '用户协议';

	/// zh-CN: '导出我的数据'
	String get exportData => '导出我的数据';

	/// zh-CN: '数据已导出：${path}'
	String exportSuccess({required Object path}) => '数据已导出：${path}';

	/// zh-CN: '健康数据授权'
	String get healthData => '健康数据授权';

	/// zh-CN: '身高体重、饮食/断食记录等敏感个人信息处理'
	String get healthDataSubtitle => '身高体重、饮食/断食记录等敏感个人信息处理';

	/// zh-CN: '已撤回健康数据授权，营养目标将使用默认值'
	String get healthDataRevoked => '已撤回健康数据授权，营养目标将使用默认值';

	/// zh-CN: '数据分析授权'
	String get analytics => '数据分析授权';

	/// zh-CN: '匿名行为统计，帮助我们改进产品，不含健康数据'
	String get analyticsSubtitle => '匿名行为统计，帮助我们改进产品，不含健康数据';

	/// zh-CN: '导出失败，请检查网络后重试'
	String get exportFailed => '导出失败，请检查网络后重试';
}

// Path: settings.health
class Translations$settings$health$zh_CN {
	Translations$settings$health$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '运动数据'
	String get group => '运动数据';

	/// zh-CN: '同步运动数据'
	String get sync => '同步运动数据';

	/// zh-CN: '读取系统健康数据（Apple 健康 / Health Connect），展示今日活动消耗'
	String get syncSubtitle => '读取系统健康数据（Apple 健康 / Health Connect），展示今日活动消耗';

	/// zh-CN: '开启运动数据同步？'
	String get consentTitle => '开启运动数据同步？';

	/// zh-CN: '将读取本机系统健康数据中的步数、活动能量与体重，仅用于在 App 内展示今日热量消耗与结余。 数据只在本机处理和展示，不会上传到服务器。你可以随时在这里关闭，关闭后将撤销系统授权并清除已读取的数据。'
	String get consentBody => '将读取本机系统健康数据中的步数、活动能量与体重，仅用于在 App 内展示今日热量消耗与结余。\n\n数据只在本机处理和展示，不会上传到服务器。你可以随时在这里关闭，关闭后将撤销系统授权并清除已读取的数据。';

	/// zh-CN: '同意并开启'
	String get consentAgree => '同意并开启';

	/// zh-CN: '暂不同意'
	String get consentDecline => '暂不同意';

	/// zh-CN: '读取中…'
	String get statusConnecting => '读取中…';

	/// zh-CN: '已授权'
	String get statusReady => '已授权';

	/// zh-CN: '未授权，可在系统健康设置中开启后重试'
	String get statusDenied => '未授权，可在系统健康设置中开启后重试';

	/// zh-CN: '当前设备不支持系统健康数据（未检测到 Health Connect / 健康服务）'
	String get statusUnsupported => '当前设备不支持系统健康数据（未检测到 Health Connect / 健康服务）';

	/// zh-CN: '读取失败，请稍后重试'
	String get statusError => '读取失败，请稍后重试';

	/// zh-CN: '已关闭运动数据同步，系统授权已撤销'
	String get revoked => '已关闭运动数据同步，系统授权已撤销';

	/// zh-CN: '步数 ${steps}'
	String steps({required Object steps}) => '步数 ${steps}';

	/// zh-CN: '活动消耗 ${kcal} kcal'
	String activeEnergy({required Object kcal}) => '活动消耗 ${kcal} kcal';

	/// zh-CN: '最新体重 ${kg} kg'
	String latestWeight({required Object kg}) => '最新体重 ${kg} kg';

	/// zh-CN: '填入今日体重记录'
	String get fillWeight => '填入今日体重记录';

	/// zh-CN: '已填入今日体重记录 ${kg} kg'
	String weightFilled({required Object kg}) => '已填入今日体重记录 ${kg} kg';

	/// zh-CN: '今日暂无运动数据'
	String get noData => '今日暂无运动数据';

	/// zh-CN: '每日消耗目标'
	String get burnGoal => '每日消耗目标';

	/// zh-CN: '${kcal} 千卡'
	String burnGoalValue({required Object kcal}) => '${kcal} 千卡';

	/// zh-CN: '每日步数目标'
	String get stepsGoal => '每日步数目标';

	/// zh-CN: '${steps} 步'
	String stepsGoalValue({required Object steps}) => '${steps} 步';

	/// zh-CN: '设置每日消耗目标'
	String get burnGoalDialogTitle => '设置每日消耗目标';

	/// zh-CN: '设置每日步数目标'
	String get stepsGoalDialogTitle => '设置每日步数目标';

	/// zh-CN: '目标（千卡，50–5000）'
	String get burnGoalInputLabel => '目标（千卡，50–5000）';

	/// zh-CN: '目标（步，500–100000）'
	String get stepsGoalInputLabel => '目标（步，500–100000）';

	/// zh-CN: '请输入范围内的有效数值'
	String get goalInvalid => '请输入范围内的有效数值';
}

// Path: settings.theme
class Translations$settings$theme$zh_CN {
	Translations$settings$theme$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '主题'
	String get title => '主题';

	/// zh-CN: '跟随系统'
	String get system => '跟随系统';

	/// zh-CN: '浅色'
	String get light => '浅色';

	/// zh-CN: '深色'
	String get dark => '深色';
}

// Path: settings.fastingPlan
class Translations$settings$fastingPlan$zh_CN {
	Translations$settings$fastingPlan$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '断食方案'
	String get title => '断食方案';

	/// zh-CN: '查看或更换断食方案，新方案次日 0:00 生效'
	String get subtitle => '查看或更换断食方案，新方案次日 0:00 生效';
}

// Path: settings.bodyProfile
class Translations$settings$bodyProfile$zh_CN {
	Translations$settings$bodyProfile$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '身体档案'
	String get title => '身体档案';

	/// zh-CN: '身高体重等，用于计算精准营养目标'
	String get subtitle => '身高体重等，用于计算精准营养目标';

	/// zh-CN: '减重目标（选填，仅减脂目标生效）'
	String get goalSection => '减重目标（选填，仅减脂目标生效）';

	/// zh-CN: '保存'
	String get save => '保存';

	/// zh-CN: '身体档案已保存'
	String get saved => '身体档案已保存';

	/// zh-CN: '每日营养目标已更新为 ${kcal} kcal'
	String goalUpdated({required Object kcal}) => '每日营养目标已更新为 ${kcal} kcal';

	/// zh-CN: '档案完善度 ${percent}%'
	String completeness({required Object percent}) => '档案完善度 ${percent}%';

	late final Translations$settings$bodyProfile$bmi$zh_CN bmi = Translations$settings$bodyProfile$bmi$zh_CN.internal(_root);
}

// Path: settings.reminders
class Translations$settings$reminders$zh_CN {
	Translations$settings$reminders$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '通知设置'
	String get notifications => '通知设置';

	/// zh-CN: '前往系统设置管理通知权限'
	String get notificationsSubtitle => '前往系统设置管理通知权限';

	/// zh-CN: '喝水提醒'
	String get waterHourly => '喝水提醒';

	/// zh-CN: '进食窗口内每小时提醒，按剩余目标量建议饮水量'
	String get waterHourlySubtitle => '进食窗口内每小时提醒，按剩余目标量建议饮水量';
}

// Path: settings.about
class Translations$settings$about$zh_CN {
	Translations$settings$about$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '版本'
	String get version => '版本';

	/// zh-CN: '免责声明与特殊人群提示'
	String get disclaimer => '免责声明与特殊人群提示';

	/// zh-CN: '检查更新'
	String get checkUpdate => '检查更新';
}

// Path: settings.aiModel
class Translations$settings$aiModel$zh_CN {
	Translations$settings$aiModel$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: 'AI 模型'
	String get title => 'AI 模型';

	/// zh-CN: '服务商'
	String get provider => '服务商';

	late final Translations$settings$aiModel$providers$zh_CN providers = Translations$settings$aiModel$providers$zh_CN.internal(_root);

	/// zh-CN: 'Base URL'
	String get baseUrl => 'Base URL';

	/// zh-CN: '模型'
	String get model => '模型';

	/// zh-CN: 'API Key'
	String get apiKey => 'API Key';

	/// zh-CN: '留空保持不变'
	String get apiKeyHint => '留空保持不变';

	/// zh-CN: '自定义服务商需填写 Base URL'
	String get baseUrlRequired => '自定义服务商需填写 Base URL';

	/// zh-CN: '自定义服务商需填写模型名称'
	String get modelRequired => '自定义服务商需填写模型名称';

	/// zh-CN: '保存'
	String get save => '保存';

	/// zh-CN: 'AI 模型配置已保存'
	String get saved => 'AI 模型配置已保存';

	/// zh-CN: '测试连接'
	String get test => '测试连接';

	/// zh-CN: '测试中…'
	String get testing => '测试中…';

	/// zh-CN: '连接成功，模型服务可用'
	String get testOk => '连接成功，模型服务可用';

	/// zh-CN: '连接失败：${reason}'
	String testFail({required Object reason}) => '连接失败：${reason}';

	/// zh-CN: '连接失败：无法连接服务器，请检查 Base URL 与网络'
	String get testFailNetwork => '连接失败：无法连接服务器，请检查 Base URL 与网络';

	/// zh-CN: '连接失败：连接超时，请检查网络后重试'
	String get testFailTimeout => '连接失败：连接超时，请检查网络后重试';

	/// zh-CN: '连接失败：API Key 无效或无权限，请检查后重试'
	String get testFailAuth => '连接失败：API Key 无效或无权限，请检查后重试';

	/// zh-CN: '清除配置'
	String get clear => '清除配置';

	/// zh-CN: '清除 AI 模型配置？'
	String get clearConfirmTitle => '清除 AI 模型配置？';

	/// zh-CN: '清除后，自定义食物估算将不可用（可开启端侧小模型或重新配置）。'
	String get clearConfirmBody => '清除后，自定义食物估算将不可用（可开启端侧小模型或重新配置）。';

	/// zh-CN: '确认清除'
	String get clearConfirmAction => '确认清除';

	/// zh-CN: 'AI 模型配置已清除'
	String get cleared => 'AI 模型配置已清除';
}

// Path: settings.onDevice
class Translations$settings$onDevice$zh_CN {
	Translations$settings$onDevice$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '端侧小模型'
	String get title => '端侧小模型';

	/// zh-CN: '下载后可在本机离线估算食物营养，数据不出设备'
	String get desc => '下载后可在本机离线估算食物营养，数据不出设备';

	/// zh-CN: '模型大小约 2.41GB'
	String get size => '模型大小约 2.41GB';

	/// zh-CN: '文件较大，建议在 Wi-Fi 环境下下载'
	String get wifiHint => '文件较大，建议在 Wi-Fi 环境下下载';

	/// zh-CN: '下载模型'
	String get download => '下载模型';

	/// zh-CN: '下载中 ${percent}%'
	String downloading({required Object percent}) => '下载中 ${percent}%';

	/// zh-CN: '取消'
	String get cancel => '取消';

	/// zh-CN: '已暂停（已下载 ${percent}%）'
	String paused({required Object percent}) => '已暂停（已下载 ${percent}%）';

	/// zh-CN: '继续下载'
	String get resume => '继续下载';

	/// zh-CN: '删除模型'
	String get delete => '删除模型';

	/// zh-CN: '删除端侧模型？'
	String get deleteConfirmTitle => '删除端侧模型？';

	/// zh-CN: '删除后如需端侧估算，需重新下载约 2.41GB 模型文件。'
	String get deleteConfirmBody => '删除后如需端侧估算，需重新下载约 2.41GB 模型文件。';

	/// zh-CN: '确认删除'
	String get deleteConfirmAction => '确认删除';

	/// zh-CN: '端侧模型已删除'
	String get deleted => '端侧模型已删除';

	/// zh-CN: '模型已就绪'
	String get ready => '模型已就绪';

	/// zh-CN: '首次估算需加载模型，可能等待数秒'
	String get coldLoadHint => '首次估算需加载模型，可能等待数秒';

	/// zh-CN: '优先使用端侧估算'
	String get enabled => '优先使用端侧估算';

	/// zh-CN: '下载失败，请检查网络后重试'
	String get errorDownload => '下载失败，请检查网络后重试';

	/// zh-CN: '可用存储不足（约需 6GB），请清理后重试'
	String get errorStorage => '可用存储不足（约需 6GB），请清理后重试';

	/// zh-CN: '设备内存不足，无法使用端侧模型'
	String get errorMemory => '设备内存不足，无法使用端侧模型';

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '设备内存不足，端侧估算已停用'
	String get oomDisabled => '设备内存不足，端侧估算已停用';

	/// zh-CN: '模型状态读取失败'
	String get statusFailed => '模型状态读取失败';

	/// zh-CN: '已下载 ${percent}%，重试将从断点继续'
	String errorResumeHint({required Object percent}) => '已下载 ${percent}%，重试将从断点继续';
}

// Path: settings.chain
class Translations$settings$chain$zh_CN {
	Translations$settings$chain$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '估算生效链路'
	String get title => '估算生效链路';

	/// zh-CN: '端侧小模型'
	String get onDevice => '端侧小模型';

	/// zh-CN: '自定义 API'
	String get userApi => '自定义 API';

	/// zh-CN: '已启用'
	String get statusEnabled => '已启用';

	/// zh-CN: '未启用'
	String get statusDisabled => '未启用';

	/// zh-CN: '未下载'
	String get statusNotDownloaded => '未下载';

	/// zh-CN: '下载中'
	String get statusDownloading => '下载中';

	/// zh-CN: '已暂停'
	String get statusPaused => '已暂停';

	/// zh-CN: '下载失败'
	String get statusError => '下载失败';

	/// zh-CN: '未就绪'
	String get statusUnknown => '未就绪';

	/// zh-CN: '已配置'
	String get statusConfigured => '已配置';

	/// zh-CN: '未配置'
	String get statusNotConfigured => '未配置';

	/// zh-CN: '当前生效'
	String get current => '当前生效';
}

// Path: legal.consent
class Translations$legal$consent$zh_CN {
	Translations$legal$consent$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '欢迎使用 EatWise'
	String get title => '欢迎使用 EatWise';

	/// zh-CN: '我们会按照《隐私政策》收集和使用你的信息，用于提供断食计时、饮食记录与营养反馈等核心功能；数据存储于中国境内并加密保护。请阅读并确认以下授权：'
	String get summary => '我们会按照《隐私政策》收集和使用你的信息，用于提供断食计时、饮食记录与营养反馈等核心功能；数据存储于中国境内并加密保护。请阅读并确认以下授权：';

	/// zh-CN: '我已阅读并同意《用户协议》与《隐私政策》'
	String get agreeMain => '我已阅读并同意《用户协议》与《隐私政策》';

	/// zh-CN: '健康数据单独同意（可选）'
	String get healthTitle => '健康数据单独同意（可选）';

	/// zh-CN: '你的身高、体重、年龄、性别及饮食、断食记录属于敏感个人信息。单独同意后，我们将其用于计算个性化营养目标与反馈，境内加密存储。你可以拒绝（营养目标将使用默认值），或随时在「设置-隐私」中撤回。'
	String get healthBody => '你的身高、体重、年龄、性别及饮食、断食记录属于敏感个人信息。单独同意后，我们将其用于计算个性化营养目标与反馈，境内加密存储。你可以拒绝（营养目标将使用默认值），或随时在「设置-隐私」中撤回。';

	/// zh-CN: '免责提示：本应用内容仅为健康生活方式的一般性参考，不构成医疗建议、诊断或治疗。'
	String get disclaimerSummary => '免责提示：本应用内容仅为健康生活方式的一般性参考，不构成医疗建议、诊断或治疗。';

	/// zh-CN: '查看不适宜断食人群提示'
	String get specialGroupsEntry => '查看不适宜断食人群提示';

	/// zh-CN: '查看《隐私政策》全文'
	String get viewPrivacyPolicy => '查看《隐私政策》全文';

	/// zh-CN: '查看《用户协议》全文'
	String get viewUserAgreement => '查看《用户协议》全文';

	/// zh-CN: '同意并继续'
	String get agreeAndContinue => '同意并继续';

	/// zh-CN: '不同意并退出'
	String get decline => '不同意并退出';
}

// Path: legal.disclaimer
class Translations$legal$disclaimer$zh_CN {
	Translations$legal$disclaimer$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '免责声明'
	String get title => '免责声明';

	/// zh-CN: '非医疗建议声明'
	String get notMedicalTitle => '非医疗建议声明';

	/// zh-CN: '明食 EatWise 提供的内容（包括断食方案、营养目标、信号灯反馈与建议）仅为健康生活方式的一般性信息参考，不构成医疗建议、诊断或治疗，不能替代医生、注册营养师等专业人士的意见。您的营养目标由通用公式估算，可能与您的个体情况存在差异。如有任何健康问题、正在服药或患有疾病，请在使用断食或调整饮食前咨询专业医疗人员。因使用本应用信息而产生的任何后果，本应用不承担医疗责任。'
	String get notMedicalBody => '明食 EatWise 提供的内容（包括断食方案、营养目标、信号灯反馈与建议）仅为健康生活方式的一般性信息参考，不构成医疗建议、诊断或治疗，不能替代医生、注册营养师等专业人士的意见。您的营养目标由通用公式估算，可能与您的个体情况存在差异。如有任何健康问题、正在服药或患有疾病，请在使用断食或调整饮食前咨询专业医疗人员。因使用本应用信息而产生的任何后果，本应用不承担医疗责任。';

	/// zh-CN: '特殊人群提示'
	String get specialGroupsTitle => '特殊人群提示';

	/// zh-CN: '⚠️ 以下人群不建议进行间歇性断食，或须在医生指导下进行：孕期及哺乳期女性；未成年人（18 岁以下）；有进食障碍（如厌食症、暴食症）病史或高风险人群；糖尿病患者（尤其使用胰岛素或降糖药者）；低血糖、低血压患者；体重过低（BMI < 18.5）者；痛风、肾病、肝病等慢性疾病患者；近期手术或处于疾病恢复期者；老年体弱者。如果您属于以上任何一类，请不要开始断食方案，并咨询医生。'
	String get specialGroupsBody => '⚠️ 以下人群不建议进行间歇性断食，或须在医生指导下进行：孕期及哺乳期女性；未成年人（18 岁以下）；有进食障碍（如厌食症、暴食症）病史或高风险人群；糖尿病患者（尤其使用胰岛素或降糖药者）；低血糖、低血压患者；体重过低（BMI < 18.5）者；痛风、肾病、肝病等慢性疾病患者；近期手术或处于疾病恢复期者；老年体弱者。如果您属于以上任何一类，请不要开始断食方案，并咨询医生。';

	/// zh-CN: '本应用内容不构成医疗建议'
	String get short => '本应用内容不构成医疗建议';
}

// Path: legal.privacyPolicy
class Translations$legal$privacyPolicy$zh_CN {
	Translations$legal$privacyPolicy$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '隐私政策'
	String get title => '隐私政策';

	/// zh-CN: '生效日期：2026-07-27｜版本 1.0.0〔待外部确认：法务终稿〕 明食 · EatWise（下称「我们」）仅面向中国大陆地区提供服务。本政策说明我们如何收集、使用、存储和保护你的个人信息，以及你享有的权利。 一、我们收集的信息 1. 手机号：用于注册、登录与账号找回，境内加密存储。 2. 身高、体重、年龄、性别：用于计算每日营养目标，属敏感个人信息，需你单独同意。 3. 饮食记录与断食记录：核心功能所需，属敏感个人信息。 4. 目标、作息、断食经验（问卷 3 题）：用于方案推荐。 5. 昵称、头像：可选，用于个性化与社区展示。 6. 设备信息与推送 token：用于推送送达与崩溃分析；不收集 IMEI/IMSI/MAC。 7. 崩溃与性能日志：脱敏处理，留存 6 个月。 8. 埋点行为数据：仅事件级行为统计，可在「设置-隐私」中关闭。 我们不收集：位置信息、通讯录、蓝牙及 HealthKit/Health Connect 健康平台数据。 二、敏感个人信息单独同意 健康相关数据（身高体重、饮食/断食记录等）依据《个人信息保护法》第 29 条取得你的单独同意；拒绝不影响账号功能，营养目标将使用默认值；你可随时在「设置-隐私」中撤回。 三、存储与安全 全部数据存储于中国境内服务器；传输使用 TLS 1.2+ 加密；手机号与健康数据采用字段级加密存储；本地数据库全库加密。无任何数据出境。 四、第三方 SDK 我们使用微信登录、Sign in with Apple、聚合推送、内容安全、崩溃监控等境内 SDK；任何 SDK 均不接收你的健康数据原文。 五、你的权利 1. 查阅复制：「设置-隐私-导出我的数据」申请导出全量个人数据（JSON+CSV）。 2. 删除：「设置-账号-删除账号」，申请后进入 7 天冷静期，冷静期内登录即撤销。 3. 撤回同意：「设置-隐私」中可随时撤回健康数据授权与数据分析授权。 六、未成年人 本产品不面向 14 岁以下儿童。 七、政策更新 本政策发生重大变更时，我们将重新征得你的同意。 八、联系我们 如对本政策有任何疑问，可通过 App 内「设置-关于」与我们联系。'
	String get body => '生效日期：2026-07-27｜版本 1.0.0〔待外部确认：法务终稿〕\n\n明食 · EatWise（下称「我们」）仅面向中国大陆地区提供服务。本政策说明我们如何收集、使用、存储和保护你的个人信息，以及你享有的权利。\n\n一、我们收集的信息\n1. 手机号：用于注册、登录与账号找回，境内加密存储。\n2. 身高、体重、年龄、性别：用于计算每日营养目标，属敏感个人信息，需你单独同意。\n3. 饮食记录与断食记录：核心功能所需，属敏感个人信息。\n4. 目标、作息、断食经验（问卷 3 题）：用于方案推荐。\n5. 昵称、头像：可选，用于个性化与社区展示。\n6. 设备信息与推送 token：用于推送送达与崩溃分析；不收集 IMEI/IMSI/MAC。\n7. 崩溃与性能日志：脱敏处理，留存 6 个月。\n8. 埋点行为数据：仅事件级行为统计，可在「设置-隐私」中关闭。\n我们不收集：位置信息、通讯录、蓝牙及 HealthKit/Health Connect 健康平台数据。\n\n二、敏感个人信息单独同意\n健康相关数据（身高体重、饮食/断食记录等）依据《个人信息保护法》第 29 条取得你的单独同意；拒绝不影响账号功能，营养目标将使用默认值；你可随时在「设置-隐私」中撤回。\n\n三、存储与安全\n全部数据存储于中国境内服务器；传输使用 TLS 1.2+ 加密；手机号与健康数据采用字段级加密存储；本地数据库全库加密。无任何数据出境。\n\n四、第三方 SDK\n我们使用微信登录、Sign in with Apple、聚合推送、内容安全、崩溃监控等境内 SDK；任何 SDK 均不接收你的健康数据原文。\n\n五、你的权利\n1. 查阅复制：「设置-隐私-导出我的数据」申请导出全量个人数据（JSON+CSV）。\n2. 删除：「设置-账号-删除账号」，申请后进入 7 天冷静期，冷静期内登录即撤销。\n3. 撤回同意：「设置-隐私」中可随时撤回健康数据授权与数据分析授权。\n\n六、未成年人\n本产品不面向 14 岁以下儿童。\n\n七、政策更新\n本政策发生重大变更时，我们将重新征得你的同意。\n\n八、联系我们\n如对本政策有任何疑问，可通过 App 内「设置-关于」与我们联系。';
}

// Path: legal.userAgreement
class Translations$legal$userAgreement$zh_CN {
	Translations$legal$userAgreement$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '用户协议'
	String get title => '用户协议';

	/// zh-CN: '生效日期：2026-07-27｜版本 1.0.0〔待外部确认：法务终稿〕 欢迎使用明食 · EatWise（下称「本应用」）。使用本应用前，请仔细阅读本协议。 一、服务内容 本应用提供间歇性断食计时、饮食记录、营养目标估算与信号灯反馈、趋势报告及社区打卡等健康生活方式工具服务。 二、账号 你可通过手机号验证码、微信或 Sign in with Apple 注册登录。你应妥善保管账号，并对账号下的行为负责。 三、非医疗建议 本应用提供的全部内容仅为一般性健康生活方式参考，不构成医疗建议、诊断或治疗，详见《免责声明》。 四、用户行为规范 你承诺发布的内容不违反法律法规、不侵犯他人权益；违规内容将被下架并可能限制账号功能。 五、知识产权 本应用的内容与程序知识产权归我们所有，你仅获得个人非商业性使用许可。 六、责任限制 因使用本应用信息产生的健康后果，我们不承担医疗责任；因不可抗力或第三方原因造成的服务中断，我们不承担责任。 七、协议变更与终止 本协议变更将以页面提示等方式通知；你可随时通过删除账号终止使用。 八、适用法律 本协议适用中华人民共和国法律。'
	String get body => '生效日期：2026-07-27｜版本 1.0.0〔待外部确认：法务终稿〕\n\n欢迎使用明食 · EatWise（下称「本应用」）。使用本应用前，请仔细阅读本协议。\n\n一、服务内容\n本应用提供间歇性断食计时、饮食记录、营养目标估算与信号灯反馈、趋势报告及社区打卡等健康生活方式工具服务。\n\n二、账号\n你可通过手机号验证码、微信或 Sign in with Apple 注册登录。你应妥善保管账号，并对账号下的行为负责。\n\n三、非医疗建议\n本应用提供的全部内容仅为一般性健康生活方式参考，不构成医疗建议、诊断或治疗，详见《免责声明》。\n\n四、用户行为规范\n你承诺发布的内容不违反法律法规、不侵犯他人权益；违规内容将被下架并可能限制账号功能。\n\n五、知识产权\n本应用的内容与程序知识产权归我们所有，你仅获得个人非商业性使用许可。\n\n六、责任限制\n因使用本应用信息产生的健康后果，我们不承担医疗责任；因不可抗力或第三方原因造成的服务中断，我们不承担责任。\n\n七、协议变更与终止\n本协议变更将以页面提示等方式通知；你可随时通过删除账号终止使用。\n\n八、适用法律\n本协议适用中华人民共和国法律。';
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

	/// zh-CN: '删除'
	String get delete => '删除';

	/// zh-CN: '确定删除这条打卡吗？删除后无法恢复。'
	String get deleteConfirm => '确定删除这条打卡吗？删除后无法恢复。';

	/// zh-CN: '已删除'
	String get deleted => '已删除';

	/// zh-CN: '删除失败，请稍后重试'
	String get deleteFailed => '删除失败，请稍后重试';

	/// zh-CN: '匿名伙伴'
	String get anonymousPoster => '匿名伙伴';
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

	/// zh-CN: '图片上传中…'
	String get photoUploading => '图片上传中…';

	/// zh-CN: '图片上传失败'
	String get photoUploadFailed => '图片上传失败';

	/// zh-CN: '图片上传失败：可以不带图发布，或取消后重新上传。'
	String get photoUploadFailedBody => '图片上传失败：可以不带图发布，或取消后重新上传。';

	/// zh-CN: '不带图发布'
	String get publishWithoutPhoto => '不带图发布';

	/// zh-CN: '重新上传'
	String get retryUpload => '重新上传';

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

	/// zh-CN: 'AI 润色'
	String get polish => 'AI 润色';

	/// zh-CN: '正在加载端侧模型…'
	String get polishLoadingModel => '正在加载端侧模型…';

	/// zh-CN: 'AI 润色中…'
	String get polishInferring => 'AI 润色中…';

	/// zh-CN: '润色失败，请稍后重试'
	String get polishFailed => '润色失败，请稍后重试';

	/// zh-CN: '已为你润色'
	String get polishDone => '已为你润色';

	/// zh-CN: '撤销润色'
	String get polishUndo => '撤销润色';

	/// zh-CN: '匿名发布'
	String get anonymous => '匿名发布';

	/// zh-CN: '选择头像'
	String get pickAvatar => '选择头像';
}

// Path: auth.login
class Translations$auth$login$zh_CN {
	Translations$auth$login$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '登录'
	String get title => '登录';

	/// zh-CN: '使用账号密码登录'
	String get subtitle => '使用账号密码登录';

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

	/// zh-CN: '用户名'
	String get usernameLabel => '用户名';

	/// zh-CN: '3-20 位字母、数字或下划线'
	String get usernameHint => '3-20 位字母、数字或下划线';

	/// zh-CN: '密码'
	String get passwordLabel => '密码';

	/// zh-CN: '请输入密码'
	String get passwordHint => '请输入密码';

	/// zh-CN: '用户名需为 3-20 位字母、数字或下划线'
	String get invalidUsername => '用户名需为 3-20 位字母、数字或下划线';

	/// zh-CN: '密码需为 8-64 位'
	String get invalidPassword => '密码需为 8-64 位';

	/// zh-CN: '没有账号？'
	String get noAccount => '没有账号？';

	/// zh-CN: '注册'
	String get toRegister => '注册';

	/// zh-CN: '其他登录方式'
	String get otherLoginMethods => '其他登录方式';
}

// Path: auth.register
class Translations$auth$register$zh_CN {
	Translations$auth$register$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '注册'
	String get title => '注册';

	/// zh-CN: '创建账号后即可开始使用'
	String get subtitle => '创建账号后即可开始使用';

	/// zh-CN: '用户名'
	String get usernameLabel => '用户名';

	/// zh-CN: '3-20 位字母、数字或下划线'
	String get usernameHint => '3-20 位字母、数字或下划线';

	/// zh-CN: '密码'
	String get passwordLabel => '密码';

	/// zh-CN: '8-64 位，需包含字母和数字'
	String get passwordHint => '8-64 位，需包含字母和数字';

	/// zh-CN: '确认密码'
	String get confirmPasswordLabel => '确认密码';

	/// zh-CN: '再次输入密码'
	String get confirmPasswordHint => '再次输入密码';

	/// zh-CN: '注册'
	String get register => '注册';

	/// zh-CN: '注册中…'
	String get registering => '注册中…';

	/// zh-CN: '两次输入的密码不一致'
	String get passwordMismatch => '两次输入的密码不一致';

	/// zh-CN: '我已阅读并同意'
	String get agreePrefix => '我已阅读并同意';

	/// zh-CN: '和'
	String get agreeAnd => '和';

	/// zh-CN: '请先阅读并同意隐私政策与用户协议'
	String get agreeRequired => '请先阅读并同意隐私政策与用户协议';

	/// zh-CN: '密码强度：弱'
	String get strengthWeak => '密码强度：弱';

	/// zh-CN: '密码强度：中'
	String get strengthMedium => '密码强度：中';

	/// zh-CN: '密码强度：强'
	String get strengthStrong => '密码强度：强';

	/// zh-CN: '密码长度至少 8 位'
	String get strengthTooShort => '密码长度至少 8 位';

	/// zh-CN: '用户名需为 3-20 位字母、数字或下划线'
	String get invalidUsername => '用户名需为 3-20 位字母、数字或下划线';
}

// Path: auth.changePassword
class Translations$auth$changePassword$zh_CN {
	Translations$auth$changePassword$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '修改密码'
	String get title => '修改密码';

	/// zh-CN: '当前密码'
	String get oldLabel => '当前密码';

	/// zh-CN: '请输入当前密码'
	String get oldHint => '请输入当前密码';

	/// zh-CN: '请输入当前密码'
	String get oldRequired => '请输入当前密码';

	/// zh-CN: '新密码'
	String get newLabel => '新密码';

	/// zh-CN: '8-64 位，需包含字母和数字'
	String get newHint => '8-64 位，需包含字母和数字';

	/// zh-CN: '确认新密码'
	String get confirmLabel => '确认新密码';

	/// zh-CN: '再次输入新密码'
	String get confirmHint => '再次输入新密码';

	/// zh-CN: '确认修改'
	String get submit => '确认修改';

	/// zh-CN: '提交中…'
	String get submitting => '提交中…';

	/// zh-CN: '密码已修改，请重新登录'
	String get success => '密码已修改，请重新登录';

	/// zh-CN: '两次输入的新密码不一致'
	String get passwordMismatch => '两次输入的新密码不一致';
}

// Path: auth.error
class Translations$auth$error$zh_CN {
	Translations$auth$error$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '用户名已被使用'
	String get usernameTaken => '用户名已被使用';

	/// zh-CN: '用户名或密码错误'
	String get invalidCredentials => '用户名或密码错误';

	/// zh-CN: '密码需 8-64 位且包含字母和数字'
	String get passwordTooWeak => '密码需 8-64 位且包含字母和数字';
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

// Path: notify.channel.general
class Translations$notify$channel$general$zh_CN {
	Translations$notify$channel$general$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '常规提醒'
	String get name => '常规提醒';

	/// zh-CN: 'App 的一般性提醒'
	String get description => 'App 的一般性提醒';
}

// Path: notify.channel.waterReminders
class Translations$notify$channel$waterReminders$zh_CN {
	Translations$notify$channel$waterReminders$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '喝水提醒'
	String get name => '喝水提醒';

	/// zh-CN: '进食窗口内的每小时喝水提醒'
	String get description => '进食窗口内的每小时喝水提醒';
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

// Path: onboarding.profile.gender
class Translations$onboarding$profile$gender$zh_CN {
	Translations$onboarding$profile$gender$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '男'
	String get male => '男';

	/// zh-CN: '女'
	String get female => '女';

	/// zh-CN: '不便透露'
	String get undisclosed => '不便透露';
}

// Path: onboarding.profile.activity
class Translations$onboarding$profile$activity$zh_CN {
	Translations$onboarding$profile$activity$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '大部分时间是坐着的（办公室/居家，几乎不运动）'
	String get sedentary => '大部分时间是坐着的（办公室/居家，几乎不运动）';

	/// zh-CN: '每周轻度运动 1–3 次（散步、瑜伽等）'
	String get light => '每周轻度运动 1–3 次（散步、瑜伽等）';

	/// zh-CN: '每周中等强度运动 3–5 次（跑步、游泳等）'
	String get moderate => '每周中等强度运动 3–5 次（跑步、游泳等）';

	/// zh-CN: '每周高强度运动 6 次以上或体力劳动'
	String get high => '每周高强度运动 6 次以上或体力劳动';
}

// Path: onboarding.profile.screening
class Translations$onboarding$profile$screening$zh_CN {
	Translations$onboarding$profile$screening$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '是否有进食障碍史（如暴食症/厌食症），或正在接受相关治疗？'
	String get title => '是否有进食障碍史（如暴食症/厌食症），或正在接受相关治疗？';

	/// zh-CN: '仅用于为你调整更温和的减重节奏；答案只保存在本机，不会上传。'
	String get hint => '仅用于为你调整更温和的减重节奏；答案只保存在本机，不会上传。';

	late final Translations$onboarding$profile$screening$options$zh_CN options = Translations$onboarding$profile$screening$options$zh_CN.internal(_root);
}

// Path: record.barcode.contribute
class Translations$record$barcode$contribute$zh_CN {
	Translations$record$barcode$contribute$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '补充商品信息'
	String get title => '补充商品信息';

	/// zh-CN: '商品条码：${code}'
	String barcodeLabel({required Object code}) => '商品条码：${code}';

	/// zh-CN: '商品名'
	String get nameLabel => '商品名';

	/// zh-CN: '请输入商品名'
	String get nameRequired => '请输入商品名';

	/// zh-CN: '包装营养表照片（必填）'
	String get photoLabel => '包装营养表照片（必填）';

	/// zh-CN: '拍摄 / 选择照片'
	String get photoAdd => '拍摄 / 选择照片';

	/// zh-CN: '请拍摄或选择包装上的营养表照片'
	String get photoRequired => '请拍摄或选择包装上的营养表照片';

	/// zh-CN: '照片上传中…'
	String get photoUploading => '照片上传中…';

	/// zh-CN: '重新上传'
	String get photoUploadRetry => '重新上传';

	/// zh-CN: '提交补录'
	String get submitAction => '提交补录';

	/// zh-CN: '已提交，审核通过后全用户都能扫到'
	String get submitted => '已提交，审核通过后全用户都能扫到';

	/// zh-CN: '该商品已在库，已为你预填'
	String get alreadyListed => '该商品已在库，已为你预填';

	/// zh-CN: '需要联网才能提交补录：商品已存本机可记餐，联网后请重新提交'
	String get offlineNotice => '需要联网才能提交补录：商品已存本机可记餐，联网后请重新提交';
}

// Path: record.customFood.contributions
class Translations$record$customFood$contributions$zh_CN {
	Translations$record$customFood$contributions$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '我的贡献'
	String get title => '我的贡献';

	/// zh-CN: '全部'
	String get filterAll => '全部';

	/// zh-CN: '暂无贡献记录'
	String get empty => '暂无贡献记录';

	/// zh-CN: '把搜不到的食物记下来，审核通过后分享给所有人'
	String get emptySubtitle => '把搜不到的食物记下来，审核通过后分享给所有人';

	/// zh-CN: '新建自定义食物'
	String get emptyCta => '新建自定义食物';

	/// zh-CN: '审核中'
	String get statusPending => '审核中';

	/// zh-CN: '已通过'
	String get statusApproved => '已通过';

	/// zh-CN: '已拒绝'
	String get statusRejected => '已拒绝';

	/// zh-CN: '拒绝原因：${reason}'
	String reasonLabel({required Object reason}) => '拒绝原因：${reason}';

	/// zh-CN: '提交于 ${date}'
	String submittedAt({required Object date}) => '提交于 ${date}';

	/// zh-CN: '加载失败，请稍后重试'
	String get loadFailed => '加载失败，请稍后重试';

	/// zh-CN: '条码商品'
	String get kindBarcode => '条码商品';

	/// zh-CN: '条码 ${code}'
	String barcodeLabel({required Object code}) => '条码 ${code}';

	/// zh-CN: '纠错'
	String get kindCorrection => '纠错';
}

// Path: record.customFood.correction
class Translations$record$customFood$correction$zh_CN {
	Translations$record$customFood$correction$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '数据纠错'
	String get title => '数据纠错';

	/// zh-CN: '改动会提交审核，通过后全用户生效'
	String get subtitle => '改动会提交审核，通过后全用户生效';

	/// zh-CN: '提交纠错'
	String get submit => '提交纠错';
}

// Path: record.exercise.conflict
class Translations$record$exercise$conflict$zh_CN {
	Translations$record$exercise$conflict$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '今天已经有运动记录'
	String get title => '今天已经有运动记录';

	/// zh-CN: '今天已记 ${count} 条，共 ${kcal} 千卡。这次是再加一条，还是用新数据替换今天的旧记录？'
	String body({required Object count, required Object kcal}) => '今天已记 ${count} 条，共 ${kcal} 千卡。这次是再加一条，还是用新数据替换今天的旧记录？';

	/// zh-CN: '再加一条'
	String get add => '再加一条';

	/// zh-CN: '替换今天记录'
	String get replace => '替换今天记录';
}

// Path: record.exercise.screenshot
class Translations$record$exercise$screenshot$zh_CN {
	Translations$record$exercise$screenshot$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '拍照识别'
	String get entryCamera => '拍照识别';

	/// zh-CN: '相册导入'
	String get entryGallery => '相册导入';

	/// zh-CN: '识别截图中…'
	String get recognizing => '识别截图中…';

	/// zh-CN: '正在提取运动数据，截图大时可能要多等几秒'
	String get recognizingHint => '正在提取运动数据，截图大时可能要多等几秒';

	/// zh-CN: '正在加载视觉模型…'
	String get loadingModel => '正在加载视觉模型…';

	/// zh-CN: '没能识别这张图，换张清晰的截图试试'
	String get unavailable => '没能识别这张图，换张清晰的截图试试';

	/// zh-CN: '确认活动数据'
	String get confirmTitleSummary => '确认活动数据';

	/// zh-CN: '确认运动记录'
	String get confirmTitleWorkout => '确认运动记录';

	/// zh-CN: '步数（步）'
	String get stepsLabel => '步数（步）';

	/// zh-CN: '距离（公里）'
	String get distanceLabel => '距离（公里）';

	/// zh-CN: '爬楼（米，仅展示）'
	String get floorsLabel => '爬楼（米，仅展示）';

	/// zh-CN: '活动热量（千卡）'
	String get activeKcalLabel => '活动热量（千卡）';

	/// zh-CN: '计入消耗（千卡）'
	String get burnLabel => '计入消耗（千卡）';

	/// zh-CN: '截图里的类型没对上，请手动选择运动类型'
	String get pickTypeHint => '截图里的类型没对上，请手动选择运动类型';
}

// Path: record.exercise.types
class Translations$record$exercise$types$zh_CN {
	Translations$record$exercise$types$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '走路'
	String get walk => '走路';

	/// zh-CN: '慢跑'
	String get jog => '慢跑';

	/// zh-CN: '快跑'
	String get run => '快跑';

	/// zh-CN: '骑车'
	String get cycling => '骑车';

	/// zh-CN: '游泳'
	String get swimming => '游泳';

	/// zh-CN: '跳绳'
	String get jumpRope => '跳绳';

	/// zh-CN: '瑜伽'
	String get yoga => '瑜伽';

	/// zh-CN: '力量训练'
	String get strength => '力量训练';

	/// zh-CN: '椭圆机'
	String get elliptical => '椭圆机';

	/// zh-CN: '爬山'
	String get hiking => '爬山';

	/// zh-CN: '羽毛球'
	String get badminton => '羽毛球';

	/// zh-CN: '篮球'
	String get basketball => '篮球';

	/// zh-CN: '足球'
	String get soccer => '足球';

	/// zh-CN: '乒乓球'
	String get tableTennis => '乒乓球';

	/// zh-CN: '网球'
	String get tennis => '网球';

	/// zh-CN: '健身操/舞蹈'
	String get dance => '健身操/舞蹈';

	/// zh-CN: 'HIIT'
	String get hiit => 'HIIT';

	/// zh-CN: '活动统计'
	String get summary => '活动统计';
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

// Path: fasting.home.endFastDialog
class Translations$fasting$home$endFastDialog$zh_CN {
	Translations$fasting$home$endFastDialog$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '结束断食'
	String get title => '结束断食';

	/// zh-CN: '已断食 ${hours} 小时 ${minutes} 分钟'
	String elapsed({required Object hours, required Object minutes}) => '已断食 ${hours} 小时 ${minutes} 分钟';

	/// zh-CN: '计划 ${hours} 小时'
	String plannedHours({required Object hours}) => '计划 ${hours} 小时';

	/// zh-CN: '计划 ${hours} 小时 ${minutes} 分钟'
	String plannedHoursMinutes({required Object hours, required Object minutes}) => '计划 ${hours} 小时 ${minutes} 分钟';

	/// zh-CN: '距计划结束还有 15 分钟以上，本次将记为不达标'
	String get earlyWarning => '距计划结束还有 15 分钟以上，本次将记为不达标';

	/// zh-CN: '继续断食'
	String get cancel => '继续断食';

	/// zh-CN: '确认结束'
	String get confirm => '确认结束';
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

	/// zh-CN: '单位：热量为千卡，蛋白质/碳水/脂肪为克。'
	String get unitsNote => '单位：热量为千卡，蛋白质/碳水/脂肪为克。';
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

	/// zh-CN: '去记录'
	String get ctaRecord => '去记录';

	/// zh-CN: '小时'
	String get hourUnit => '小时';
}

// Path: nutrition.data.burn
class Translations$nutrition$data$burn$zh_CN {
	Translations$nutrition$data$burn$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '今日消耗'
	String get title => '今日消耗';

	/// zh-CN: '活动消耗'
	String get activeEnergy => '活动消耗';

	/// zh-CN: '步数'
	String get steps => '步数';

	/// zh-CN: '${kcal} kcal'
	String kcalValue({required Object kcal}) => '${kcal} kcal';

	/// zh-CN: '约 ${kcal} kcal（按步数估算）'
	String estimatedValue({required Object kcal}) => '约 ${kcal} kcal（按步数估算）';

	/// zh-CN: '摄入 − 消耗结余：${kcal} kcal'
	String balance({required Object kcal}) => '摄入 − 消耗结余：${kcal} kcal';

	/// zh-CN: '${kcal} / ${goal} 千卡'
	String goalProgress({required Object kcal, required Object goal}) => '${kcal} / ${goal} 千卡';

	/// zh-CN: '${steps} / ${goal} 步'
	String stepsGoalProgress({required Object steps, required Object goal}) => '${steps} / ${goal} 步';

	/// zh-CN: '今日消耗目标进度 ${percent}%'
	String goalRingLabel({required Object percent}) => '今日消耗目标进度 ${percent}%';

	/// zh-CN: '手动记运动可计入消耗'
	String get manualGuide => '手动记运动可计入消耗';
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

// Path: streak.milestone.shareCard
class Translations$streak$milestone$shareCard$zh_CN {
	Translations$streak$milestone$shareCard$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '点亮成就 · 分享图卡'
	String get sheetTitle => '点亮成就 · 分享图卡';

	/// zh-CN: '天'
	String get daysUnit => '天';

	/// zh-CN: '明食 EatWise'
	String get appName => '明食 EatWise';

	/// zh-CN: '轻盈断食，自在生活'
	String get tagline => '轻盈断食，自在生活';

	/// zh-CN: '保存到相册'
	String get saveToAlbum => '保存到相册';

	/// zh-CN: '系统分享'
	String get shareSystem => '系统分享';

	/// zh-CN: '已保存到相册'
	String get saveSuccess => '已保存到相册';

	/// zh-CN: '保存失败，请检查相册权限后重试'
	String get saveFailed => '保存失败，请检查相册权限后重试';

	/// zh-CN: '分享失败，请稍后重试'
	String get shareFailed => '分享失败，请稍后重试';
}

// Path: settings.bodyProfile.bmi
class Translations$settings$bodyProfile$bmi$zh_CN {
	Translations$settings$bodyProfile$bmi$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: 'BMI'
	String get title => 'BMI';

	/// zh-CN: '偏低'
	String get underweight => '偏低';

	/// zh-CN: '标准'
	String get normal => '标准';

	/// zh-CN: '偏高'
	String get overweight => '偏高';

	/// zh-CN: '肥胖'
	String get obese => '肥胖';

	/// zh-CN: '补全身高体重后展示 BMI'
	String get missing => '补全身高体重后展示 BMI';

	/// zh-CN: '体重单位是公斤，如果你是按斤填的，请改一下体重'
	String get unitHint => '体重单位是公斤，如果你是按斤填的，请改一下体重';
}

// Path: settings.aiModel.providers
class Translations$settings$aiModel$providers$zh_CN {
	Translations$settings$aiModel$providers$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '自定义'
	String get custom => '自定义';

	/// zh-CN: 'DeepSeek'
	String get deepseek => 'DeepSeek';

	/// zh-CN: '通义千问（Qwen）'
	String get qwen => '通义千问（Qwen）';

	/// zh-CN: 'Kimi'
	String get kimi => 'Kimi';
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

// Path: onboarding.profile.screening.options
class Translations$onboarding$profile$screening$options$zh_CN {
	Translations$onboarding$profile$screening$options$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '是'
	String get yes => '是';

	/// zh-CN: '否'
	String get no => '否';

	/// zh-CN: '不愿透露'
	String get preferNotToSay => '不愿透露';
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
			'notify.channel.general.name' => '常规提醒',
			'notify.channel.general.description' => 'App 的一般性提醒',
			'notify.channel.waterReminders.name' => '喝水提醒',
			'notify.channel.waterReminders.description' => '进食窗口内的每小时喝水提醒',
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
			'onboarding.recommendation.planChangeTitle' => '更换断食方案',
			'onboarding.recommendation.planChangeConfirm' => ({required Object date}) => '新方案将于 ${date} 00:00 生效，今天仍按当前方案计时。',
			'onboarding.recommendation.weightLossPlan' => ({required Object rate, required Object date}) => '预计每周减 ${rate} kg · 约 ${date} 达成',
			'onboarding.recommendation.dailyKcalTarget' => ({required Object kcal}) => '每日热量目标约 ${kcal} kcal',
			'onboarding.recommendation.clampedNotice' => '你的目标节奏偏快，已按安全上限调整为每周最多减 1 kg。',
			'onboarding.recommendation.gentleNotice' => '已为你按温和节奏安排，每周最多减 0.5 kg。',
			'onboarding.recommendation.edNotice' => '你提到有进食障碍相关经历：减重目标已按温和节奏调整。本应用不提供医疗建议，建议同步咨询专业医生或营养师。',
			'onboarding.science.title' => '断食原理小科普',
			'onboarding.science.card1Title' => '给身体一点休息时间',
			'onboarding.science.card1Body' => '断食期间，身体会慢慢切换到燃脂模式，用储存的能量供能。',
			'onboarding.science.card2Title' => '不是节食，是节奏',
			'onboarding.science.card2Body' => '轻断食关注「什么时候吃」，而不是「这不能吃那不能吃」，进食窗口里好好吃饭很重要。',
			'onboarding.science.disclaimer' => '本内容仅为健康科普，非医疗建议。如有基础疾病，或在孕期、哺乳期等特殊情况，请先咨询医生。',
			'onboarding.science.back' => '返回',
			'onboarding.profile.title' => '了解你的身体，目标更精准',
			'onboarding.profile.subtitle' => '以下信息仅用于计算每日营养目标，属敏感个人信息：可以整页跳过，也可以只填部分；留空项将使用默认估算。',
			'onboarding.profile.genderLabel' => '生理性别（用于热量公式）',
			'onboarding.profile.gender.male' => '男',
			'onboarding.profile.gender.female' => '女',
			'onboarding.profile.gender.undisclosed' => '不便透露',
			'onboarding.profile.birthYearLabel' => '出生年份',
			'onboarding.profile.birthYearHint' => '如 1995',
			'onboarding.profile.birthYearInvalid' => ({required Object min, required Object max}) => '请输入 ${min}–${max} 之间的年份',
			'onboarding.profile.heightLabel' => '身高（cm）',
			'onboarding.profile.heightHint' => '如 168',
			'onboarding.profile.heightInvalid' => '请输入 100–250 之间的身高',
			'onboarding.profile.weightLabel' => '体重（kg）',
			'onboarding.profile.weightLabelJin' => '体重（斤）',
			'onboarding.profile.weightHint' => '如 60',
			'onboarding.profile.weightHintJin' => '如 120',
			'onboarding.profile.weightInvalid' => '请输入 25–300 之间的体重',
			'onboarding.profile.weightInvalidJin' => '请输入 50–600 之间的体重（斤）',
			'onboarding.profile.weightUnitKg' => '公斤',
			'onboarding.profile.weightUnitJin' => '斤',
			'onboarding.profile.activityLabel' => '日常活动量',
			'onboarding.profile.activity.sedentary' => '大部分时间是坐着的（办公室/居家，几乎不运动）',
			'onboarding.profile.activity.light' => '每周轻度运动 1–3 次（散步、瑜伽等）',
			'onboarding.profile.activity.moderate' => '每周中等强度运动 3–5 次（跑步、游泳等）',
			'onboarding.profile.activity.high' => '每周高强度运动 6 次以上或体力劳动',
			'onboarding.profile.save' => '保存并继续',
			'onboarding.profile.skip' => '跳过，使用默认估算',
			'onboarding.profile.screening.title' => '是否有进食障碍史（如暴食症/厌食症），或正在接受相关治疗？',
			'onboarding.profile.screening.hint' => '仅用于为你调整更温和的减重节奏；答案只保存在本机，不会上传。',
			'onboarding.profile.screening.options.yes' => '是',
			'onboarding.profile.screening.options.no' => '否',
			'onboarding.profile.screening.options.preferNotToSay' => '不愿透露',
			'onboarding.goal.title' => '定个减重小目标',
			'onboarding.goal.subtitle' => '填上目标体重和日期，就能按安全节奏算出每天的热量目标；也可以跳过，先按默认折算。',
			'onboarding.goal.targetWeightLabel' => '目标体重（kg）',
			'onboarding.goal.targetWeightLabelJin' => '目标体重（斤）',
			'onboarding.goal.targetWeightHint' => '如 55',
			'onboarding.goal.targetWeightHintJin' => '如 110',
			'onboarding.goal.targetWeightInvalid' => '请输入 25–300 之间的体重',
			'onboarding.goal.targetWeightInvalidJin' => '请输入 50–600 之间的体重（斤）',
			'onboarding.goal.targetDateLabel' => '希望在哪天达成？',
			'onboarding.goal.quickWeeks' => ({required Object weeks}) => '${weeks} 周后',
			'onboarding.goal.customDate' => '自选日期',
			'onboarding.goal.clearDate' => '清除日期',
			'onboarding.goal.save' => '保存并继续',
			'onboarding.goal.skip' => '跳过',
			'record.page.title' => '记录',
			'record.page.confirm' => '确认记录',
			'record.page.loggedToday' => ({required Object count}) => '今日已记 ${count} 笔',
			'record.page.todayKcal' => ({required Object kcal}) => '今日约 ${kcal} 千卡（待云端校准）',
			'record.meal.label' => '餐次',
			'record.meal.breakfast' => '早餐',
			'record.meal.lunch' => '午餐',
			'record.meal.dinner' => '晚餐',
			'record.meal.snack' => '加餐',
			'record.meal.other' => '其他',
			'record.today.title' => '今日记录',
			'record.today.deleteEntry' => '删除这条记录？',
			'record.today.deleteConfirmAction' => '删除',
			'record.today.deleted' => '已删除',
			'record.entries.photo' => '拍照记',
			'record.entries.voice' => '语音记',
			'record.entries.frequent' => '常吃',
			'record.entries.exercise' => '记运动',
			'record.entries.comingSoon' => '即将上线，先用手动搜索记一笔吧',
			'record.pending.banner' => ({required Object count}) => '还有 ${count} 条记录在路上，联网后自动同步',
			'record.search.hint' => '搜索食物（中文或英文）',
			'record.search.empty' => '没找到？换个关键词试试',
			'record.search.clear' => '清空搜索',
			'record.search.addRow' => ({required Object query}) => '添加「${query}」为自定义食物',
			'record.amount.label' => '份量（克）',
			'record.amount.invalid' => '请输入大于 0 的份量',
			'record.nutrition.kcal' => '热量',
			'record.nutrition.protein' => '蛋白质',
			'record.nutrition.carb' => '碳水',
			'record.nutrition.fat' => '脂肪',
			'record.nutrition.sodium' => '钠',
			'record.nutrition.kcalUnit' => '千卡',
			'record.nutrition.kjUnit' => '千焦',
			'record.nutrition.gramUnit' => '克',
			'record.nutrition.mgUnit' => '毫克',
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
			'record.photo.noFoodTitle' => '未识别到食物',
			'record.photo.noFoodHint' => '换个角度拍，或手动搜索试试',
			'record.photo.gotIt' => '知道了',
			'record.photo.retake' => '重新拍摄',
			'record.photo.recognizingHint' => '首次识别需要加载视觉引擎，可能需要几秒',
			'record.photo.loadingModel' => '正在加载视觉模型…',
			'record.photo.mealConfirmTitle' => '确认这餐明细',
			'record.photo.logAll' => '全部记录',
			'record.photo.loggedItems' => ({required Object count}) => '已记录 ${count} 条',
			'record.photo.unmatchedItemTag' => '库未收录，将自动新建',
			'record.photo.labelValueTag' => '标签值',
			'record.photo.engineGuideTitle' => 'AI 识别需要一个模型',
			'record.photo.engineGuideBody' => '下载本地模型（离线可用，约 2.4GB，下载后无需联网），或配置云端 API 使用你的模型服务。',
			'record.photo.engineGuideDownload' => '下载本地模型（推荐）',
			'record.photo.engineGuideConfigApi' => '配置云端 API',
			'record.photo.engineGuideManual' => '先手动搜索',
			'record.photo.similarFoodsTitle' => '库中已有相似食物：',
			'record.photo.useThisFood' => '用这个',
			'record.photo.loggedWithPending' => ({required Object count, required Object pending}) => '已记录 ${count} 条（${pending} 条待审核）',
			'record.barcode.entry' => '扫码记',
			'record.barcode.title' => '扫描商品条码',
			'record.barcode.torch' => '照明灯',
			'record.barcode.manualInput' => '手动输码',
			'record.barcode.manualTitle' => '输入条码',
			'record.barcode.manualHint' => '请输入包装上的 8–14 位数字条码',
			'record.barcode.manualConfirm' => '查询',
			'record.barcode.invalid' => '条码格式不正确，应为 8–14 位数字',
			'record.barcode.looking' => '查询中…',
			'record.barcode.notFoundTitle' => '未收录该商品',
			'record.barcode.notFoundBody' => '食物库里还没有这个商品，你可以补充商品信息（拍营养表提交审核，通过后大家都能扫到），或手动搜索、添加自定义食物。',
			'record.barcode.notFoundSearch' => '手动搜索',
			'record.barcode.notFoundCustom' => '添加自定义食物',
			'record.barcode.notFoundContribute' => '补充商品信息',
			'record.barcode.unavailable' => '查询失败，请检查网络后重试',
			'record.barcode.deniedTitle' => '相机未授权',
			'record.barcode.deniedBody' => '扫不了码也能记，手动搜索或输码一样快',
			'record.barcode.openSettings' => '去开启',
			'record.barcode.useManual' => '手动搜索',
			'record.barcode.contribute.title' => '补充商品信息',
			'record.barcode.contribute.barcodeLabel' => ({required Object code}) => '商品条码：${code}',
			'record.barcode.contribute.nameLabel' => '商品名',
			'record.barcode.contribute.nameRequired' => '请输入商品名',
			'record.barcode.contribute.photoLabel' => '包装营养表照片（必填）',
			'record.barcode.contribute.photoAdd' => '拍摄 / 选择照片',
			'record.barcode.contribute.photoRequired' => '请拍摄或选择包装上的营养表照片',
			'record.barcode.contribute.photoUploading' => '照片上传中…',
			'record.barcode.contribute.photoUploadRetry' => '重新上传',
			'record.barcode.contribute.submitAction' => '提交补录',
			'record.barcode.contribute.submitted' => '已提交，审核通过后全用户都能扫到',
			'record.barcode.contribute.alreadyListed' => '该商品已在库，已为你预填',
			'record.barcode.contribute.offlineNotice' => '需要联网才能提交补录：商品已存本机可记餐，联网后请重新提交',
			'record.voice.listening' => '正在听… 说说吃了什么，如「一碗米饭」',
			'record.voice.tapToStart' => '点一下开始说话',
			'record.voice.finish' => '完成',
			'record.voice.unavailable' => '这台设备暂时用不了语音识别，打字搜一样快',
			'record.voice.deniedTitle' => '麦克风未授权',
			'record.voice.deniedBody' => '开不了语音也能记，打字搜一样快',
			'record.voice.noMatch' => '没听出是什么食物，换个说法或手动搜索',
			'record.voice.noMatchTyped' => '没找到匹配的食物，换个说法搜索或添加自定义食物',
			'record.voice.typeInput' => '键盘输入',
			'record.voice.typeHint' => '说一句，比如「中午吃了一碗牛肉面加个蛋」',
			'record.voice.understanding' => '理解中…',
			'record.voice.noSpeechHint' => '没听清，请再说一次，或点右边键盘图标打字',
			'record.voice.errorGeneric' => '语音识别不可用，点右边键盘图标打字输入',
			'record.voice.recordingNow' => '正在录音… 再点一下停止',
			'record.voice.transcribingNow' => '转写中…',
			'record.voice.transcribeFailed' => '没转写出来，再录一次，或点右边键盘图标打字',
			'record.voice.retry' => '再说一次',
			'record.voice.useOnDeviceAsr' => '用离线小模型识别',
			'record.voice.loadingModel' => '正在加载离线模型，首次较慢…',
			'record.voice.downloadTitle' => '下载离线模型',
			'record.frequent.title' => '常吃的食物',
			'record.frequent.empty' => '多记几笔，常吃榜就出来啦',
			'record.frequent.emptyCta' => '去搜一搜',
			'record.card.pleaseConfirm' => '请确认',
			'record.customFood.cta' => '找不到？添加自定义食物',
			'record.customFood.badge' => '自定义',
			'record.customFood.title' => '添加自定义食物',
			'record.customFood.nameLabel' => '菜名',
			'record.customFood.nameRequired' => '请输入菜名',
			'record.customFood.aliasLabel' => '别名（可选，逗号分隔）',
			'record.customFood.estimate' => 'AI 估算',
			'record.customFood.estimating' => '估算中…',
			'record.customFood.estimateLow' => '置信度较低，请仔细核对数值',
			'record.customFood.estimateUnavailable' => '估算暂不可用，请手动填写',
			'record.customFood.estimateBadgeOnDevice' => '端侧估算，请确认',
			'record.customFood.estimateBadgeUserApi' => '自定义 API 估算，请确认',
			'record.customFood.estimateDubious' => '估算存疑，请核对数值',
			'record.customFood.kcalLabel' => '热量（千卡 / 100 克）',
			'record.customFood.proteinLabel' => '蛋白质（克 / 100 克）',
			'record.customFood.carbLabel' => '碳水（克 / 100 克）',
			'record.customFood.fatLabel' => '脂肪（克 / 100 克）',
			'record.customFood.nutritionRequired' => '请填写大于 0 的数值',
			'record.customFood.kcalRange' => '热量需在 0–900 千卡之间',
			'record.customFood.macroRange' => '需在 0–100 克之间',
			'record.customFood.savedOffline' => '已保存到本机，联网后自动同步',
			'record.customFood.savedOnline' => '已保存',
			'record.customFood.shareOptIn' => '分享给所有用户（审核通过后大家都能搜到）',
			'record.customFood.shareAction' => '分享给所有用户',
			'record.customFood.submittedReview' => '已提交审核',
			'record.customFood.badgePending' => '审核中',
			'record.customFood.badgeApproved' => '已共享',
			'record.customFood.badgeRejected' => '未通过',
			'record.customFood.badgeCommunity' => '社区',
			'record.customFood.reviewRejectedNotice' => ({required Object name}) => '你提交的食品「${name}」未通过审核，相关记录已移除',
			'record.customFood.editTitle' => '编辑自定义食物',
			'record.customFood.editAction' => '编辑',
			'record.customFood.editSave' => '保存修改',
			'record.customFood.deleteAction' => '删除',
			'record.customFood.deleteConfirmTitle' => '删除这个自定义食物？',
			'record.customFood.deleteConfirmBody' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '将同时删除 ${n} 条相关历史记录，此操作不可撤销', other: '将同时删除 ${n} 条相关历史记录，此操作不可撤销', ), 
			'record.customFood.deleteDone' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '已删除（含 ${n} 条记录）', other: '已删除（含 ${n} 条记录）', ), 
			'record.customFood.underReviewDeleteBlocked' => '该食物正在审核中，暂时无法删除，请先等待审核完成',
			'record.customFood.contributions.title' => '我的贡献',
			'record.customFood.contributions.filterAll' => '全部',
			'record.customFood.contributions.empty' => '暂无贡献记录',
			'record.customFood.contributions.emptySubtitle' => '把搜不到的食物记下来，审核通过后分享给所有人',
			'record.customFood.contributions.emptyCta' => '新建自定义食物',
			'record.customFood.contributions.statusPending' => '审核中',
			'record.customFood.contributions.statusApproved' => '已通过',
			'record.customFood.contributions.statusRejected' => '已拒绝',
			'record.customFood.contributions.reasonLabel' => ({required Object reason}) => '拒绝原因：${reason}',
			'record.customFood.contributions.submittedAt' => ({required Object date}) => '提交于 ${date}',
			'record.customFood.contributions.loadFailed' => '加载失败，请稍后重试',
			'record.customFood.contributions.kindBarcode' => '条码商品',
			'record.customFood.contributions.barcodeLabel' => ({required Object code}) => '条码 ${code}',
			'record.customFood.contributions.kindCorrection' => '纠错',
			'record.customFood.correction.title' => '数据纠错',
			'record.customFood.correction.subtitle' => '改动会提交审核，通过后全用户生效',
			'record.customFood.correction.submit' => '提交纠错',
			'record.customFood.photoOcr' => '拍营养表',
			'record.customFood.photoOcrReading' => '读表中…',
			'record.customFood.photoOcrFailed' => '没读出来，换个角度拍或手动填写',
			'record.customFood.estimateBadgeOcr' => 'AI 读表，请核对',
			'record.water.title' => '今日饮水',
			'record.water.progress' => ({required Object total, required Object goal}) => '${total} / ${goal} 毫升',
			'record.water.quickAddLabel' => ({required Object ml}) => '加 ${ml} 毫升水',
			'record.weight.title' => '体重',
			'record.weight.notLogged' => '记一下',
			'record.weight.current' => ({required Object kg}) => '${kg} 千克',
			'record.weight.dialogTitle' => '记录今日体重',
			'record.weight.inputLabel' => '体重（千克）',
			'record.weight.inputLabelJin' => '体重（斤）',
			'record.weight.invalid' => '请输入 20 到 300 之间的数',
			'record.weight.invalidJin' => '请输入 40 到 600 之间的数（斤）',
			'record.weight.unitKg' => '千克',
			'record.weight.unitJin' => '斤',
			'record.weight.bodyFatLabel' => '体脂率（%，可不填）',
			'record.weight.bodyFatInvalid' => '体脂率需在 1–70% 之间',
			'record.exercise.title' => '记运动',
			'record.exercise.typeLabel' => '运动类型',
			'record.exercise.durationLabel' => '时长（分钟）',
			'record.exercise.kcalLabel' => '消耗（千卡）',
			'record.exercise.estimatedWeightHint' => '未填体重，按 60 千克估算',
			'record.exercise.durationInvalid' => '请输入大于 0 的分钟数',
			'record.exercise.kcalInvalid' => '请输入大于 0 的千卡数',
			'record.exercise.todayList' => '今日运动',
			'record.exercise.minutesValue' => ({required Object min}) => '${min} 分钟',
			'record.exercise.kcalValue' => ({required Object kcal}) => '${kcal} 千卡',
			'record.exercise.stepsLabel' => '步数（步）',
			'record.exercise.stepsEstimateHint' => '填步数则按步数自动估算距离与热量，时长可留空',
			'record.exercise.stepsValue' => ({required Object steps}) => '${steps} 步',
			'record.exercise.conflict.title' => '今天已经有运动记录',
			'record.exercise.conflict.body' => ({required Object count, required Object kcal}) => '今天已记 ${count} 条，共 ${kcal} 千卡。这次是再加一条，还是用新数据替换今天的旧记录？',
			'record.exercise.conflict.add' => '再加一条',
			'record.exercise.conflict.replace' => '替换今天记录',
			'record.exercise.deleteLabel' => '删除该条运动记录',
			'record.exercise.deleted' => '已删除',
			'record.exercise.screenshot.entryCamera' => '拍照识别',
			'record.exercise.screenshot.entryGallery' => '相册导入',
			'record.exercise.screenshot.recognizing' => '识别截图中…',
			'record.exercise.screenshot.recognizingHint' => '正在提取运动数据，截图大时可能要多等几秒',
			'record.exercise.screenshot.loadingModel' => '正在加载视觉模型…',
			'record.exercise.screenshot.unavailable' => '没能识别这张图，换张清晰的截图试试',
			'record.exercise.screenshot.confirmTitleSummary' => '确认活动数据',
			'record.exercise.screenshot.confirmTitleWorkout' => '确认运动记录',
			'record.exercise.screenshot.stepsLabel' => '步数（步）',
			'record.exercise.screenshot.distanceLabel' => '距离（公里）',
			'record.exercise.screenshot.floorsLabel' => '爬楼（米，仅展示）',
			'record.exercise.screenshot.activeKcalLabel' => '活动热量（千卡）',
			'record.exercise.screenshot.burnLabel' => '计入消耗（千卡）',
			'record.exercise.screenshot.pickTypeHint' => '截图里的类型没对上，请手动选择运动类型',
			'record.exercise.types.walk' => '走路',
			'record.exercise.types.jog' => '慢跑',
			'record.exercise.types.run' => '快跑',
			'record.exercise.types.cycling' => '骑车',
			'record.exercise.types.swimming' => '游泳',
			'record.exercise.types.jumpRope' => '跳绳',
			'record.exercise.types.yoga' => '瑜伽',
			'record.exercise.types.strength' => '力量训练',
			'record.exercise.types.elliptical' => '椭圆机',
			'record.exercise.types.hiking' => '爬山',
			'record.exercise.types.badminton' => '羽毛球',
			'record.exercise.types.basketball' => '篮球',
			'record.exercise.types.soccer' => '足球',
			'record.exercise.types.tableTennis' => '乒乓球',
			'record.exercise.types.tennis' => '网球',
			'record.exercise.types.dance' => '健身操/舞蹈',
			'record.exercise.types.hiit' => 'HIIT',
			'record.exercise.types.summary' => '活动统计',
			'record.home.title' => '记录',
			'record.home.logMeal' => '记一笔',
			'record.empty.title' => '肚子的故事还没写呢，点橙色按钮记一笔？',
			'record.duringFast.badge' => '断食期用餐',
			'record.foodDetail.per100g' => '每 100 克',
			'record.foodDetail.kcalKj' => ({required Object kj}) => '千卡 / ${kj} 千焦 · 每 100 克',
			'record.foodDetail.walkSteps' => ({required Object steps}) => '大约需走 ${steps} 步',
			'record.foodDetail.nutrientColumn' => '营养素',
			'record.foodDetail.nrvColumn' => 'NRV%',
			'record.foodDetail.macrosTitle' => '三大营养素供能比例',
			'record.foodDetail.energyShareNote' => '圆环按供能占比绘制：1 克脂肪供能 9 千卡，是碳水和蛋白质（各 4 千卡）的 2.25 倍',
			'record.foodDetail.moreTitle' => '每 100 克营养明细',
			'record.foodDetail.supplyKcal' => ({required Object kcal}) => '供能 ${kcal} 千卡',
			'record.foodDetail.aliases' => ({required Object names}) => '别名：${names}',
			'record.foodDetail.badgeGreen' => '绿灯 · 放心吃',
			'record.foodDetail.badgeYellow' => '黄灯 · 适量少吃',
			'record.foodDetail.badgeRed' => '红灯 · 尽量别吃',
			'record.foodDetail.badgeBasis' => '按每 100 克对照你的每日营养目标判定',
			'record.foodDetail.reportIssue' => '数据有误？告诉我们',
			'common.appName' => 'EatWise',
			'common.action.save' => '保存',
			'common.action.cancel' => '取消',
			'common.action.undo' => '撤销',
			'common.action.retry' => '重试',
			'common.action.confirm' => '确定',
			'common.error.network' => '网络连接失败，请检查网络后重试',
			'common.error.timeout' => '请求超时，请稍后重试',
			'fasting.home.title' => '断食计时',
			'fasting.home.endFast' => '结束断食',
			'fasting.home.extend' => '延长',
			'fasting.home.startPlan' => '选择你的断食方案',
			'fasting.home.stateEating' => '进食窗口中',
			'fasting.home.stateFasting' => '断食中',
			'fasting.home.stateFastingExtended' => '断食中 · 已延长',
			'fasting.home.stateNoPlan' => '还未开始断食方案',
			'fasting.home.attribution' => ({required Object date}) => '本次断食计入 ${date}',
			'fasting.home.attributionEating' => ({required Object date}) => '下一段断食将计入 ${date}',
			'fasting.home.extendedBadge' => ({required Object minutes}) => '已延长 +${minutes} 分钟',
			'fasting.home.extendLimit' => '单次最多延长 4 小时',
			'fasting.home.planTag' => ({required Object fast, required Object start, required Object end}) => '断食 ${fast} 小时 · 进食窗口 ${start}–${end}',
			'fasting.home.pendingPlanEdit' => '修改',
			'fasting.home.pendingPlanApply' => '立即应用',
			'fasting.home.pendingPlanApplied' => '新方案已立即生效',
			'fasting.home.pendingPlanRescheduled' => '新方案已更新，将按原定时间生效',
			'fasting.home.pendingPlanBadge' => '待生效方案',
			'fasting.home.pendingPlanEffective' => ({required Object date}) => '将于 ${date} 0:00 自动生效',
			'fasting.home.pendingPlanCancelBody' => '取消后将继续使用当前方案，本次换方案不再生效。',
			'fasting.home.pendingPlanCancelled' => '已取消新方案，当前方案保持不变',
			'fasting.home.noPlanSubtitle' => '3 个小问题，帮你找到最适合的断食节奏',
			'fasting.home.celebrationTitle' => '断食完成！身体悄悄做了次大扫除 ✨',
			'fasting.home.celebrationBadge' => '断食完成 ✨',
			'fasting.home.signalEmpty' => '今天还没记录，记一笔后信号灯会亮起来',
			'fasting.home.budgetEmpty' => ({required Object kcal}) => '今日还未记录 · 目标 ${kcal} 千卡',
			'fasting.home.budgetNormal' => ({required Object eaten, required Object left}) => '已吃 ${eaten} 千卡 · 还可吃 ${left} 千卡',
			'fasting.home.budgetOver' => ({required Object eaten, required Object over}) => '已吃 ${eaten} 千卡 · 已超 ${over} 千卡',
			'fasting.home.budgetExercise' => ({required Object kcal}) => ' · 运动 +${kcal}',
			'fasting.home.planProgress' => ({required Object week, required Object lost, required Object goal}) => '第 ${week} 周 · 已减 ${lost} kg / 目标 ${goal} kg',
			'fasting.home.planProgressBehind' => ({required Object week, required Object gap}) => '第 ${week} 周 · 距目标还差 ${gap} kg',
			'fasting.home.greeting.morning' => '早上好',
			'fasting.home.greeting.noon' => '中午好',
			'fasting.home.greeting.afternoon' => '下午好',
			'fasting.home.greeting.evening' => '晚上好',
			'fasting.home.greeting.night' => '这么晚还醒着？喝口水早点睡也是养生哦',
			'fasting.home.endFastDialog.title' => '结束断食',
			'fasting.home.endFastDialog.elapsed' => ({required Object hours, required Object minutes}) => '已断食 ${hours} 小时 ${minutes} 分钟',
			'fasting.home.endFastDialog.plannedHours' => ({required Object hours}) => '计划 ${hours} 小时',
			'fasting.home.endFastDialog.plannedHoursMinutes' => ({required Object hours, required Object minutes}) => '计划 ${hours} 小时 ${minutes} 分钟',
			'fasting.home.endFastDialog.earlyWarning' => '距计划结束还有 15 分钟以上，本次将记为不达标',
			'fasting.home.endFastDialog.cancel' => '继续断食',
			'fasting.home.endFastDialog.confirm' => '确认结束',
			'fasting.window.entry' => '自定义进食窗口',
			'fasting.window.title' => '自定义进食窗口',
			'fasting.window.duration' => '进食时长',
			'fasting.window.hoursOption' => ({required Object hours}) => '${hours} 小时',
			'fasting.window.start' => '开始时间',
			'fasting.window.preview' => ({required Object window, required Object hours}) => '进食 ${window} · 禁食 ${hours} 小时',
			'fasting.window.resetRecommended' => '重置为推荐窗口',
			'fasting.window.confirm' => '确定',
			'fasting.widget.dueEat' => ({required Object time}) => '${time} 可进食',
			'fasting.widget.dueEatEnd' => ({required Object time}) => '${time} 进食截止',
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
			'notification.water.hourly' => ({required Object ml, required Object remaining}) => '该喝水啦～建议喝 ${ml} 毫升，今天还差 ${remaining} 毫升',
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
			'nutrition.data.proDetails.unitsNote' => '单位：热量为千卡，蛋白质/碳水/脂肪为克。',
			'nutrition.data.trend.title' => '近 7 日趋势',
			'nutrition.data.trend.kcal' => '热量',
			'nutrition.data.trend.fasting' => '断食时长',
			'nutrition.data.trend.empty' => '记满几天，趋势曲线就跑起来啦',
			'nutrition.data.trend.ctaRecord' => '去记录',
			'nutrition.data.trend.hourUnit' => '小时',
			'nutrition.data.burn.title' => '今日消耗',
			'nutrition.data.burn.activeEnergy' => '活动消耗',
			'nutrition.data.burn.steps' => '步数',
			'nutrition.data.burn.kcalValue' => ({required Object kcal}) => '${kcal} kcal',
			'nutrition.data.burn.estimatedValue' => ({required Object kcal}) => '约 ${kcal} kcal（按步数估算）',
			'nutrition.data.burn.balance' => ({required Object kcal}) => '摄入 − 消耗结余：${kcal} kcal',
			'nutrition.data.burn.goalProgress' => ({required Object kcal, required Object goal}) => '${kcal} / ${goal} 千卡',
			'nutrition.data.burn.stepsGoalProgress' => ({required Object steps, required Object goal}) => '${steps} / ${goal} 步',
			'nutrition.data.burn.goalRingLabel' => ({required Object percent}) => '今日消耗目标进度 ${percent}%',
			'nutrition.data.burn.manualGuide' => '手动记运动可计入消耗',
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
			_ => null,
		} ?? switch (path) {
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
			'reports.trend.targetLine' => ({required Object kg}) => '目标 ${kg} 公斤',
			'reports.trend.toGoal' => ({required Object kg}) => '距目标还有 ${kg} 公斤',
			'reports.trend.goalReached' => '已达到目标体重',
			'reports.trend.weightUnlock' => ({required Object count}) => '再记录 ${count} 次体重，解锁完整曲线',
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
			'reports.weekly.entries' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '记录 ${n} 条', ), 
			'reports.weekly.greenRatio' => ({required Object percent}) => '绿灯占比 ${percent}%',
			'reports.weekly.cheer.great' => '这一周节奏超稳，给自己点个大大的赞 🌱',
			'reports.weekly.cheer.mixed' => '有起有落很正常，稳住节奏，下周继续～',
			'reports.weekly.cheer.start' => '先动起来就很棒，数据会陪你一起进步。',
			'reports.weekly.empty' => '周报还差一点点数据，记一笔或完成一次断食就生成啦',
			'reports.weeklySummary.title' => '上周小结',
			'reports.weeklySummary.chipQualified' => ({required Object days}) => '达标 ${days} 天',
			'reports.weeklySummary.chipRecorded' => ({required Object days}) => '记录 ${days} 天',
			'reports.weeklySummary.chipAvgKcal' => ({required Object kcal, required Object target}) => '平均 ${kcal} · 目标 ${target} 千卡',
			'reports.weeklySummary.chipWeight' => ({required Object kg}) => '体重 ${kg} 公斤',
			'reports.weeklySummary.fastingPlain' => ({required Object days}) => '上周断食达标 ${days} 天',
			'reports.weeklySummary.fastingMore' => ({required Object days, required Object delta}) => '上周断食达标 ${days} 天，比前周多 ${delta} 天',
			'reports.weeklySummary.fastingLess' => ({required Object days, required Object delta}) => '上周断食达标 ${days} 天，比前周少 ${delta} 天',
			'reports.weeklySummary.fastingSame' => ({required Object days}) => '上周断食达标 ${days} 天，与前周持平',
			'reports.weeklySummary.intakeWithin' => ({required Object kcal}) => '平均每日摄入 ${kcal} 千卡，在目标范围内',
			'reports.weeklySummary.intakeAbove' => ({required Object kcal, required Object percent}) => '平均每日摄入 ${kcal} 千卡，比目标高 ${percent}%',
			'reports.weeklySummary.intakeBelow' => ({required Object kcal, required Object percent}) => '平均每日摄入 ${kcal} 千卡，比目标低 ${percent}%',
			'reports.weeklySummary.weightUp' => ({required Object kg}) => '体重上升 ${kg} 公斤',
			'reports.weeklySummary.weightDown' => ({required Object kg}) => '体重下降 ${kg} 公斤',
			'reports.weeklySummary.weightSame' => '体重基本持平',
			'reports.weeklySummary.disclaimer' => '仅供健康生活方式参考',
			'reports.weeklySummary.empty' => '先记录几天，下周这时见',
			'reports.monthly.prevMonth' => '上一月',
			'reports.monthly.nextMonth' => '下一月',
			'reports.monthly.qualified' => ({required Object days}) => '断食达标 ${days} 天',
			'reports.monthly.recordedDays' => ({required Object days}) => '记录 ${days} 天',
			'reports.monthly.avgFastingHours' => ({required Object hours}) => '平均断食 ${hours} 小时',
			'reports.monthly.avgFastingHoursMinutes' => ({required Object hours, required Object minutes}) => '平均断食 ${hours} 小时 ${minutes} 分钟',
			'reports.monthly.kcalAvg' => ({required Object kcal, required Object target}) => '月均热量 ${kcal} 千卡 · 目标 ${target} 千卡',
			'reports.monthly.macros' => ({required Object protein, required Object carbs, required Object fat}) => '蛋白质 ${protein}g · 碳水 ${carbs}g · 脂肪 ${fat}g',
			'reports.monthly.weightChange' => ({required Object value}) => '体重变化 ${value}',
			'reports.monthly.empty' => '本月暂无记录',
			'reports.monthly.emptyHint' => '记一笔饮食或完成一次断食，月报就会长出来～',
			'streak.home.streakDays' => ({required Object days}) => '连续 ${days} 天 🔥',
			'streak.home.startHint' => '完成今天断食，开启第 1 天',
			'streak.milestone.title' => ({required Object days}) => '连续 ${days} 天！这个节奏太稳了，继续保持 🎉',
			'streak.milestone.badgeLabel' => ({required Object days}) => '${days} 天连胜',
			'streak.milestone.share' => '分享',
			'streak.milestone.accept' => '收下啦',
			'streak.milestone.shareCard.sheetTitle' => '点亮成就 · 分享图卡',
			'streak.milestone.shareCard.daysUnit' => '天',
			'streak.milestone.shareCard.appName' => '明食 EatWise',
			'streak.milestone.shareCard.tagline' => '轻盈断食，自在生活',
			'streak.milestone.shareCard.saveToAlbum' => '保存到相册',
			'streak.milestone.shareCard.shareSystem' => '系统分享',
			'streak.milestone.shareCard.saveSuccess' => '已保存到相册',
			'streak.milestone.shareCard.saveFailed' => '保存失败，请检查相册权限后重试',
			'streak.milestone.shareCard.shareFailed' => '分享失败，请稍后重试',
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
			'settings.title' => '设置',
			'settings.language.title' => '语言',
			'settings.language.system' => '跟随系统',
			'settings.language.zhCN' => '简体中文',
			'settings.language.en' => 'English',
			'settings.group.account' => '账号',
			'settings.group.privacy' => '隐私',
			'settings.group.preferences' => '偏好',
			'settings.group.reminders' => '提醒',
			'settings.group.about' => '关于',
			'settings.account.account' => '账号',
			'settings.account.cancelDeletion' => '撤销删除',
			'settings.account.changePassword' => '修改密码',
			'settings.account.contributions' => '我的贡献',
			'settings.account.moderation' => '审批中心',
			'settings.account.deleteAccount' => '删除账号',
			'settings.account.deleteConfirmAction' => '确认删除',
			'settings.account.deleteConfirmBody' => '删除后，你的手机号、基础资料、全部饮食/断食记录等个人数据将被物理删除，且不可恢复。申请后进入 7 天冷静期：冷静期内登录即视为撤销删除，第 7 天执行删除。',
			'settings.account.deleteConfirmTitle' => '删除账号？',
			'settings.account.deleteRequested' => '删除申请已提交，账号进入 7 天冷静期',
			'settings.account.deleteScheduledBody' => ({required Object date}) => '删除申请已提交。账号将于 ${date} 删除，此日期前重新登录即可撤销。',
			'settings.account.deletionCancelled' => '已撤销删除申请，账号恢复正常',
			'settings.account.deletionScheduled' => ({required Object days}) => '删除已预约，${days} 日后执行，到期前可撤销',
			'settings.account.logout' => '登出',
			'settings.account.notLoggedIn' => '未登录',
			'settings.privacy.privacyPolicy' => '隐私政策',
			'settings.privacy.userAgreement' => '用户协议',
			'settings.privacy.exportData' => '导出我的数据',
			'settings.privacy.exportSuccess' => ({required Object path}) => '数据已导出：${path}',
			'settings.privacy.healthData' => '健康数据授权',
			'settings.privacy.healthDataSubtitle' => '身高体重、饮食/断食记录等敏感个人信息处理',
			'settings.privacy.healthDataRevoked' => '已撤回健康数据授权，营养目标将使用默认值',
			'settings.privacy.analytics' => '数据分析授权',
			'settings.privacy.analyticsSubtitle' => '匿名行为统计，帮助我们改进产品，不含健康数据',
			'settings.privacy.exportFailed' => '导出失败，请检查网络后重试',
			'settings.health.group' => '运动数据',
			'settings.health.sync' => '同步运动数据',
			'settings.health.syncSubtitle' => '读取系统健康数据（Apple 健康 / Health Connect），展示今日活动消耗',
			'settings.health.consentTitle' => '开启运动数据同步？',
			'settings.health.consentBody' => '将读取本机系统健康数据中的步数、活动能量与体重，仅用于在 App 内展示今日热量消耗与结余。\n\n数据只在本机处理和展示，不会上传到服务器。你可以随时在这里关闭，关闭后将撤销系统授权并清除已读取的数据。',
			'settings.health.consentAgree' => '同意并开启',
			'settings.health.consentDecline' => '暂不同意',
			'settings.health.statusConnecting' => '读取中…',
			'settings.health.statusReady' => '已授权',
			'settings.health.statusDenied' => '未授权，可在系统健康设置中开启后重试',
			'settings.health.statusUnsupported' => '当前设备不支持系统健康数据（未检测到 Health Connect / 健康服务）',
			'settings.health.statusError' => '读取失败，请稍后重试',
			'settings.health.revoked' => '已关闭运动数据同步，系统授权已撤销',
			'settings.health.steps' => ({required Object steps}) => '步数 ${steps}',
			'settings.health.activeEnergy' => ({required Object kcal}) => '活动消耗 ${kcal} kcal',
			'settings.health.latestWeight' => ({required Object kg}) => '最新体重 ${kg} kg',
			'settings.health.fillWeight' => '填入今日体重记录',
			'settings.health.weightFilled' => ({required Object kg}) => '已填入今日体重记录 ${kg} kg',
			'settings.health.noData' => '今日暂无运动数据',
			'settings.health.burnGoal' => '每日消耗目标',
			'settings.health.burnGoalValue' => ({required Object kcal}) => '${kcal} 千卡',
			'settings.health.stepsGoal' => '每日步数目标',
			'settings.health.stepsGoalValue' => ({required Object steps}) => '${steps} 步',
			'settings.health.burnGoalDialogTitle' => '设置每日消耗目标',
			'settings.health.stepsGoalDialogTitle' => '设置每日步数目标',
			'settings.health.burnGoalInputLabel' => '目标（千卡，50–5000）',
			'settings.health.stepsGoalInputLabel' => '目标（步，500–100000）',
			'settings.health.goalInvalid' => '请输入范围内的有效数值',
			'settings.theme.title' => '主题',
			'settings.theme.system' => '跟随系统',
			'settings.theme.light' => '浅色',
			'settings.theme.dark' => '深色',
			'settings.fastingPlan.title' => '断食方案',
			'settings.fastingPlan.subtitle' => '查看或更换断食方案，新方案次日 0:00 生效',
			'settings.bodyProfile.title' => '身体档案',
			'settings.bodyProfile.subtitle' => '身高体重等，用于计算精准营养目标',
			'settings.bodyProfile.goalSection' => '减重目标（选填，仅减脂目标生效）',
			'settings.bodyProfile.save' => '保存',
			'settings.bodyProfile.saved' => '身体档案已保存',
			'settings.bodyProfile.goalUpdated' => ({required Object kcal}) => '每日营养目标已更新为 ${kcal} kcal',
			'settings.bodyProfile.completeness' => ({required Object percent}) => '档案完善度 ${percent}%',
			'settings.bodyProfile.bmi.title' => 'BMI',
			'settings.bodyProfile.bmi.underweight' => '偏低',
			'settings.bodyProfile.bmi.normal' => '标准',
			'settings.bodyProfile.bmi.overweight' => '偏高',
			'settings.bodyProfile.bmi.obese' => '肥胖',
			'settings.bodyProfile.bmi.missing' => '补全身高体重后展示 BMI',
			'settings.bodyProfile.bmi.unitHint' => '体重单位是公斤，如果你是按斤填的，请改一下体重',
			'settings.reminders.notifications' => '通知设置',
			'settings.reminders.notificationsSubtitle' => '前往系统设置管理通知权限',
			'settings.reminders.waterHourly' => '喝水提醒',
			'settings.reminders.waterHourlySubtitle' => '进食窗口内每小时提醒，按剩余目标量建议饮水量',
			'settings.about.version' => '版本',
			'settings.about.disclaimer' => '免责声明与特殊人群提示',
			'settings.about.checkUpdate' => '检查更新',
			'settings.aiModel.title' => 'AI 模型',
			'settings.aiModel.provider' => '服务商',
			'settings.aiModel.providers.custom' => '自定义',
			'settings.aiModel.providers.deepseek' => 'DeepSeek',
			'settings.aiModel.providers.qwen' => '通义千问（Qwen）',
			'settings.aiModel.providers.kimi' => 'Kimi',
			'settings.aiModel.baseUrl' => 'Base URL',
			'settings.aiModel.model' => '模型',
			'settings.aiModel.apiKey' => 'API Key',
			'settings.aiModel.apiKeyHint' => '留空保持不变',
			'settings.aiModel.baseUrlRequired' => '自定义服务商需填写 Base URL',
			'settings.aiModel.modelRequired' => '自定义服务商需填写模型名称',
			'settings.aiModel.save' => '保存',
			'settings.aiModel.saved' => 'AI 模型配置已保存',
			'settings.aiModel.test' => '测试连接',
			'settings.aiModel.testing' => '测试中…',
			'settings.aiModel.testOk' => '连接成功，模型服务可用',
			'settings.aiModel.testFail' => ({required Object reason}) => '连接失败：${reason}',
			'settings.aiModel.testFailNetwork' => '连接失败：无法连接服务器，请检查 Base URL 与网络',
			'settings.aiModel.testFailTimeout' => '连接失败：连接超时，请检查网络后重试',
			'settings.aiModel.testFailAuth' => '连接失败：API Key 无效或无权限，请检查后重试',
			'settings.aiModel.clear' => '清除配置',
			'settings.aiModel.clearConfirmTitle' => '清除 AI 模型配置？',
			'settings.aiModel.clearConfirmBody' => '清除后，自定义食物估算将不可用（可开启端侧小模型或重新配置）。',
			'settings.aiModel.clearConfirmAction' => '确认清除',
			'settings.aiModel.cleared' => 'AI 模型配置已清除',
			'settings.onDevice.title' => '端侧小模型',
			'settings.onDevice.desc' => '下载后可在本机离线估算食物营养，数据不出设备',
			'settings.onDevice.size' => '模型大小约 2.41GB',
			'settings.onDevice.wifiHint' => '文件较大，建议在 Wi-Fi 环境下下载',
			'settings.onDevice.download' => '下载模型',
			'settings.onDevice.downloading' => ({required Object percent}) => '下载中 ${percent}%',
			'settings.onDevice.cancel' => '取消',
			'settings.onDevice.paused' => ({required Object percent}) => '已暂停（已下载 ${percent}%）',
			'settings.onDevice.resume' => '继续下载',
			'settings.onDevice.delete' => '删除模型',
			'settings.onDevice.deleteConfirmTitle' => '删除端侧模型？',
			'settings.onDevice.deleteConfirmBody' => '删除后如需端侧估算，需重新下载约 2.41GB 模型文件。',
			'settings.onDevice.deleteConfirmAction' => '确认删除',
			'settings.onDevice.deleted' => '端侧模型已删除',
			'settings.onDevice.ready' => '模型已就绪',
			'settings.onDevice.coldLoadHint' => '首次估算需加载模型，可能等待数秒',
			'settings.onDevice.enabled' => '优先使用端侧估算',
			'settings.onDevice.errorDownload' => '下载失败，请检查网络后重试',
			'settings.onDevice.errorStorage' => '可用存储不足（约需 6GB），请清理后重试',
			'settings.onDevice.errorMemory' => '设备内存不足，无法使用端侧模型',
			'settings.onDevice.retry' => '重试',
			'settings.onDevice.oomDisabled' => '设备内存不足，端侧估算已停用',
			'settings.onDevice.statusFailed' => '模型状态读取失败',
			'settings.onDevice.errorResumeHint' => ({required Object percent}) => '已下载 ${percent}%，重试将从断点继续',
			'settings.chain.title' => '估算生效链路',
			'settings.chain.onDevice' => '端侧小模型',
			'settings.chain.userApi' => '自定义 API',
			'settings.chain.statusEnabled' => '已启用',
			'settings.chain.statusDisabled' => '未启用',
			'settings.chain.statusNotDownloaded' => '未下载',
			'settings.chain.statusDownloading' => '下载中',
			'settings.chain.statusPaused' => '已暂停',
			'settings.chain.statusError' => '下载失败',
			'settings.chain.statusUnknown' => '未就绪',
			'settings.chain.statusConfigured' => '已配置',
			'settings.chain.statusNotConfigured' => '未配置',
			'settings.chain.current' => '当前生效',
			'legal.draftNote' => '〔待外部确认：法务终稿〕',
			'legal.consent.title' => '欢迎使用 EatWise',
			'legal.consent.summary' => '我们会按照《隐私政策》收集和使用你的信息，用于提供断食计时、饮食记录与营养反馈等核心功能；数据存储于中国境内并加密保护。请阅读并确认以下授权：',
			'legal.consent.agreeMain' => '我已阅读并同意《用户协议》与《隐私政策》',
			'legal.consent.healthTitle' => '健康数据单独同意（可选）',
			'legal.consent.healthBody' => '你的身高、体重、年龄、性别及饮食、断食记录属于敏感个人信息。单独同意后，我们将其用于计算个性化营养目标与反馈，境内加密存储。你可以拒绝（营养目标将使用默认值），或随时在「设置-隐私」中撤回。',
			'legal.consent.disclaimerSummary' => '免责提示：本应用内容仅为健康生活方式的一般性参考，不构成医疗建议、诊断或治疗。',
			'legal.consent.specialGroupsEntry' => '查看不适宜断食人群提示',
			'legal.consent.viewPrivacyPolicy' => '查看《隐私政策》全文',
			'legal.consent.viewUserAgreement' => '查看《用户协议》全文',
			'legal.consent.agreeAndContinue' => '同意并继续',
			'legal.consent.decline' => '不同意并退出',
			'legal.disclaimer.title' => '免责声明',
			'legal.disclaimer.notMedicalTitle' => '非医疗建议声明',
			'legal.disclaimer.notMedicalBody' => '明食 EatWise 提供的内容（包括断食方案、营养目标、信号灯反馈与建议）仅为健康生活方式的一般性信息参考，不构成医疗建议、诊断或治疗，不能替代医生、注册营养师等专业人士的意见。您的营养目标由通用公式估算，可能与您的个体情况存在差异。如有任何健康问题、正在服药或患有疾病，请在使用断食或调整饮食前咨询专业医疗人员。因使用本应用信息而产生的任何后果，本应用不承担医疗责任。',
			'legal.disclaimer.specialGroupsTitle' => '特殊人群提示',
			'legal.disclaimer.specialGroupsBody' => '⚠️ 以下人群不建议进行间歇性断食，或须在医生指导下进行：孕期及哺乳期女性；未成年人（18 岁以下）；有进食障碍（如厌食症、暴食症）病史或高风险人群；糖尿病患者（尤其使用胰岛素或降糖药者）；低血糖、低血压患者；体重过低（BMI < 18.5）者；痛风、肾病、肝病等慢性疾病患者；近期手术或处于疾病恢复期者；老年体弱者。如果您属于以上任何一类，请不要开始断食方案，并咨询医生。',
			'legal.disclaimer.short' => '本应用内容不构成医疗建议',
			'legal.privacyPolicy.title' => '隐私政策',
			'legal.privacyPolicy.body' => '生效日期：2026-07-27｜版本 1.0.0〔待外部确认：法务终稿〕\n\n明食 · EatWise（下称「我们」）仅面向中国大陆地区提供服务。本政策说明我们如何收集、使用、存储和保护你的个人信息，以及你享有的权利。\n\n一、我们收集的信息\n1. 手机号：用于注册、登录与账号找回，境内加密存储。\n2. 身高、体重、年龄、性别：用于计算每日营养目标，属敏感个人信息，需你单独同意。\n3. 饮食记录与断食记录：核心功能所需，属敏感个人信息。\n4. 目标、作息、断食经验（问卷 3 题）：用于方案推荐。\n5. 昵称、头像：可选，用于个性化与社区展示。\n6. 设备信息与推送 token：用于推送送达与崩溃分析；不收集 IMEI/IMSI/MAC。\n7. 崩溃与性能日志：脱敏处理，留存 6 个月。\n8. 埋点行为数据：仅事件级行为统计，可在「设置-隐私」中关闭。\n我们不收集：位置信息、通讯录、蓝牙及 HealthKit/Health Connect 健康平台数据。\n\n二、敏感个人信息单独同意\n健康相关数据（身高体重、饮食/断食记录等）依据《个人信息保护法》第 29 条取得你的单独同意；拒绝不影响账号功能，营养目标将使用默认值；你可随时在「设置-隐私」中撤回。\n\n三、存储与安全\n全部数据存储于中国境内服务器；传输使用 TLS 1.2+ 加密；手机号与健康数据采用字段级加密存储；本地数据库全库加密。无任何数据出境。\n\n四、第三方 SDK\n我们使用微信登录、Sign in with Apple、聚合推送、内容安全、崩溃监控等境内 SDK；任何 SDK 均不接收你的健康数据原文。\n\n五、你的权利\n1. 查阅复制：「设置-隐私-导出我的数据」申请导出全量个人数据（JSON+CSV）。\n2. 删除：「设置-账号-删除账号」，申请后进入 7 天冷静期，冷静期内登录即撤销。\n3. 撤回同意：「设置-隐私」中可随时撤回健康数据授权与数据分析授权。\n\n六、未成年人\n本产品不面向 14 岁以下儿童。\n\n七、政策更新\n本政策发生重大变更时，我们将重新征得你的同意。\n\n八、联系我们\n如对本政策有任何疑问，可通过 App 内「设置-关于」与我们联系。',
			'legal.userAgreement.title' => '用户协议',
			'legal.userAgreement.body' => '生效日期：2026-07-27｜版本 1.0.0〔待外部确认：法务终稿〕\n\n欢迎使用明食 · EatWise（下称「本应用」）。使用本应用前，请仔细阅读本协议。\n\n一、服务内容\n本应用提供间歇性断食计时、饮食记录、营养目标估算与信号灯反馈、趋势报告及社区打卡等健康生活方式工具服务。\n\n二、账号\n你可通过手机号验证码、微信或 Sign in with Apple 注册登录。你应妥善保管账号，并对账号下的行为负责。\n\n三、非医疗建议\n本应用提供的全部内容仅为一般性健康生活方式参考，不构成医疗建议、诊断或治疗，详见《免责声明》。\n\n四、用户行为规范\n你承诺发布的内容不违反法律法规、不侵犯他人权益；违规内容将被下架并可能限制账号功能。\n\n五、知识产权\n本应用的内容与程序知识产权归我们所有，你仅获得个人非商业性使用许可。\n\n六、责任限制\n因使用本应用信息产生的健康后果，我们不承担医疗责任；因不可抗力或第三方原因造成的服务中断，我们不承担责任。\n\n七、协议变更与终止\n本协议变更将以页面提示等方式通知；你可随时通过删除账号终止使用。\n\n八、适用法律\n本协议适用中华人民共和国法律。',
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
			'social.feed.delete' => '删除',
			'social.feed.deleteConfirm' => '确定删除这条打卡吗？删除后无法恢复。',
			'social.feed.deleted' => '已删除',
			'social.feed.deleteFailed' => '删除失败，请稍后重试',
			'social.feed.anonymousPoster' => '匿名伙伴',
			'social.compose.title' => '发布打卡',
			'social.compose.hint' => '记录这一刻的坚持…',
			'social.compose.charCount' => ({required Object n}) => '${n}/500',
			'social.compose.addPhoto' => '添加图片',
			'social.compose.removePhoto' => '移除图片',
			'social.compose.photoUploading' => '图片上传中…',
			'social.compose.photoUploadFailed' => '图片上传失败',
			'social.compose.photoUploadFailedBody' => '图片上传失败：可以不带图发布，或取消后重新上传。',
			'social.compose.publishWithoutPhoto' => '不带图发布',
			'social.compose.retryUpload' => '重新上传',
			'social.compose.streakBadge' => ({required Object days}) => '当前连续 ${days} 天 🔥',
			'social.compose.noStreak' => '完成今天的断食，打卡就会带上连胜徽章哦',
			'social.compose.publish' => '发布',
			'social.compose.publishFailed' => '发布失败，请稍后重试',
			'social.compose.emptyText' => '先写点什么吧',
			'social.compose.polish' => 'AI 润色',
			'social.compose.polishLoadingModel' => '正在加载端侧模型…',
			'social.compose.polishInferring' => 'AI 润色中…',
			'social.compose.polishFailed' => '润色失败，请稍后重试',
			'social.compose.polishDone' => '已为你润色',
			'social.compose.polishUndo' => '撤销润色',
			'social.compose.anonymous' => '匿名发布',
			'social.compose.pickAvatar' => '选择头像',
			'auth.login.title' => '登录',
			'auth.login.subtitle' => '使用账号密码登录',
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
			'auth.login.usernameLabel' => '用户名',
			'auth.login.usernameHint' => '3-20 位字母、数字或下划线',
			'auth.login.passwordLabel' => '密码',
			'auth.login.passwordHint' => '请输入密码',
			'auth.login.invalidUsername' => '用户名需为 3-20 位字母、数字或下划线',
			'auth.login.invalidPassword' => '密码需为 8-64 位',
			'auth.login.noAccount' => '没有账号？',
			'auth.login.toRegister' => '注册',
			'auth.login.otherLoginMethods' => '其他登录方式',
			'auth.logout' => '退出登录',
			'auth.logoutConfirm' => '确定退出登录吗？未同步的记录会保留在本机。',
			'auth.loggedOut' => '已退出登录',
			'auth.register.title' => '注册',
			'auth.register.subtitle' => '创建账号后即可开始使用',
			'auth.register.usernameLabel' => '用户名',
			'auth.register.usernameHint' => '3-20 位字母、数字或下划线',
			'auth.register.passwordLabel' => '密码',
			'auth.register.passwordHint' => '8-64 位，需包含字母和数字',
			'auth.register.confirmPasswordLabel' => '确认密码',
			'auth.register.confirmPasswordHint' => '再次输入密码',
			'auth.register.register' => '注册',
			'auth.register.registering' => '注册中…',
			'auth.register.passwordMismatch' => '两次输入的密码不一致',
			'auth.register.agreePrefix' => '我已阅读并同意',
			'auth.register.agreeAnd' => '和',
			'auth.register.agreeRequired' => '请先阅读并同意隐私政策与用户协议',
			'auth.register.strengthWeak' => '密码强度：弱',
			'auth.register.strengthMedium' => '密码强度：中',
			'auth.register.strengthStrong' => '密码强度：强',
			'auth.register.strengthTooShort' => '密码长度至少 8 位',
			'auth.register.invalidUsername' => '用户名需为 3-20 位字母、数字或下划线',
			'auth.changePassword.title' => '修改密码',
			'auth.changePassword.oldLabel' => '当前密码',
			'auth.changePassword.oldHint' => '请输入当前密码',
			'auth.changePassword.oldRequired' => '请输入当前密码',
			'auth.changePassword.newLabel' => '新密码',
			'auth.changePassword.newHint' => '8-64 位，需包含字母和数字',
			'auth.changePassword.confirmLabel' => '确认新密码',
			'auth.changePassword.confirmHint' => '再次输入新密码',
			'auth.changePassword.submit' => '确认修改',
			'auth.changePassword.submitting' => '提交中…',
			'auth.changePassword.success' => '密码已修改，请重新登录',
			'auth.changePassword.passwordMismatch' => '两次输入的新密码不一致',
			'auth.error.usernameTaken' => '用户名已被使用',
			'auth.error.invalidCredentials' => '用户名或密码错误',
			'auth.error.passwordTooWeak' => '密码需 8-64 位且包含字母和数字',
			'update.title' => '发现新版本',
			'update.newVersion' => ({required Object version}) => '最新版本：${version}',
			'update.updateNow' => '立即更新',
			'update.later' => '以后再说',
			'update.upToDate' => '当前已是最新版本',
			'update.checkFailed' => '检查更新失败，请稍后重试',
			'update.downloading' => ({required Object percent}) => '下载中 ${percent}%',
			'update.downloadingNoProgress' => '下载中…',
			'update.downloadFailed' => '下载失败，请检查网络后重试',
			'update.retry' => '重试',
			'moderation.title' => '审批中心',
			'moderation.subtitle' => '审核用户贡献的食品',
			'moderation.empty' => '暂无待审批的食品候选',
			'moderation.approve' => '通过',
			'moderation.reject' => '驳回',
			'moderation.approveConfirm' => '通过后该食品将进入共享食物库，所有用户都能搜到。确认通过？',
			'moderation.rejectConfirmTitle' => '驳回该候选',
			'moderation.rejectConfirmBody' => '驳回后提交者的相关记录将被移除。',
			'moderation.reasonHint' => '驳回原因（可选）',
			'moderation.approved' => '已通过',
			'moderation.rejected' => '已驳回',
			'moderation.kindCustom' => '自定义食品',
			'moderation.kindBarcode' => '条码商品',
			'moderation.kindCorrection' => '数据纠错',
			'moderation.barcodeLabel' => ({required Object code}) => '条码：${code}',
			'moderation.submittedAt' => ({required Object date}) => '提交于 ${date}',
			'moderation.suggestionTitle' => '建议值',
			'moderation.currentTitle' => '当前值',
			'moderation.per100gSummary' => ({required Object kcal, required Object protein, required Object carb, required Object fat}) => '每100克：${kcal} 千卡 · 蛋白 ${protein}g · 碳水 ${carb}g · 脂肪 ${fat}g',
			'moderation.loadFailed' => '加载失败，下拉重试',
			_ => null,
		};
	}
}
