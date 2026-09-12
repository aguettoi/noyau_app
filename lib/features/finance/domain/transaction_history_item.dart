import '../../../core/money/money.dart';
import 'transaction_draft.dart';

class TransactionHistoryItem {
  const TransactionHistoryItem({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.description,
    required this.amount,
    required this.createdAt,
    this.hasEnvelopeMovement = true,
  });

  final String id;
  final LedgerTransactionType type;
  final DateTime occurredAt;
  final String description;
  final Money amount;
  final DateTime createdAt;
  final bool hasEnvelopeMovement;
}
