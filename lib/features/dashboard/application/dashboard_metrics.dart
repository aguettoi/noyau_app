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

enum DashboardAlertSeverity { attention, warning, critical }

enum DashboardDestination {
  accounts,
  envelopes,
  budget,
  debts,
  receivables,
  goals,
  priorities,
}

class DashboardAlert {
  const DashboardAlert({
    required this.title,
    required this.detail,
    required this.severity,
    this.destination = DashboardDestination.accounts,
  });

  final String title;
  final String detail;
  final DashboardAlertSeverity severity;
  final DashboardDestination destination;
}

enum DashboardPeriod {
  currentMonth('Mois courant'),
  previousMonth('Mois précédent'),
  threeMonths('3 mois'),
  sixMonths('6 mois'),
  year('Année');

  const DashboardPeriod(this.label);
  final String label;
  ({DateTime start, DateTime end}) bounds(DateTime now) {
    final end = DateTime(now.year, now.month + (this == previousMonth ? 0 : 1));
    final start = switch (this) {
      currentMonth => DateTime(now.year, now.month),
      previousMonth => DateTime(now.year, now.month - 1),
      threeMonths => DateTime(now.year, now.month - 2),
      sixMonths => DateTime(now.year, now.month - 5),
      year => DateTime(now.year),
    };
    return (start: start, end: end);
  }
}

/// Presentation thresholds only; no mutation or accounting rule.
class DashboardThresholds {
  const DashboardThresholds({
    this.budgetWarning = .8,
    this.dueDays = 7,
    this.reconciliationDays = 30,
  });
  final double budgetWarning;
  final int dueDays;
  final int reconciliationDays;
}

class DashboardFlowPoint {
  const DashboardFlowPoint(this.month, this.flow);
  final DateTime month;
  final DashboardMonthlyFlow flow;
}

/// Missing months are omitted, never invented as historical zero snapshots.
List<DashboardFlowPoint> dashboardFlowSeries(
  Iterable<Map<String, Object?>> rows,
) {
  final grouped = <DateTime, List<Map<String, Object?>>>{};
  for (final row in rows) {
    if (!const [
      'income',
      'income_receivable',
      'expense',
      'debt_expense',
    ].contains(row['type'])) {
      continue;
    }
    final date = DateTime.parse(row['occurred_at'] as String).toLocal();
    final month = DateTime(date.year, date.month);
    grouped.putIfAbsent(month, () => []).add(row);
  }
  final months = grouped.keys.toList()..sort();
  return [
    for (final month in months)
      DashboardFlowPoint(
        month,
        DashboardMonthlyFlow.fromTransactionRows(grouped[month]!),
      ),
  ];
}
