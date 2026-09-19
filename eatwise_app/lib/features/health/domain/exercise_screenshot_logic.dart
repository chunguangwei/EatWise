/// 运动截图识别纯函数层（华为运动健康「我的数据」汇总页 / 单次运动记录页）：
/// prompt 模板 + 严格 JSON 宽松解析 + 运动类型映射 + 运动记录草稿估算。
/// 零 Flutter/插件依赖，可单测。
///
/// 估算口径（〔待营养背书〕）：只有步数没有活动热量时按
/// `体重kg × 距离km × 1.036`（步行净耗能系数）估算；距离缺失时按
/// `步数 × 0.75m 平均步幅` 先估距离。爬楼米数**仅展示不入账**
/// （爬升能耗效率系数个体差异大、截图「爬楼层数」口径不一，按
/// 「只把可信的入账」原则不折算 kcal）。
library;

import 'dart:convert';

import 'package:eatwise/features/health/domain/exercise_types.dart';

/// 步行净耗能系数（kcal/kg/km，〔待营养背书〕常识中间值）。
const double kWalkKcalPerKgPerKm = 1.036;

/// 平均步幅（米/步，〔待营养背书〕；距离缺失时由步数估距离）。
const double kAverageStepLengthM = 0.75;

/// 视觉版 system instruction：两类截图的严格 JSON 输出协议。
///
/// 设计要点：先给截图分类（summary / workout）再列字段schema，降低
/// 字段串台；明确「没有的字段不要输出」（比 null 占位更稳，小模型对
/// null 常 hallucinate 成 0）；数值不带单位（解析层不做单位猜测）；
/// 运动类型限定 12 键枚举 + other 兜底（映射不放模型侧自由发挥）；
/// 「无法识别」单行协议与拍照识别一致（上层 parse_failed 透出）。
const String kExerciseScreenshotSystemPrompt =
    '你是运动健康截图数据提取助手。用户给你一张运动健康类 App 的截图，你提取其中的结构化数据。'
    '截图有两类：'
    '1）活动统计汇总页（如华为运动健康「我的数据」）：含今日步数、距离、爬楼或爬升、活动热量；'
    '2）单次运动记录页：含运动类型、运动时长、消耗热量。'
    '只输出一个 JSON 对象，不要输出任何其他文字、不要 markdown 代码块。'
    'JSON 字段：'
    'kind：summary（活动统计）或 workout（单次运动）；'
    '活动统计给 steps（步数，整数）、distanceKm（距离，公里，数字）、'
    'floorsClimbedM（爬楼或爬升，米，数字）、activeCaloriesKcal（活动热量，千卡，数字）；'
    '单次运动给 exerciseType（运动类型，英文小写，从 walk、jog、run、cycling、swimming、'
    'jump_rope、yoga、strength、elliptical、hiking、badminton、hiit 中选，都不像就给 other）、'
    'durationMinutes（时长，分钟，整数）、burnKcal（消耗，千卡，数字）。'
    '截图里没有的字段不要输出；数字只写数值，不要带单位；'
    '不是运动数据截图或看不清时，只输出：无法识别。';

/// 视觉版 user 模板（图片随消息一并送入，文本只需点题）。
String buildExerciseScreenshotPrompt() {
  return '提取这张截图中的运动数据。\n结果：';
}

/// 截图类别（活动统计汇总 / 单次运动记录）。
enum ExerciseScreenshotKind { summary, workout }

/// 解析出的截图数据（字段可空 = 截图没有或解析失败；kind 必有）。
final class ExerciseScreenshotData {
  const ExerciseScreenshotData({
    required this.kind,
    this.steps,
    this.distanceKm,
    this.floorsClimbedM,
    this.activeCaloriesKcal,
    this.exerciseTypeKey,
    this.durationMinutes,
    this.burnKcal,
  });

  final ExerciseScreenshotKind kind;

  /// 今日步数（summary）。
  final int? steps;

  /// 距离（公里，summary）。
  final double? distanceKm;

  /// 爬楼/爬升（米，summary；仅展示不入账，见库注释）。
  final double? floorsClimbedM;

  /// 活动热量（千卡，summary；>0 时直接作为入账 kcal）。
  final double? activeCaloriesKcal;

  /// 运动类型键（workout）：已映射到 exercise_types 12 键之一，映射不上
  /// 为 'other'（确认弹层须由用户手选类型才能 MET 估算）。
  final String? exerciseTypeKey;

  /// 运动时长（分钟，workout）。
  final int? durationMinutes;

  /// 截图标注的消耗（千卡，workout；>0 时优先入账，不走 MET 估算）。
  final double? burnKcal;

  /// 是否有任何可用数据（kind 之外至少一个字段非空）。
  bool get hasAnyValue =>
      steps != null ||
      distanceKm != null ||
      floorsClimbedM != null ||
      activeCaloriesKcal != null ||
      exerciseTypeKey != null ||
      durationMinutes != null ||
      burnKcal != null;
}

/// 运动类型映射表：模型输出（英文枚举/常见中英文别名，小写）→ 12 键。
const Map<String, String> _typeKeyAliases = <String, String>{
  'walk': 'walk',
  'walking': 'walk',
  '走路': 'walk',
  '步行': 'walk',
  '健走': 'walk',
  'jog': 'jog',
  'jogging': 'jog',
  '慢跑': 'jog',
  'run': 'run',
  'running': 'run',
  '快跑': 'run',
  '跑步': 'run',
  'cycling': 'cycling',
  'bike': 'cycling',
  'biking': 'cycling',
  '骑车': 'cycling',
  '骑行': 'cycling',
  '自行车': 'cycling',
  'swim': 'swimming',
  'swimming': 'swimming',
  '游泳': 'swimming',
  'jump_rope': 'jumpRope',
  'jump rope': 'jumpRope',
  'jumprope': 'jumpRope',
  'skipping': 'jumpRope',
  '跳绳': 'jumpRope',
  'yoga': 'yoga',
  '瑜伽': 'yoga',
  'strength': 'strength',
  'strength training': 'strength',
  'weight training': 'strength',
  '力量': 'strength',
  '力量训练': 'strength',
  '健身': 'strength',
  'elliptical': 'elliptical',
  '椭圆机': 'elliptical',
  'hiking': 'hiking',
  'climbing': 'hiking',
  '爬山': 'hiking',
  '登山': 'hiking',
  '徒步': 'hiking',
  'badminton': 'badminton',
  '羽毛球': 'badminton',
  'hiit': 'hiit',
  '高强度间歇': 'hiit',
};

