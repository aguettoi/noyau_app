import '../../domain/financial_account.dart';
import 'accounts_import_plan.dart';
import 'import_account.dart';

class AccountsImportPlanner {
  AccountsImportPlan plan({
    required List<ImportAccount> importedAccounts,
    required Iterable<FinancialAccount> existingAccounts,
  }) {
    final existingNames = existingAccounts
        .map((account) => _normalize(account.name))
        .toSet();
    final decisions = importedAccounts
        .map(
          (account) => AccountImportDecision(
            account: account,
            action: existingNames.contains(_normalize(account.name))
                ? AccountImportAction.alreadyExists
                : AccountImportAction.create,
          ),
        )
        .toList(growable: false);
    return AccountsImportPlan(decisions: decisions);
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
