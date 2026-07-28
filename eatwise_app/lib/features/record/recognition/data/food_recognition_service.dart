import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eatwise/features/record/recognition/domain/recognition_models.dart';

/// 拍照识别服务抽象（D-16：MVP 接第三方食物识别 API，
/// 达标线 Top-1 ≥70% / Top-3 ≥90%，未达标降级「拍照→手动搜索」）。
///
/// 实现方须保证**异步不阻塞主流程**：调用方在等待期间可取消，
/// 取消不丢用户已输入内容。
abstract interface class FoodRecognitionService {
  /// 识别一张食物照片，返回候选食物（含默认份量与置信度）或不可用原因。
  ///
  /// [imageBytes] 为 JPEG/PNG 字节；实现方自行压缩/缩放后再上行，
  /// 不识别的照片绝不上传（合规 §3.1 照片条款）。
  Future<RecognitionOutcome> recognize(Uint8List imageBytes);
}

/// 远端识别占位实现（**stub，未接通真实识别**）。
///
/// 〔待外部确认：第三方食物识别 API 选型 M0 定〕——服务端尚无识别端点
/// （契约未含 /foods/recognize），本实现按约定路径 POST multipart，
/// 收到 404/网络错误/超时一律映射为 [RecognitionUnavailable]，
/// 由 UI 走 D-16 一级兜底（手动搜索 + 常吃复用）。
///
/// 诚实性说明：在真实第三方 API 选定并落地服务端端点前，本实现
/// 对任何输入都只会返回 [RecognitionUnavailable]，不会产生伪识别结果。
final class RemoteFoodRecognitionStub implements FoodRecognitionService {
  RemoteFoodRecognitionStub({required this.dio});

  /// 已装配 dio（复用 core/network 的请求头/错误映射）。
  final Dio dio;

  /// 约定端点（服务端未实现，〔待外部确认〕随第三方 API 选型落定）。
  static const String endpoint = '/foods/recognize';

  @override
  Future<RecognitionOutcome> recognize(Uint8List imageBytes) async {
    try {
      await dio.post<Map<String, dynamic>>(
        endpoint,
        data: FormData.fromMap(<String, dynamic>{
          'image': MultipartFile.fromBytes(imageBytes, filename: 'meal.jpg'),
        }),
      );
      // 服务端端点落地前不会走到这里；走到说明契约已变但未实现
      // 响应解析，按不可用处理而不是猜测字段。
      return const RecognitionUnavailable('not_integrated');
    } on DioException catch (e) {
      return RecognitionUnavailable(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => 'timeout',
        DioExceptionType.connectionError ||
        DioExceptionType.unknown => 'network',
        _ => 'server_error',
      });
    }
  }
}
