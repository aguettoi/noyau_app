import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money/money.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

/// A real-world observation is evidence only: it never changes the ledger.
class AccountBalanceObservation {
  const AccountBalanceObservation({
    required this.id,
    required this.accountId,
    required this.actualBalance,
    required this.observedAt,
    required this.reason,
    required this.actorId,
    required this.actorName,
    required this.createdAt,
    this.theoreticalBalanceSnapshot,
    this.differenceSnapshot,
    this.status,
    this.remainingDifference,
  });

  final String id;
  final String accountId;
  final Money actualBalance;
  final DateTime observedAt;
  final String reason;
  final String actorId;
  final String actorName;
  final DateTime createdAt;
  final Money? theoreticalBalanceSnapshot;
  final Money? differenceSnapshot;
  final String? status;
  final Money? remainingDifference;
}

class AccountReconciliationResolution {
  const AccountReconciliationResolution({
    required this.id,
    required this.kind,
    required this.effectiveAmount,
    required this.comment,
    required this.createdAt,
    required this.actorName,
    this.financialEventId,
    this.followUpObservationId,
  });
  final String id;
  final String kind;
  final Money effectiveAmount;
  final String comment;
  final DateTime createdAt;
  final String actorName;
  final String? financialEventId;
  final String? followUpObservationId;
}

class AccountReconciliationCase {
  const AccountReconciliationCase({
    required this.observation,
    required this.status,
    required this.remainingDifference,
    required this.resolutions,
  });
  final AccountBalanceObservation observation;
  final String status;
  final Money? remainingDifference;
  final List<AccountReconciliationResolution> resolutions;
}

abstract interface class AccountBalanceObservationGateway {
  Future<AccountBalanceObservation?> fetchLatest({
    required String householdId,
    required String accountId,
  });

  Future<void> record({
    required String accountId,
    required DateTime observedAt,
    required Money actualBalance,
    required String reason,
  });

  Future<List<AccountReconciliationCase>> fetchHistory({
    required String householdId,
    required String accountId,
  });

  Future<void> explain({
    required String observationId,
    required String kind,
    required String comment,
    required String idempotencyKey,
  });

  Future<void> linkFinancialEvent({
    required String observationId,
    required String financialEventId,
    required String comment,
    required String idempotencyKey,
  });

  Future<void> resolveByFollowUp({
    required String observationId,
    required String followUpObservationId,
    required String comment,
    required String idempotencyKey,
  });
}

