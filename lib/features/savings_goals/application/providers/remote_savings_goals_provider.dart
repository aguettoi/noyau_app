import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import '../../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../../finance/application/providers/active_household_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../domain/savings_goal.dart';

abstract interface class SavingsGoalsGateway {
  Future<List<SavingsGoal>> fetchGoals(String householdId);

  Future<List<SavingsGoalHistoryItem>> fetchHistory(
    String householdId,
    String goalId,
  );

  Future<String> create({
    required String householdId,
    required SavingsGoalDraft draft,
    required SavingsGoalStatus initialStatus,
  });

  Future<void> update({
    required String householdId,
    required String goalId,
    required SavingsGoalDraft draft,
  });

  Future<void> setStatus({
    required String householdId,
    required String goalId,
    required SavingsGoalStatus status,
    String? reason,
  });
}

class SupabaseSavingsGoalsGateway implements SavingsGoalsGateway {
  SupabaseSavingsGoalsGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SavingsGoal>> fetchGoals(String householdId) async {
    final rows = await _client
        .from('budget_goals')
        .select(
          'id, household_id, name, goal_type, target_amount, target_date, priority, status, funding_envelope_id, monthly_target, notes, created_by, created_at, updated_by, updated_at, closed_at, closed_by, closure_reason',
        )
        .eq('household_id', householdId)
        .order('priority')
        .order('created_at');
    return List.unmodifiable(
      (rows as List<dynamic>)
          .map((raw) => _goal(Map<String, Object?>.from(raw as Map)))
          .toList(growable: false),
    );
  }

  @override
  Future<List<SavingsGoalHistoryItem>> fetchHistory(
    String householdId,
    String goalId,
  ) async {
    final rows = await _client
        .from('budget_goal_history')
        .select('id, action, reason, actor_id, created_at')
        .eq('household_id', householdId)
        .eq('goal_id', goalId)
        .order('created_at', ascending: false);
    final items = (rows as List<dynamic>)
        .map((raw) => Map<String, Object?>.from(raw as Map))
        .toList(growable: false);
    final actorIds = items
        .map((item) => item['actor_id'])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final actorNames = <String, String>{};
    if (actorIds.isNotEmpty) {
      try {
        final profiles = await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', actorIds);
        for (final raw in profiles as List<dynamic>) {
          final profile = Map<String, Object?>.from(raw as Map);
          final id = profile['id'] as String?;
          final name = profile['display_name']?.toString().trim() ?? '';
          if (id != null && name.isNotEmpty) actorNames[id] = name;
        }
      } on Object {
        // Goal history stays readable if a historical profile is unavailable.
      }
    }
    return List.unmodifiable(
      items
          .map((item) {
            final actorId = item['actor_id'] as String;
            return SavingsGoalHistoryItem(
              id: item['id'] as String,
              action: item['action'] as String,
              reason: item['reason'] as String?,
              actorId: actorId,
              actorName: actorNames[actorId] ?? 'Utilisateur inconnu',
              createdAt: DateTime.parse(item['created_at'] as String),
            );
          })
          .toList(growable: false),
    );
  }

  @override
  Future<String> create({
    required String householdId,
    required SavingsGoalDraft draft,
    required SavingsGoalStatus initialStatus,
  }) async {
    final result = await _client.rpc(
      'create_budget_goal',
      params: {
        'p_household_id': householdId,
        'p_name': draft.name.trim(),
        'p_goal_type': draft.type.databaseValue,
        'p_target_amount': draft.targetAmount.dirhams.toStringAsFixed(2),
        'p_target_date': draft.targetDate?.toIso8601String().split('T').first,
        'p_priority': draft.priority,
        'p_funding_envelope_id': draft.fundingEnvelopeId,
        'p_monthly_target': draft.monthlyTarget?.dirhams.toStringAsFixed(2),
        'p_notes': _optional(draft.notes),
        'p_status': initialStatus.databaseValue,
      },
    );
    if (result is! String || result.isEmpty) {
      throw StateError(
        'La création de l’objectif n’a retourné aucun identifiant.',
      );
    }
    return result;
  }

  @override
  Future<void> update({
    required String householdId,
    required String goalId,
    required SavingsGoalDraft draft,
  }) => _client.rpc(
    'update_budget_goal',
    params: {
      'p_household_id': householdId,
      'p_goal_id': goalId,
      'p_name': draft.name.trim(),
      'p_goal_type': draft.type.databaseValue,
      'p_target_amount': draft.targetAmount.dirhams.toStringAsFixed(2),
      'p_target_date': draft.targetDate?.toIso8601String().split('T').first,
      'p_priority': draft.priority,
      'p_funding_envelope_id': draft.fundingEnvelopeId,
      'p_monthly_target': draft.monthlyTarget?.dirhams.toStringAsFixed(2),
      'p_notes': _optional(draft.notes),
    },
  );

