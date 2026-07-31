import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/record/barcode/data/barcode_food_service.dart';
import 'package:eatwise/features/record/barcode/data/barcode_scanner_gateway.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 扫码入口（生产 mobile_scanner；测试 override 为 fake）。
final Provider<BarcodeScannerGateway> barcodeScannerGatewayProvider =
    Provider<BarcodeScannerGateway>((ref) => MobileScannerBarcodeGateway());

/// 条码查询服务（生产远端 OFF 代理端点；测试 override 为 fake）。
final Provider<BarcodeFoodService> barcodeFoodServiceProvider =
    Provider<BarcodeFoodService>((ref) {
      return RemoteBarcodeFoodService(
        dio: ref.watch(apiDioProvider),
        db: ref.watch(recordRepositoryProvider).db,
      );
    });
