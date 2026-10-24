import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

class AppQuietTabs<T> extends StatelessWidget {
  const AppQuietTabs({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final value in values)
          Expanded(
            child: _QuietTab(
              label: labelOf(value),
              selected: value == selected,
              onTap: () => onSelected(value),
            ),
          ),
      ],
    );
  }
}

class _QuietTab extends StatelessWidget {
  const _QuietTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: radii.rSm,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s1,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: textStyles.textBase.copyWith(
                        color: selected
                            ? colors.brandPrimary
                            : colors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s1),
                Container(
                  width: selected ? 24 : 0,
                  height: 2,
                  color: selected ? colors.brandPrimary : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
