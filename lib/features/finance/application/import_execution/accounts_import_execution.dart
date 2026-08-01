import '../import_models/import_account.dart';

/// Politique appliquée aux soldes d'ouverture des comptes déjà existants.
enum ExistingAccountOpeningBalancePolicy {
  ignoreCsvValue,
  replaceExistingOpeningBalance,
}

/// Contrat transactionnel minimal requis pour exécuter un import de comptes.
abstract interface class AccountsImportTransaction {
  Future<void> createAccount(ImportAccount account);

  Future<void> replaceOpeningBalance({
    required ImportAccount account,
    required int openingBalanceCents,
  });
}

/// Exécute [operation] dans une transaction atomique fournie par l'infrastructure.
typedef RunAccountsImportTransaction =
    Future<AccountsImportTransactionResult> Function({
      required String importExecutionId,
      required Future<void> Function(AccountsImportTransaction transaction)
      operation,
    });

/// Etat retourné par l'infrastructure après l'appel atomique.
enum AccountsImportTransactionStatus { executed, alreadyExecuted }

class AccountsImportTransactionResult {
  const AccountsImportTransactionResult(this.status);

  final AccountsImportTransactionStatus status;
}

/// Etat final de l'exécution demandée par l'utilisateur.
enum AccountsImportExecutionStatus { executed, alreadyExecuted, failed }

/// Rapport immutable de l'exécution d'un plan d'import de comptes.
class AccountsImportExecutionResult {
  AccountsImportExecutionResult({
    required this.status,
    required this.isSuccess,
    required this.createdCount,
    required this.keptExistingCount,
    required this.replacedOpeningBalanceCount,
    required this.skippedMissingOpeningBalanceCount,
    required List<String> createdAccountNames,
    required List<String> keptExistingAccountNames,
    required List<String> replacedOpeningBalanceAccountNames,
    required List<String> skippedMissingOpeningBalanceAccountNames,
    required List<String> errors,
  }) : createdAccountNames = List.unmodifiable(createdAccountNames),
       keptExistingAccountNames = List.unmodifiable(keptExistingAccountNames),
       replacedOpeningBalanceAccountNames = List.unmodifiable(
         replacedOpeningBalanceAccountNames,
       ),
       skippedMissingOpeningBalanceAccountNames = List.unmodifiable(
         skippedMissingOpeningBalanceAccountNames,
       ),
       errors = List.unmodifiable(errors);

  final bool isSuccess;
  final AccountsImportExecutionStatus status;
  final int createdCount;
  final int keptExistingCount;
  final int replacedOpeningBalanceCount;
  final int skippedMissingOpeningBalanceCount;
  final List<String> createdAccountNames;
  final List<String> keptExistingAccountNames;
  final List<String> replacedOpeningBalanceAccountNames;
  final List<String> skippedMissingOpeningBalanceAccountNames;
  final List<String> errors;

  factory AccountsImportExecutionResult.success({
    required AccountsImportExecutionStatus status,
    required List<String> createdAccountNames,
    required List<String> keptExistingAccountNames,
    required List<String> replacedOpeningBalanceAccountNames,
    required List<String> skippedMissingOpeningBalanceAccountNames,
  }) => AccountsImportExecutionResult(
    status: status,
    isSuccess: true,
    createdCount: createdAccountNames.length,
    keptExistingCount: keptExistingAccountNames.length,
    replacedOpeningBalanceCount: replacedOpeningBalanceAccountNames.length,
    skippedMissingOpeningBalanceCount:
        skippedMissingOpeningBalanceAccountNames.length,
    createdAccountNames: createdAccountNames,
    keptExistingAccountNames: keptExistingAccountNames,
    replacedOpeningBalanceAccountNames: replacedOpeningBalanceAccountNames,
    skippedMissingOpeningBalanceAccountNames:
        skippedMissingOpeningBalanceAccountNames,
    errors: const [],
  );

  factory AccountsImportExecutionResult.failure(Object error) =>
      AccountsImportExecutionResult(
        status: AccountsImportExecutionStatus.failed,
        isSuccess: false,
        createdCount: 0,
        keptExistingCount: 0,
        replacedOpeningBalanceCount: 0,
        skippedMissingOpeningBalanceCount: 0,
        createdAccountNames: const [],
        keptExistingAccountNames: const [],
        replacedOpeningBalanceAccountNames: const [],
        skippedMissingOpeningBalanceAccountNames: const [],
        errors: ['Erreur d’import : $error'],
      );
}
