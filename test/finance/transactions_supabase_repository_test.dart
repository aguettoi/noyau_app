import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/finance/infrastructure/transactions_supabase_repository.dart';

void main() {
  test(
    'la lecture conserve l’historique distant et les montants en centimes',
    () async {
      final gateway = _Gateway(
        rows: [
          {
            'id': 'tx-1',
            'type': 'income',
            'occurred_at': '2026-08-05T10:00:00Z',
            'description': 'Salaire',
            'amount': '12345.67',
            'created_at': '2026-08-05T10:01:00Z',
          },
        ],
      );
      final repository = TransactionsSupabaseRepository(
        gateway: gateway,
        householdId: 'home-1',
      );

      final item = (await repository.all()).single;

      expect(item.amount.minorUnits, 1234567);
      expect(item.description, 'Salaire');
      expect(item.type, LedgerTransactionType.income);
    },
  );

  for (final type in [
    'expense',
    'cash_expense',
    'cash_income',
    'account_opening',
    'debt_expense',
    'income_receivable',
    'recovery',
    'recovery_receivable',
    'debt_settlement',
    'receivable_settlement',
    'recovery_settlement',
    'allocation',
    'account_transfer',
    'envelope_transfer',
  ]) {
    test(
      'le type FinancialEvent $type reste lisible dans le Grand Livre',
      () async {
        final repository = TransactionsSupabaseRepository(
          gateway: _Gateway(
            rows: [
              {
                'id': 'transaction-$type',
                'type': type,
                'occurred_at': '2026-08-10T10:00:00Z',
                'description': 'Opération',
                'amount': '10.00',
                'created_at': '2026-08-10T10:00:00Z',
              },
            ],
          ),
          householdId: 'home-1',
        );
        expect(
          (await repository.all()).single.type,
          isNot(LedgerTransactionType.unknown),
        );
      },
    );
  }

  test('un type legacy inconnu reste consultable', () async {
    final repository = TransactionsSupabaseRepository(
      gateway: _Gateway(
        rows: [
          {
            'id': 'transaction-old',
            'type': 'legacy_unknown_type',
            'occurred_at': '2026-08-10T10:00:00Z',
            'description': 'Ancienne opération',
            'amount': '10.00',
            'created_at': '2026-08-10T10:00:00Z',
          },
        ],
      ),
      householdId: 'home-1',
    );
    expect((await repository.all()).single.type, LedgerTransactionType.unknown);
  });
}

class _Gateway implements TransactionsSupabaseGateway {
  _Gateway({this.rows = const []});

  final List<Map<String, Object?>> rows;
  @override
  Future<List<Map<String, Object?>>> fetchTransactions(
    String householdId, {
    TransactionHistoryFilter filter = const TransactionHistoryFilter(),
  }) async => rows;
}
