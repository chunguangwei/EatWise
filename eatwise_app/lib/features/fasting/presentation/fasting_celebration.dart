import 'dart:math' as math;

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// 破壳庆祝微交互（设计稿 §5.1-1）：断食归零/结束断食且达标时——
/// 绿弧走满 + 中心数字弹性回弹 + 12 颗绿+橙小光点 + 庆祝文案。
///
/// 无障碍降级（§4.3 / 四态规范 3.2.4）：系统「减弱动态效果」开启时
/// （`MediaQuery.disableAnimations`），改为光点淡入静态徽章，无位移/迸发动画。
class FastingCelebration extends StatefulWidget {
  const FastingCelebration({required this.onDismiss, super.key});

  /// 动画播完（完整动效）或用户点按（降级徽章）时回调。
  final VoidCallback onDismiss;

  @override
  State<FastingCelebration> createState() => _FastingCelebrationState();
}

class _FastingCelebrationState extends State<FastingCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1200),
        )..addStatusListener((status) {
          // 完整动效播完自动收尾；降级路径不启动 controller（见 build）。
          if (status == AnimationStatus.completed) widget.onDismiss();
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      // prefers-reduced-motion 降级：静态徽章淡入，点按关闭。
      return GestureDetector(
        onTap: widget.onDismiss,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: const _CelebrationBadge(),
        ),
      );
    }
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
    return GestureDetector(
      onTap: widget.onDismiss,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final colors = Theme.of(context).extension<AppColors>()!;
          final t = Translations.of(context);
          // 弹性回弹（中心徽章缩放）。
          final scale = CurvedAnimation(
            parent: _controller,
            curve: const Interval(0, 0.6, curve: Curves.elasticOut),
          ).value;
          // 光点迸发（后半程）。
          final burst = CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.25, 1, curve: Curves.easeOut),
          ).value;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: const Size.square(220),
                painter: _BurstPainter(
                  progress: burst,
                  dotColors: <Color>[colors.brandPrimary, colors.brandAccent],
                ),
              ),
              Transform.scale(
                scale: 0.6 + 0.4 * scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.celebration_outlined,
                      color: colors.brandPrimary,
                      size: 32,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                      ),
                      child: Text(
                        t.fasting.home.celebrationTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .extension<AppTextStyles>()!
                            .textSm
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 降级静态徽章（减弱动效：图标 + 文字，无迸发动画）。
class _CelebrationBadge extends StatelessWidget {
  const _CelebrationBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    final t = Translations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: radii.rFull,
        border: Border.all(color: colors.brandPrimary, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check_circle, color: colors.signalGreen),
          const SizedBox(width: AppSpacing.s2),
          Text(
            t.fasting.home.celebrationBadge,
            style: textStyles.textBase.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// 12 颗绿+橙小光点：自环心沿 12 个方向迸发并渐隐（克制不腻，§5.1-1）。
class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.dotColors});

  final double progress;
  final List<Color> dotColors;

  static const int _dotCount = 12;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide / 2;
    for (var i = 0; i < _dotCount; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / _dotCount);
      final distance = baseRadius * (0.35 + 0.75 * progress);
      final offset =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      canvas.drawCircle(
        offset,
        4 * (1 - progress * 0.5),
        Paint()
          ..color = dotColors[i % dotColors.length].withValues(
            alpha: 1 - progress,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
