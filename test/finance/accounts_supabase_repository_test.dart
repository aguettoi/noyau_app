import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/infrastructure/accounts_supabase_repository.dart';

void main() {
  Map<String, Object?> row({
    String kind = 'bank',
    Object openingBalance = '123.45',
  }) => {
    'id': 'account-1',
    'household_id': 'household-1',
    'name': 'Compte courant',
    'kind': kind,
    'opening_balance': openingBalance,
    'archived_at': null,
    'created_at': '2026-08-01T10:00:00Z',
    'updated_at': '2026-08-01T10:00:00Z',
  };

  test('le householdId exact est transmis au gateway', () async {
    final gateway = _Gateway(rows: [row()]);
    final repository = AccountsSupabaseRepository(
      gateway: gateway,
      householdId: 'household-1',
    );

    await repository.all();

    expect(gateway.householdId, 'household-1');
  });

  for (final entry in {
    'bank': FinancialAccountType.bank,
    'cash': FinancialAccountType.cash,
    'savings': FinancialAccountType.savings,
    'loan': FinancialAccountType.debt,
  }.entries) {
    test('mapping ${entry.key}', () async {
      final repository = AccountsSupabaseRepository(
        gateway: _Gateway(rows: [row(kind: entry.key)]),
        householdId: 'household-1',
      );

      final account = (await repository.all()).single;

      expect(account.type, entry.value);
    });
  }

  test('opening_balance est mappe en centimes', () async {
    final repository = AccountsSupabaseRepository(
      gateway: _Gateway(rows: [row(openingBalance: '44311.70')]),
      householdId: 'household-1',
    );

    expect((await repository.all()).single.openingBalance.minorUnits, 4431170);
  });

  test('les comptes hors foyer sont refuses', () async {
    final invalid = row()..['household_id'] = 'another-household';
    final repository = AccountsSupabaseRepository(
      gateway: _Gateway(rows: [invalid]),
      householdId: 'household-1',
    );

    expect(repository.all, throwsStateError);
  });

  test('les erreurs du gateway sont propagees', () async {
    final repository = AccountsSupabaseRepository(
      gateway: _Gateway(error: true),
      householdId: 'household-1',
    );

    expect(repository.all, throwsException);
  });
}

class _Gateway implements AccountsSupabaseGateway {
  _Gateway({this.rows = const [], this.error = false});

  final List<Map<String, Object?>> rows;
  final bool error;
  String? householdId;

  @override
  Future<List<Map<String, Object?>>> fetchAccounts(String value) async {
    householdId = value;
    if (error) {
      throw Exception('reseau indisponible');
    }
    return rows;
  }
}
