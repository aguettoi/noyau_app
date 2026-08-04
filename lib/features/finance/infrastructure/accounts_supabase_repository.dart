import '../../../core/money/money.dart';
import '../domain/account_ownership.dart';
import '../domain/financial_account.dart';

abstract interface class AccountsSupabaseGateway {
  Future<List<Map<String, Object?>>> fetchAccounts(String householdId);

  Future<void> createAccount({
    required String householdId,
    required Map<String, Object?> values,
    required AccountOwnershipType ownershipType,
    required List<String> holderUserIds,
  });
}

class CreateRemoteAccountRequest {
  const CreateRemoteAccountRequest({
    required this.name,
    required this.type,
    required this.openingBalanceCents,
    required this.archived,
    this.ownershipType = AccountOwnershipType.household,
    this.holderUserIds = const [],
  });

  final String name;
  final FinancialAccountType type;
  final int openingBalanceCents;
  final bool archived;
  final AccountOwnershipType ownershipType;
  final List<String> holderUserIds;
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

  Future<void> create(CreateRemoteAccountRequest request) =>
      gateway.createAccount(
        householdId: householdId,
        values: {
          'household_id': householdId,
          'name': request.name.trim(),
          'kind': _accountKind(request.type),
          'opening_balance': _madFromCents(request.openingBalanceCents),
          if (request.archived)
            'archived_at': DateTime.now().toUtc().toIso8601String(),
        },
        ownershipType: request.ownershipType,
        holderUserIds: List.unmodifiable(request.holderUserIds),
      );

  static FinancialAccount _map(Map<String, Object?> row, String householdId) {
    if (row['household_id'] != householdId) {
      throw StateError('Un compte ne correspond pas au foyer actif.');
    }
    final id = _requiredString(row, 'id');
    final name = _requiredString(row, 'name');
    final kind = _requiredString(row, 'kind');
    final openingBalance = _moneyFromSql(row['opening_balance']);
    final ownershipType = _ownershipType(
      (row['ownership_type'] as String?) ?? 'household',
    );
    final holders = _holdersFromSql(row['account_holders']);
    return FinancialAccount(
      id: id,
      name: name,
      type: _financialAccountType(kind),
      openingBalance: openingBalance,
      ownershipType: ownershipType,
      holders: holders,
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

  static AccountOwnershipType _ownershipType(String value) => switch (value) {
    'household' => AccountOwnershipType.household,
    'individual' => AccountOwnershipType.individual,
    'shared' => AccountOwnershipType.shared,
    _ => throw StateError("Le type de titularité '$value' est invalide."),
  };

  static List<AccountHolder> _holdersFromSql(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw StateError("La colonne 'account_holders' est invalide.");
    }
    return List.unmodifiable(
      raw.map((item) {
        if (item is! Map) {
          throw StateError("La colonne 'account_holders' est invalide.");
        }
        final row = Map<String, Object?>.from(item);
        final userId = _requiredString(row, 'user_id');
        final membership = row['household_members'];
        if (membership is! Map) {
          throw StateError("Le membre d'un titulaire est invalide.");
        }
        final membershipRow = Map<String, Object?>.from(membership);
        if (_requiredString(membershipRow, 'user_id') != userId) {
          throw StateError("Le titulaire ne correspond pas à son foyer.");
        }
        return AccountHolder(userId: userId, displayName: 'Membre du foyer');
      }),
    );
  }

  static String _accountKind(FinancialAccountType type) => switch (type) {
    FinancialAccountType.bank => 'bank',
    FinancialAccountType.cash => 'cash',
    FinancialAccountType.savings => 'savings',
    FinancialAccountType.debt => 'loan',
  };

  static String _madFromCents(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    return '$sign${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

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
