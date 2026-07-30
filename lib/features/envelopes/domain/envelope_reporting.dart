import '../../../core/money/money.dart';

/// A signed line from the source `Journal` sheet for one envelope.
///
/// Positive amounts feed an envelope; negative amounts spend from it.  This is
/// deliberately the same convention as `SUMIF(Journal!C:C; envelope;
/// Journal!D:D)` in the source workbook.
class EnvelopeMovement {
  const EnvelopeMovement({
    required this.envelopeId,
    required this.occurredAt,
    required this.amount,
  });

  final String envelopeId;
  final DateTime occurredAt;
  final Money amount;
}

class EnvelopeReportCalculator {
  const EnvelopeReportCalculator();

  /// Current theoretical balance for each envelope (the source column
  /// “Reste enveloppe”).
  Map<String, Money> balancesByEnvelope(Iterable<EnvelopeMovement> movements) {
    final balances = <String, Money>{};
    for (final movement in movements) {
      balances.update(
        movement.envelopeId,
        (value) => value + movement.amount,
        ifAbsent: () => movement.amount,
      );
    }
    return balances;
  }

  /// Signed net movements per calendar month, matching the source `SUMIFS`
  /// monthly columns. This is not an end-of-month balance.
  Map<DateTime, Money> monthlyNetForEnvelope(
    Iterable<EnvelopeMovement> movements,
    String envelopeId,
  ) {
    final totals = <DateTime, Money>{};
    for (final movement in movements.where(
      (item) => item.envelopeId == envelopeId,
    )) {
      final month = DateTime(
        movement.occurredAt.year,
        movement.occurredAt.month,
      );
      totals.update(
        month,
        (value) => value + movement.amount,
        ifAbsent: () => movement.amount,
      );
    }
    return totals;
  }

  Money totalEnvelopeFunds(Iterable<EnvelopeMovement> movements) =>
      balancesByEnvelope(movements).values.fold(
        const Money.fromMinorUnits(0),
        (total, amount) => total + amount,
      );
}

/// The source workbook compares a calculated (theoretical) account balance
/// with an entered real-world balance. A zero difference means reconciled.
class AccountReconciliation {
  const AccountReconciliation({
    required this.accountId,
    required this.theoreticalBalance,
    required this.actualBalance,
  });

  final String accountId;
  final Money theoreticalBalance;
  final Money actualBalance;

  /// Source convention: theoretical balance minus actual balance.
  Money get difference => theoreticalBalance - actualBalance;
  bool get isReconciled => difference.minorUnits == 0;
}

class EnvelopeSavingsReserve {
  const EnvelopeSavingsReserve({
    required this.savingsBalance,
    required this.protectedAmount,
    required this.recoverableAmount,
  });

  /// The “Epargne a garder” value: it remains unavailable for other uses.
  final Money protectedAmount;

  /// Current balance of the Savings envelope.
  final Money savingsBalance;

  /// Amount expected back from a household member or third party. It is
  /// tracked separately and is never silently added to available cash.
  final Money recoverableAmount;

  Money get spendableSavings => savingsBalance - protectedAmount;
}

/// Faithful projection from the upper-right goal block of `Enveloppes`.
/// Excel uses ROUND(..., 0), rather than CEILING, so the same rounding is kept.
class EnvelopeGoalProjection {
  EnvelopeGoalProjection({
    required this.goalAmount,
    required this.availableCash,
    required this.familyLoan,
    required this.monthlyContribution,
    required this.baseDate,
  }) : assert(monthlyContribution.minorUnits > 0);

  final Money goalAmount;
  final Money availableCash;
  final Money familyLoan;
  final Money monthlyContribution;
  final DateTime baseDate;

  Money get amountStillNeededWithLoan =>
      goalAmount - availableCash - familyLoan;
  Money get amountStillNeededWithoutLoan => goalAmount - availableCash;

  int get monthsWithLoan => _roundedMonths(amountStillNeededWithLoan);
  int get monthsWithoutLoan => _roundedMonths(amountStillNeededWithoutLoan);

  DateTime get estimatedDateWithLoan => _addMonths(baseDate, monthsWithLoan);
  DateTime get estimatedDateWithoutLoan =>
      _addMonths(baseDate, monthsWithoutLoan);

  int _roundedMonths(Money amount) =>
      (amount.minorUnits / monthlyContribution.minorUnits).round();

  static DateTime _addMonths(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }
}
