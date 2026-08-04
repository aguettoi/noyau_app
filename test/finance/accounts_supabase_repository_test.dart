import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';
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

  test(
    'creation convertit les centimes et le type vers le schema distant',
    () async {
      final gateway = _Gateway();
      final repository = AccountsSupabaseRepository(
        gateway: gateway,
        householdId: 'household-1',
      );

      await repository.create(
        const CreateRemoteAccountRequest(
          name: '  Compte epargne  ',
          type: FinancialAccountType.savings,
          openingBalanceCents: 250050,
          archived: false,
        ),
      );

      expect(gateway.createdHouseholdId, 'household-1');
      expect(gateway.createdValues, {
        'household_id': 'household-1',
        'name': 'Compte epargne',
        'kind': 'savings',
        'opening_balance': '2500.50',
      });
    },
  );

  test('creation propage les erreurs du gateway', () async {
    final repository = AccountsSupabaseRepository(
      gateway: _Gateway(createError: true),
      householdId: 'household-1',
    );

    expect(
      () => repository.create(
        const CreateRemoteAccountRequest(
          name: 'Compte',
          type: FinancialAccountType.bank,
          openingBalanceCents: 0,
          archived: false,
        ),
      ),
      throwsException,
    );
  });

  test('creation conserve la titularite et les UUID des titulaires', () async {
    final gateway = _Gateway();
    final repository = AccountsSupabaseRepository(
      gateway: gateway,
      householdId: 'household-1',
    );

    await repository.create(
      const CreateRemoteAccountRequest(
        name: 'Compte partage',
        type: FinancialAccountType.bank,
        openingBalanceCents: 0,
        archived: false,
        ownershipType: AccountOwnershipType.shared,
        holderUserIds: ['ibrahim-id', 'nora-id'],
      ),
    );

    expect(gateway.createdOwnershipType, AccountOwnershipType.shared);
    expect(gateway.createdHolderUserIds, ['ibrahim-id', 'nora-id']);
  });

  test('lecture distante mappe la titularité et les titulaires', () async {
    final accountRow = row()
      ..['ownership_type'] = 'shared'
      ..['account_holders'] = [
        {
          'user_id': 'ibrahim-id',
          'household_members': {'user_id': 'ibrahim-id'},
        },
        {
          'user_id': 'nora-id',
          'household_members': {'user_id': 'nora-id'},
        },
      ];
    final repository = AccountsSupabaseRepository(
      gateway: _Gateway(rows: [accountRow]),
      householdId: 'household-1',
    );

    final account = (await repository.all()).single;

    expect(account.ownershipType, AccountOwnershipType.shared);
    expect(account.holders.map((holder) => holder.userId), [
      'ibrahim-id',
      'nora-id',
    ]);
    expect(account.holders.map((holder) => holder.displayName), [
      'Membre du foyer',
      'Membre du foyer',
    ]);
  });
}

class _Gateway implements AccountsSupabaseGateway {
  _Gateway({
    this.rows = const [],
    this.error = false,
    this.createError = false,
  });

  final List<Map<String, Object?>> rows;
  final bool error;
  final bool createError;
  String? householdId;
  String? createdHouseholdId;
  Map<String, Object?>? createdValues;
  AccountOwnershipType? createdOwnershipType;
  List<String>? createdHolderUserIds;

  @override
  Future<List<Map<String, Object?>>> fetchAccounts(String value) async {
    householdId = value;
    if (error) {
      throw Exception('reseau indisponible');
    }
    return rows;
  }

  @override
  Future<void> createAccount({
    required String householdId,
    required Map<String, Object?> values,
    required AccountOwnershipType ownershipType,
    required List<String> holderUserIds,
  }) async {
    if (createError) {
      throw Exception('reseau indisponible');
    }
    createdHouseholdId = householdId;
    createdValues = Map<String, Object?>.from(values);
    createdOwnershipType = ownershipType;
    createdHolderUserIds = List<String>.from(holderUserIds);
  }
}
