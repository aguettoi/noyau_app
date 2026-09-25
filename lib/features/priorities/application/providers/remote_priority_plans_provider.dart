import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../../savings_goals/domain/savings_goal.dart';
import '../../../shopping_list/application/providers/remote_shopping_list_provider.dart';
import '../../../shopping_list/domain/shopping_item.dart';
import '../../domain/priority_plan.dart';

abstract interface class PriorityPlansGateway {
  Future<List<PriorityPlan>> fetchPlans(String householdId);
  Future<List<PriorityPlanItem>> fetchItems(String householdId);
  Future<String> create(String householdId, PriorityPlanDraft draft);
  Future<void> update(
    String householdId,
    String planId,
    PriorityPlanDraft draft,
  );
  Future<void> setStatus(
    String householdId,
    String planId,
    PriorityPlanStatus status,
  );
  Future<void> activate(String householdId, String planId);
  Future<String> addItem(
    String householdId,
    String planId,
    PrioritySourceType sourceType,
    String sourceId,
  );
  Future<void> removeItem(String householdId, String planId, String itemId);
  Future<void> reorderItems(
    String householdId,
    String planId,
    List<String> itemIds,
  );
}

class SupabasePriorityPlansGateway implements PriorityPlansGateway {
  SupabasePriorityPlansGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<List<PriorityPlan>> fetchPlans(String householdId) async {
    final rows = await _client
        .from('priority_plans')
        .select(
          'id, household_id, name, status, monthly_capacity, notes, created_by, created_at, updated_by, updated_at',
        )
        .eq('household_id', householdId)
        .order('updated_at', ascending: false);
    return List.unmodifiable(
      (rows as List<dynamic>)
          .map((row) => _plan(Map<String, Object?>.from(row as Map)))
          .toList(growable: false),
    );
  }

  @override
  Future<List<PriorityPlanItem>> fetchItems(String householdId) async {
    final rows = await _client
        .from('priority_plan_items')
        .select(
          'id, household_id, plan_id, rank, shopping_item_id, budget_goal_id, created_by, created_at, updated_by, updated_at',
        )
        .eq('household_id', householdId)
        .order('plan_id')
        .order('rank');
    return List.unmodifiable(
      (rows as List<dynamic>)
          .map((row) => _planItem(Map<String, Object?>.from(row as Map)))
          .toList(growable: false),
    );
  }

  @override
  Future<String> create(String householdId, PriorityPlanDraft draft) async {
    final result = await _client.rpc(
      'create_priority_plan',
      params: _draftParams(householdId, draft),
    );
    if (result is! String || result.isEmpty) {
      throw StateError('La création du plan n’a retourné aucun identifiant.');
    }
    return result;
  }

  @override
  Future<void> update(
    String householdId,
    String planId,
    PriorityPlanDraft draft,
  ) => _client.rpc(
    'update_priority_plan',
    params: {..._draftParams(householdId, draft), 'p_plan_id': planId},
  );

  @override
  Future<void> setStatus(
    String householdId,
    String planId,
    PriorityPlanStatus status,
  ) => _client.rpc(
    'set_priority_plan_status',
    params: {
      'p_household_id': householdId,
      'p_plan_id': planId,
      'p_status': status.databaseValue,
    },
  );

  @override
  Future<void> activate(String householdId, String planId) => _client.rpc(
    'activate_priority_plan',
    params: {'p_household_id': householdId, 'p_plan_id': planId},
  );

  @override
  Future<String> addItem(
    String householdId,
    String planId,
    PrioritySourceType sourceType,
    String sourceId,
  ) async {
    final result = await _client.rpc(
      'add_priority_plan_item',
      params: {
        'p_household_id': householdId,
        'p_plan_id': planId,
        'p_shopping_item_id': sourceType == PrioritySourceType.shoppingItem
            ? sourceId
            : null,
        'p_budget_goal_id': sourceType == PrioritySourceType.budgetGoal
            ? sourceId
            : null,
      },
    );
    if (result is! String || result.isEmpty) {
      throw StateError(
        'L’ajout de la priorité n’a retourné aucun identifiant.',
      );
    }
    return result;
  }

  @override
  Future<void> removeItem(String householdId, String planId, String itemId) =>
      _client.rpc(
        'remove_priority_plan_item',
        params: {
          'p_household_id': householdId,
          'p_plan_id': planId,
          'p_item_id': itemId,
        },
      );

  @override
  Future<void> reorderItems(
    String householdId,
    String planId,
    List<String> itemIds,
  ) => _client.rpc(
    'reorder_priority_plan_items',
    params: {
      'p_household_id': householdId,
      'p_plan_id': planId,
      'p_item_ids': itemIds,
    },
  );
}

Map<String, Object?> _draftParams(
  String householdId,
  PriorityPlanDraft draft,
) => {
  'p_household_id': householdId,
  'p_name': draft.name.trim(),
  'p_monthly_capacity': draft.monthlyCapacity?.dirhams.toStringAsFixed(2),
  'p_notes': _optional(draft.notes),
};

