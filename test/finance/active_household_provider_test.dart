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

  test('un seul foyer operationnel est selectionne automatiquement', () async {
    final gateway = _Gateway(memberships: const [_Membership('household-1')]);
    final scope = container(userId: 'user-1', gateway: gateway);
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(gateway.userId, 'user-1');
    expect(state.status, ActiveHouseholdStatus.singleHousehold);
    expect(state.householdId, 'household-1');
  });

  test(
    'un foyer operationnel et un foyer technique resolvent le foyer operationnel',
    () async {
      final scope = container(
        userId: 'user-1',
        gateway: _Gateway(
          memberships: const [
            _Membership('household-operational'),
            _Membership('household-technical', technical: true),
          ],
        ),
      );
      addTearDown(scope.dispose);

      final state = await scope.read(activeHouseholdProvider.future);

      expect(state.status, ActiveHouseholdStatus.singleHousehold);
      expect(state.householdId, 'household-operational');
      expect(state.householdIds, ['household-operational']);
    },
  );

  test(
    'un foyer operationnel et plusieurs foyers techniques restent non ambigus',
    () async {
      final scope = container(
        userId: 'user-1',
        gateway: _Gateway(
          memberships: const [
            _Membership('household-operational'),
            _Membership('household-technical-1', technical: true),
            _Membership('household-technical-2', technical: true),
          ],
        ),
      );
      addTearDown(scope.dispose);

      final state = await scope.read(activeHouseholdProvider.future);

      expect(state.status, ActiveHouseholdStatus.singleHousehold);
      expect(state.householdId, 'household-operational');
    },
  );

  test('plusieurs foyers operationnels restent ambigus', () async {
    final scope = container(
      userId: 'user-1',
      gateway: _Gateway(
        memberships: const [
          _Membership('household-1'),
          _Membership('household-2'),
        ],
      ),
    );
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(state.status, ActiveHouseholdStatus.multipleHouseholds);
    expect(state.householdId, isNull);
    expect(state.householdIds, ['household-1', 'household-2']);
  });

  test(
    'uniquement des foyers techniques ne donnent aucun foyer actif',
    () async {
      final scope = container(
        userId: 'user-1',
        gateway: _Gateway(
          memberships: const [
            _Membership('household-technical-1', technical: true),
            _Membership('household-technical-2', technical: true),
          ],
        ),
      );
      addTearDown(scope.dispose);

      final state = await scope.read(activeHouseholdProvider.future);

      expect(state.status, ActiveHouseholdStatus.noHousehold);
      expect(state.householdId, isNull);
    },
  );

  test('erreur de chargement retournee sous forme detat', () async {
    final scope = container(userId: 'user-1', gateway: _Gateway(error: true));
    addTearDown(scope.dispose);

    final state = await scope.read(activeHouseholdProvider.future);

    expect(state.status, ActiveHouseholdStatus.error);
    expect(state.error, isA<Exception>());
  });
}

class _Gateway implements HouseholdMembershipGateway {
  _Gateway({this.memberships = const [], this.error = false});

  final List<_Membership> memberships;
  final bool error;
  String? userId;

  @override
  Future<List<HouseholdMembership>> householdsForUser(String value) async {
    userId = value;
    if (error) {
      throw Exception('reseau indisponible');
    }
    return memberships
        .map(
          (membership) => HouseholdMembership(
            householdId: membership.id,
            classification: membership.technical
                ? HouseholdClassification.technical
                : HouseholdClassification.operational,
          ),
        )
        .toList(growable: false);
  }
}

class _Membership {
  const _Membership(this.id, {this.technical = false});

  final String id;
  final bool technical;
}
