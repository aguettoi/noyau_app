import '../../../core/money/money.dart';
import 'financial_account.dart';

class AccountSplit {
  const AccountSplit({required this.account, required this.amount});

  final FinancialAccount account;
  final Money amount;
}

/// One business operation can use several payment/receipt accounts, while the
/// exact total remains one immutable operation in the Grand Livre.
class MultiAccountOperation {
  MultiAccountOperation({
    required this.total,
    required this.splits,
    required this.recordedByMemberId,
    this.paidByMemberId,
    this.advancedFor,
  }) {
    if (total.minorUnits <= 0) {
      throw ArgumentError.value(
        total,
        'total',
        'Le montant doit être positif.',
      );
    }
    if (splits.isEmpty || splits.any((split) => split.amount.minorUnits <= 0)) {
      throw ArgumentError('Chaque ventilation doit avoir un montant positif.');
    }
    if (splits.any((split) => split.account.isArchived)) {
      throw ArgumentError('Un compte archivé ne peut pas être utilisé.');
    }
    final splitTotal = splits.fold(
      const Money.fromMinorUnits(0),
      (value, split) => value + split.amount,
    );
    if (splitTotal != total) {
      throw ArgumentError(
        'La somme des ventilations doit être égale au total.',
      );
    }
  }

  final Money total;
  final List<AccountSplit> splits;
  final String recordedByMemberId;
  final String? paidByMemberId;
  final String? advancedFor;
}
