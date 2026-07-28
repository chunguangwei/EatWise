import 'package:eatwise/core/storage/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 本地数据库实例（drift，D-17）。
///
/// 默认抛 [UnimplementedError]：真实实例由集成方在启动时 override 为
/// `await AppDatabase.open()`（异步建库 + SQLCipher executor 接入点，
/// 《规格-数据同步与四态持久化》§7.2）；测试 override 为 `AppDatabase.memory()`。
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider 需在集成时 override 为 AppDatabase.open() 实例',
  );
});
