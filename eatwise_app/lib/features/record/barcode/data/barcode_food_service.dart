import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:eatwise/core/network/api_exception.dart';
import 'package:eatwise/core/storage/database.dart';

/// 条码查询结果（三态：命中 / 未收录 / 查询不可用）。
sealed class BarcodeLookupOutcome {
  const BarcodeLookupOutcome();
}

/// 命中：OFF 商品已合入本地食物缓存（离线后仍可选中入账）。
final class BarcodeLookupHit extends BarcodeLookupOutcome {
  const BarcodeLookupHit(this.food);

  /// 本地 Foods 行（id=off_{code}）。
  final Food food;
}

/// 服务端 404 FOOD_BARCODE_NOT_FOUND：未收录，UI 走双动作承接。
final class BarcodeLookupNotFound extends BarcodeLookupOutcome {
  const BarcodeLookupNotFound();
}

/// 网络/超时/5xx：提示后重试（不误判为「未收录」）。
final class BarcodeLookupUnavailable extends BarcodeLookupOutcome {
  const BarcodeLookupUnavailable(this.error);

  /// 原始领域异常；上屏文案由流程层经 apiErrorDisplayMessage 解析
  /// （业务错误用服务端本地化 message，网络/超时走本地 i18n 兜底，D-15）。
  final ApiException error;
}

/// 条码查询服务抽象（测试 override 为 fake）。
abstract interface class BarcodeFoodService {
  /// 按条码查包装食品（条码合法性由调用方先校验）。
  Future<BarcodeLookupOutcome> lookup(String code);
}

/// 远端实现：GET /foods/barcode/{code}（服务端代理 Open Food Facts）。
/// 命中项 upsert 进本地 Foods 缓存（与 RemoteFoodSearch 同一映射口径）。
final class RemoteBarcodeFoodService implements BarcodeFoodService {
  RemoteBarcodeFoodService({required this.dio, required this.db});

  /// 已装配 dio。
  final Dio dio;

  /// 本地库。
  final AppDatabase db;

  static const String endpoint = '/foods/barcode';

  @override
  Future<BarcodeLookupOutcome> lookup(String code) async {
    final Map<String, dynamic> item;
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$endpoint/${Uri.encodeComponent(code.trim())}',
      );
      item = response.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      final api = toApiException(e);
      if (api.code == 'FOOD_BARCODE_NOT_FOUND') {
        return const BarcodeLookupNotFound();
      }
      return BarcodeLookupUnavailable(api);
    }
    final id = item['id'] as String?;
    if (id == null) return const BarcodeLookupNotFound();
    await db.foodDao.upsertAll(<FoodsCompanion>[_toCompanion(item)]);
    final food = await db.foodDao.getById(id);
    if (food == null) return const BarcodeLookupNotFound();
    return BarcodeLookupHit(food);
  }

  /// 条码命中项 → Foods 行（与 K1 搜索合入缓存同构；服务端无 aliases 时给空）。
  FoodsCompanion _toCompanion(Map<String, dynamic> item) {
    return FoodsCompanion(
      id: Value(item['id']! as String),
      nameZh: Value(item['nameZh']! as String),
      nameEn: Value(item['nameEn']! as String),
      aliasesZh: const Value('[]'),
      kcalPer100g: Value((item['kcalPer100g'] as num?)?.toDouble() ?? 0),
      proteinPer100g: Value((item['proteinPer100g'] as num?)?.toDouble() ?? 0),
      carbPer100g: Value((item['carbsPer100g'] as num?)?.toDouble() ?? 0),
      fatPer100g: Value((item['fatPer100g'] as num?)?.toDouble() ?? 0),
      isCustom: const Value(false),
    );
  }
}
