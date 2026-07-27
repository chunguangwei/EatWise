import 'package:eatwise/features/fasting/domain/nutrition_rule_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 《规格-营养规则》§5.2 单测清单 U25（配置版本回退，§5.3）。
///
/// U26（Dart/Node 黄金用例一致）依赖服务端 Node 实现，属后端交付范围，
/// 本 Spike 不覆盖；黄金 fixtures 即 U1–U22 的输入输出。
void main() {
  Map<String, dynamic> validJson(String version) => <String, dynamic>{
    'version': version,
    'tdee': <String, dynamic>{
      'activityFactors': <String, dynamic>{
        'sedentary': 1.2,
        'light': 1.375,
        'moderate': 1.55,
        'high': 1.725,
      },
      'loseDeficit': 0.8,
      'minKcal': <String, dynamic>{'female': 1200, 'male': 1500},
      'roundingStepKcal': 10,
    },
    'macroRatio': <String, dynamic>{'protein': 0.25, 'carb': 0.45, 'fat': 0.30},
    'fallback': <String, dynamic>{
      'femaleKcal': 1800,
      'maleKcal': 2200,
      'unknownKcal': 2000,
    },
    'thresholds': <String, dynamic>{
      'kcal': <String, dynamic>{
        'greenLow': 85,
        'greenHigh': 110,
        'yellowLow': 60,
        'yellowHigh': 130,
        'redHigh': 130,
        'redLowOver': null,
      },
      'protein': <String, dynamic>{
        'greenLow': 90,
        'greenHigh': 150,
        'yellowLow': 70,
        'yellowHigh': null,
        'redHigh': 150,
        'redLowOver': 150,
      },
      'carb': <String, dynamic>{
        'greenLow': 85,
        'greenHigh': 115,
        'yellowLow': 65,
        'yellowHigh': 135,
        'redHigh': 135,
        'redLowOver': null,
      },
      'fat': <String, dynamic>{
        'greenLow': 80,
        'greenHigh': 110,
        'yellowLow': 55,
        'yellowHigh': 130,
        'redHigh': 130,
        'redLowOver': null,
      },
    },
    'adviceTemplateVersion': '1.0.0',
  };

  test('U25 本地缓存版本新于服务端时用本地', () {
    final config = resolveConfig(
      cachedJson: validJson('1.2.0'),
      remoteJson: validJson('1.1.0'),
    );
    expect(config.version, '1.2.0');
  });

  test('U25 服务端版本更新时用服务端', () {
    final config = resolveConfig(
      cachedJson: validJson('1.1.0'),
      remoteJson: validJson('1.3.0'),
    );
    expect(config.version, '1.3.0');
  });

  test('U25 schema 校验失败时用内置默认配置（降级可用）', () {
    final config = resolveConfig(
      cachedJson: <String, dynamic>{'version': 'broken'},
      remoteJson: <String, dynamic>{'garbage': true},
    );
    expect(config.version, NutritionRuleConfig.defaults.version);
    expect(config.thresholds.length, 4);
  });

  test('U25 单边损坏时用另一边；全空用内置默认', () {
    expect(
      resolveConfig(cachedJson: validJson('1.1.0'), remoteJson: null).version,
      '1.1.0',
    );
    expect(
      resolveConfig(
        cachedJson: <String, dynamic>{'bad': 1},
        remoteJson: validJson('1.4.0'),
      ).version,
      '1.4.0',
    );
    expect(resolveConfig().version, NutritionRuleConfig.defaults.version);
  });
}
