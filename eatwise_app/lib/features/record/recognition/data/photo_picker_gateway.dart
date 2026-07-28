import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 照片来源（拍照入口内的两条路径，合规 §3.1/§3.2）。
enum PhotoSource {
  /// 调起相机拍摄（iOS 需 NSCameraUsageDescription；Android CAMERA）。
  camera,

  /// 从相册选已有照片（Android 优先系统 Photo Picker，可不申请权限；
  /// iOS 申请 PHPhotoLibrary Limited）。
  gallery,
}

/// 相机/相册权限被系统拒绝（《规格-全局 UI 四态》§4.3 降级 UI 触发条件）。
final class PhotoPermissionDeniedException implements Exception {
  const PhotoPermissionDeniedException(this.source);

  /// 被拒绝的入口路径。
  final PhotoSource source;

  @override
  String toString() => 'PhotoPermissionDeniedException($source)';
}

/// 拍照/相册取图抽象（便于 widget 测试注入 fake，真机用
/// [ImagePickerPhotoGateway]；权限申请时机跟随功能：首次点击入口时，
/// 合规 §3 用时申请原则）。
abstract interface class PhotoPickerGateway {
  /// 取一张图；用户主动取消返回 null；权限被拒抛
  /// [PhotoPermissionDeniedException]。
  Future<Uint8List?> pick(PhotoSource source);
}

/// image_picker 实现（生产路径）。
final class ImagePickerPhotoGateway implements PhotoPickerGateway {
  ImagePickerPhotoGateway({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // 上行识别前压一版，省流量也缩小隐私暴露面（合规 §3 最小化）。
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return null;
      return file.readAsBytes();
    } on Exception catch (e) {
      // image_picker 平台侧权限拒绝统一抛异常（iOS camera_access_denied /
      // photo_access_denied，Android SecurityException 包装），
      // 无法可靠区分时按权限拒绝处理走降级 UI（§4.3），
      // 用户取消由各平台返回 null 已在上面拦截。
      final message = e.toString().toLowerCase();
      if (message.contains('denied') ||
          message.contains('permission') ||
          message.contains('security')) {
        throw PhotoPermissionDeniedException(source);
      }
      rethrow;
    }
  }
}
