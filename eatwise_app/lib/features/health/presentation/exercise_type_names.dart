import 'package:eatwise/app/l10n/strings.g.dart';

/// 运动类型展示名（i18n key `record.exercise.types.<key>`；未知键原样回退，
/// 向前兼容后续新增类型）。'summary' 为截图活动统计导入的专用类型键。
String exerciseTypeName(Translations t, String key) {
  return switch (key) {
    'walk' => t.record.exercise.types.walk,
    'jog' => t.record.exercise.types.jog,
    'run' => t.record.exercise.types.run,
    'cycling' => t.record.exercise.types.cycling,
    'swimming' => t.record.exercise.types.swimming,
    'jumpRope' => t.record.exercise.types.jumpRope,
    'yoga' => t.record.exercise.types.yoga,
    'strength' => t.record.exercise.types.strength,
    'elliptical' => t.record.exercise.types.elliptical,
    'hiking' => t.record.exercise.types.hiking,
    'badminton' => t.record.exercise.types.badminton,
    'basketball' => t.record.exercise.types.basketball,
    'soccer' => t.record.exercise.types.soccer,
    'tableTennis' => t.record.exercise.types.tableTennis,
    'tennis' => t.record.exercise.types.tennis,
    'dance' => t.record.exercise.types.dance,
    'hiit' => t.record.exercise.types.hiit,
    'summary' => t.record.exercise.types.summary,
    _ => key,
  };
}
