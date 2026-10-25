/// 手动记运动领域层（无 GMS 设备手动兜底，鸿蒙等 Health Connect 不可用场景）。
///
/// 边界：运动记录为设备级数据，纯本地落库、不上行服务端；MET 系数与
/// 估算口径均为纯函数，UI 只做接线。
library;

/// 运动类型（key 即落库 typeKey 与 i18n key `record.exercise.types.<key>`）。
final class ExerciseType {
  const ExerciseType({required this.key, required this.met});

  /// 稳定键（见 [exerciseTypes] 表；i18n key 同名）。
  final String key;

  /// MET 代谢当量（常识中间值，〔待营养背书〕）。
  final double met;
}

/// 常见运动 MET 系数表（〔待营养背书〕：取各类运动常见强度区间中间值，
/// 数值改动须同步《规格-营养规则-TDEE公式与信号灯阈值》）。
///
/// 覆盖行业惯例高频项（对照薄荷/华为运动健康常见列表）：走路/跑步两档/
/// 骑车/游泳/跳绳/瑜伽/力量/椭圆机/爬山/羽毛球/HIIT + 篮球/足球/乒乓球/
/// 网球/健身操。
const List<ExerciseType> exerciseTypes = <ExerciseType>[
  ExerciseType(key: 'walk', met: 3.5), // 走路（中速）
  ExerciseType(key: 'jog', met: 7.0), // 慢跑
  ExerciseType(key: 'run', met: 9.8), // 快跑
  ExerciseType(key: 'cycling', met: 6.8), // 骑车（中等强度）
  ExerciseType(key: 'swimming', met: 7.0), // 游泳（中等强度）
  ExerciseType(key: 'jumpRope', met: 10.0), // 跳绳
  ExerciseType(key: 'yoga', met: 3.0), // 瑜伽
  ExerciseType(key: 'strength', met: 5.0), // 力量训练
  ExerciseType(key: 'elliptical', met: 5.0), // 椭圆机
  ExerciseType(key: 'hiking', met: 6.0), // 爬山
  ExerciseType(key: 'badminton', met: 5.5), // 羽毛球
  ExerciseType(key: 'basketball', met: 6.5), // 篮球（半场/一般）
  ExerciseType(key: 'soccer', met: 7.0), // 足球（一般）
  ExerciseType(key: 'tableTennis', met: 4.0), // 乒乓球
  ExerciseType(key: 'tennis', met: 7.0), // 网球（一般）
  ExerciseType(key: 'dance', met: 6.5), // 健身操/舞蹈（有氧）
  ExerciseType(key: 'hiit', met: 9.0), // HIIT
];

/// 按 key 查运动类型（未知键返回 null，落库数据向前兼容）。
ExerciseType? exerciseTypeByKey(String key) {
  for (final type in exerciseTypes) {
    if (type.key == key) return type;
  }
  return null;
}

/// 档案未填体重时的估算兜底体重（kg，中性值；UI 须标注「按 60kg 估算」）。
const double defaultExerciseWeightKg = 60;

/// 手动录入与截图确认共用的写入上限（与服务端 ExerciseLogPayloadDto 一致）。
const int maxExerciseDurationMin = 1440;
const double maxExerciseKcal = 10000;
const int maxExerciseSteps = 200000;

/// MET 估算消耗（kcal）：MET × 体重 kg × 时长小时（标准公式〔待营养背书〕）。
///
/// [weightKg] 传档案体重；缺省（档案未填）由调用方传 [defaultExerciseWeightKg]
/// 并在 UI 标注估算。非法输入（met ≤ 0、体重 ≤ 0、分钟 ≤ 0）返回 0。
double estimateExerciseKcal({
  required double met,
  required double weightKg,
  required int minutes,
}) {
  if (met <= 0 || weightKg <= 0 || minutes <= 0) return 0;
  return met * weightKg * (minutes / 60);
}

/// 步行净耗能系数（kcal/kg/km，〔待营养背书〕常识中间值；步数→热量
/// 估算用，截图汇总导入与手动「走路按步数录入」共用）。
const double kWalkKcalPerKgPerKm = 1.036;

/// 平均步幅（米/步，〔待营养背书〕；距离缺失时由步数估距离）。
const double kAverageStepLengthM = 0.75;

/// 步数 → 步行消耗估算（kcal）：`体重kg × 距离km × 1.036`，距离缺省按
/// `步数 × 0.75m 平均步幅` 折算（常量〔待营养背书〕）。
///
/// 非法输入（步数 ≤ 0、体重 ≤ 0）返回 0。
double estimateKcalFromStepsWalk({
  required int steps,
  required double weightKg,
  double? distanceKm,
}) {
  if (steps <= 0 || weightKg <= 0) return 0;
  final km = (distanceKm != null && distanceKm > 0)
      ? distanceKm
      : steps * kAverageStepLengthM / 1000;
  return weightKg * km * kWalkKcalPerKgPerKm;
}

/// 系统日汇总优先，缺失时使用手动汇总；无时间区间，不能把两者安全相加。
/// 系统明确返回 0 是有效读数；手动 0 无法区分无记录，保留空态。
double? mergeBurnKcal({double? systemKcal, double? manualKcal}) {
  if (systemKcal != null && systemKcal.isFinite && systemKcal >= 0) {
    return systemKcal;
  }
  return manualKcal != null && manualKcal.isFinite && manualKcal > 0
      ? manualKcal
      : null;
}

/// 与活动能量同样采用来源优先，避免同一段步行被系统和截图重复累计。
int? mergeSteps({int? systemSteps, int? manualSteps}) {
  if (systemSteps != null && systemSteps >= 0) return systemSteps;
  return manualSteps != null && manualSteps > 0 ? manualSteps : null;
}
