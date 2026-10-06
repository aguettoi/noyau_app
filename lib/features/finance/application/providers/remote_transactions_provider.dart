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
    String householdId, {
    TransactionHistoryFilter filter = const TransactionHistoryFilter(),
  }) async {
    final response = await _client.rpc(
      'search_financial_event_history',
      params: {
        'p_household_id': householdId,
        'p_query': filter.query,
        'p_from': filter.from?.toUtc().toIso8601String(),
        'p_to': filter.to?.toUtc().toIso8601String(),
        'p_account_id': filter.accountId,
        'p_envelope_id': filter.envelopeId,
        'p_payment_method_id': filter.paymentMethodId,
        'p_event_type': filter.eventType,
        'p_reversal_state': filter.reversalState,
        'p_limit': filter.pageSize,
        'p_offset': filter.page * filter.pageSize,
      },
    );
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

final filteredTransactionsProvider =
    FutureProvider.family<
      List<TransactionHistoryItem>,
      TransactionHistoryFilter
    >((ref, filter) async {
      final household = await ref.watch(activeHouseholdProvider.future);
      if (!household.hasActiveHousehold) {
        throw StateError('Aucun foyer actif sans ambiguïté.');
      }
      return ref
          .watch(transactionsSupabaseRepositoryProvider)
          .all(filter: filter);
    });

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
      return ref
          .watch(transactionsSupabaseRepositoryProvider)
          .all(
            filter: TransactionHistoryFilter(
              accountId: accountId,
              pageSize: 100,
            ),
          );
    });
