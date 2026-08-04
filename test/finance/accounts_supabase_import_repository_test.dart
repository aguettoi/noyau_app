import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/import_execution/accounts_import_execution.dart';
import 'package:noyau_app/features/finance/application/import_models/import_account.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/infrastructure/import/accounts_supabase_import_repository.dart';

void main() {
  ImportAccount account(
    String name, {
    FinancialAccountType type = FinancialAccountType.bank,
    int? openingBalanceCents,
  }) => ImportAccount(
    name: name,
    type: type,
    openingBalanceCents: openingBalanceCents,
  );

  test(
    'createAccount écrit les données, le foyer et l’identifiant exacts',
    () async {
      final gateway = _FakeGateway();
      final repository = _repository(gateway);

      await repository.runTransaction(
        importExecutionId: _executionId,
        operation: (transaction) => transaction.createAccount(
          account(
            'Compte CIH',
            type: FinancialAccountType.savings,
            openingBalanceCents: 12345,
          ),
        ),
      );

      expect(gateway.householdId, 'household-1');
      expect(gateway.importExecutionId, _executionId);
      expect(gateway.operations, [
        {
          'operation': 'create',
          'name': 'Compte CIH',
          'kind': 'savings',
          'opening_balance_cents': 12345,
          'ownership_type': 'household',
          'holder_user_ids': [],
        },
      ]);
    },
  );

  test('createAccount conserve un solde d’ouverture absent', () async {
    final gateway = _FakeGateway();

    await _repository(gateway).runTransaction(
      importExecutionId: _executionId,
      operation: (transaction) => transaction.createAccount(account('Espèces')),
    );

    expect(gateway.operations.single['opening_balance_cents'], isNull);
  });

  test('replaceOpeningBalance écrit zéro explicitement', () async {
    final gateway = _FakeGateway();

    await _repository(gateway).runTransaction(
      importExecutionId: _executionId,
      operation: (transaction) => transaction.replaceOpeningBalance(
        account: account('Compte AWB'),
        openingBalanceCents: 0,
      ),
    );

    expect(gateway.operations, [
      {
        'operation': 'replace_opening_balance',
        'name': 'Compte AWB',
        'opening_balance_cents': 0,
      },
    ]);
  });

  test(
    'la transaction envoie toutes les opérations dans un seul lot ordonné',
    () async {
      final gateway = _FakeGateway();

      await _repository(gateway).runTransaction(
        importExecutionId: _executionId,
        operation: (transaction) async {
          await transaction.createAccount(account('Premier'));
          await transaction.replaceOpeningBalance(
            account: account('Second'),
            openingBalanceCents: -50,
          );
        },
      );

      expect(gateway.callCount, 1);
      expect(gateway.operations.map((operation) => operation['name']), [
        'Premier',
        'Second',
      ]);
    },
  );

  test('une exception Supabase est propagée', () async {
    final gateway = _FakeGateway(error: Exception('réseau indisponible'));

    expect(
      () => _repository(gateway).runTransaction(
        importExecutionId: _executionId,
        operation: (transaction) =>
            transaction.createAccount(account('Compte')),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('une erreur de préparation ne déclenche aucun appel Supabase', () async {
    final gateway = _FakeGateway();

    expect(
      () => _repository(gateway).runTransaction(
        importExecutionId: _executionId,
        operation: (_) async => throw StateError('plan invalide'),
      ),
      throwsStateError,
    );
    expect(gateway.callCount, 0);
  });

  test(
    'un retry avec le même identifiant est reconnu sans nouvelle écriture',
    () async {
      final gateway = _IdempotentFakeGateway();
      final repository = _repository(gateway);

      final first = await repository.runTransaction(
        importExecutionId: _executionId,
        operation: (transaction) =>
            transaction.createAccount(account('Compte')),
      );
      final retry = await repository.runTransaction(
        importExecutionId: _executionId,
        operation: (transaction) =>
            transaction.createAccount(account('Compte')),
      );

      expect(first.status, AccountsImportTransactionStatus.executed);
      expect(retry.status, AccountsImportTransactionStatus.alreadyExecuted);
      expect(gateway.executedIds, {_executionId});
    },
  );

  test('un identifiant différent autorise une nouvelle exécution', () async {
    final gateway = _IdempotentFakeGateway();
    final repository = _repository(gateway);

    await repository.runTransaction(
      importExecutionId: _executionId,
      operation: (transaction) => transaction.createAccount(account('Premier')),
    );
    await repository.runTransaction(
      importExecutionId: '33333333-3333-4333-8333-333333333333',
      operation: (transaction) => transaction.createAccount(account('Second')),
    );

    expect(gateway.executedIds, hasLength(2));
  });

  test(
    'deux appels concurrents avec le même identifiant ne sont exécutés qu’une fois',
    () async {
      final gateway = _IdempotentFakeGateway();
      final repository = _repository(gateway);

      final results = await Future.wait([
        repository.runTransaction(
          importExecutionId: _executionId,
          operation: (transaction) =>
              transaction.createAccount(account('Compte')),
        ),
        repository.runTransaction(
          importExecutionId: _executionId,
          operation: (transaction) =>
              transaction.createAccount(account('Compte')),
        ),
      ]);

      expect(gateway.executedIds, {_executionId});
      expect(
        results.map((result) => result.status),
        containsAll([
          AccountsImportTransactionStatus.executed,
          AccountsImportTransactionStatus.alreadyExecuted,
        ]),
      );
    },
  );

  test(
    'un retry avec le même identifiant peut réussir après un échec',
    () async {
      final gateway = _RetryAfterFailureGateway();
      final repository = _repository(gateway);

      await expectLater(
        repository.runTransaction(
          importExecutionId: _executionId,
          operation: (transaction) =>
              transaction.createAccount(account('Compte')),
        ),
        throwsA(isA<Exception>()),
      );
      final retry = await repository.runTransaction(
        importExecutionId: _executionId,
        operation: (transaction) =>
            transaction.createAccount(account('Compte')),
      );

      expect(retry.status, AccountsImportTransactionStatus.executed);
      expect(gateway.callCount, 2);
    },
  );
}

const _executionId = '11111111-1111-4111-8111-111111111111';

AccountsSupabaseImportRepository _repository(
  AccountsSupabaseImportGateway gateway,
) => AccountsSupabaseImportRepository(
  gateway: gateway,
  householdId: 'household-1',
);

class _FakeGateway implements AccountsSupabaseImportGateway {
  _FakeGateway({this.error});

  final Exception? error;
  String? householdId;
  String? importExecutionId;
  List<Map<String, Object?>> operations = const [];
  var callCount = 0;

  @override
  Future<AccountsImportTransactionResult> executeAccountsImport({
    required String householdId,
    required String importExecutionId,
    required List<Map<String, Object?>> operations,
  }) async {
    callCount++;
    this.householdId = householdId;
    this.importExecutionId = importExecutionId;
    this.operations = List.unmodifiable(operations);
    if (error != null) {
      throw error!;
    }
    return const AccountsImportTransactionResult(
      AccountsImportTransactionStatus.executed,
    );
  }
}

class _IdempotentFakeGateway implements AccountsSupabaseImportGateway {
  final executedIds = <String>{};

  @override
  Future<AccountsImportTransactionResult> executeAccountsImport({
    required String householdId,
    required String importExecutionId,
    required List<Map<String, Object?>> operations,
  }) async => AccountsImportTransactionResult(
    executedIds.add(importExecutionId)
        ? AccountsImportTransactionStatus.executed
        : AccountsImportTransactionStatus.alreadyExecuted,
  );
}

class _RetryAfterFailureGateway implements AccountsSupabaseImportGateway {
  var callCount = 0;

  @override
  Future<AccountsImportTransactionResult> executeAccountsImport({
    required String householdId,
    required String importExecutionId,
    required List<Map<String, Object?>> operations,
  }) async {
    callCount++;
    if (callCount == 1) {
      throw Exception('échec transactionnel');
    }
    return const AccountsImportTransactionResult(
      AccountsImportTransactionStatus.executed,
    );
  }
}
