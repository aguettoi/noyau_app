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
    this.financialEventId,
    this.hasEnvelopeMovement = true,
    this.sourceAccountId,
    this.sourceAccountName,
    this.destinationAccountId,
    this.destinationAccountName,
    this.paymentMethodId,
    this.paymentMethodName,
    this.envelopes = const [],
    this.recommendationSnapshot = const [],
    this.isReversed = false,
    this.isReversal = false,
    this.reversalReason,
    this.attachments = const [],
    this.actorId,
  });

  final String id;
  final LedgerTransactionType type;
  final DateTime occurredAt;
  final String description;
  final Money amount;
  final DateTime createdAt;
  final String? financialEventId;
  final bool hasEnvelopeMovement;
  final String? sourceAccountId, sourceAccountName;
  final String? destinationAccountId, destinationAccountName;
  final String? paymentMethodId, paymentMethodName;
  final List<TransactionEnvelopeReference> envelopes;
  final List<Map<String, Object?>> recommendationSnapshot;
  final bool isReversed, isReversal;
  final String? reversalReason, actorId;
  final List<FinancialEventAttachment> attachments;
}

class TransactionEnvelopeReference {
  const TransactionEnvelopeReference({required this.id, required this.name});
  final String id, name;
}

class FinancialEventAttachment {
  const FinancialEventAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.uploadedAt,
    required this.uploadedBy,
    required this.storagePath,
  });
  final String id, filename, mimeType, uploadedBy, storagePath;
  final int fileSize;
  final DateTime uploadedAt;
}

class TransactionHistoryFilter {
  const TransactionHistoryFilter({
    this.query,
    this.from,
    this.to,
    this.accountId,
    this.envelopeId,
    this.paymentMethodId,
    this.eventType,
    this.reversalState,
    this.page = 0,
    this.pageSize = 50,
  });
  final String? query, accountId, envelopeId, paymentMethodId, eventType;
  final DateTime? from, to;
  final String? reversalState;
  final int page, pageSize;

  @override
  bool operator ==(Object other) =>
      other is TransactionHistoryFilter &&
      other.query == query &&
      other.from == from &&
      other.to == to &&
      other.accountId == accountId &&
      other.envelopeId == envelopeId &&
      other.paymentMethodId == paymentMethodId &&
      other.eventType == eventType &&
      other.reversalState == reversalState &&
      other.page == page &&
      other.pageSize == pageSize;
  @override
  int get hashCode => Object.hash(
    query,
    from,
    to,
    accountId,
    envelopeId,
    paymentMethodId,
    eventType,
    reversalState,
    page,
    pageSize,
  );
}
