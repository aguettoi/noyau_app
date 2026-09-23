import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import '../../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../../savings_goals/domain/savings_goal.dart';
import '../../domain/shopping_item.dart';

abstract interface class ShoppingListGateway {
  Future<List<ShoppingItem>> fetchItems(String householdId);
  Future<List<ShoppingMemberPriority>> fetchMemberPriorities(
    String householdId,
  );
  Future<List<ShoppingItemHistoryEntry>> fetchHistory(
    String householdId,
    String itemId,
  );
  Future<String> create(String householdId, ShoppingItemDraft draft);
  Future<void> update(
    String householdId,
    String itemId,
    ShoppingItemDraft draft,
  );
  Future<void> setMyPriority(String householdId, String itemId, int priority);
  Future<void> cancel(String householdId, String itemId, String? reason);
  Future<void> archive(String householdId, String itemId, String? reason);
}

class SupabaseShoppingListGateway implements ShoppingListGateway {
  SupabaseShoppingListGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ShoppingItem>> fetchItems(String householdId) async {
    final rows = await _client
        .from('shopping_items')
        .select(
          'id, household_id, label, estimated_amount, notes, desired_date, status, envelope_id, budget_goal_id, final_priority, final_priority_set_by, final_priority_set_at, created_by, created_at, updated_by, updated_at, cancelled_by, cancelled_at, cancellation_reason, archived_by, archived_at',
        )
        .eq('household_id', householdId)
        .order('final_priority')
        .order('desired_date')
        .order('created_at');
    return List.unmodifiable(
      (rows as List<dynamic>)
          .map((row) => _item(Map<String, Object?>.from(row as Map)))
          .toList(growable: false),
    );
  }

