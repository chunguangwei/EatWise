import 'package:eatwise/features/fasting/domain/nutrition_types.dart';

/// 营养规则热配置（《规格-营养规则》§5.3，D-04/D-05）。
///
/// 服务端下发 JSON 覆盖默认值；本地缓存兜底；schema 校验失败用内置默认
/// （U25）。`const` 默认值即 D-04/D-05 拍板值，营养侧背书后仅改配置升版本。

/// 单营养素阈值（§5.3 `zone` 定义，边界规则见 §3.1）。
final class ZoneThreshold {
  const ZoneThreshold({
    required this.greenLow,
    required this.greenHigh,
    required this.yellowLow,
    required this.yellowHigh,
    required this.redHigh,
    this.redLowOver,
  });

  /// 绿区下界（含）。
  final double greenLow;

  /// 绿区上界（含）。
  final double greenHigh;

  /// 黄-低下界（含），低于此即红-低。
  final double yellowLow;

  /// 黄-高上界（含），高于此即红-高；蛋白质无黄-高区，置 null。
  final double? yellowHigh;

  /// 红-高触发值（不含），如 130。
  final double redHigh;

  /// 过量标红触发值（不含），仅蛋白质用 150，其余为 null。
  final double? redLowOver;

  static ZoneThreshold fromJson(Map<String, dynamic> json) {
    return ZoneThreshold(
      greenLow: (json['greenLow'] as num).toDouble(),
      greenHigh: (json['greenHigh'] as num).toDouble(),
      yellowLow: (json['yellowLow'] as num).toDouble(),
      yellowHigh: (json['yellowHigh'] as num?)?.toDouble(),
      redHigh: (json['redHigh'] as num).toDouble(),
      redLowOver: (json['redLowOver'] as num?)?.toDouble(),
    );
  }
}

/// 规则配置全集。
final class NutritionRuleConfig {
  const NutritionRuleConfig({
    required this.version,
    required this.activityFactors,
    required this.loseDeficit,
    required this.minKcalFemale,
    required this.minKcalMale,
    required this.roundingStepKcal,
    required this.proteinRatio,
    required this.carbRatio,
    required this.fatRatio,
    required this.fallbackFemaleKcal,
    required this.fallbackMaleKcal,
    required this.fallbackUnknownKcal,
    required this.thresholds,
    required this.adviceTemplateVersion,
  });

  /// 内置默认配置（= D-04/D-05 拍板值，§5.3 `const` 列）。
  static const NutritionRuleConfig defaults = NutritionRuleConfig(
    version: '1.0.0',
    activityFactors: <ActivityLevel, double>{
      ActivityLevel.sedentary: 1.2,
      ActivityLevel.light: 1.375,
      ActivityLevel.moderate: 1.55,
      ActivityLevel.high: 1.725,
    },
    loseDeficit: 0.8,
    minKcalFemale: 1200,
    minKcalMale: 1500,
    roundingStepKcal: 10,
    proteinRatio: 0.25,
    carbRatio: 0.45,
    fatRatio: 0.30,
    fallbackFemaleKcal: 1800,
    fallbackMaleKcal: 2200,
    fallbackUnknownKcal: 2000,
    thresholds: <NutrientType, ZoneThreshold>{
      NutrientType.kcal: ZoneThreshold(
        greenLow: 85,
        greenHigh: 110,
        yellowLow: 60,
        yellowHigh: 130,
        redHigh: 130,
      ),
      NutrientType.protein: ZoneThreshold(
        greenLow: 90,
        greenHigh: 150,
        yellowLow: 70,
        yellowHigh: null, // 蛋白质无黄-高区
        redHigh: 150,
        redLowOver: 150, // 过量标红（D-05）
      ),
      NutrientType.carb: ZoneThreshold(
        greenLow: 85,
        greenHigh: 115,
        yellowLow: 65,
        yellowHigh: 135,
        redHigh: 135,
      ),
      NutrientType.fat: ZoneThreshold(
        greenLow: 80,
        greenHigh: 110,
        yellowLow: 55,
        yellowHigh: 130,
        redHigh: 130,
      ),
    },
    adviceTemplateVersion: '1.0.0',
  );

  /// 语义化版本号，如 1.0.0。
  final String version;

  /// 活动系数表（§1.3）。
  final Map<ActivityLevel, double> activityFactors;

  /// 减脂折算系数（0.8）。
  final double loseDeficit;

