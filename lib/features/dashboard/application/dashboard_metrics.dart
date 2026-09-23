import '../../../core/money/money.dart';

/// Pure, read-only calculations used by the financial dashboard.
///
/// The dashboard deliberately distinguishes recognition events from settlements:
/// paying a debt and collecting a receivable are cash movements, not a second
/// expense or revenue recognition.
class DashboardMonthlyFlow {
  const DashboardMonthlyFlow({required this.income, required this.expense});

  final Money income;
  final Money expense;

  Money get remainder => income - expense;

  static DashboardMonthlyFlow fromTransactionRows(
    Iterable<Map<String, Object?>> rows,
  ) {
    var income = 0;
    var expense = 0;
    for (final row in rows) {
      final amount = _cents(row['amount']);
      switch (row['type']) {
        case 'income':
        case 'income_receivable':
          income += amount.abs();
        case 'expense':
        case 'debt_expense':
          expense += amount.abs();
      }
    }
    return DashboardMonthlyFlow(
      income: Money.fromMinorUnits(income),
      expense: Money.fromMinorUnits(expense),
    );
  }

  static int _cents(Object? value) {
    final match = RegExp(
      r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
    ).firstMatch(value?.toString().trim() ?? '');
    if (match == null) return 0;
    final decimals = (match.group(3) ?? '').padRight(2, '0');
    final amount =
        int.parse(match.group(2)!) * 100 +
        (decimals.isEmpty ? 0 : int.parse(decimals));
    return match.group(1) == '-' ? -amount : amount;
  }
}

enum DashboardAlertSeverity { attention, warning }

class DashboardAlert {
  const DashboardAlert({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;
  final DashboardAlertSeverity severity;
}
