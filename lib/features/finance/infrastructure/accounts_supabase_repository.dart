import '../../../core/money/money.dart';
import '../domain/financial_account.dart';

abstract interface class AccountsSupabaseGateway {
  Future<List<Map<String, Object?>>> fetchAccounts(String householdId);
}

class AccountsSupabaseRepository {
  AccountsSupabaseRepository({
    required this.gateway,
    required this.householdId,
  });

  final AccountsSupabaseGateway gateway;
  final String householdId;

  Future<List<FinancialAccount>> all() async {
    final rows = await gateway.fetchAccounts(householdId);
    return List.unmodifiable(rows.map((row) => _map(row, householdId)));
  }

  static FinancialAccount _map(Map<String, Object?> row, String householdId) {
    if (row['household_id'] != householdId) {
      throw StateError('Un compte ne correspond pas au foyer actif.');
    }
    final id = _requiredString(row, 'id');
    final name = _requiredString(row, 'name');
    final kind = _requiredString(row, 'kind');
    final openingBalance = _moneyFromSql(row['opening_balance']);
    return FinancialAccount(
      id: id,
      name: name,
      type: _financialAccountType(kind),
      openingBalance: openingBalance,
      archivedAt: _nullableDateTime(row['archived_at']),
      createdAt: _requiredDateTime(row, 'created_at'),
      updatedAt: _requiredDateTime(row, 'updated_at'),
    );
  }

  static String _requiredString(Map<String, Object?> row, String column) {
    final value = row[column];
    if (value is! String || value.trim().isEmpty) {
      throw StateError("La colonne '$column' est invalide.");
    }
    return value;
  }

  static FinancialAccountType _financialAccountType(String kind) =>
      switch (kind) {
        'bank' => FinancialAccountType.bank,
        'cash' => FinancialAccountType.cash,
        'savings' => FinancialAccountType.savings,
        'loan' => FinancialAccountType.debt,
        _ => throw StateError("Le type de compte '$kind' est invalide."),
      };

  static Money _moneyFromSql(Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^(-?)(\d+)(?:[.,](\d{1,2}))?$').firstMatch(text);
    if (match == null) {
      throw StateError("La colonne 'opening_balance' est invalide.");
    }
    final whole = int.parse(match.group(2)!);
    final fraction = (match.group(3) ?? '').padRight(2, '0');
    final cents = (whole * 100) + (fraction.isEmpty ? 0 : int.parse(fraction));
    return Money.fromMinorUnits(match.group(1) == '-' ? -cents : cents);
  }

  static DateTime _requiredDateTime(Map<String, Object?> row, String column) {
    final value = row[column];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError("La colonne '$column' est invalide.");
    }
    return parsed;
  }

  static DateTime? _nullableDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw StateError("La colonne 'archived_at' est invalide.");
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw StateError("La colonne 'archived_at' est invalide.");
    }
    return parsed;
  }
}
