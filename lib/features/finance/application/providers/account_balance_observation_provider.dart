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
  });

  final String id;
  final String accountId;
  final Money actualBalance;
  final DateTime observedAt;
  final String reason;
  final String actorId;
  final String actorName;
  final DateTime createdAt;
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
          'id, account_id, actual_balance, observed_at, reason, created_by, created_at',
        )
        .eq('household_id', householdId)
        .eq('account_id', accountId)
        .order('observed_at', ascending: false)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;

    final row = Map<String, Object?>.from(rows.single as Map);
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
        if (name.isNotEmpty) actorName = name;
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
    );
  }

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
      };
    });

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
