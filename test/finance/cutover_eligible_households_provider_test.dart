import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';

void main() {
  test(
    'le Cutover liste uniquement les households membres, techniques inclus',
    () async {
      final gateway = _Gateway();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          cutoverEligibleHouseholdsGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      final households = await container.read(
        cutoverEligibleHouseholdsProvider.future,
      );

      expect(gateway.userId, 'user-1');
      expect(households.map((item) => item.id), [
        'operational-household',
        'technical-household',
      ]);
      expect(households.last.name, 'CUTOVER-B1-E2E');
      expect(households.last.classification, HouseholdClassification.technical);
      expect(households.last.classificationLabel, 'TECHNIQUE');
      expect(households.map((item) => item.id), isNot(contains('non-member')));
    },
  );

  test('sans session, le Cutover ne propose aucun household', () async {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(null),
        cutoverEligibleHouseholdsGatewayProvider.overrideWithValue(_Gateway()),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(cutoverEligibleHouseholdsProvider.future),
      isEmpty,
    );
  });
}

class _Gateway implements CutoverEligibleHouseholdsGateway {
  String? userId;

  @override
  Future<List<CutoverEligibleHousehold>> householdsForUser(String value) async {
    userId = value;
    return const [
      CutoverEligibleHousehold(
        id: 'operational-household',
        name: 'Sandbox',
        classification: HouseholdClassification.operational,
      ),
      CutoverEligibleHousehold(
        id: 'technical-household',
        name: 'CUTOVER-B1-E2E',
        classification: HouseholdClassification.technical,
      ),
    ];
  }
}
