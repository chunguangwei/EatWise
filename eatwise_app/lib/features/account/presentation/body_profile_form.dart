import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/fasting/domain/nutrition_types.dart';
import 'package:eatwise/features/onboarding/domain/onboarding_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 身体档案表单（阶段 A：onboarding 档案页与「我的-身体档案」共用控件）。
///
/// 全部字段可留空（D-18 敏感信息，空项走兜底）；非空字段做取值域校验
/// （[isValidBirthYear]/[isValidHeightCm]/[isValidWeightKg]，纯函数在
/// onboarding/domain/onboarding_profile.dart），非法输入即时提示并
/// 通过 [onChanged] 上报 isValid=false 由父级禁用提交。
class BodyProfileForm extends StatefulWidget {
  const BodyProfileForm({
    super.key,
    required this.currentYear,
    required this.onChanged,
    this.initial = OnboardingProfile.empty,
  });

  /// 当前年（出生年校验上界；测试注入固定时钟）。
  final int currentYear;

  /// 初始值（本地已采集档案或服务端档案）。
  final OnboardingProfile initial;

  /// 取值变化回调（profile 为当前表单值，isValid 为整体可提交性）。
  final void Function(OnboardingProfile profile, bool isValid) onChanged;

  @override
  State<BodyProfileForm> createState() => _BodyProfileFormState();
}

class _BodyProfileFormState extends State<BodyProfileForm> {
  late ProfileSex? _sex = widget.initial.sex;
  late ActivityLevel? _activityLevel = widget.initial.activityLevel;
  late final TextEditingController _birthYearController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    String numText(num? v) =>
        v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : '$v');
    _birthYearController = TextEditingController(
      text: widget.initial.birthYear?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: numText(widget.initial.heightCm),
    );
    _weightController = TextEditingController(
      text: numText(widget.initial.weightKg),
    );
    // 初始值合法（来自已持久化档案），直接上报一次供父级初始化。
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _birthYearController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  int? get _birthYear {
    final raw = _birthYearController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  double? get _heightCm {
    final raw = _heightController.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  double? get _weightKg {
    final raw = _weightController.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _birthYearError(Translations t) {
    final raw = _birthYearController.text.trim();
    if (raw.isEmpty) return null;
    final year = int.tryParse(raw);
    if (year == null || !isValidBirthYear(year, widget.currentYear)) {
      return t.onboarding.profile.birthYearInvalid(
        min: ProfileFieldLimits.birthYearMin,
        max: widget.currentYear,
      );
    }
    return null;
  }

  String? _heightError(Translations t) {
    final raw = _heightController.text.trim();
    if (raw.isEmpty) return null;
    final cm = double.tryParse(raw);
    if (cm == null || !isValidHeightCm(cm)) {
      return t.onboarding.profile.heightInvalid;
    }
    return null;
  }

  String? _weightError(Translations t) {
    final raw = _weightController.text.trim();
    if (raw.isEmpty) return null;
    final kg = double.tryParse(raw);
    if (kg == null || !isValidWeightKg(kg)) {
      return t.onboarding.profile.weightInvalid;
    }
    return null;
  }

  void _emit() {
    final t = Translations.of(context);
    final valid =
        _birthYearError(t) == null &&
        _heightError(t) == null &&
        _weightError(t) == null;
    widget.onChanged(
      OnboardingProfile(
        sex: _sex,
        birthYear: _birthYear,
        heightCm: _heightCm,
        weightKg: _weightKg,
        activityLevel: _activityLevel,
      ),
      valid,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.onboarding.profile.genderLabel,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        SegmentedButton<ProfileSex>(
          segments: <ButtonSegment<ProfileSex>>[
            ButtonSegment<ProfileSex>(
              value: ProfileSex.male,
              label: Text(t.onboarding.profile.gender.male),
            ),
            ButtonSegment<ProfileSex>(
              value: ProfileSex.female,
              label: Text(t.onboarding.profile.gender.female),
            ),
            ButtonSegment<ProfileSex>(
              value: ProfileSex.undisclosed,
              label: Text(t.onboarding.profile.gender.undisclosed),
            ),
          ],
          selected: <ProfileSex>{?_sex},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) {
            setState(() => _sex = selection.firstOrNull);
            _emit();
          },
        ),
        const SizedBox(height: AppSpacing.s4),
        _ProfileField(
          key: const ValueKey<String>('profile.birthYear'),
          label: t.onboarding.profile.birthYearLabel,
          hint: t.onboarding.profile.birthYearHint,
          controller: _birthYearController,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          errorText: _birthYearError(t),
          onChanged: _onFieldChanged,
        ),
        const SizedBox(height: AppSpacing.s3),
        _ProfileField(
          key: const ValueKey<String>('profile.heightCm'),
          label: t.onboarding.profile.heightLabel,
          hint: t.onboarding.profile.heightHint,
          controller: _heightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: _heightError(t),
          onChanged: _onFieldChanged,
        ),
        const SizedBox(height: AppSpacing.s3),
        _ProfileField(
          key: const ValueKey<String>('profile.weightKg'),
          label: t.onboarding.profile.weightLabel,
          hint: t.onboarding.profile.weightHint,
          controller: _weightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: _weightError(t),
          onChanged: _onFieldChanged,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          t.onboarding.profile.activityLabel,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        for (final level in ActivityLevel.values) ...<Widget>[
          _ActivityOption(
            key: ValueKey<String>('profile.activity.${level.name}'),
            label: _activityLabel(t, level),
            selected: level == _activityLevel,
            onTap: () {
              setState(
                () => _activityLevel = level == _activityLevel ? null : level,
              );
              _emit();
            },
          ),
          const SizedBox(height: AppSpacing.s2),
        ],
      ],
    );
  }

  void _onFieldChanged() {
    setState(() {}); // 触发错误文案刷新
    _emit();
  }

  static String _activityLabel(Translations t, ActivityLevel level) {
    final activity = t.onboarding.profile.activity;
    return switch (level) {
      ActivityLevel.sedentary => activity.sedentary,
      ActivityLevel.light => activity.light,
      ActivityLevel.moderate => activity.moderate,
      ActivityLevel.high => activity.high,
    };
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.keyboardType,
    required this.onChanged,
    this.inputFormatters,
    this.errorText,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final VoidCallback onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s1),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: (_) => onChanged(),
          style: textStyles.textBase,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            filled: true,
            fillColor: colors.bgSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityOption extends StatelessWidget {
  const _ActivityOption({
    super.key,
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
      color: colors.bgSecondary,
      borderRadius: radii.rLg,
      child: InkWell(
        borderRadius: radii.rLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s3),
          decoration: BoxDecoration(
            borderRadius: radii.rLg,
            border: Border.all(
              color: selected ? colors.brandPrimary : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: textStyles.textSm)),
              if (selected)
                Icon(Icons.check_circle, color: colors.brandPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
