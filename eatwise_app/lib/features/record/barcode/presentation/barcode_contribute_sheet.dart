import 'dart:async';

import 'package:eatwise/app/l10n/strings.g.dart';
import 'package:eatwise/core/analytics/analytics_providers.dart';
import 'package:eatwise/core/analytics/analytics_service.dart';
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/core/storage/tables.dart';
import 'package:eatwise/core/theme/app_colors.dart';
import 'package:eatwise/core/theme/app_radii.dart';
import 'package:eatwise/core/theme/app_spacing.dart';
import 'package:eatwise/core/theme/app_text_styles.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_providers.dart';
import 'package:eatwise/features/record/custom_food/presentation/custom_food_strings.dart';
import 'package:eatwise/features/record/domain/record_models.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:eatwise/features/record/presentation/record_strings.dart';
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/record/recognition/presentation/photo_flow.dart';
import 'package:eatwise/features/social/application/feed_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 扫码未命中补录结果（弹层返回 → 流程层按 outcome 提示并回填结果卡）。
final class BarcodeContributeResult {
  const BarcodeContributeResult({
    required this.food,
    required this.outcome,
    this.message,
  });

  /// 已落本地的食物行（isCustom=true；无论贡献成败都可立即记餐）。
  final Food food;

  /// 提交结局。
  final BarcodeContributeOutcome outcome;

  /// 拒收场景的服务端双语原因（rejected 时有值）。
  final String? message;
}

/// 补录提交结局。
enum BarcodeContributeOutcome {
  /// 两步链路完成（创建自定义食物 + 带条码贡献），等待审核。
  submitted,

  /// 服务端 409：同条码已上架共享库，本地食物仍预填记账。
  alreadyListed,

  /// 保存时离线（仅落本地 pending）：不做离线队列，提示联网后重新提交。
  offlineSaved,

  /// 机审拒收：食物仍落本地可记餐，原因随 [BarcodeContributeResult.message] 展示。
  rejected,
}

