import '../../../core/money/money.dart';
import '../domain/financial_account.dart';
import '../domain/ledger_entry.dart';

/// Pure counterpart of `account_ledger_balances`, used by tests and previews.
class LedgerAccountBalanceCalculator {
  const LedgerAccountBalanceCalculator();

  Money calculate({
    required Money openingBalance,
    required String accountId,
    required Iterable<LedgerEntry> entries,
    FinancialAccountType type = FinancialAccountType.bank,
  }) {
    final movement = entries
        .where((entry) => entry.accountId == accountId)
        .fold(
          const Money.fromMinorUnits(0),
          (total, entry) => total + entry.signedAmount,
        );
    return type == FinancialAccountType.debt
        ? openingBalance - movement
        : openingBalance + movement;
  }
}
