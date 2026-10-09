import '../../../core/money/money.dart';
import '../domain/transaction_draft.dart';
import '../domain/transaction_history_item.dart';

abstract interface class TransactionsSupabaseGateway {
  Future<List<Map<String, Object?>>> fetchTransactions(
    String householdId, {
    TransactionHistoryFilter filter = const TransactionHistoryFilter(),
  });
}

class TransactionsSupabaseRepository {
  const TransactionsSupabaseRepository({
    required this.gateway,
    required this.householdId,
  });

  final TransactionsSupabaseGateway gateway;
  final String householdId;

  Future<List<TransactionHistoryItem>> all({
    TransactionHistoryFilter filter = const TransactionHistoryFilter(),
  }) async {
    final rows = await gateway.fetchTransactions(householdId, filter: filter);
    return List.unmodifiable(rows.map(mapRow));
  }

  static TransactionHistoryItem mapRow(Map<String, Object?> row) =>
      TransactionHistoryItem(
        id: _requiredString(
          row,
          row.containsKey('transaction_id') ? 'transaction_id' : 'id',
        ),
        type: _type(
          _requiredString(
            row,
            row.containsKey('event_type') ? 'event_type' : 'type',
          ),
        ),
        occurredAt: _date(row, 'occurred_at'),
        description: _requiredString(row, 'description'),
        amount: Money.fromMinorUnits(_cents(row['amount'])),
        createdAt: _date(row, 'created_at'),
        financialEventId:
            (row['event_id'] ?? row['financial_event_id']) as String?,
        hasEnvelopeMovement:
            (row['envelope_movements'] as List?)?.isNotEmpty ?? false,
        sourceAccountId: row['source_account_id'] as String?,
        sourceAccountName: row['source_account_name'] as String?,
        destinationAccountId: row['destination_account_id'] as String?,
        destinationAccountName: row['destination_account_name'] as String?,
        paymentMethodId: row['actual_payment_method_id'] as String?,
        paymentMethodName: row['actual_payment_method_name'] as String?,
        actorId: row['created_by'] as String?,
        isReversed: row['is_reversed'] as bool? ?? false,
        isReversal: row['is_reversal'] as bool? ?? false,
        reversalReason: row['reversal_reason'] as String?,
        envelopes: _maps(row['envelopes'])
            .map(
              (m) => TransactionEnvelopeReference(
                id: m['id'] as String,
                name: m['name'] as String,
              ),
            )
            .toList(growable: false),
        recommendationSnapshot: _maps(row['recommendation_snapshot']),
        attachments: _maps(row['attachments'])
            .map(
              (m) => FinancialEventAttachment(
                id: m['id'] as String,
                filename: m['filename'] as String,
                mimeType: m['mime_type'] as String,
                fileSize: (m['file_size'] as num).toInt(),
                uploadedAt: DateTime.parse(m['uploaded_at'] as String),
                uploadedBy: m['uploaded_by'] as String,
                storagePath: m['storage_path'] as String,
              ),
            )
            .toList(growable: false),
      );

  static List<Map<String, Object?>> _maps(Object? value) => value is List
      ? value
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList(growable: false)
      : const [];

  static String _requiredString(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw StateError("La colonne '$key' est invalide.");
    }
    return value;
  }

  static DateTime _date(Map<String, Object?> row, String key) {
    final value = row[key];
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) {
      throw StateError("La colonne '$key' est invalide.");
    }
    return date;
  }

  static int _cents(Object? value) {
    final match = RegExp(
      r'^(-?)(\d+)(?:[.,](\d{1,2}))?$',
    ).firstMatch(value?.toString().trim() ?? '');
    if (match == null) {
      throw StateError("La colonne 'amount' est invalide.");
    }
    final whole = int.parse(match.group(2)!);
    final decimals = (match.group(3) ?? '').padRight(2, '0');
    final cents = whole * 100 + (decimals.isEmpty ? 0 : int.parse(decimals));
    return match.group(1) == '-' ? -cents : cents;
  }

  static LedgerTransactionType _type(String value) => switch (value) {
    'expense' || 'cash_expense' => LedgerTransactionType.expense,
    'income' || 'cash_income' => LedgerTransactionType.income,
    'transfer' => LedgerTransactionType.transfer,
    'adjustment' => LedgerTransactionType.adjustment,
    'opening_balance' ||
    'account_opening' => LedgerTransactionType.openingBalance,
    'correction' => LedgerTransactionType.correction,
    'debt_expense' => LedgerTransactionType.debtExpense,
    'income_receivable' => LedgerTransactionType.incomeReceivable,
    'recovery' => LedgerTransactionType.recovery,
    'recovery_receivable' => LedgerTransactionType.recoveryReceivable,
    'debt_settlement' => LedgerTransactionType.debtSettlement,
    'receivable_settlement' => LedgerTransactionType.receivableSettlement,
    'recovery_settlement' => LedgerTransactionType.recoverySettlement,
    'allocation' => LedgerTransactionType.allocation,
    'account_transfer' => LedgerTransactionType.accountTransfer,
    'envelope_transfer' => LedgerTransactionType.envelopeTransfer,
    'daily_reversal' => LedgerTransactionType.correction,
    _ => LedgerTransactionType.unknown,
  };
}
