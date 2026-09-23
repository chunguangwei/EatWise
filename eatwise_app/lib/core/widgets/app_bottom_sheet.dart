import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 带动作按钮的底部弹层统一骨架（真机走查收口：华为小屏 + 系统大字体 +
/// 键盘弹起时「确认按钮被顶出屏幕/滚出可视区」系列问题的统一口径）。
///
/// 三条硬约束：
/// - **封顶**：整体最大高度 =（屏高 − 键盘高度）× [maxHeightFactor]
///   （默认 90%），内容再高也不会把弹层撑出屏幕；
/// - **内滚**：内容区 [content] 包在 `Flexible + SingleChildScrollView`
///   里，超高时内部滚动；
/// - **按钮常驻**：[bottomBar]（动作按钮区）在滚动区**之外**，固定在弹层
///   底部，不随内容滚走、不被键盘顶出（骨架已含 viewInsets 键盘避让与
///   SafeArea）。
///
/// 用法：`showModalBottomSheet(isScrollControlled: true)` 的 builder 直接
/// 返回本骨架；内容自身的四边 padding 由骨架统一给（[contentPadding] /
/// [bottomBarPadding]），内容内不再各自加 viewInsets/SafeArea。
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    required this.content,
    super.key,
    this.bottomBar,
    this.maxHeightFactor = 0.9,
    this.contentPadding = const EdgeInsets.all(AppSpacing.s4),
    this.bottomBarPadding = const EdgeInsets.fromLTRB(
      AppSpacing.s4,
      AppSpacing.s2,
      AppSpacing.s4,
      AppSpacing.s4,
    ),
  });

  /// 内容区（超高内部滚动）。
  final Widget content;

  /// 底部动作区（确认/保存等主按钮；常驻弹层底部，null = 无动作区）。
  final Widget? bottomBar;

  /// 封顶比例（占「屏高 − 键盘高度」的比例）。
  final double maxHeightFactor;

  /// 内容区 padding。
  final EdgeInsets contentPadding;

  /// 动作区 padding。
  final EdgeInsets bottomBarPadding;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight =
        (MediaQuery.sizeOf(context).height - keyboard) * maxHeightFactor;
    final bottomBar = this.bottomBar;
    return SafeArea(
      child: Padding(
        // 键盘顶起时整体上移（isScrollControlled 下 viewInsets 不被消化）。
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: SingleChildScrollView(
                  padding: contentPadding,
                  child: content,
                ),
              ),
              // 动作按钮固定在滚动区外（小屏/大字体/键盘下恒可见可点）。
              if (bottomBar != null)
                Padding(padding: bottomBarPadding, child: bottomBar),
            ],
          ),
        ),
      ),
    );
  }
}
