import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';

void main() {
  test('les noms de profil sont affiches sans exposer les UUID', () {
    final members = householdMembersForDisplay(
      userIds: const ['uuid-ibrahim', 'uuid-nora'],
      displayNamesByUserId: const {
        'uuid-ibrahim': 'Ibrahim',
        'uuid-nora': 'Nora',
      },
    );

    expect(members.map((member) => member.id), ['uuid-ibrahim', 'uuid-nora']);
    expect(members.map((member) => member.displayName), ['Ibrahim', 'Nora']);
    expect(
      members.any((member) => member.displayName.contains('uuid-')),
      isFalse,
    );
  });

  test('un email remplace un display_name absent', () {
    final members = householdMembersForDisplay(
      userIds: const ['uuid-1', 'uuid-2'],
      displayNamesByUserId: const {'uuid-1': 'Ibrahim'},
      emailsByUserId: const {'uuid-2': 'nora@example.com'},
    );

    expect(members.map((member) => member.id), ['uuid-1', 'uuid-2']);
    expect(members.map((member) => member.displayName), [
      'Ibrahim',
      'nora@example.com',
    ]);
  });

  test('sans nom ni email le fallback ne revele pas les UUID', () {
    final members = householdMembersForDisplay(
      userIds: const ['uuid-1', 'uuid-2'],
      displayNamesByUserId: const {},
    );

    expect(members.map((member) => member.displayName), [
      'Membre du foyer',
      'Membre du foyer',
    ]);
    expect(
      members.any((member) => member.displayName.contains('uuid-')),
      isFalse,
    );
  });
}
