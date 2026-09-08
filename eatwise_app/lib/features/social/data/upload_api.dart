import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/core/network/api_exception.dart';

/// 上传结果（契约 U1：201 `{id, url}`）。
final class UploadedImageRef {
  const UploadedImageRef({required this.id, required this.url});

  /// 服务端落盘文件名（uuid + 真实格式扩展名）。
  final String id;

  /// 读取路径（`/v1/uploads/<id>`，服务端标公开无鉴权）；创建帖子时作为
  /// imageUrls 元素上行，也是 feed 里 Image.network 的图源。
  final String url;

  factory UploadedImageRef.fromJson(Map<String, dynamic> json) {
    return UploadedImageRef(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

/// 图片真实格式（魔数嗅探结果）。
enum ImageFormat {
  jpg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const ImageFormat(this.mime, this.ext);

  final String mime;
  final String ext;
}

/// U1 图片上传接口（打卡配图链路：先传图拿 URL，再带 URL 建帖）。
class UploadApi {
  UploadApi(this._dio);

  final Dio _dio;

  /// 上传一张图片字节，返回可上行/可上屏的服务端 URL。
  ///
  /// multipart 字段名固定 `file`（服务端契约）；文件名与声明类型按文件头
  /// 魔数嗅探（[detectImageFormat]）。服务端以魔数为唯一判据，客户端猜错
  /// 不会改变落盘扩展名，但嗅探能让中间层日志/未来 CDN 看到一致的
  /// mimetype，也避免把明显不是图片的字节（如 HEIC）当 jpg 白传一趟。
  ///
  /// 失败抛 [ApiException]（UPLOAD_FILE_TOO_LARGE / UPLOAD_TYPE_UNSUPPORTED /
  /// 网络类），调用方按 code 决定提示与是否可重试。
  Future<UploadedImageRef> uploadImage(Uint8List bytes) async {
    final format = detectImageFormat(bytes) ?? ImageFormat.jpg;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/uploads',
        // FormData 会覆盖全局 json contentType，走 multipart/form-data。
        data: FormData.fromMap(<String, dynamic>{
          'file': MultipartFile.fromBytes(
            bytes,
            filename: 'photo.${format.ext}',
            contentType: DioMediaType.parse(format.mime),
          ),
        }),
      );
      return UploadedImageRef.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}

/// 文件头魔数 → 图片格式；识别不出（含 HEIC/裸 gif）返回 null，
/// 由调用方决定兜底（服务端仍会按魔数给出权威 415）。
ImageFormat? detectImageFormat(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47) {
    return ImageFormat.png;
  }
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
    return ImageFormat.jpg;
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return ImageFormat.webp;
  }
  return null;
}
