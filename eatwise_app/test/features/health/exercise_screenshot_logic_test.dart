import 'package:eatwise/features/health/domain/exercise_screenshot_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 运动截图识别纯函数测试：严格 JSON 宽松解析 / 类型映射 / 草稿估算口径。
void main() {
  group('parseExerciseScreenshotJson', () {
    test('活动统计汇总页：四字段齐备', () {
      final data = parseExerciseScreenshotJson(
        '{"kind":"summary","steps":8245,"distanceKm":5.6,'
        '"floorsClimbedM":30,"activeCaloriesKcal":320}',
      )!;
      expect(data.kind, ExerciseScreenshotKind.summary);
      expect(data.steps, 8245);
      expect(data.distanceKm, 5.6);
      expect(data.floorsClimbedM, 30);
      expect(data.activeCaloriesKcal, 320);
    });

    test('单次运动记录页：类型映射 + 时长 + 消耗', () {
      final data = parseExerciseScreenshotJson(
        '{"kind":"workout","exerciseType":"running",'
        '"durationMinutes":32,"burnKcal":285}',
      )!;
      expect(data.kind, ExerciseScreenshotKind.workout);
      expect(data.exerciseTypeKey, 'run');
      expect(data.durationMinutes, 32);
      expect(data.burnKcal, 285);
    });

    test('宽松解析：JSON 前后夹带复述文字/代码块围栏也能提取', () {
      final data = parseExerciseScreenshotJson(
        '结果：```json\n{"kind":"summary","steps":5000}\n```',
      )!;
      expect(data.steps, 5000);
    });

    test('数字容忍字符串形态；缺字段不输出即为 null', () {
      final data = parseExerciseScreenshotJson(
        '{"kind":"summary","steps":"6200"}',
      )!;
      expect(data.steps, 6200);
      expect(data.distanceKm, isNull);
      expect(data.activeCaloriesKcal, isNull);
    });

    test('无法识别/坏 JSON/缺 kind/空对象 → null', () {
      expect(parseExerciseScreenshotJson('无法识别'), isNull);
      expect(parseExerciseScreenshotJson('{bad json}'), isNull);
      expect(parseExerciseScreenshotJson('{"steps":100}'), isNull);
      expect(
        parseExerciseScreenshotJson('{"kind":"unknown","steps":1}'),
        isNull,
      );
      expect(parseExerciseScreenshotJson('{"kind":"summary"}'), isNull);
    });
  });

  group('mapExerciseTypeKey', () {
    test('英文枚举与中文别名命中 17 键', () {
      expect(mapExerciseTypeKey('walk'), 'walk');
      expect(mapExerciseTypeKey('Jump Rope'), 'jumpRope');
      expect(mapExerciseTypeKey('骑行'), 'cycling');
      expect(mapExerciseTypeKey('羽毛球'), 'badminton');
      expect(mapExerciseTypeKey('登山'), 'hiking');
      expect(mapExerciseTypeKey('basketball'), 'basketball');
      expect(mapExerciseTypeKey('足球'), 'soccer');
      expect(mapExerciseTypeKey('乒乓球'), 'tableTennis');
      expect(mapExerciseTypeKey('tennis'), 'tennis');
      expect(mapExerciseTypeKey('健身操'), 'dance');
    });

    test('映射不上 / 空 → other', () {
      expect(mapExerciseTypeKey('boxing'), 'other');
      expect(mapExerciseTypeKey('拳击'), 'other');
      expect(mapExerciseTypeKey(null), 'other');
      expect(mapExerciseTypeKey(''), 'other');
    });
  });

  group('draftFromSummaryScreenshot（〔待营养背书〕估算口径）', () {
    test('活动热量 >0 → 直接用截图值（非估算），步数随草稿落库', () {
      final draft = draftFromSummaryScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.summary,
          steps: 8245,
          activeCaloriesKcal: 320,
        ),
        weightKg: 60,
      )!;
      expect(draft.typeKey, 'summary');
      expect(draft.durationMin, 0);
      expect(draft.kcal, 320);
      expect(draft.estimated, isFalse);
      expect(draft.steps, 8245); // 识别有步数 → 必须随记录持久化
    });

    test('只有步数+距离 → 体重 × 距离 × 1.036（60kg × 5km = 310.8）', () {
      final draft = draftFromSummaryScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.summary,
          steps: 6200,
          distanceKm: 5,
        ),
        weightKg: 60,
      )!;
      expect(draft.kcal, moreOrLessEquals(310.8, epsilon: 1e-9));
      expect(draft.estimated, isTrue);
      expect(draft.steps, 6200);
    });

    test('只有步数没有距离 → 步数 × 0.75m 步幅估距离再折算'
        '（8000 步 × 0.75m = 6km → 60 × 6 × 1.036 = 372.96）', () {
      final draft = draftFromSummaryScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.summary,
          steps: 8000,
        ),
        weightKg: 60,
      )!;
      expect(draft.kcal, moreOrLessEquals(372.96, epsilon: 1e-9));
      expect(draft.estimated, isTrue);
    });

    test('爬楼不折算入账：只有爬楼 → null（仅展示口径）', () {
      expect(
        draftFromSummaryScreenshot(
          const ExerciseScreenshotData(
            kind: ExerciseScreenshotKind.summary,
            floorsClimbedM: 50,
          ),
          weightKg: 60,
        ),
        isNull,
      );
    });

    test('无任何可入账数据 → null；非 summary 类别 → null', () {
      expect(
        draftFromSummaryScreenshot(
          const ExerciseScreenshotData(kind: ExerciseScreenshotKind.summary),
          weightKg: 60,
        ),
        isNull,
      );
      expect(
        draftFromSummaryScreenshot(
          const ExerciseScreenshotData(
            kind: ExerciseScreenshotKind.workout,
            burnKcal: 100,
          ),
          weightKg: 60,
        ),
        isNull,
      );
    });
  });

  group('draftFromWorkoutScreenshot', () {
    test('截图消耗 >0 → 优先用截图值（不走 MET）', () {
      final draft = draftFromWorkoutScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.workout,
          exerciseTypeKey: 'jog',
          durationMinutes: 30,
          burnKcal: 285,
        ),
        weightKg: 60,
      );
      expect(draft.typeKey, 'jog');
      expect(draft.durationMin, 30);
      expect(draft.kcal, 285);
      expect(draft.estimated, isFalse);
    });

    test('无截图消耗 → MET 表估算（慢跑 60kg 30 分钟 = 210）', () {
      final draft = draftFromWorkoutScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.workout,
          exerciseTypeKey: 'jog',
          durationMinutes: 30,
        ),
        weightKg: 60,
      );
      expect(draft.kcal, moreOrLessEquals(210, epsilon: 1e-9));
      expect(draft.estimated, isTrue);
    });

    test('类型 other 且无消耗 → kcal null（弹层手选/手填兜底）', () {
      final draft = draftFromWorkoutScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.workout,
          exerciseTypeKey: 'other',
          durationMinutes: 45,
        ),
        weightKg: 60,
      );
      expect(draft.typeKey, 'other');
      expect(draft.kcal, isNull);
    });

    test('时长缺失 → durationMin 0（弹层必填校验兜底）', () {
      final draft = draftFromWorkoutScreenshot(
        const ExerciseScreenshotData(
          kind: ExerciseScreenshotKind.workout,
          exerciseTypeKey: 'yoga',
        ),
        weightKg: 60,
      );
      expect(draft.durationMin, 0);
      expect(draft.kcal, isNull);
    });
  });
}
