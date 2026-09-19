import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 里程碑分享图卡（US-5.1 / 设计稿 §5.1 微交互 3「点亮成就」可点按分享图卡）。
///
/// 设计要点（品牌规范 §2.2/§2.5）：
/// - 1080×1350（4:5，适配主流社交信息流）固定设计尺寸，预览用 FittedBox
///   等比缩放，导出按宽度回算 pixelRatio 恒得 1080px 宽 PNG；
/// - 云白底 + 轻盈绿主视觉（60%）+ 暖阳橙仅点缀；
/// - 大数字连胜天数（Inter Bold 回退链）+ 中英双语里程碑文案
///   （自我鼓励口径，无用户间比较——原「超过了 80% 的伙伴」为无真实
///   数据支撑的虚假分位，2026-09-19 走查移除）；
/// - Logo 近似：无 Logo 素材，用「叶片 + 时钟弧」CustomPaint 简笔
///   （§2.5：主体轻盈绿一笔弧、弧线收尾暖阳橙点，象征进食—断食循环）。
///
/// 卡片为品牌静态物料，不跟随 App 亮暗主题，文案/日期全部由调用方注入，
/// 便于 golden 与语义测试。
class MilestoneShareCard extends StatelessWidget {
  const MilestoneShareCard({
    required this.days,
    required this.date,
    required this.primaryTitle,
    required this.secondaryTitle,
    required this.daysUnit,
    required this.appName,
    required this.tagline,
    super.key,
  });

  /// 设计宽度（导出 PNG 恒为该宽度）。
  static const double designWidth = 1080;

  /// 设计高度（4:5）。
  static const double designHeight = 1350;

  /// 品牌 Token 固化（卡片不跟随主题）。
  static const Color brandGreen = Color(0xFF3DBE8B);
  static const Color brandGreenDeep = Color(0xFF2A9970);
  static const Color accentOrange = Color(0xFFFF9F45);
  static const Color cloudWhite = Color(0xFFF7F9F8);
  static const Color ink = Color(0xFF1E2A28);
  static const Color fog = Color(0xFF8A9694);

  /// 里程碑/连胜天数（大数字）。
  final int days;

  /// 分享日期（yyyy-MM-dd，由调用方按设备时区格式化）。
  final String date;

  /// 主语种里程碑文案（中文，如「连续 7 天！这个节奏太稳了，继续保持 🎉」）。
  final String primaryTitle;

  /// 副语种里程碑文案（英文，双语出海物料要求）。
  final String secondaryTitle;

  /// 天数单位（跟随当前语种：天 / days）。
  final String daysUnit;

  /// App 名（「明食 EatWise」/「EatWise」）。
  final String appName;

