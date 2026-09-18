/// 体重输入单位（真机走查防呆：国内用户常按「斤」填体重）。
///
/// 内部存储/计算一律 kg（§1.1 取值域 25–300 kg）；「斤」仅是输入与
/// 表单展示的换算层（1 斤 = 0.5 kg），保存前除以 2 转回 kg。
library;

/// 体重输入单位（默认公斤）。
enum WeightUnit { kg, jin }

/// 斤 → kg。
double jinToKg(double jin) => jin / 2;

/// kg → 斤。
double kgToJin(double kg) => kg * 2;

/// 按存储值（kg）格式化某单位下的展示文本：整数不带小数，否则 1 位小数。
String formatWeightForUnit(double kg, WeightUnit unit) {
  final value = unit == WeightUnit.jin ? kgToJin(kg) : kg;
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}

/// 持久化值解析（'kg'/'jin'，非法/缺失回落 null 由调用方给默认）。
WeightUnit? weightUnitFromName(String? name) {
  return switch (name) {
    'kg' => WeightUnit.kg,
    'jin' => WeightUnit.jin,
    _ => null,
  };
}
