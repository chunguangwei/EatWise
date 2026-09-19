import 'package:eatwise/features/record/custom_food/domain/contribution_review_logic.dart';
import 'package:eatwise/features/record/custom_food/domain/custom_food_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 贡献审核状态迁移 diff 纯逻辑：pending→approved 转正、pending→rejected
/// 清理+提示；首次见到静默纳入基线（历史终态不当新事件）。
void main() {
  FoodContribution contribution(
    String id,
    FoodContributionStatus status, {
    String? foodId,
  }) {
    return FoodContribution(
      id: id,
      foodId: foodId ?? 'cf-$id',
      status: status,
      reason: status == FoodContributionStatus.rejected ? '营养数据存疑' : null,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 19),
    );
  }

  group('diffContributionTransitions', () {
    test('pending → approved 产出转正迁移', () {
      final transitions = diffContributionTransitions(
        <String, String>{'fc-1': 'pending'},
        <FoodContribution>[
          contribution('fc-1', FoodContributionStatus.approved),
        ],
      );
      expect(transitions, hasLength(1));
      expect(transitions.single.candidateId, 'fc-1');
      expect(transitions.single.foodId, 'cf-fc-1');
      expect(transitions.single.to, FoodContributionStatus.approved);
    });

    test('pending → rejected 产出驳回迁移（触发清理+提示）', () {
      final transitions = diffContributionTransitions(
        <String, String>{'fc-1': 'pending'},
        <FoodContribution>[
          contribution('fc-1', FoodContributionStatus.rejected),
        ],
      );
      expect(transitions.single.to, FoodContributionStatus.rejected);
    });

    test('首次见到的候选静默纳入基线（含历史 rejected/approved），不产迁移', () {
      final transitions =
          diffContributionTransitions(<String, String>{}, <FoodContribution>[
            contribution('fc-1', FoodContributionStatus.rejected),
            contribution('fc-2', FoodContributionStatus.approved),
            contribution('fc-3', FoodContributionStatus.pending),
          ]);
      expect(transitions, isEmpty);
    });

    test('pending → pending / approved → approved 不产迁移；终态起点不再迁移', () {
      final transitions = diffContributionTransitions(
        <String, String>{
          'fc-1': 'pending',
          'fc-2': 'approved',
          'fc-3': 'rejected',
        },
        <FoodContribution>[
          contribution('fc-1', FoodContributionStatus.pending),
          contribution('fc-2', FoodContributionStatus.approved),
          // 防御：终态起点即使服务端再变也不重复触发
          contribution('fc-3', FoodContributionStatus.approved),
        ],
      );
      expect(transitions, isEmpty);
    });

    test('幂等：迁移后已知表落库，下一轮同状态不再产出', () {
      final current = <FoodContribution>[
        contribution('fc-1', FoodContributionStatus.rejected),
      ];
      final first = diffContributionTransitions(<String, String>{
        'fc-1': 'pending',
      }, current);
      expect(first, hasLength(1));
      final second = diffContributionTransitions(
        knownStatusMapOf(current),
        current,
      );
      expect(second, isEmpty);
    });
  });

  group('knownStatusMapOf', () {
    test('全量替换口径：只保留服务端仍返回的候选', () {
      final map = knownStatusMapOf(<FoodContribution>[
        contribution('fc-1', FoodContributionStatus.pending),
        contribution('fc-2', FoodContributionStatus.approved),
      ]);
      expect(map, <String, String>{'fc-1': 'pending', 'fc-2': 'approved'});
    });
  });
}
