import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/financial_account.dart';
import '../../domain/account_ownership.dart';
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
            'id, household_id, name, kind, ownership_type, opening_balance, archived_at, created_at, updated_at, account_holders(user_id, household_members(user_id))',
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

  @override
  Future<void> createAccount({
    required String householdId,
    required Map<String, Object?> values,
    required AccountOwnershipType ownershipType,
    required List<String> holderUserIds,
  }) async {
    try {
      final payload = createAccountWithHoldersRpcParameters(
        householdId: householdId,
        values: values,
        ownershipType: ownershipType,
        holderUserIds: holderUserIds,
      );
      await _client.rpc('create_account_with_holders', params: payload);
    } on Exception catch (error) {
      if (error.toString().contains('23505')) {
        throw Exception('Un compte portant ce nom existe déjà dans le foyer.');
      }
      throw Exception('Impossible de créer le compte : $error');
    }
  }
}

Map<String, Object?> createAccountWithHoldersRpcParameters({
  required String householdId,
  required Map<String, Object?> values,
  required AccountOwnershipType ownershipType,
  required List<String> holderUserIds,
}) => {
  'p_household_id': householdId,
  'p_name': values['name'],
  'p_kind': values['kind'],
  'p_opening_balance': values['opening_balance'],
  'p_archived_at': values['archived_at'],
  'p_ownership_type': ownershipType.name,
  'p_holder_user_ids': List<String>.unmodifiable(holderUserIds),
};

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
