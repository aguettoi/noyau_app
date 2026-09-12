import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/infrastructure/transactions_supabase_repository.dart';

void main() {
  FinancialTransactionDraft draft({
    LedgerTransactionType type = LedgerTransactionType.expense,
    String? source = 'source-id',
    String? destination,
    List<EnvelopeAllocationDraft> allocations = const [
      EnvelopeAllocationDraft(
        envelopeId: 'envelope-id',
        amount: Money.fromMinorUnits(4599),
      ),
    ],
  }) => FinancialTransactionDraft(
    type: type,
    occurredAt: DateTime.utc(2026, 8, 5, 10),
    description: '  Courses  ',
    amount: Money.fromMinorUnits(4599),
    sourceAccountId: source,
    destinationAccountId: destination,
    envelopeAllocations: allocations,
  );

  test(
    'la création transmet un payload RPC précis sans SQL dans le domaine',
    () async {
      final gateway = _Gateway();
      final repository = TransactionsSupabaseRepository(
        gateway: gateway,
        householdId: 'home-1',
      );

      final id = await repository.create(draft());

      expect(id, 'transaction-1');
      expect(gateway.parameters, {
        'p_household_id': 'home-1',
        'p_type': 'expense',
        'p_occurred_at': '2026-08-05T10:00:00.000Z',
        'p_description': 'Courses',
        'p_amount': '45.99',
        'p_source_account_id': 'source-id',
        'p_destination_account_id': null,
        'p_category_id': null,
        'p_notes': null,
        'p_direction': 'increase',
        'p_envelope_allocations': [
          {'envelope_id': 'envelope-id', 'amount': '45.99'},
        ],
      });
    },
  );

  for (final scenario in [
    (
      label: 'un revenu',
      draft: draft(
        type: LedgerTransactionType.income,
        source: null,
        destination: 'destination-id',
        allocations: const [],
      ),
      expectedType: 'income',
      expectedSource: null,
      expectedDestination: 'destination-id',
      expectedDirection: 'increase',
    ),
    (
      label: 'un virement',
      draft: draft(
        type: LedgerTransactionType.transfer,
        destination: 'destination-id',
        allocations: const [],
      ),
      expectedType: 'transfer',
      expectedSource: 'source-id',
      expectedDestination: 'destination-id',
      expectedDirection: 'increase',
    ),
    (
      label: 'un ajustement manuel',
      draft: FinancialTransactionDraft(
        type: LedgerTransactionType.adjustment,
        occurredAt: DateTime.utc(2026, 8, 5, 10),
        description: '  Correction de caisse  ',
        amount: Money.fromMinorUnits(1200),
        sourceAccountId: 'source-id',
        direction: BalanceDirection.decrease,
      ),
      expectedType: 'adjustment',
      expectedSource: 'source-id',
      expectedDestination: null,
      expectedDirection: 'decrease',
    ),
  ]) {
    test(
      '${scenario.label} transmet les comptes et le sens attendus',
      () async {
        final gateway = _Gateway();
        final repository = TransactionsSupabaseRepository(
          gateway: gateway,
          householdId: 'home-1',
        );

        await repository.create(scenario.draft);

        expect(gateway.parameters!['p_type'], scenario.expectedType);
        expect(
          gateway.parameters!['p_source_account_id'],
          scenario.expectedSource,
        );
        expect(
          gateway.parameters!['p_destination_account_id'],
          scenario.expectedDestination,
        );
        expect(gateway.parameters!['p_direction'], scenario.expectedDirection);
      },
    );
  }

  test('un brouillon invalide ne déclenche aucun appel distant', () async {
    final gateway = _Gateway();
    final repository = TransactionsSupabaseRepository(
      gateway: gateway,
      householdId: 'home-1',
    );

    await expectLater(repository.create(draft(source: null)), throwsStateError);

    expect(gateway.parameters, isNull);
  });

  test(
    'un virement déséquilibré est refusé avant tout appel distant',
    () async {
      final gateway = _Gateway();
      final repository = TransactionsSupabaseRepository(
        gateway: gateway,
        householdId: 'home-1',
      );

      await expectLater(
        repository.create(
          draft(type: LedgerTransactionType.transfer, destination: 'source-id'),
        ),
        throwsStateError,
      );

      expect(gateway.parameters, isNull);
    },
  );

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
  Map<String, Object?>? parameters;

  @override
  Future<String> createLedgerTransaction({
    required Map<String, Object?> parameters,
  }) async {
    this.parameters = Map<String, Object?>.from(parameters);
    return 'transaction-1';
  }

  @override
  Future<List<Map<String, Object?>>> fetchTransactions(
    String householdId,
  ) async => rows;
}
