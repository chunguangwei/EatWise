import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show photoPickerGatewayProvider;
import 'package:eatwise/features/record/recognition/data/photo_picker_gateway.dart';
import 'package:eatwise/features/settings/application/settings_providers.dart';
import 'package:eatwise/features/social/application/feed_controller.dart'
    show uploadApiProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 头像上传结果（我的页资料头卡按结果给 SnackBar/降级弹窗）。
enum AvatarUploadResult {
  /// 已上传并回写 PATCH /users/me（avatarUrl 字段级 LWW）。
  success,

  /// 用户在选择器里主动取消（不提示）。
  cancelled,

  /// 相册/相机权限被系统拒绝（走 §4.3 降级弹窗引导去设置）。
  permissionDenied,

  /// 上传/回写失败（网络或服务端拒绝，提示重试）。
  failed,
}

/// 头像上传在途标记（头卡据此禁用入口并显「上传中…」，防连点重复传）。
final avatarUploadingProvider = StateProvider<bool>((ref) => false);

/// 更换头像全链路（2026-09-30）：取图（image_picker，权限「用时申请」
/// 跟随用户点击）→ POST /v1/uploads 拿相对 URL → PATCH /users/me
/// 回写 avatarUrl（服务端字段级 LWW，协议白名单校验）→ 失效
/// userMeProvider 让全页（头卡/社区作者位）读新值。
Future<AvatarUploadResult> uploadAvatar(
  WidgetRef ref,
  PhotoSource source,
) async {
  if (ref.read(avatarUploadingProvider)) return AvatarUploadResult.cancelled;
  ref.read(avatarUploadingProvider.notifier).state = true;
  try {
    final bytes = await ref.read(photoPickerGatewayProvider).pick(source);
    if (bytes == null) return AvatarUploadResult.cancelled;
    final uploaded = await ref.read(uploadApiProvider).uploadImage(bytes);
    await ref.read(userApiProvider).patchMe(<String, Object?>{
      'avatarUrl': uploaded.url,
    });
    ref.invalidate(userMeProvider);
    return AvatarUploadResult.success;
  } on PhotoPermissionDeniedException {
    return AvatarUploadResult.permissionDenied;
  } on ApiException {
    return AvatarUploadResult.failed;
  } on Object {
    return AvatarUploadResult.failed;
  } finally {
    ref.read(avatarUploadingProvider.notifier).state = false;
  }
}
