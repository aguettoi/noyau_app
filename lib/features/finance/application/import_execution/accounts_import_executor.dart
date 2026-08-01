import '../import_models/accounts_import_plan.dart';
import 'accounts_import_execution.dart';

/// Exécute un [AccountsImportPlan] en déléguant toute persistance à une
/// transaction atomique injectée.
class AccountsImportExecutor {
  const AccountsImportExecutor({required this._runTransaction});

  final RunAccountsImportTransaction _runTransaction;

  Future<AccountsImportExecutionResult> execute({
    required AccountsImportPlan plan,
    required ExistingAccountOpeningBalancePolicy openingBalancePolicy,
    required String importExecutionId,
  }) async {
    if (plan.decisions.isEmpty) {
      return AccountsImportExecutionResult.success(
        status: AccountsImportExecutionStatus.executed,
        createdAccountNames: const [],
        keptExistingAccountNames: const [],
        replacedOpeningBalanceAccountNames: const [],
        skippedMissingOpeningBalanceAccountNames: const [],
      );
    }

    final createdNames = <String>[];
    final keptNames = <String>[];
    final replacedNames = <String>[];
    final skippedNames = <String>[];

    try {
      final transactionResult = await _runTransaction(
        importExecutionId: importExecutionId,
        operation: (transaction) async {
          for (final decision in plan.decisions) {
            final account = decision.account;
            switch (decision.action) {
              case AccountImportAction.create:
                await transaction.createAccount(account);
                createdNames.add(account.name);
              case AccountImportAction.alreadyExists:
                if (openingBalancePolicy ==
                    ExistingAccountOpeningBalancePolicy.ignoreCsvValue) {
                  keptNames.add(account.name);
                } else if (account.openingBalanceCents == null) {
                  skippedNames.add(account.name);
                } else {
                  await transaction.replaceOpeningBalance(
                    account: account,
                    openingBalanceCents: account.openingBalanceCents!,
                  );
                  replacedNames.add(account.name);
                }
            }
          }
        },
      );
      if (transactionResult.status ==
          AccountsImportTransactionStatus.alreadyExecuted) {
        return AccountsImportExecutionResult.success(
          status: AccountsImportExecutionStatus.alreadyExecuted,
          createdAccountNames: const [],
          keptExistingAccountNames: const [],
          replacedOpeningBalanceAccountNames: const [],
          skippedMissingOpeningBalanceAccountNames: const [],
        );
      }
    } on Exception catch (error) {
      return AccountsImportExecutionResult.failure(error);
    } on StateError catch (error) {
      return AccountsImportExecutionResult.failure(error);
    }

    return AccountsImportExecutionResult.success(
      status: AccountsImportExecutionStatus.executed,
      createdAccountNames: createdNames,
      keptExistingAccountNames: keptNames,
      replacedOpeningBalanceAccountNames: replacedNames,
      skippedMissingOpeningBalanceAccountNames: skippedNames,
    );
  }
}
