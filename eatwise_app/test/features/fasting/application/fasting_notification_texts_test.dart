import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_plan.dart';
import 'package:eatwise/features/fasting/application/fasting_notification_texts.dart';
import 'package:eatwise/features/fasting/domain/fasting_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通知文案 slang 适配器测试（D-15：三类文案走 i18n key，双语）。
void main() {
  const base = 1780000000; // 任意 UTC 锚点
  PlannedFastingNotification item(
    FastingNotificationKind kind, {
    LocalDate? attributionDate,
  }) {
    return PlannedFastingNotification(
      kind: kind,
      id: fastingNotificationId(base, kind),
      triggerAtUtcSec: base,
      attributionDate: attributionDate,
    );
  }

  group('slangFastingNotificationTextResolver', () {
    test('zh-CN：三类文案 + 归属日「X月X日」（D-07 文案）', () {
      final resolver = slangFastingNotificationTextResolver(
        AppLocale.zhCn.buildSync(),
      );

      expect(
        resolver(item(FastingNotificationKind.eatSoon)).body,
        '还有 15 分钟就可以进食啦',
      );
      expect(
        resolver(
          item(
            FastingNotificationKind.eatStart,
            attributionDate: const LocalDate(2026, 7, 28),
          ),
        ).body,
        '可以进食啦，本次断食计入 7月28日 ✅',
      );
      expect(
        resolver(item(FastingNotificationKind.fastStart)).body,
        '断食窗口开始啦，今天也很棒，加油坚持～',
      );
      expect(resolver(item(FastingNotificationKind.eatSoon)).title, 'EatWise');
    });

    test('en：三类文案 + 归属日「MMM d」', () {
      final resolver = slangFastingNotificationTextResolver(
        AppLocale.en.buildSync(),
      );

      expect(
        resolver(item(FastingNotificationKind.eatSoon)).body,
        'Eating window opens in 15 min',
      );
      expect(
        resolver(
          item(
            FastingNotificationKind.eatStart,
            attributionDate: const LocalDate(2026, 7, 28),
          ),
        ).body,
        'Time to eat! This fast counts toward Jul 28 ✅',
      );
      expect(
        resolver(item(FastingNotificationKind.fastStart)).body,
        "Your fasting window has started — you're doing great, keep it up!",
      );
    });

    test('eatStart 归属日缺失时按 UTC 兜底，不崩', () {
      final resolver = slangFastingNotificationTextResolver(
        AppLocale.zhCn.buildSync(),
      );
      expect(
        () => resolver(item(FastingNotificationKind.eatStart)),
        returnsNormally,
      );
    });
  });

  group('formatAttributionDate', () {
    test('zh-CN 与 en 两种格式', () {
      const date = LocalDate(2026, 1, 5);
      expect(formatAttributionDate(date, locale: AppLocale.zhCn), '1月5日');
      expect(formatAttributionDate(date, locale: AppLocale.en), 'Jan 5');
    });
  });

  group('fastingReminderChannel', () {
    test('渠道 id 稳定，名称来自 i18n', () {
      final channel = fastingReminderChannel(AppLocale.zhCn.buildSync());
      expect(channel.id, fastingReminderChannelId);
      expect(channel.name, 'EatWise');
    });
  });
}
