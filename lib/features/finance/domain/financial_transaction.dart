import '../../../core/money/money.dart';
import 'ledger_line.dart';

enum FinancialTransactionType {
  allocation,
  expense,
  transfer,
  adjustment,
  recovery,
}

class FinancialTransaction {
  FinancialTransaction({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.reason,
    required this.createdByMemberId,
    required this.lines,
  }) : assert(
         lines.length >= 2,
         'Une écriture doit avoir au moins deux lignes.',
       );

  final String id;
  final FinancialTransactionType type;
  final DateTime occurredAt;
  final String reason;
  final String createdByMemberId;
  final List<LedgerLine> lines;

  Money get balance => lines.fold(
    const Money.fromMinorUnits(0),
    (total, line) => total + line.amount,
  );

  bool get isBalanced => balance.minorUnits == 0;
}