  /// 女下限保护（kcal）。
  final double minKcalFemale;

  /// 男下限保护（kcal）。
  final double minKcalMale;

  /// 目标热量取整步进（10 kcal）。
  final int roundingStepKcal;

  /// 蛋白供能占比（0.25）。
  final double proteinRatio;

  /// 碳水供能占比（0.45）。
  final double carbRatio;

  /// 脂肪供能占比（0.30）。
  final double fatRatio;

  /// 兜底目标：女（kcal）。
  final double fallbackFemaleKcal;

  /// 兜底目标：男（kcal）。
  final double fallbackMaleKcal;

  /// 兜底目标：性别缺失（kcal）。
  final double fallbackUnknownKcal;

  /// 四营养素阈值（§3.1）。
  final Map<NutrientType, ZoneThreshold> thresholds;

  /// 建议模板库版本（指向 i18n 文案包）。
  final String adviceTemplateVersion;

  /// 从服务端 JSON 解析；结构非法时抛 [FormatException]，
  /// 由 [resolveConfig] 降级为缓存/内置默认（U25）。
  static NutritionRuleConfig fromJson(Map<String, dynamic> json) {
    try {
      final tdee = json['tdee']! as Map<String, dynamic>;
      final factors = tdee['activityFactors']! as Map<String, dynamic>;
      final minKcal = tdee['minKcal']! as Map<String, dynamic>;
      final macro = json['macroRatio']! as Map<String, dynamic>;
      final fallback = json['fallback']! as Map<String, dynamic>;
      final thresholds = json['thresholds']! as Map<String, dynamic>;
      return NutritionRuleConfig(
        version: json['version']! as String,
        activityFactors: <ActivityLevel, double>{
          ActivityLevel.sedentary: (factors['sedentary']! as num).toDouble(),
          ActivityLevel.light: (factors['light']! as num).toDouble(),
          ActivityLevel.moderate: (factors['moderate']! as num).toDouble(),
          ActivityLevel.high: (factors['high']! as num).toDouble(),
        },
        loseDeficit: (tdee['loseDeficit']! as num).toDouble(),
        minKcalFemale: (minKcal['female']! as num).toDouble(),
        minKcalMale: (minKcal['male']! as num).toDouble(),
        roundingStepKcal: (tdee['roundingStepKcal']! as num).toInt(),
        proteinRatio: (macro['protein']! as num).toDouble(),
        carbRatio: (macro['carb']! as num).toDouble(),
        fatRatio: (macro['fat']! as num).toDouble(),
        fallbackFemaleKcal: (fallback['femaleKcal']! as num).toDouble(),
        fallbackMaleKcal: (fallback['maleKcal']! as num).toDouble(),
        fallbackUnknownKcal: (fallback['unknownKcal']! as num).toDouble(),
        thresholds: <NutrientType, ZoneThreshold>{
          for (final type in NutrientType.values)
            type: ZoneThreshold.fromJson(
              thresholds[type.name]! as Map<String, dynamic>,
            ),
        },
        adviceTemplateVersion: json['adviceTemplateVersion']! as String,
      );
    } on Object catch (e) {
      throw FormatException('NutritionRuleConfig schema 校验失败: $e');
    }
  }
}

/// 配置版本回退策略（U25）：
/// 本地缓存版本新于服务端时用本地；schema 校验失败时用内置默认配置。
NutritionRuleConfig resolveConfig({
  Map<String, dynamic>? cachedJson,
  Map<String, dynamic>? remoteJson,
}) {
  NutritionRuleConfig? cached;
  NutritionRuleConfig? remote;
  if (cachedJson != null) {
    try {
      cached = NutritionRuleConfig.fromJson(cachedJson);
    } on FormatException {
      cached = null; // 缓存损坏，按无缓存处理
    }
  }
  if (remoteJson != null) {
    try {
      remote = NutritionRuleConfig.fromJson(remoteJson);
    } on FormatException {
      remote = null; // 服务端下发非法，不采用
    }
  }
  if (cached == null && remote == null) return NutritionRuleConfig.defaults;
  if (cached == null) return remote!;
  if (remote == null) return cached;
  return _compareVersion(cached.version, remote.version) >= 0 ? cached : remote;
}

/// 语义化版本比较（major.minor.patch）。
int _compareVersion(String a, String b) {
  List<int> parse(String v) {
    final parts = v.split('.');
    return <int>[
      for (var i = 0; i < 3; i++)
        i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    ];
  }

  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}