/// 扫码未命中「补充商品信息」入口流程（众包补录：条码 + 营养表佐证照片）。
///
/// 步骤：弹层表单（商品名 + 每 100g 营养 + 营养表照片，条码只读）→
/// 选图即传（POST /uploads）→ 创建自定义食物（/foods/custom）→
/// 贡献（/foods/custom/:id/contribute 带 barcode + evidenceImageUrl）。
/// 成功后把本地食物回填记录结果卡（EntrySource.barcode，份量留空必填），
/// 自己立即可记餐；409 已在库同样预填。
///
/// 离线口径：照片上传与贡献都依赖服务端，**不做离线队列**——保存降级落
/// 本地 pending 时按 [BarcodeContributeOutcome.offlineSaved] 提示联网后
/// 重新提交（照片不会随本地食物保留重传）。
Future<void> startBarcodeContributeFlow(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  final result = await showModalBottomSheet<BarcodeContributeResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: BarcodeContributeSheet(barcode: code),
    ),
  );
  if (result == null || !context.mounted) return;
  // 各结局食物都已落本地：回填结果卡，份量必填留空（与其他入口口径一致）。
  ref.read(recordSelectedFoodProvider.notifier).state = result.food;
  ref.read(recordAmountTextProvider.notifier).state = '';
  ref.read(recordEntrySourceProvider.notifier).state = EntrySource.barcode;
  ref.read(recordLowConfidenceProvider.notifier).state = false;
  final t = Translations.of(context).record.barcode.contribute;
  final text = switch (result.outcome) {
    BarcodeContributeOutcome.submitted => t.submitted,
    BarcodeContributeOutcome.alreadyListed => t.alreadyListed,
    BarcodeContributeOutcome.offlineSaved => t.offlineNotice,
    BarcodeContributeOutcome.rejected => result.message ?? t.submitted,
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// 未命中补录弹层：商品名（必填）+ 每 100g 四营养（必填，与自定义食物同
/// 口径范围校验）+ 包装营养表照片（必填，拍照/相册，选图即传）+ 条码只读。
class BarcodeContributeSheet extends ConsumerStatefulWidget {
  const BarcodeContributeSheet({super.key, required this.barcode});

  /// 扫码上下文带过来的条码号（只读展示，贡献时原样上行）。
  final String barcode;

  @override
  ConsumerState<BarcodeContributeSheet> createState() =>
      _BarcodeContributeSheetState();
}

class _BarcodeContributeSheetState
    extends ConsumerState<BarcodeContributeSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _kcalController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();

  /// 已选照片字节（本地预览）。
  Uint8List? _photo;

  /// 上传成功后的服务端读取路径（`/v1/uploads/<id>`，贡献时作 evidenceImageUrl）。
  String? _photoUrl;

  /// 上传在途（提交禁用，避免发出缺佐证贡献）。
  bool _uploading = false;

  /// 上传失败文案（服务端本地化 message；就地重试或换图重选，不阻断）。
  String? _uploadError;

  /// 上传代际：换图后丢弃在途回调，避免旧图 URL 覆盖新图。
  int _uploadSeq = 0;

  /// 点过提交但缺照片（照片区下方内联错误；选图成功即清除）。
  bool _photoMissing = false;

  /// 提交在途（防连点重复提交）。
  bool _saving = false;

  /// 埋点服务（与记录页同一实例；未授权时 track 为 no-op）。
  late final AnalyticsService _analytics = ref.read(analyticsServiceProvider);

  @override
  void dispose() {
    _nameController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  /// 选照片：来源选择（拍照/相册）→ 取图 → 选图即传。
  Future<void> _pickPhoto() async {
    final t = Translations.of(context);
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.record.photo.takePhoto),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t.record.photo.fromGallery),
              onTap: () => Navigator.of(sheetContext).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    Uint8List bytes;
    try {
      final picked = await ref.read(photoPickerGatewayProvider).pick(source);
      // 用户主动取消取图：静默返回，不动表单。
      if (picked == null || !mounted) return;
      bytes = picked;
    } on PhotoPermissionDeniedException {
      // 权限拒绝走 §4.3 降级说明卡（与拍照识别同构，不阻断表单）。
      if (mounted) {
        await showPhotoPermissionDeniedCard(context, RecordStrings.of(context));
      }
      return;
    }
    setState(() {
      _photo = bytes;
      _photoUrl = null;
      _photoMissing = false;
    });
    await _uploadPhoto(bytes);
  }

  /// 上传照片（POST /uploads，U1 契约）：上传态 + 失败就地重试，
  /// 失败不阻断换图重选。
  Future<void> _uploadPhoto(Uint8List bytes) async {
    final seq = ++_uploadSeq;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final uploaded = await ref.read(uploadApiProvider).uploadImage(bytes);
      if (!mounted || seq != _uploadSeq) return;
      setState(() {
        _photoUrl = uploaded.url;
        _uploading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _uploadSeq) return;
      setState(() {
        _uploading = false;
        _uploadError = e.message;
      });
    }
  }

  /// 提交：校验（含照片必填）→ 创建自定义食物 → 带条码贡献。
  Future<void> _onSubmit() async {
    if (_saving) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (_photoUrl == null) {
      // 照片必填：未选/上传失败都不可提交（上传失败时已展示重试入口）。
      setState(() => _photoMissing = true);
      return;
    }
    if (!valid) return;
    _saving = true;
    _analytics.track(
      'record_barcode_contribute',
      properties: <String, Object?>{'result': 'submit'},
    );
    try {
      final name = _nameController.text.trim();
      final draft = CustomFoodDraft(
        nameZh: name,
        // 单输入框不区分中英：英文字母开头的名字同步进英文名（同自定义食物口径）。
        nameEn: _looksEnglish(name) ? name : null,
        // 条码由贡献链路单独承载（候选 barcode 字段），不混入别名。
        aliasesZh: const <String>[],
        per100g: NutritionSnapshot(
          kcal: double.parse(_kcalController.text.trim()),
          proteinG: double.parse(_proteinController.text.trim()),
          carbG: double.parse(_carbController.text.trim()),
          fatG: double.parse(_fatController.text.trim()),
        ),
        source: CustomFoodSource.manual,
      );
      final saved = await ref.read(customFoodRepositoryProvider).save(draft);
      if (!saved.uploaded) {
        // 离线：不做离线队列（照片 URL 已上传但贡献必须到服务端）；
        // 食物已落本地可记餐，提示联网后重新提交。
        _analytics.track(
          'record_barcode_contribute',
          properties: <String, Object?>{'result': 'fail', 'reason': 'offline'},
        );
        if (mounted) {
          Navigator.of(context).pop(
            BarcodeContributeResult(
              food: saved.food,
              outcome: BarcodeContributeOutcome.offlineSaved,
            ),
          );
        }
        return;
      }
      try {
        await ref
            .read(customFoodRepositoryProvider)
            .contribute(
              saved.food.id,
              barcode: widget.barcode,
              evidenceImageUrl: _photoUrl,
            );
        _analytics.track(
          'record_barcode_contribute',
          properties: <String, Object?>{'result': 'success'},
        );
        if (mounted) {
          Navigator.of(context).pop(
            BarcodeContributeResult(
              food: saved.food,
              outcome: BarcodeContributeOutcome.submitted,
            ),
          );
        }
      } on BusinessApiException catch (e) {
        if (e.httpStatus == 409) {
          // 同条码已上架：食物已在库，直接预填本地食物记账。
          _analytics.track(
            'record_barcode_contribute',
            properties: <String, Object?>{
              'result': 'fail',
              'reason': 'conflict',
            },
          );
          if (mounted) {
            Navigator.of(context).pop(
              BarcodeContributeResult(
                food: saved.food,
                outcome: BarcodeContributeOutcome.alreadyListed,
              ),
            );
          }
        } else if (e.code == 'FOOD_CONTRIBUTE_REJECTED') {
          // 机审拒收：食物仍落本地可记餐，服务端双语原因由流程层展示。
          _analytics.track(
            'record_barcode_contribute',
            properties: <String, Object?>{
              'result': 'fail',
              'reason': 'rejected',
            },
          );
          if (mounted) {
            Navigator.of(context).pop(
              BarcodeContributeResult(
                food: saved.food,
                outcome: BarcodeContributeOutcome.rejected,
                message: e.message,
              ),
            );
          }
        } else {
          _analytics.track(
            'record_barcode_contribute',
            properties: <String, Object?>{'result': 'fail', 'reason': 'error'},
          );
          // 留在表单可重试（贡献幂等，重试不产生重复候选）。
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
      } on ApiException catch (e) {
        // 网络/超时：留在表单可重试。
        _analytics.track(
          'record_barcode_contribute',
          properties: <String, Object?>{'result': 'fail', 'reason': 'network'},
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } on ApiException catch (e) {
      // 保存业务错误（4xx/5xx）：留在表单，服务端双语 message 直接上屏。
      _analytics.track(
        'record_barcode_contribute',
        properties: <String, Object?>{'result': 'fail', 'reason': 'error'},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      _saving = false;
    }
  }

  /// 是否纯英文名（粗略：不含 CJK 字符，与自定义食物弹层同口径）。
  static bool _looksEnglish(String name) => !RegExp(r'[一-鿿]').hasMatch(name);

  /// 营养字段校验：必填 >0；热量 ≤900，宏量 ≤100（与自定义食物同口径）。
  FormFieldValidator<String> _nutritionValidator(
    CustomFoodStrings cs,
    double max,
    String rangeMsg,
  ) {
    return (value) {
      final parsed = double.tryParse((value ?? '').trim());
      if (parsed == null || parsed <= 0) return cs.nutritionRequired;
      if (parsed > max) return rangeMsg;
      return null;
    };
  }

  InputDecoration _fieldDecoration(
    AppColors colors,
    AppRadii radii,
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.bgSecondary,
      constraints: const BoxConstraints(minHeight: AppSpacing.s12),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: radii.rMd,
        borderSide: BorderSide.none,
      ),
      // 表单规范：focus 品牌绿描边。
      focusedBorder: OutlineInputBorder(
        borderRadius: radii.rMd,
        borderSide: BorderSide(color: colors.brandPrimary, width: 2),
      ),
    );
  }

  /// 照片区：未选 → 选图入口；已选 → 本地预览 + 上传态/失败重试/换图。
  Widget _buildPhotoSection(
    BuildContext context,
    AppColors colors,
    AppTextStyles textStyles,
    AppRadii radii,
  ) {
    final t = Translations.of(context).record.barcode.contribute;
    final photo = _photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.photoLabel,
          style: textStyles.textSm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        if (photo == null)
          OutlinedButton.icon(
            onPressed: _saving ? null : () => unawaited(_pickPhoto()),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.s12),
              foregroundColor: colors.brandPrimary,
              side: BorderSide(color: colors.brandPrimary),
            ),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(t.photoAdd, style: textStyles.textBase),
          )
        else
          Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: radii.rMd,
                // 上传前后都用本地字节预览（免网络图闪烁；佐证照不需再下载）。
                child: Image.memory(
                  photo,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              if (_uploading)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: Semantics(
                        label: t.photoUploading,
                        child: const SizedBox(
                          height: 28,
                          width: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: AppSpacing.s1,
                right: AppSpacing.s1,
                child: IconButton.filled(
                  icon: const Icon(Icons.close),
                  tooltip: t.photoAdd,
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          // 递增代际作废在途上传；回到未选态可重新选择。
                          _uploadSeq++;
                          _photo = null;
                          _photoUrl = null;
                          _uploading = false;
                          _uploadError = null;
                        }),
                ),
              ),
            ],
          ),
        if (_uploadError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _uploadError!,
                  style: textStyles.textSm.copyWith(color: colors.signalRed),
                ),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_uploadPhoto(photo!)),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t.photoUploadRetry),
              ),
            ],
          ),
        ],
        if (_photoMissing && _photoUrl == null && _uploadError == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s2),
            child: Text(
              t.photoRequired,
              style: textStyles.textSm.copyWith(color: colors.signalRed),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).record.barcode.contribute;
    final cs = CustomFoodStrings.of(context);
    final colors = Theme.of(context).extension<AppColors>()!;
    final textStyles = Theme.of(context).extension<AppTextStyles>()!;
    final radii = Theme.of(context).extension<AppRadii>()!;
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    final numberFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(t.title, style: textStyles.textLg),
              const SizedBox(height: AppSpacing.s4),
              // 条码只读展示（来自扫码上下文，贡献时原样上行）。
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: colors.bgSecondary,
                  borderRadius: radii.rSm,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.qr_code_2,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        t.barcodeLabel(code: widget.barcode),
                        style: textStyles.textSm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _nameController,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, t.nameLabel),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? t.nameRequired : null,
              ),
              const SizedBox(height: AppSpacing.s3),
              // 四营养输入（每 100g；全部必填 >0，热量 ≤900 / 宏量 ≤100）。
              TextFormField(
                controller: _kcalController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.kcalLabel),
                validator: _nutritionValidator(cs, 900, cs.kcalRange),
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _proteinController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.proteinLabel),
                validator: _nutritionValidator(cs, 100, cs.macroRange),
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _carbController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.carbLabel),
                validator: _nutritionValidator(cs, 100, cs.macroRange),
              ),
              const SizedBox(height: AppSpacing.s3),
              TextFormField(
                controller: _fatController,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                style: textStyles.textBase,
                decoration: _fieldDecoration(colors, radii, cs.fatLabel),
                validator: _nutritionValidator(cs, 100, cs.macroRange),
              ),
              const SizedBox(height: AppSpacing.s4),
              _buildPhotoSection(context, colors, textStyles, radii),
              const SizedBox(height: AppSpacing.s4),
              FilledButton(
                onPressed: _saving || _uploading
                    ? null
                    : () => unawaited(_onSubmit()),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.s12),
                ),
                child: Text(t.submitAction, style: textStyles.textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
