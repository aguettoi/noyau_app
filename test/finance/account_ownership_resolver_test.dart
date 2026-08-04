import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/import_models/account_ownership_resolver.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';

void main() {
  const members = [
    HouseholdMember(id: 'ibrahim-id', displayName: 'Ibrahim'),
    HouseholdMember(id: 'nora-id', displayName: 'Nora'),
  ];

  const resolver = AccountOwnershipResolver();

  test('Commun et household associent les membres au compte foyer', () {
    for (final value in ['Commun', 'household', 'foyer']) {
      final result = resolver.resolve(rawValue: value, members: members);
      expect(result.ownershipType, AccountOwnershipType.household);
      expect(result.holderUserIds, ['ibrahim-id', 'nora-id']);
    }
  });

  test('un membre unique résout un compte individuel', () {
    final result = resolver.resolve(rawValue: '  ibRAhim ', members: members);

    expect(result.ownershipType, AccountOwnershipType.individual);
    expect(result.holderUserIds, ['ibrahim-id']);
  });

  test('plusieurs membres résolvent un compte partagé', () {
    final result = resolver.resolve(
      rawValue: 'Ibrahim | Nora',
      members: members,
    );

    expect(result.ownershipType, AccountOwnershipType.shared);
    expect(result.holderUserIds, ['ibrahim-id', 'nora-id']);
  });

  test('un identifiant stable est accepté', () {
    final result = resolver.resolve(rawValue: 'nora-id', members: members);

    expect(result.holderUserIds, ['nora-id']);
  });

  test('un titulaire inconnu est refusé', () {
    expect(
      () => resolver.resolve(rawValue: 'Inconnu', members: members),
      throwsStateError,
    );
  });

  test('un titulaire ambigu est refusé', () {
    expect(
      () => resolver.resolve(
        rawValue: 'Ibrahim',
        members: const [
          HouseholdMember(id: 'one', displayName: 'Ibrahim'),
          HouseholdMember(id: 'two', displayName: 'ibrahim'),
        ],
      ),
      throwsStateError,
    );
  });

  test('un titulaire dupliqué est refusé', () {
    expect(
      () => resolver.resolve(rawValue: 'Ibrahim|Ibrahim', members: members),
      throwsStateError,
    );
  });
}
