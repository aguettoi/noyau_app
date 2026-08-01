import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/import_execution/accounts_import_execution.dart';
import 'package:noyau_app/features/finance/application/import_execution/accounts_import_executor.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_plan.dart';
import 'package:noyau_app/features/finance/application/import_models/import_account.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  ImportAccount account(String name, {int? balance = 0}) => ImportAccount(
    name: name,
    type: FinancialAccountType.bank,
    openingBalanceCents: balance,
  );

  AccountsImportPlan plan(List<AccountImportDecision> decisions) =>
      AccountsImportPlan(decisions: decisions);

  AccountImportDecision create(ImportAccount value) =>
      AccountImportDecision(account: value, action: AccountImportAction.create);

  AccountImportDecision existing(ImportAccount value) => AccountImportDecision(
    account: value,
    action: AccountImportAction.alreadyExists,
  );

  test('plan vide retourne un succès sans transaction', () async {
    var transactionCalls = 0;
    final executor = AccountsImportExecutor(
      runTransaction: ({required importExecutionId, required operation}) async {
        transactionCalls++;
        return const AccountsImportTransactionResult(
          AccountsImportTransactionStatus.executed,
        );
      },
    );

    final result = await executor.execute(
      plan: plan(const []),
      openingBalancePolicy: ExistingAccountOpeningBalancePolicy.ignoreCsvValue,
      importExecutionId: _executionId,
    );

    expect(result.isSuccess, isTrue);
    expect(transactionCalls, 0);
    expect(result.createdCount, 0);
    expect(result.errors, isEmpty);
  });

  test('crée les comptes dans l’ordre et rapporte les noms', () async {
    final transaction = _FakeTransaction();
    final executor = _executor(transaction);
    final first = account('Premier');
    final second = account('Second');

    final result = await executor.execute(
      plan: plan([create(first), create(second)]),
      openingBalancePolicy: ExistingAccountOpeningBalancePolicy.ignoreCsvValue,
      importExecutionId: _executionId,
    );

    expect(transaction.events, ['create:Premier', 'create:Second']);
    expect(result.createdCount, 2);
    expect(result.createdAccountNames, ['Premier', 'Second']);
  });

  test('ignore les comptes existants et conserve leur ordre', () async {
    final transaction = _FakeTransaction();
    final executor = _executor(transaction);

    final result = await executor.execute(
      plan: plan([
        existing(account('A', balance: 100)),
        existing(account('B')),
      ]),
      openingBalancePolicy: ExistingAccountOpeningBalancePolicy.ignoreCsvValue,
      importExecutionId: _executionId,
    );

    expect(transaction.events, isEmpty);
    expect(result.keptExistingCount, 2);
    expect(result.keptExistingAccountNames, ['A', 'B']);
    expect(result.replacedOpeningBalanceCount, 0);
  });

  test(
    'un solde absent est ignoré avec la politique de remplacement',
    () async {
      final transaction = _FakeTransaction();
      final executor = _executor(transaction);

      final result = await executor.execute(
        plan: plan([existing(account('Sans solde', balance: null))]),
        openingBalancePolicy:
            ExistingAccountOpeningBalancePolicy.replaceExistingOpeningBalance,
        importExecutionId: _executionId,
      );

      expect(transaction.events, isEmpty);
      expect(result.skippedMissingOpeningBalanceCount, 1);
      expect(result.skippedMissingOpeningBalanceAccountNames, ['Sans solde']);
    },
  );

  for (final balance in [2500, -125, 0]) {
    test('remplace un solde existant explicite de $balance centimes', () async {
      final transaction = _FakeTransaction();
      final executor = _executor(transaction);
      final imported = account('Existant', balance: balance);

      final result = await executor.execute(
        plan: plan([existing(imported)]),
        openingBalancePolicy:
            ExistingAccountOpeningBalancePolicy.replaceExistingOpeningBalance,
        importExecutionId: _executionId,
      );

      expect(transaction.events, ['replace:Existant:$balance']);
      expect(result.replacedOpeningBalanceCount, 1);
      expect(result.replacedOpeningBalanceAccountNames, ['Existant']);
    });
  }

  test(
    'traite un plan mixte dans une transaction unique et dans l’ordre',
    () async {
      final transaction = _FakeTransaction();
      var transactionCalls = 0;
      final executor = AccountsImportExecutor(
        runTransaction:
            ({required importExecutionId, required operation}) async {
              transactionCalls++;
              await operation(transaction);
              return const AccountsImportTransactionResult(
                AccountsImportTransactionStatus.executed,
              );
            },
      );

      final result = await executor.execute(
        plan: plan([
          create(account('Nouveau')),
          existing(account('Déjà là', balance: 42)),
          existing(account('Sans valeur', balance: null)),
        ]),
        openingBalancePolicy:
            ExistingAccountOpeningBalancePolicy.replaceExistingOpeningBalance,
        importExecutionId: _executionId,
      );

      expect(transactionCalls, 1);
      expect(transaction.events, ['create:Nouveau', 'replace:Déjà là:42']);
      expect(result.createdCount, 1);
      expect(result.replacedOpeningBalanceCount, 1);
      expect(result.skippedMissingOpeningBalanceCount, 1);
    },
  );

  for (final failure in [_Failure.create, _Failure.replace]) {
    test('une erreur $failure retourne un échec atomique', () async {
      final transaction = _FakeTransaction(failure: failure);
      final executor = _executor(transaction);

      final result = await executor.execute(
        plan: failure == _Failure.create
            ? plan([create(account('Nouveau'))])
            : plan([existing(account('Existant', balance: 1))]),
        openingBalancePolicy:
            ExistingAccountOpeningBalancePolicy.replaceExistingOpeningBalance,
        importExecutionId: _executionId,
      );

      expect(result.isSuccess, isFalse);
      expect(result.createdCount, 0);
      expect(result.keptExistingCount, 0);
      expect(result.replacedOpeningBalanceCount, 0);
      expect(result.skippedMissingOpeningBalanceCount, 0);
      expect(result.createdAccountNames, isEmpty);
      expect(result.keptExistingAccountNames, isEmpty);
      expect(result.replacedOpeningBalanceAccountNames, isEmpty);
      expect(result.skippedMissingOpeningBalanceAccountNames, isEmpty);
      expect(result.errors.single, startsWith('Erreur d’import :'));
    });
  }

  test('ne modifie pas les objets source', () async {
    final imported = account('Source', balance: 99);
    final decision = existing(imported);
    final executor = _executor(_FakeTransaction());

    await executor.execute(
      plan: plan([decision]),
      openingBalancePolicy:
          ExistingAccountOpeningBalancePolicy.replaceExistingOpeningBalance,
      importExecutionId: _executionId,
    );

    expect(imported.name, 'Source');
    expect(imported.type, FinancialAccountType.bank);
    expect(imported.openingBalanceCents, 99);
    expect(decision.action, AccountImportAction.alreadyExists);
  });

  test('transmet exactement l’identifiant durable à la transaction', () async {
    String? receivedId;
    final executor = _executor(
      _FakeTransaction(),
      onExecutionId: (value) => receivedId = value,
    );
    const executionId = '22222222-2222-4222-8222-222222222222';

    await executor.execute(
      plan: plan([create(account('Compte'))]),
      openingBalancePolicy: ExistingAccountOpeningBalancePolicy.ignoreCsvValue,
      importExecutionId: executionId,
    );

    expect(receivedId, executionId);
  });

  test(
    'une exécution déjà réalisée est distinguée sans compte déclaré créé',
    () async {
      final executor = _executor(
        _FakeTransaction(),
        status: AccountsImportTransactionStatus.alreadyExecuted,
      );

      final result = await executor.execute(
        plan: plan([create(account('Compte'))]),
        openingBalancePolicy:
            ExistingAccountOpeningBalancePolicy.ignoreCsvValue,
        importExecutionId: _executionId,
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, AccountsImportExecutionStatus.alreadyExecuted);
      expect(result.createdCount, 0);
    },
  );
}

const _executionId = '11111111-1111-4111-8111-111111111111';

AccountsImportExecutor _executor(
  _FakeTransaction transaction, {
  AccountsImportTransactionStatus status =
      AccountsImportTransactionStatus.executed,
  void Function(String importExecutionId)? onExecutionId,
}) => AccountsImportExecutor(
  runTransaction: ({required importExecutionId, required operation}) async {
    onExecutionId?.call(importExecutionId);
    await operation(transaction);
    return AccountsImportTransactionResult(status);
  },
);

enum _Failure { create, replace }

class _FakeTransaction implements AccountsImportTransaction {
  _FakeTransaction({this.failure});

  final _Failure? failure;
  final events = <String>[];

  @override
  Future<void> createAccount(ImportAccount account) async {
    if (failure == _Failure.create) {
      throw StateError('création impossible');
    }
    events.add('create:${account.name}');
  }

  @override
  Future<void> replaceOpeningBalance({
    required ImportAccount account,
    required int openingBalanceCents,
  }) async {
    if (failure == _Failure.replace) {
      throw StateError('remplacement impossible');
    }
    events.add('replace:${account.name}:$openingBalanceCents');
  }
}
