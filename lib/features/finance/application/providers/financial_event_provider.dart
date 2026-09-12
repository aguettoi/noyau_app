import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../infrastructure/financial_event_supabase_repository.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class SupabaseFinancialEventGateway implements FinancialEventSupabaseGateway {
  SupabaseFinancialEventGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Object?> call(String function, Map<String, Object?> parameters) =>
      _client.rpc(function, params: parameters);
}

final financialEventGatewayProvider = Provider<FinancialEventSupabaseGateway>(
  (ref) => SupabaseFinancialEventGateway(ref.watch(supabaseClientProvider)),
);

final financialEventRepositoryProvider =
    FutureProvider<FinancialEventSupabaseRepository>((ref) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return FinancialEventSupabaseRepository(
        gateway: ref.watch(financialEventGatewayProvider),
        householdId: householdId,
      );
    });
