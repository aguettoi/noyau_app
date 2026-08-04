import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';
import 'package:noyau_app/features/finance/infrastructure/accounts_supabase_repository.dart';

void main() {
  ActiveHouseholdState activeHousehold() => const ActiveHouseholdState(
    status: ActiveHouseholdStatus.singleHousehold,
    householdId: 'household-1',
    householdIds: ['household-1'],
  );

  ProviderContainer container(_Gateway gateway) => ProviderContainer(
    overrides: [
      activeHouseholdProvider.overrideWith((ref) async => activeHousehold()),
      supabaseAccountsGatewayProvider.overrideWithValue(gateway),
    ],
  );

  test(
    'remoteAccountsProvider utilise uniquement la source distante',
    () async {
      final gateway = _Gateway();
      final scope = container(gateway);
      addTearDown(scope.dispose);

      final accounts = await scope.read(remoteAccountsProvider.future);

      expect(gateway.calls, 1);
      expect(accounts.single.name, 'Compte distant');
    },
  );

  test('remoteAccountsProvider peut etre invalide apres un import', () async {
    final gateway = _Gateway();
    final scope = container(gateway);
    addTearDown(scope.dispose);

    await scope.read(remoteAccountsProvider.future);
    scope.invalidate(remoteAccountsProvider);
    await scope.read(remoteAccountsProvider.future);

    expect(gateway.calls, 2);
  });

  test('la RPC recoit les parametres de titularite exacts', () {
    final parameters = createAccountWithHoldersRpcParameters(
      householdId: 'household-1',
      values: {
        'name': 'Compte partage',
        'kind': 'bank',
        'opening_balance': '120.00',
        'archived_at': null,
      },
      ownershipType: AccountOwnershipType.shared,
      holderUserIds: const ['ibrahim-id', 'nora-id'],
    );

    expect(parameters['p_household_id'], 'household-1');
    expect(parameters['p_ownership_type'], 'shared');
    expect(parameters['p_holder_user_ids'], ['ibrahim-id', 'nora-id']);
    expect(
      parameters.keys,
      containsAll(['p_name', 'p_kind', 'p_opening_balance', 'p_archived_at']),
    );
  });

  test(
    'absence de foyer actif ne bascule pas silencieusement vers le local',
    () async {
      final scope = ProviderContainer(
        overrides: [
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.noHousehold,
            ),
          ),
          supabaseAccountsGatewayProvider.overrideWithValue(_Gateway()),
        ],
      );
      addTearDown(scope.dispose);

      expect(scope.read(remoteAccountsProvider.future), throwsStateError);
    },
  );
}

class _Gateway implements AccountsSupabaseGateway {
  var calls = 0;

  @override
  Future<List<Map<String, Object?>>> fetchAccounts(String householdId) async {
    calls++;
    return [
      {
        'id': 'account-1',
        'household_id': householdId,
        'name': 'Compte distant',
        'kind': 'bank',
        'opening_balance': '0',
        'archived_at': null,
        'created_at': '2026-08-01T10:00:00Z',
        'updated_at': '2026-08-01T10:00:00Z',
      },
    ];
  }

  @override
  Future<void> createAccount({
    required String householdId,
    required Map<String, Object?> values,
    required dynamic ownershipType,
    required List<String> holderUserIds,
  }) async {}
}
