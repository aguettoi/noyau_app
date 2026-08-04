import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/import/accounts_supabase_import_repository.dart';
import '../import_execution/accounts_import_executor.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

final accountsSupabaseImportGatewayProvider =
    Provider<AccountsSupabaseImportGateway>(
      (ref) => SupabaseAccountsImportGateway(ref.watch(supabaseClientProvider)),
    );

/// Construit le moteur uniquement quand le foyer actif est non ambigu.
final accountsImportExecutorProvider = Provider<AccountsImportExecutor>((ref) {
  final household = ref.watch(activeHouseholdProvider).requireValue;
  final householdId = household.householdId;
  if (householdId == null) {
    throw StateError('Aucun foyer actif sans ambiguïté.');
  }
  final repository = AccountsSupabaseImportRepository(
    gateway: ref.watch(accountsSupabaseImportGatewayProvider),
    householdId: householdId,
  );
  return AccountsImportExecutor(runTransaction: repository.runTransaction);
});