  /// 品牌口号。
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: designWidth,
      height: designHeight,
      color: cloudWhite,
      child: Stack(
        children: <Widget>[
          // 背景时钟弧装饰（绿弧 + 橙点收尾，克制点缀）。
          const Positioned.fill(
            child: CustomPaint(painter: ClockArcBackgroundPainter()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 88, vertical: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 顶部品牌行：叶片+时钟弧近似 Logo + App 名。
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(painter: LeafClockLogoPainter()),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      appName,
                      style: _style(44, FontWeight.w600, ink, height: 1.2),
                    ),
                  ],
                ),
                const Spacer(),
                // 大数字连胜天数（Inter Bold 回退链，轻盈绿主视觉）。
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '$days',
                        style: _style(340, FontWeight.w700, brandGreen),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        daysUnit,
                        style: _style(64, FontWeight.w600, brandGreenDeep),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // 中英双语里程碑文案（品牌语气，自我鼓励口径无虚假分位）。
                Center(
                  child: Text(
                    primaryTitle,
                    style: _style(48, FontWeight.w600, ink, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    secondaryTitle,
                    style: _style(32, FontWeight.w400, fog, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Spacer(),
                // 底部：日期 + 品牌口号。
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(date, style: _style(30, FontWeight.w400, fog)),
                    Text(tagline, style: _style(30, FontWeight.w400, fog)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _style(
    double fontSize,
    FontWeight weight,
    Color color, {
    double height = 1.1,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      height: height,
      color: color,
      fontFamilyFallback: AppTextStyles.fontFamilyFallback,
    );
  }
}

/// 「叶片 + 时钟弧」Logo 近似（§2.5：轻盈绿一笔弧，收尾暖阳橙点，
/// 弧内简笔叶片象征生机；无 Logo 素材时的图形近似）。
class LeafClockLogoPainter extends CustomPainter {
  const LeafClockLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    // 时钟弧：轻盈绿，自顶部起扫 300°，留口象征循环未闭合。
    final arcPaint = Paint()
      ..color = MilestoneShareCard.brandGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.16
      ..strokeCap = StrokeCap.round;
    const startAngle = -math.pi / 2;
    const sweepAngle = math.pi * 5 / 3;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.82),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
    // 弧线收尾暖阳橙点（§2.5）。
    final endAngle = startAngle + sweepAngle;
    final dotCenter = Offset(
      center.dx + radius * 0.82 * math.cos(endAngle),
      center.dy + radius * 0.82 * math.sin(endAngle),
    );
    canvas.drawCircle(
      dotCenter,
      radius * 0.14,
      Paint()..color = MilestoneShareCard.accentOrange,
    );
    // 叶片：弧内两笔贝塞尔合成，轻盈绿填充。
    final leafPath = Path()
      ..moveTo(center.dx, center.dy + radius * 0.42)
      ..quadraticBezierTo(
        center.dx + radius * 0.62,
        center.dy + radius * 0.05,
        center.dx + radius * 0.1,
        center.dy - radius * 0.46,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.5,
        center.dy - radius * 0.02,
        center.dx,
        center.dy + radius * 0.42,
      )
      ..close();
    canvas.drawPath(leafPath, Paint()..color = MilestoneShareCard.brandGreen);
    // 叶脉：云白细线。
    final veinPaint = Paint()
      ..color = MilestoneShareCard.cloudWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy + radius * 0.32),
      Offset(center.dx + radius * 0.08, center.dy - radius * 0.34),
      veinPaint,
    );
  }

  @override
  bool shouldRepaint(LeafClockLogoPainter oldDelegate) => false;
}

/// 卡片背景时钟弧装饰（右下大弧，轻盈绿低透明 + 橙点收尾；
/// 橙仅点缀，绿占主视觉）。
class ClockArcBackgroundPainter extends CustomPainter {
  const ClockArcBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.92, size.height * 0.88);
    const radius = 320.0;
    final arcPaint = Paint()
      ..color = MilestoneShareCard.brandGreen.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 56
      ..strokeCap = StrokeCap.round;
    const startAngle = -math.pi / 2;
    const sweepAngle = math.pi * 1.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
    final endAngle = startAngle + sweepAngle;
    canvas.drawCircle(
      Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      ),
      30,
      Paint()..color = MilestoneShareCard.accentOrange,
    );
    // 左上角呼应小弧（同构，更淡）。
    final echoPaint = Paint()
      ..color = MilestoneShareCard.brandGreen.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width * 0.06, 80), radius: 220),
      math.pi * 0.4,
      math.pi * 0.9,
      false,
      echoPaint,
    );
  }

  @override
  bool shouldRepaint(ClockArcBackgroundPainter oldDelegate) => false;
}

/// 分享图卡导出（纯渲染函数，golden/单元测试可直接调用）：
/// 从 [boundaryKey] 包裹的 RepaintBoundary 抓取图层，输出宽度恒为
/// [MilestoneShareCard.designWidth] 的 PNG 字节。
///
/// 需在帧渲染完成后调用（按钮回调时机天然满足）；widget 测试中需置于
/// `tester.runAsync` 内以允许真实图片编解码。
Future<Uint8List> captureShareCardPng(GlobalKey boundaryKey) async {
  final context = boundaryKey.currentContext;
  if (context == null) {
    throw StateError('分享图卡尚未渲染，无法导出');
  }
  final boundary = context.findRenderObject()! as RenderRepaintBoundary;
  final pixelRatio = MilestoneShareCard.designWidth / boundary.size.width;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('分享图卡 PNG 编码失败');
    }
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