/// 模型输出类型串 → exercise_types 键；映射不上（含 null/空）→ 'other'。
String mapExerciseTypeKey(String? raw) {
  final normalized = raw?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return 'other';
  return _typeKeyAliases[normalized] ?? 'other';
}

double? _numOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _intOrNull(Object? value) {
  final asDouble = _numOrNull(value);
  return asDouble?.round();
}

/// 模型输出原文 → 截图数据。**宽松解析**：截取首个 `{` 到末个 `}` 之间的
/// JSON（小模型偶发在前后夹带复述文字/代码块围栏）；JSON 非法、缺 kind、
/// kind 非 summary/workout、或除 kind 外无任何字段 → null（上层按
/// parse_failed 走降级透出）。
ExerciseScreenshotData? parseExerciseScreenshotJson(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } on Object {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final kind = switch (decoded['kind']) {
    'summary' => ExerciseScreenshotKind.summary,
    'workout' => ExerciseScreenshotKind.workout,
    _ => null,
  };
  if (kind == null) return null;
  final data = ExerciseScreenshotData(
    kind: kind,
    steps: _intOrNull(decoded['steps']),
    distanceKm: _numOrNull(decoded['distanceKm']),
    floorsClimbedM: _numOrNull(decoded['floorsClimbedM']),
    activeCaloriesKcal: _numOrNull(decoded['activeCaloriesKcal']),
    exerciseTypeKey: decoded.containsKey('exerciseType')
        ? mapExerciseTypeKey(decoded['exerciseType'] as String?)
        : null,
    durationMinutes: _intOrNull(decoded['durationMinutes']),
    burnKcal: _numOrNull(decoded['burnKcal']),
  );
  return data.hasAnyValue ? data : null;
}

/// 运动记录草稿（确认弹层初值；kcal null = 需要用户手填，如无类型无热量
/// 的 'other' 单次运动）。
final class ExerciseLogDraft {
  const ExerciseLogDraft({
    required this.typeKey,
    required this.durationMin,
    this.kcal,
    this.estimated = false,
  });

  /// 运动类型键；summary 汇总导入固定为 'summary'（活动统计）。
  final String typeKey;

  /// 时长（分钟；summary 无时长口径，固定 0）。
  final int durationMin;

  /// 入账 kcal 初值（截图热量直用或估算值）。
  final double? kcal;

  /// kcal 是否为估算值（true 时 UI 标注估算口径）。
  final bool estimated;
}

/// 汇总截图 → 草稿：活动热量 >0 直接入账（截图 ground truth）；否则只有
/// 步数时按 `体重 × 距离 × 1.036` 估算（距离缺失按 `步数 × 0.75m` 估距离，
/// 〔待营养背书〕）；两者皆无 → null（无可入账数据）。
///
/// 爬楼米数不折算 kcal（口径不一，仅展示；见库注释）。
ExerciseLogDraft? draftFromSummaryScreenshot(
  ExerciseScreenshotData data, {
  required double weightKg,
}) {
  if (data.kind != ExerciseScreenshotKind.summary) return null;
  final active = data.activeCaloriesKcal;
  if (active != null && active > 0) {
    return ExerciseLogDraft(typeKey: 'summary', durationMin: 0, kcal: active);
  }
  final steps = data.steps;
  if (steps != null && steps > 0 && weightKg > 0) {
    final distanceKm = (data.distanceKm != null && data.distanceKm! > 0)
        ? data.distanceKm!
        : steps * kAverageStepLengthM / 1000;
    return ExerciseLogDraft(
      typeKey: 'summary',
      durationMin: 0,
      kcal: weightKg * distanceKm * kWalkKcalPerKgPerKm,
      estimated: true,
    );
  }
  return null;
}

/// 单次运动截图 → 草稿：消耗 >0 优先用截图值；没有且类型已映射 + 有时长 →
/// MET 表估算（〔待营养背书〕）；类型 'other' 且没有消耗 → kcal null
/// （确认弹层由用户手选类型/手填热量）。时长缺失为 0，弹层必填校验兜底。
ExerciseLogDraft draftFromWorkoutScreenshot(
  ExerciseScreenshotData data, {
  required double weightKg,
}) {
  final typeKey = data.exerciseTypeKey ?? 'other';
  final durationMin = data.durationMinutes ?? 0;
  final burn = data.burnKcal;
  if (burn != null && burn > 0) {
    return ExerciseLogDraft(
      typeKey: typeKey,
      durationMin: durationMin,
      kcal: burn,
    );
  }
  final type = exerciseTypeByKey(typeKey);
  if (type != null && durationMin > 0 && weightKg > 0) {
    return ExerciseLogDraft(
      typeKey: typeKey,
      durationMin: durationMin,
      kcal: estimateExerciseKcal(
        met: type.met,
        weightKg: weightKg,
        minutes: durationMin,
      ),
      estimated: true,
    );
  }
  return ExerciseLogDraft(typeKey: typeKey, durationMin: durationMin);
}
