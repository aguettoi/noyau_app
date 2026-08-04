import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
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
}
