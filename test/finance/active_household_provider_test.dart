import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';

void main() {
  ProviderContainer container({
    String? userId,
    required HouseholdMembershipGateway gateway,
  }) => ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      householdMembershipGatewayProvider.overrideWithValue(gateway),
    ],
  );

  test('utilisateur non connecte retourne un etat explicite', () async {
    final scope = container(userId: null, gateway: _Gateway());
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(state.status, ActiveHouseholdStatus.noAuthenticatedUser);
    expect(state.householdId, isNull);
  });

  test('aucun foyer retourne un etat explicite', () async {
    final scope = container(userId: 'user-1', gateway: _Gateway());
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(state.status, ActiveHouseholdStatus.noHousehold);
    expect(state.householdId, isNull);
  });

  test('un seul foyer est selectionne automatiquement', () async {
    final gateway = _Gateway(ids: const ['household-1']);
    final scope = container(userId: 'user-1', gateway: gateway);
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(gateway.userId, 'user-1');
    expect(state.status, ActiveHouseholdStatus.singleHousehold);
    expect(state.householdId, 'household-1');
  });

  test('plusieurs foyers restent ambigus', () async {
    final scope = container(
      userId: 'user-1',
      gateway: _Gateway(ids: const ['household-1', 'household-2']),
    );
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(state.status, ActiveHouseholdStatus.multipleHouseholds);
    expect(state.householdId, isNull);
    expect(state.householdIds, ['household-1', 'household-2']);
  });

  test('erreur de chargement retournee sous forme detat', () async {
    final scope = container(userId: 'user-1', gateway: _Gateway(error: true));
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(state.status, ActiveHouseholdStatus.error);
    expect(state.error, isA<Exception>());
  });
}

class _Gateway implements HouseholdMembershipGateway {
  _Gateway({this.ids = const [], this.error = false});

  final List<String> ids;
  final bool error;
  String? userId;

  @override
  Future<List<String>> householdIdsForUser(String value) async {
    userId = value;
    if (error) {
      throw Exception('reseau indisponible');
    }
    return ids;
  }
}
