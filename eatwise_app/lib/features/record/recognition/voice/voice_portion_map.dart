/// 份量词 → 克数映射表（D-16 语音轻量解析的份量正则底座）。
///
/// 〔假设〕以下换算为常识近似值，供 MVP 预填份量、用户可在结果卡上
/// 修改；正式上线前需营养专业侧校准（与 D-04/D-05 背书一并确认）。
library;

/// 中文份量词 → 单份克数。
const Map<String, double> kPortionGramsZh = <String, double>{
  '碗': 200,
  '杯': 250,
  '个': 100,
  '只': 100,
  '颗': 100,
  '份': 200,
  '片': 30,
  '勺': 15,
  '拳头': 150,
};

/// 英文份量词 → 单份克数。
const Map<String, double> kPortionGramsEn = <String, double>{
  'bowl': 200,
  'cup': 250,
  'glass': 250,
  'piece': 100,
  'serving': 200,
  'portion': 200,
  'slice': 30,
  'spoon': 15,
  'tablespoon': 15,
  'fist': 150,
};

/// 中文数字词 → 数值（「两」作数量词 = 2，不作重量单位）。
const Map<String, double> kChineseNumerals = <String, double>{
  '半': 0.5,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
  '十': 10,
};

/// 英文数量词 → 数值。
const Map<String, double> kEnglishNumerals = <String, double>{
  'half': 0.5,
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
};