class SupabaseAccountBalanceObservationGateway
    implements AccountBalanceObservationGateway {
  SupabaseAccountBalanceObservationGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<AccountBalanceObservation?> fetchLatest({
    required String householdId,
    required String accountId,
  }) async {
    final rows = await _client
        .from('account_balance_observations')
        .select(
          'id, account_id, actual_balance, observed_at, reason, created_by, created_at, theoretical_balance_snapshot, difference_snapshot, snapshot_version',
        )
        .eq('household_id', householdId)
        .eq('account_id', accountId)
        .order('observed_at', ascending: false)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;

    final row = Map<String, Object?>.from(rows.single as Map);
    final caseRows = await _client
        .from('account_reconciliation_cases')
        .select('remaining_difference, status')
        .eq('observation_id', row['id'] as String)
        .limit(1);
    final caseRow = caseRows.isEmpty
        ? null
        : Map<String, Object?>.from(caseRows.single as Map);
    final actorId = row['created_by'] as String;
    var actorName = 'Utilisateur inconnu';
    try {
      final profiles = await _client
          .from('profiles')
          .select('id, display_name')
          .eq('id', actorId)
          .limit(1);
      if (profiles.isNotEmpty) {
        final profile = Map<String, Object?>.from(profiles.single as Map);
        final name = profile['display_name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          actorName = name;
        }
      }
    } on Object {
      // An observation remains readable even if its historical profile is gone.
    }

    return AccountBalanceObservation(
      id: row['id'] as String,
      accountId: row['account_id'] as String,
      actualBalance: _money(row['actual_balance']),
      observedAt: DateTime.parse(row['observed_at'] as String),
      reason: row['reason'] as String,
      actorId: actorId,
      actorName: actorName,
      createdAt: DateTime.parse(row['created_at'] as String),
      theoreticalBalanceSnapshot: row['theoretical_balance_snapshot'] == null
          ? null
          : _money(row['theoretical_balance_snapshot']),
      differenceSnapshot: row['difference_snapshot'] == null
          ? null
          : _money(row['difference_snapshot']),
      remainingDifference: caseRow == null
          ? null
          : _money(caseRow['remaining_difference']),
      status: caseRow?['status'] as String?,
    );
  }

  @override
  Future<List<AccountReconciliationCase>> fetchHistory({
    required String householdId,
    required String accountId,
  }) async {
    final rows = await _client
        .from('account_balance_observations')
        .select(
          'id, account_id, actual_balance, observed_at, reason, created_by, created_at, theoretical_balance_snapshot, difference_snapshot',
        )
        .eq('household_id', householdId)
        .eq('account_id', accountId)
        .order('observed_at', ascending: false)
        .order('created_at', ascending: false);
    final cases = await _client
        .from('account_reconciliation_cases')
        .select('observation_id, status, remaining_difference')
        .eq('household_id', householdId)
        .eq('account_id', accountId);
    final caseById = {
      for (final raw in cases as List<dynamic>)
        (raw as Map)['observation_id'] as String: Map<String, Object?>.from(
          raw,
        ),
    };
    final resolutionRows = await _client
        .from('account_reconciliation_resolutions')
        .select(
          'id, observation_id, resolution_kind, effective_amount, comment, financial_event_id, follow_up_observation_id, created_by, created_at',
        )
        .eq('household_id', householdId)
        .eq('account_id', accountId)
        .order('created_at');
    final profiles = <String, String>{};
    final actorIds = <String>{
      for (final raw in rows as List<dynamic>)
        (raw as Map)['created_by'] as String,
      for (final raw in resolutionRows as List<dynamic>)
        (raw as Map)['created_by'] as String,
    };
    if (actorIds.isNotEmpty) {
      final profileRows = await _client
          .from('profiles')
          .select('id, display_name')
          .inFilter('id', actorIds.toList());
      for (final raw in profileRows as List<dynamic>) {
        final profile = raw as Map;
        profiles[profile['id'] as String] =
            (profile['display_name']?.toString().trim().isNotEmpty ?? false)
            ? profile['display_name'].toString().trim()
            : 'Utilisateur inconnu';
      }
    }
    final byObservation = <String, List<AccountReconciliationResolution>>{};
    for (final raw in resolutionRows as List<dynamic>) {
      final row = Map<String, Object?>.from(raw as Map);
      (byObservation[row['observation_id'] as String] ??= []).add(
        AccountReconciliationResolution(
          id: row['id'] as String,
          kind: row['resolution_kind'] as String,
          effectiveAmount: _money(row['effective_amount']),
          comment: row['comment'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          actorName:
              profiles[row['created_by'] as String] ?? 'Utilisateur inconnu',
          financialEventId: row['financial_event_id'] as String?,
          followUpObservationId: row['follow_up_observation_id'] as String?,
        ),
      );
    }
    return List.unmodifiable(
      (rows as List<dynamic>).map((raw) {
        final row = Map<String, Object?>.from(raw as Map);
        final id = row['id'] as String;
        final c = caseById[id];
        final observation = AccountBalanceObservation(
          id: id,
          accountId: row['account_id'] as String,
          actualBalance: _money(row['actual_balance']),
          observedAt: DateTime.parse(row['observed_at'] as String),
          reason: row['reason'] as String,
          actorId: row['created_by'] as String,
          actorName:
              profiles[row['created_by'] as String] ?? 'Utilisateur inconnu',
          createdAt: DateTime.parse(row['created_at'] as String),
          theoreticalBalanceSnapshot:
              row['theoretical_balance_snapshot'] == null
              ? null
              : _money(row['theoretical_balance_snapshot']),
          differenceSnapshot: row['difference_snapshot'] == null
              ? null
              : _money(row['difference_snapshot']),
          status: c?['status'] as String?,
          remainingDifference: c == null
              ? null
              : _money(c['remaining_difference']),
        );
        return AccountReconciliationCase(
          observation: observation,
          status: c?['status'] as String? ?? 'legacy_unfrozen',
          remainingDifference: c == null
              ? null
              : _money(c['remaining_difference']),
          resolutions: List.unmodifiable(byObservation[id] ?? const []),
        );
      }).toList(),
    );
  }

  @override
  Future<void> explain({
    required String observationId,
    required String kind,
    required String comment,
    required String idempotencyKey,
  }) => _client.rpc(
    'add_account_reconciliation_explanation',
    params: {
      'p_observation_id': observationId,
      'p_kind': kind,
      'p_comment': comment.trim(),
      'p_idempotency_key': idempotencyKey,
    },
  );

  @override
  Future<void> linkFinancialEvent({
    required String observationId,
    required String financialEventId,
    required String comment,
    required String idempotencyKey,
  }) => _client.rpc(
    'link_account_reconciliation_financial_event',
    params: {
      'p_observation_id': observationId,
      'p_financial_event_id': financialEventId,
      'p_comment': comment.trim(),
      'p_idempotency_key': idempotencyKey,
    },
  );

  @override
  Future<void> resolveByFollowUp({
    required String observationId,
    required String followUpObservationId,
    required String comment,
    required String idempotencyKey,
  }) => _client.rpc(
    'resolve_account_reconciliation_by_follow_up',
    params: {
      'p_observation_id': observationId,
      'p_follow_up_observation_id': followUpObservationId,
      'p_comment': comment.trim(),
      'p_idempotency_key': idempotencyKey,
    },
  );

  @override
  Future<void> record({
    required String accountId,
    required DateTime observedAt,
    required Money actualBalance,
    required String reason,
  }) async {
    await _client.rpc(
      'record_account_balance_observation',
      params: {
        'p_account_id': accountId,
        'p_observed_at': observedAt.toUtc().toIso8601String(),
        'p_actual_balance': actualBalance.dirhams.toStringAsFixed(2),
        'p_reason': reason.trim(),
      },
    );
  }
}

final accountBalanceObservationGatewayProvider =
    Provider<AccountBalanceObservationGateway>(
      (ref) => SupabaseAccountBalanceObservationGateway(
        ref.watch(supabaseClientProvider),
      ),
    );

final latestAccountBalanceObservationProvider =
    FutureProvider.family<AccountBalanceObservation?, String>((
      ref,
      accountId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return ref
          .watch(accountBalanceObservationGatewayProvider)
          .fetchLatest(householdId: householdId, accountId: accountId);
    });

final accountReconciliationHistoryProvider =
    FutureProvider.family<List<AccountReconciliationCase>, String>((
      ref,
      accountId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final id = household.householdId;
      if (!household.hasActiveHousehold || id == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return ref
          .watch(accountBalanceObservationGatewayProvider)
          .fetchHistory(householdId: id, accountId: accountId);
    });

final recordAccountBalanceObservationProvider =
    Provider<
      Future<void> Function({
        required String accountId,
        required DateTime observedAt,
        required Money actualBalance,
        required String reason,
      })
    >((ref) {
      return ({
        required String accountId,
        required DateTime observedAt,
        required Money actualBalance,
        required String reason,
      }) async {
        if (reason.trim().isEmpty || reason.trim().length > 280) {
          throw StateError(
            'Le commentaire doit contenir entre 1 et 280 caractères.',
          );
        }
        await ref
            .read(accountBalanceObservationGatewayProvider)
            .record(
              accountId: accountId,
              observedAt: observedAt,
              actualBalance: actualBalance,
              reason: reason,
            );
        ref.invalidate(latestAccountBalanceObservationProvider(accountId));
        ref.invalidate(accountReconciliationHistoryProvider(accountId));
      };
    });

final addAccountReconciliationExplanationProvider =
    Provider<
      Future<void> Function({
        required String accountId,
        required String observationId,
        required String kind,
        required String comment,
        required String idempotencyKey,
      })
    >(
      (ref) =>
          ({
            required accountId,
            required observationId,
            required kind,
            required comment,
            required idempotencyKey,
          }) async {
            await ref
                .read(accountBalanceObservationGatewayProvider)
                .explain(
                  observationId: observationId,
                  kind: kind,
                  comment: comment,
                  idempotencyKey: idempotencyKey,
                );
            ref.invalidate(latestAccountBalanceObservationProvider(accountId));
            ref.invalidate(accountReconciliationHistoryProvider(accountId));
          },
    );

final linkAccountReconciliationFinancialEventProvider =
    Provider<
      Future<void> Function({
        required String accountId,
        required String observationId,
        required String financialEventId,
        required String comment,
        required String idempotencyKey,
      })
    >(
      (ref) =>
          ({
            required accountId,
            required observationId,
            required financialEventId,
            required comment,
            required idempotencyKey,
          }) async {
            await ref
                .read(accountBalanceObservationGatewayProvider)
                .linkFinancialEvent(
                  observationId: observationId,
                  financialEventId: financialEventId,
                  comment: comment,
                  idempotencyKey: idempotencyKey,
                );
            ref.invalidate(latestAccountBalanceObservationProvider(accountId));
            ref.invalidate(accountReconciliationHistoryProvider(accountId));
          },
    );

final resolveAccountReconciliationFollowUpProvider =
    Provider<
      Future<void> Function({
        required String accountId,
        required String observationId,
        required String followUpObservationId,
        required String comment,
        required String idempotencyKey,
      })
    >(
      (ref) =>
          ({
            required accountId,
            required observationId,
            required followUpObservationId,
            required comment,
            required idempotencyKey,
          }) async {
            await ref
                .read(accountBalanceObservationGatewayProvider)
                .resolveByFollowUp(
                  observationId: observationId,
                  followUpObservationId: followUpObservationId,
                  comment: comment,
                  idempotencyKey: idempotencyKey,
                );
            ref.invalidate(latestAccountBalanceObservationProvider(accountId));
            ref.invalidate(accountReconciliationHistoryProvider(accountId));
          },
    );

Money _money(Object? value) {
  final match = RegExp(
    r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value?.toString().trim() ?? '');
  if (match == null) throw StateError('Le solde réel est invalide.');
  final decimals = (match.group(3) ?? '').padRight(2, '0');
  final cents =
      int.parse(match.group(2)!) * 100 +
      (decimals.isEmpty ? 0 : int.parse(decimals));
  return Money.fromMinorUnits(match.group(1) == '-' ? -cents : cents);
}
