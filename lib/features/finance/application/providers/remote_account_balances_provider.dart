import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/money/money.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

abstract interface class AccountLedgerBalancesGateway {
  Future<List<Map<String, Object?>>> fetchTheoreticalBalances(
    String householdId,
  );
}

class SupabaseAccountLedgerBalancesGateway
    implements AccountLedgerBalancesGateway {
  SupabaseAccountLedgerBalancesGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> fetchTheoreticalBalances(
    String householdId,
  ) async {
    final rows = await _client
        .from('account_ledger_balances')
        .select('account_id, theoretical_balance')
        .eq('household_id', householdId);
    return (rows as List<dynamic>)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }
}

final accountLedgerBalancesGatewayProvider =
    Provider<AccountLedgerBalancesGateway>(
      (ref) => SupabaseAccountLedgerBalancesGateway(
        ref.watch(supabaseClientProvider),
      ),
    );

/// The theoretical balance is read from the ledger view; it is never persisted
/// by Flutter as a mutable account value.
final remoteAccountBalancesProvider = FutureProvider<Map<String, Money>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final householdId = household.householdId;
  if (!household.hasActiveHousehold || householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final rows = await ref
      .watch(accountLedgerBalancesGatewayProvider)
      .fetchTheoreticalBalances(householdId);
  return Map.unmodifiable({
    for (final raw in rows)
      raw['account_id'] as String: _moneyFromSql(raw['theoretical_balance']),
  });
});

Money _moneyFromSql(Object? value) {
  final match = RegExp(
    r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
  ).firstMatch(value?.toString().trim() ?? '');
  if (match == null) throw StateError('Le solde théorique est invalide.');
  final whole = int.parse(match.group(2)!);
  final decimals = (match.group(3) ?? '').padRight(2, '0');
  final cents = whole * 100 + (decimals.isEmpty ? 0 : int.parse(decimals));
  return Money.fromMinorUnits(match.group(1) == '-' ? -cents : cents);
}
