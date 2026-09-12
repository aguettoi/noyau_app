import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/transaction_draft.dart';
import '../../domain/transaction_history_item.dart';
import '../../infrastructure/transactions_supabase_repository.dart';
import 'active_household_provider.dart';
import 'supabase_client_provider.dart';

class SupabaseTransactionsGateway implements TransactionsSupabaseGateway {
  SupabaseTransactionsGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> fetchTransactions(
    String householdId,
  ) async {
    final response = await _client
        .from('financial_transactions')
        .select(
          'id, type, occurred_at, description, amount, created_at, envelope_movements(id)',
        )
        .eq('household_id', householdId)
        .isFilter('archived_at', null)
        .order('occurred_at', ascending: false)
        .order('created_at', ascending: false);
    return (response as List<dynamic>)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<String> createLedgerTransaction({
    required Map<String, Object?> parameters,
  }) async {
    final result = await _client.rpc(
      'create_financial_transaction_with_envelopes',
      params: parameters,
    );
    if (result is! String || result.isEmpty) {
      throw StateError(
        'La création de la transaction n’a retourné aucun identifiant.',
      );
    }
    return result;
  }
}

final supabaseTransactionsGatewayProvider =
    Provider<TransactionsSupabaseGateway>(
      (ref) => SupabaseTransactionsGateway(ref.watch(supabaseClientProvider)),
    );

final transactionsSupabaseRepositoryProvider =
    Provider<TransactionsSupabaseRepository>((ref) {
      final household = ref.watch(activeHouseholdProvider).requireValue;
      final householdId = household.householdId;
      if (householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return TransactionsSupabaseRepository(
        gateway: ref.watch(supabaseTransactionsGatewayProvider),
        householdId: householdId,
      );
    });

final remoteTransactionsProvider = FutureProvider<List<TransactionHistoryItem>>(
  (ref) async {
    final household = await ref.watch(activeHouseholdProvider.future);
    if (!household.hasActiveHousehold) {
      throw StateError('Aucun foyer actif sans ambiguïté.');
    }
    return ref.watch(transactionsSupabaseRepositoryProvider).all();
  },
);

final createRemoteTransactionProvider =
    Provider<Future<String> Function(FinancialTransactionDraft draft)>((ref) {
      return (draft) =>
          ref.read(transactionsSupabaseRepositoryProvider).create(draft);
    });

final accountTransactionHistoryProvider =
    FutureProvider.family<List<TransactionHistoryItem>, String>((
      ref,
      accountId,
    ) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      final householdId = household.householdId;
      if (!household.hasActiveHousehold || householdId == null) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      final rows = await ref
          .watch(supabaseClientProvider)
          .from('financial_transactions')
          .select(
            'id, type, occurred_at, description, amount, created_at, envelope_movements(id)',
          )
          .eq('household_id', householdId)
          .or(
            'source_account_id.eq.$accountId,destination_account_id.eq.$accountId',
          )
          .isFilter('archived_at', null)
          .order('occurred_at', ascending: false);
      return List.unmodifiable(
        (rows as List<dynamic>)
            .map(
              (raw) => TransactionsSupabaseRepository.mapRow(
                Map<String, Object?>.from(raw as Map),
              ),
            )
            .toList(growable: false),
      );
    });