  @override
  Future<List<ShoppingMemberPriority>> fetchMemberPriorities(
    String householdId,
  ) async {
    final rows = await _client
        .from('shopping_item_member_priorities')
        .select('shopping_item_id, member_user_id, priority')
        .eq('household_id', householdId);
    final values = (rows as List<dynamic>)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
    final ids = values
        .map((row) => row['member_user_id'] as String)
        .toSet()
        .toList(growable: false);
    final names = await _profileNames(ids);
    return List.unmodifiable(
      values
          .map(
            (row) => ShoppingMemberPriority(
              itemId: row['shopping_item_id'] as String,
              memberUserId: row['member_user_id'] as String,
              priority: row['priority'] as int,
              memberName:
                  names[row['member_user_id'] as String] ??
                  'Utilisateur inconnu',
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<List<ShoppingItemHistoryEntry>> fetchHistory(
    String householdId,
    String itemId,
  ) async {
    final rows = await _client
        .from('shopping_item_history')
        .select('id, action, reason, actor_id, created_at')
        .eq('household_id', householdId)
        .eq('shopping_item_id', itemId)
        .order('created_at', ascending: false);
    final values = (rows as List<dynamic>)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
    final names = await _profileNames(
      values.map((row) => row['actor_id'] as String).toSet().toList(),
    );
    return List.unmodifiable(
      values
          .map(
            (row) => ShoppingItemHistoryEntry(
              id: row['id'] as String,
              action: row['action'] as String,
              actorId: row['actor_id'] as String,
              actorName:
                  names[row['actor_id'] as String] ?? 'Utilisateur inconnu',
              createdAt: DateTime.parse(row['created_at'] as String),
              reason: row['reason'] as String?,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<Map<String, String>> _profileNames(List<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', ids);
      return {
        for (final row in rows as List<dynamic>)
          if ((row as Map)['display_name']?.toString().trim().isNotEmpty ??
              false)
            row['id'] as String: row['display_name'] as String,
      };
    } on Object {
      return const {};
    }
  }

  @override
  Future<String> create(String householdId, ShoppingItemDraft draft) async {
    final value = await _client.rpc(
      'create_shopping_item_with_member_priorities',
      params: _draftParams(householdId, draft),
    );
    if (value is! String || value.isEmpty) {
      throw StateError(
        'La création de l’article n’a retourné aucun identifiant.',
      );
    }
    return value;
  }

  @override
  Future<void> update(
    String householdId,
    String itemId,
    ShoppingItemDraft draft,
  ) => _client.rpc(
    'update_shopping_item_with_member_priorities',
    params: {..._draftParams(householdId, draft), 'p_item_id': itemId},
  );

  @override
  Future<void> setMyPriority(
    String householdId,
    String itemId,
    int priority,
  ) async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) throw StateError('Utilisateur non authentifié.');
    await _client.rpc(
      'set_shopping_item_member_priority',
      params: {
        'p_household_id': householdId,
        'p_item_id': itemId,
        'p_member_user_id': actor,
        'p_priority': priority,
      },
    );
  }

  @override
  Future<void> cancel(String householdId, String itemId, String? reason) =>
      _client.rpc(
        'cancel_shopping_item',
        params: {
          'p_household_id': householdId,
          'p_item_id': itemId,
          'p_reason': _optional(reason),
        },
      );

  @override
  Future<void> archive(String householdId, String itemId, String? reason) =>
      _client.rpc(
        'archive_shopping_item',
        params: {
          'p_household_id': householdId,
          'p_item_id': itemId,
          'p_reason': _optional(reason),
        },
      );
}

Map<String, Object?> _draftParams(
  String householdId,
  ShoppingItemDraft draft,
) => {
  'p_household_id': householdId,
  'p_label': draft.label.trim(),
  'p_estimated_amount': draft.estimatedAmount?.dirhams.toStringAsFixed(2),
  'p_notes': _optional(draft.notes),
  'p_desired_date': draft.desiredDate?.toIso8601String().split('T').first,
  'p_envelope_id': draft.envelopeId,
  'p_budget_goal_id': draft.budgetGoalId,
  'p_final_priority': draft.finalPriority,
  'p_member_priorities': [
    for (final entry in draft.memberPriorities.entries)
      {'member_user_id': entry.key, 'priority': entry.value},
  ],
};

String? _optional(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

ShoppingItem _item(Map<String, Object?> row) => ShoppingItem(
  id: row['id'] as String,
  householdId: row['household_id'] as String,
  label: row['label'] as String,
  estimatedAmount: row['estimated_amount'] == null
      ? null
      : _money(row['estimated_amount']),
  notes: row['notes'] as String?,
  desiredDate: _date(row['desired_date']),
  status: ShoppingItemStatusLabel.fromDatabase(row['status']),
  envelopeId: row['envelope_id'] as String?,
  budgetGoalId: row['budget_goal_id'] as String?,
  finalPriority: row['final_priority'] as int?,
  finalPrioritySetBy: row['final_priority_set_by'] as String?,
  finalPrioritySetAt: _date(row['final_priority_set_at']),
  createdBy: row['created_by'] as String,
  createdAt: DateTime.parse(row['created_at'] as String),
  updatedBy: row['updated_by'] as String?,
  updatedAt: DateTime.parse(row['updated_at'] as String),
  cancelledBy: row['cancelled_by'] as String?,
  cancelledAt: _date(row['cancelled_at']),
  cancellationReason: row['cancellation_reason'] as String?,
  archivedBy: row['archived_by'] as String?,
  archivedAt: _date(row['archived_at']),
);

DateTime? _date(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

Money _money(Object? value) {
  final match = RegExp(
    r'^(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value.toString());
  if (match == null) throw StateError('Montant Shopping List invalide.');
  return Money.fromMinorUnits(
    int.parse(match.group(1)!) * 100 +
        int.parse((match.group(2) ?? '').padRight(2, '0')),
  );
}

final shoppingListGatewayProvider = Provider<ShoppingListGateway>(
  (ref) => SupabaseShoppingListGateway(ref.watch(supabaseClientProvider)),
);

final shoppingItemsProvider = FutureProvider<List<ShoppingItemView>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final gateway = ref.watch(shoppingListGatewayProvider);
  final results = await Future.wait([
    gateway.fetchItems(householdId),
    gateway.fetchMemberPriorities(householdId),
    ref.watch(remoteEnvelopeHistoryProvider.future),
    ref.watch(savingsGoalsProvider.future),
  ]);
  final items = results[0] as List<ShoppingItem>;
  final priorities = results[1] as List<ShoppingMemberPriority>;
  final envelopes = results[2] as List<RemoteEnvelopeBalance>;
  final goals = results[3] as List<SavingsGoalProgress>;
  final envelopeById = {for (final item in envelopes) item.id: item};
  final goalById = {for (final item in goals) item.goal.id: item};
  return List.unmodifiable(
    items
        .map((item) {
          final envelope = item.envelopeId == null
              ? null
              : envelopeById[item.envelopeId];
          final goal = item.budgetGoalId == null
              ? null
              : goalById[item.budgetGoalId];
          return ShoppingItemView(
            item: item,
            memberPriorities: priorities
                .where((priority) => priority.itemId == item.id)
                .toList(growable: false),
            envelopeName: envelope?.name,
            envelopeBalance: envelope?.balance,
            goalName: goal?.goal.name,
            goalProgress: goal?.progressForIndicator,
          );
        })
        .toList(growable: false),
  );
});

final shoppingItemHistoryProvider =
    FutureProvider.family<List<ShoppingItemHistoryEntry>, String>((
      ref,
      itemId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return ref
          .watch(shoppingListGatewayProvider)
          .fetchHistory(householdId, itemId);
    });

Future<String> createShoppingItem(
  WidgetRef ref,
  ShoppingItemDraft draft,
) async {
  final error = draft.validate();
  if (error != null) throw StateError(error);
  final household = await ref.read(activeHouseholdProvider.future);
  final id = await ref
      .read(shoppingListGatewayProvider)
      .create(household.householdId!, draft);
  ref.invalidate(shoppingItemsProvider);
  return id;
}

Future<void> updateShoppingItem(
  WidgetRef ref,
  String itemId,
  ShoppingItemDraft draft,
) async {
  final error = draft.validate();
  if (error != null) throw StateError(error);
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(shoppingListGatewayProvider)
      .update(household.householdId!, itemId, draft);
  ref.invalidate(shoppingItemsProvider);
  ref.invalidate(shoppingItemHistoryProvider(itemId));
}

Future<void> setMyShoppingPriority(
  WidgetRef ref,
  String itemId,
  int priority,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(shoppingListGatewayProvider)
      .setMyPriority(household.householdId!, itemId, priority);
  ref.invalidate(shoppingItemsProvider);
  ref.invalidate(shoppingItemHistoryProvider(itemId));
}

Future<void> cancelShoppingItem(
  WidgetRef ref,
  String itemId,
  String? reason,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(shoppingListGatewayProvider)
      .cancel(household.householdId!, itemId, reason);
  ref.invalidate(shoppingItemsProvider);
  ref.invalidate(shoppingItemHistoryProvider(itemId));
}

Future<void> archiveShoppingItem(
  WidgetRef ref,
  String itemId,
  String? reason,
) async {
  final household = await ref.read(activeHouseholdProvider.future);
  await ref
      .read(shoppingListGatewayProvider)
      .archive(household.householdId!, itemId, reason);
  ref.invalidate(shoppingItemsProvider);
  ref.invalidate(shoppingItemHistoryProvider(itemId));
}