String? _optional(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

PriorityPlan _plan(Map<String, Object?> row) => PriorityPlan(
  id: row['id'] as String,
  householdId: row['household_id'] as String,
  name: row['name'] as String,
  status: PriorityPlanStatusLabel.fromDatabase(row['status']),
  monthlyCapacity: row['monthly_capacity'] == null
      ? null
      : _money(row['monthly_capacity']!),
  notes: row['notes'] as String?,
  createdBy: row['created_by'] as String,
  createdAt: DateTime.parse(row['created_at'] as String),
  updatedBy: row['updated_by'] as String?,
  updatedAt: DateTime.parse(row['updated_at'] as String),
);

PriorityPlanItem _planItem(Map<String, Object?> row) {
  final shoppingId = row['shopping_item_id'] as String?;
  final goalId = row['budget_goal_id'] as String?;
  if ((shoppingId == null) == (goalId == null)) {
    throw StateError('La priorité ne référence pas une source valide.');
  }
  return PriorityPlanItem(
    id: row['id'] as String,
    householdId: row['household_id'] as String,
    planId: row['plan_id'] as String,
    rank: row['rank'] as int,
    sourceType: shoppingId == null
        ? PrioritySourceType.budgetGoal
        : PrioritySourceType.shoppingItem,
    sourceId: shoppingId ?? goalId!,
    createdBy: row['created_by'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedBy: row['updated_by'] as String?,
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}

Money _money(Object value) {
  final match = RegExp(
    r'^(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value.toString());
  if (match == null) throw StateError('Montant PRIOS invalide.');
  return Money.fromMinorUnits(
    int.parse(match.group(1)!) * 100 +
        int.parse((match.group(2) ?? '').padRight(2, '0')),
  );
}

final priorityPlansGatewayProvider = Provider<PriorityPlansGateway>(
  (ref) => SupabasePriorityPlansGateway(ref.watch(supabaseClientProvider)),
);

final priorityPlansProvider = FutureProvider<List<PriorityPlanView>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final gateway = ref.watch(priorityPlansGatewayProvider);
  final results = await Future.wait([
    gateway.fetchPlans(householdId),
    gateway.fetchItems(householdId),
    ref.watch(shoppingItemsProvider.future),
    ref.watch(savingsGoalsProvider.future),
  ]);
  final plans = results[0] as List<PriorityPlan>;
  final planItems = results[1] as List<PriorityPlanItem>;
  final shopping = results[2] as List<ShoppingItemView>;
  final goals = results[3] as List<SavingsGoalProgress>;
  final shoppingById = {for (final item in shopping) item.item.id: item};
  final goalsById = {for (final item in goals) item.goal.id: item};

  PrioritySourceSnapshot? snapshotFor(PriorityPlanItem item) {
    if (item.sourceType == PrioritySourceType.shoppingItem) {
      final source = shoppingById[item.sourceId];
      if (source == null) return null;
      final linkedGoal = source.item.budgetGoalId == null
          ? null
          : goalsById[source.item.budgetGoalId!];
      return PrioritySourceSnapshot(
        type: item.sourceType,
        id: source.item.id,
        label: source.item.label,
        status: source.item.status.label,
        estimatedNeed: linkedGoal?.remaining ?? source.item.estimatedAmount,
        date: source.item.desiredDate,
        progress: linkedGoal?.progressForIndicator,
        goalId: source.item.budgetGoalId,
      );
    }
    final source = goalsById[item.sourceId];
    if (source == null) return null;
    return PrioritySourceSnapshot(
      type: item.sourceType,
      id: source.goal.id,
      label: source.goal.name,
      status: source.goal.status.label,
      estimatedNeed: source.remaining,
      date: source.goal.targetDate,
      progress: source.progressForIndicator,
    );
  }

  return List.unmodifiable(
    plans
        .map(
          (plan) => PriorityPlanView(
            plan: plan,
            items: planItems
                .where((item) => item.planId == plan.id)
                .map((item) {
                  final source = snapshotFor(item);
                  return source == null
                      ? null
                      : PriorityPlanItemView(item: item, source: source);
                })
                .whereType<PriorityPlanItemView>()
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
  );
});

Future<void> createPriorityPlan(WidgetRef ref, PriorityPlanDraft draft) async {
  final error = draft.validate();
  if (error != null) throw StateError(error);
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(priorityPlansGatewayProvider)
      .create(household.householdId!, draft);
  ref.invalidate(priorityPlansProvider);
}

Future<void> updatePriorityPlan(
  WidgetRef ref,
  String planId,
  PriorityPlanDraft draft,
) async {
  final error = draft.validate();
  if (error != null) throw StateError(error);
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(priorityPlansGatewayProvider)
      .update(household.householdId!, planId, draft);
  ref.invalidate(priorityPlansProvider);
}

Future<void> setPriorityPlanStatus(
  WidgetRef ref,
  String planId,
  PriorityPlanStatus status,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(priorityPlansGatewayProvider)
      .setStatus(household.householdId!, planId, status);
  ref.invalidate(priorityPlansProvider);
}

/// Makes this plan the household's sole read-only projection reference.
/// The RPC only updates PRIOS metadata and never creates a financial entry.
Future<void> activatePriorityPlan(WidgetRef ref, String planId) async {
  final household = await ref.read(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  await ref.read(priorityPlansGatewayProvider).activate(householdId, planId);
  ref.invalidate(priorityPlansProvider);
}

Future<void> addPriorityPlanItem(
  WidgetRef ref,
  String planId,
  PrioritySourceType sourceType,
  String sourceId,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(priorityPlansGatewayProvider)
      .addItem(household.householdId!, planId, sourceType, sourceId);
  ref.invalidate(priorityPlansProvider);
}

Future<void> removePriorityPlanItem(
  WidgetRef ref,
  String planId,
  String itemId,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(priorityPlansGatewayProvider)
      .removeItem(household.householdId!, planId, itemId);
  ref.invalidate(priorityPlansProvider);
}

Future<void> reorderPriorityPlanItems(
  WidgetRef ref,
  String planId,
  List<String> itemIds,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(priorityPlansGatewayProvider)
      .reorderItems(household.householdId!, planId, itemIds);
  ref.invalidate(priorityPlansProvider);
}
