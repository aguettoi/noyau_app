import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/financial_account.dart';
import '../../infrastructure/accounts_supabase_repository.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class SupabaseAccountsGateway implements AccountsSupabaseGateway {
  SupabaseAccountsGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> fetchAccounts(String householdId) async {
    try {
      final response = await _client
          .from('accounts')
          .select(
            'id, household_id, name, kind, opening_balance, archived_at, created_at, updated_at',
          )
          .eq('household_id', householdId)
          .order('created_at');
      return (response as List<dynamic>)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList(growable: false);
    } on Exception catch (error) {
      throw Exception('Impossible de charger les comptes : $error');
    }
  }
}

final supabaseAccountsGatewayProvider = Provider<AccountsSupabaseGateway>(
  (ref) => SupabaseAccountsGateway(ref.watch(supabaseClientProvider)),
);

final supabaseAccountsRepositoryProvider = Provider<AccountsSupabaseRepository>(
  (ref) {
    final household = ref.watch(activeHouseholdProvider).requireValue;
    final householdId = household.householdId;
    if (householdId == null) {
      throw StateError('Aucun foyer actif sans ambiguïté.');
    }
    return AccountsSupabaseRepository(
      gateway: ref.watch(supabaseAccountsGatewayProvider),
      householdId: householdId,
    );
  },
);

/// Source distante isolée. Elle ne fusionne jamais les comptes locaux.
final remoteAccountsProvider = FutureProvider<List<FinancialAccount>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  if (!household.hasActiveHousehold) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  return ref.watch(supabaseAccountsRepositoryProvider).all();
});
