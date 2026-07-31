import 'package:eatwise/core/storage/database.dart';
import 'package:eatwise/features/record/barcode/data/barcode_food_service.dart';
import 'package:eatwise/features/record/barcode/data/barcode_scanner_gateway.dart';
import 'package:flutter/widgets.dart';

/// 扫码入口 fake：可配置返回条码 / 用户取消（null）/ 权限拒绝。
final class FakeBarcodeScannerGateway implements BarcodeScannerGateway {
  String? code = '7622210449283';
  bool throwDenied = false;
  int calls = 0;

  @override
  Future<String?> scan(BuildContext context) async {
    calls += 1;
    if (throwDenied) throw const BarcodePermissionDeniedException();
    return code;
  }
}

/// 条码查询 fake：按条码配置结果，记录调用次数（默认未收录）。
final class FakeBarcodeFoodService implements BarcodeFoodService {
  final Map<String, BarcodeLookupOutcome> outcomes =
      <String, BarcodeLookupOutcome>{};
  final List<String> calls = <String>[];

  @override
  Future<BarcodeLookupOutcome> lookup(String code) async {
    calls.add(code);
    return outcomes[code.trim()] ?? const BarcodeLookupNotFound();
  }
}

/// 构造一条条码命中的 Food（OFF 代理口径：id=off_{code}，无双语别名）。
Food barcodeFood({
  String code = '7622210449283',
  String nameZh = '奥利奥原味夹心饼干',
  String nameEn = 'Oreo Original',
}) {
  return Food(
    id: 'off_$code',
    nameZh: nameZh,
    nameEn: nameEn,
    aliasesZh: '[]',
    aliasesEn: '[]',
    kcalPer100g: 480,
    proteinPer100g: 4.7,
    carbPer100g: 68.5,
    fatPer100g: 20.4,
    isCustom: false,
    customSyncPending: false,
    customClientRequestId: '',
  );
}
