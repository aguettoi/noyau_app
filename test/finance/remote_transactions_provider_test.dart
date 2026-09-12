import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/infrastructure/transactions_supabase_repository.dart';

void main() {
  test(
    'le provider lit exclusivement le repository distant du foyer actif',
    () async {
      final gateway = _Gateway();
      final container = ProviderContainer(
        overrides: [
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: 'home-1',
            ),
          ),
          supabaseTransactionsGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      final transactions = await container.read(
        remoteTransactionsProvider.future,
      );

      expect(gateway.householdId, 'home-1');
      expect(transactions.single.description, 'Salaire');
    },
  );
}

class _Gateway implements TransactionsSupabaseGateway {
  String? householdId;

  @override
  Future<String> createLedgerTransaction({
    required Map<String, Object?> parameters,
  }) async => 'unused';

  @override
  Future<List<Map<String, Object?>>> fetchTransactions(
    String householdId,
  ) async {
    this.householdId = householdId;
    return [
      {
        'id': 'tx-1',
        'type': LedgerTransactionType.income.name,
        'occurred_at': '2026-08-05T10:00:00Z',
        'description': 'Salaire',
        'amount': '100.00',
        'created_at': '2026-08-05T10:00:00Z',
      },
    ];
  }
}
