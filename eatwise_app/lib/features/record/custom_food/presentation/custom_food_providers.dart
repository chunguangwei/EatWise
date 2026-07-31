import 'package:eatwise/core/network/network_providers.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_remote.dart';
import 'package:eatwise/features/record/custom_food/data/custom_food_repository.dart';
import 'package:eatwise/features/record/presentation/record_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自定义食物远程端（生产 REST；测试 override 为 FakeCustomFoodRemote）。
final Provider<CustomFoodRemote> customFoodRemoteProvider =
    Provider<CustomFoodRemote>((ref) {
      return RemoteCustomFoodApi(dio: ref.watch(apiDioProvider));
    });

/// 自定义食物仓储（远端直调 + 本地 drift 落库，离线 pending 重试）。
final Provider<CustomFoodRepository> customFoodRepositoryProvider =
    Provider<CustomFoodRepository>((ref) {
      return CustomFoodRepository(
        db: ref.watch(recordRepositoryProvider).db,
        remote: ref.watch(customFoodRemoteProvider),
      );
    });
