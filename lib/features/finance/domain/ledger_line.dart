import '../../../core/money/money.dart';

class LedgerLine {
  const LedgerLine({
    required this.accountId,
    required this.amount,
    this.envelopeId,
    this.memberId,
  });

  final String accountId;
  final String? envelopeId;
  final String? memberId;
  final Money amount;
}
