import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_account_balances_provider.dart';

void main() {
  test(
    'les soldes proviennent de la vue distante et sont convertis en centimes',
    () async {
      final gateway = _Gateway();
      final container = ProviderContainer(
        overrides: [
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: 'home-1',
            ),
          ),
          accountLedgerBalancesGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      final balances = await container.read(
        remoteAccountBalancesProvider.future,
      );

      expect(gateway.householdId, 'home-1');
      expect(balances['cash']!.minorUnits, 12345);
      expect(balances['bank']!.minorUnits, -500);
    },
  );

  test('un foyer absent empêche toute lecture de la vue des soldes', () async {
    final gateway = _Gateway();
    final container = ProviderContainer(
      overrides: [
        activeHouseholdProvider.overrideWith(
          (ref) async => const ActiveHouseholdState(
            status: ActiveHouseholdStatus.noHousehold,
          ),
        ),
        accountLedgerBalancesGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(remoteAccountBalancesProvider.future),
      throwsStateError,
    );

    expect(gateway.householdId, isNull);
  });
}

class _Gateway implements AccountLedgerBalancesGateway {
  String? householdId;

  @override
  Future<List<Map<String, Object?>>> fetchTheoreticalBalances(
    String householdId,
  ) async {
    this.householdId = householdId;
    return const [
      {'account_id': 'cash', 'theoretical_balance': '123.45'},
      {'account_id': 'bank', 'theoretical_balance': '-5.00'},
    ];
  }
}
