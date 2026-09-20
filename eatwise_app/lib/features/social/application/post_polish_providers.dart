import 'package:eatwise/core/llm/ondevice/ondevice_providers.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart'
    show onDeviceRecognitionActive;
import 'package:eatwise/features/record/recognition/data/ondevice_food_recognition_service.dart'
    show normalizeFoodPhoto;
import 'package:eatwise/features/social/application/post_polish_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// AI 润色服务（发布打卡页）：端侧开关开且模型就绪 → Gemma4-E2B
/// 视觉润色；否则 null（UI 隐藏「AI 润色」入口，与营养表 OCR 同口径）。
/// 网关/下载管理器与拍照识别共享单例（引擎单租户）。
final Provider<PostPolishService?> postPolishServiceProvider =
    Provider<PostPolishService?>((ref) {
      if (!onDeviceRecognitionActive(ref)) return null;
      return OnDevicePostPolishService(
        gateway: ref.watch(onDeviceLlmGatewayProvider),
        modelPath: ref.watch(onDeviceModelManagerProvider).modelPath,
        normalizeImage: normalizeFoodPhoto,
      );
    });