  @override
  Future<void> setStatus({
    required String householdId,
    required String goalId,
    required SavingsGoalStatus status,
    String? reason,
  }) => _client.rpc(
    'set_budget_goal_status',
    params: {
      'p_household_id': householdId,
      'p_goal_id': goalId,
      'p_status': status.databaseValue,
      'p_reason': _optional(reason),
    },
  );
}

String? _optional(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

SavingsGoal _goal(Map<String, Object?> row) => SavingsGoal(
  id: row['id'] as String,
  householdId: row['household_id'] as String,
  name: row['name'] as String,
  type: SavingsGoalType.fromDatabase(row['goal_type']),
  targetAmount: _money(row['target_amount']),
  targetDate: _date(row['target_date']),
  priority: row['priority'] as int? ?? 0,
  status: SavingsGoalStatusLabel.fromDatabase(row['status']),
  fundingEnvelopeId: row['funding_envelope_id'] as String,
  monthlyTarget: row['monthly_target'] == null
      ? null
      : _money(row['monthly_target']),
  notes: row['notes'] as String?,
  createdBy: row['created_by'] as String,
  createdAt: DateTime.parse(row['created_at'] as String),
  updatedBy: row['updated_by'] as String?,
  updatedAt: DateTime.parse(row['updated_at'] as String),
  closedAt: _dateTime(row['closed_at']),
  closedBy: row['closed_by'] as String?,
  closureReason: row['closure_reason'] as String?,
);

DateTime? _date(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

DateTime? _dateTime(Object? value) => _date(value);

Money _money(Object? value) {
  final match = RegExp(
    r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value?.toString().trim() ?? '');
  if (match == null) throw StateError('Montant d’objectif invalide.');
  final decimals = (match.group(3) ?? '').padRight(2, '0');
  final cents =
      int.parse(match.group(2)!) * 100 +
      (decimals.isEmpty ? 0 : int.parse(decimals));
  return Money.fromMinorUnits(match.group(1) == '-' ? -cents : cents);
}

final savingsGoalsGatewayProvider = Provider<SavingsGoalsGateway>(
  (ref) => SupabaseSavingsGoalsGateway(ref.watch(supabaseClientProvider)),
);

final savingsGoalsProvider = FutureProvider<List<SavingsGoalProgress>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final goals = await ref
      .watch(savingsGoalsGatewayProvider)
      .fetchGoals(householdId);
  final envelopes = await ref.watch(remoteEnvelopeHistoryProvider.future);
  final envelopesById = {
    for (final envelope in envelopes) envelope.id: envelope,
  };
  return List.unmodifiable(
    goals
        .map((goal) {
          final envelope = envelopesById[goal.fundingEnvelopeId];
          return SavingsGoalProgress(
            goal: goal,
            envelopeName: envelope?.name ?? 'Enveloppe indisponible',
            accumulated: envelope?.balance ?? Money.fromMinorUnits(0),
          );
        })
        .toList(growable: false),
  );
});

final savingsGoalHistoryProvider =
    FutureProvider.family<List<SavingsGoalHistoryItem>, String>((
      ref,
      goalId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return ref
          .watch(savingsGoalsGatewayProvider)
          .fetchHistory(householdId, goalId);
    });

final createSavingsGoalProvider =
    Provider<Future<String> Function(SavingsGoalDraft, SavingsGoalStatus)>((
      ref,
    ) {
      return (draft, status) async {
        final error = draft.validate();
        if (error != null) throw StateError(error);
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        final id = await ref
            .read(savingsGoalsGatewayProvider)
            .create(
              householdId: householdId,
              draft: draft,
              initialStatus: status,
            );
        ref.invalidate(savingsGoalsProvider);
        return id;
      };
    });

final updateSavingsGoalProvider =
    Provider<Future<void> Function(String, SavingsGoalDraft)>((ref) {
      return (goalId, draft) async {
        final error = draft.validate();
        if (error != null) throw StateError(error);
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        await ref
            .read(savingsGoalsGatewayProvider)
            .update(householdId: householdId, goalId: goalId, draft: draft);
        ref.invalidate(savingsGoalsProvider);
        ref.invalidate(savingsGoalHistoryProvider(goalId));
      };
    });

final setSavingsGoalStatusProvider =
    Provider<Future<void> Function(String, SavingsGoalStatus, String?)>((ref) {
      return (goalId, status, reason) async {
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        await ref
            .read(savingsGoalsGatewayProvider)
            .setStatus(
              householdId: householdId,
              goalId: goalId,
              status: status,
              reason: reason,
            );
        ref.invalidate(savingsGoalsProvider);
        ref.invalidate(savingsGoalHistoryProvider(goalId));
      };
    });
