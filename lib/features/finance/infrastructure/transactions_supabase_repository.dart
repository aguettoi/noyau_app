import '../../../core/money/money.dart';
import '../domain/transaction_draft.dart';
import '../domain/transaction_history_item.dart';

abstract interface class TransactionsSupabaseGateway {
  Future<List<Map<String, Object?>>> fetchTransactions(String householdId);

  Future<String> createLedgerTransaction({
    required Map<String, Object?> parameters,
  });
}

class TransactionsSupabaseRepository {
  const TransactionsSupabaseRepository({
    required this.gateway,
    required this.householdId,
  });

  final TransactionsSupabaseGateway gateway;
  final String householdId;

  Future<List<TransactionHistoryItem>> all() async {
    final rows = await gateway.fetchTransactions(householdId);
    return List.unmodifiable(rows.map(mapRow));
  }

  Future<String> create(FinancialTransactionDraft draft) {
    final validationError = draft.validate();
    if (validationError != null) {
      return Future.error(StateError(validationError));
    }
    return gateway.createLedgerTransaction(
      parameters: {
        'p_household_id': householdId,
        'p_type': _sqlType(draft.type),
        'p_occurred_at': draft.occurredAt.toUtc().toIso8601String(),
        'p_description': draft.description.trim(),
        'p_amount': _madFromCents(draft.amount.minorUnits),
        'p_source_account_id': draft.sourceAccountId,
        'p_destination_account_id': draft.destinationAccountId,
        'p_category_id': draft.categoryId,
        'p_notes': draft.notes?.trim().isEmpty ?? true
            ? null
            : draft.notes?.trim(),
        'p_direction': draft.direction.name,
        'p_envelope_allocations': [
          for (final allocation in draft.envelopeAllocations)
            {
              'envelope_id': allocation.envelopeId,
              'amount': _madFromCents(allocation.amount.minorUnits),
            },
        ],
      },
    );
  }

  static TransactionHistoryItem mapRow(Map<String, Object?> row) =>
      TransactionHistoryItem(
        id: _requiredString(row, 'id'),
        type: _type(_requiredString(row, 'type')),
        occurredAt: _date(row, 'occurred_at'),
        description: _requiredString(row, 'description'),
        amount: Money.fromMinorUnits(_cents(row['amount'])),
        createdAt: _date(row, 'created_at'),
        hasEnvelopeMovement:
            (row['envelope_movements'] as List?)?.isNotEmpty ?? false,
      );

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

  static String _madFromCents(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    return '$sign${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  static LedgerTransactionType _type(String value) => switch (value) {
    'expense' => LedgerTransactionType.expense,
    'income' => LedgerTransactionType.income,
    'transfer' => LedgerTransactionType.transfer,
    'adjustment' => LedgerTransactionType.adjustment,
    'opening_balance' => LedgerTransactionType.openingBalance,
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
    _ => LedgerTransactionType.unknown,
  };

  static String _sqlType(LedgerTransactionType type) => switch (type) {
    LedgerTransactionType.expense => 'expense',
    LedgerTransactionType.income => 'income',
    LedgerTransactionType.transfer => 'transfer',
    LedgerTransactionType.adjustment => 'adjustment',
    LedgerTransactionType.openingBalance => 'opening_balance',
    LedgerTransactionType.correction => 'correction',
    LedgerTransactionType.debtExpense => 'debt_expense',
    LedgerTransactionType.incomeReceivable => 'income_receivable',
    LedgerTransactionType.recovery => 'recovery',
    LedgerTransactionType.recoveryReceivable => 'recovery_receivable',
    LedgerTransactionType.debtSettlement => 'debt_settlement',
    LedgerTransactionType.receivableSettlement => 'receivable_settlement',
    LedgerTransactionType.recoverySettlement => 'recovery_settlement',
    LedgerTransactionType.allocation => 'allocation',
    LedgerTransactionType.accountTransfer => 'account_transfer',
    LedgerTransactionType.envelopeTransfer => 'envelope_transfer',
    LedgerTransactionType.unknown => 'unknown',
  };
}
