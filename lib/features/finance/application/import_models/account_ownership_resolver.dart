import '../../domain/account_ownership.dart';
import '../../domain/household_member.dart';

class AccountOwnershipResolution {
  const AccountOwnershipResolution({
    required this.ownershipType,
    required this.holderUserIds,
  });

  final AccountOwnershipType ownershipType;
  final List<String> holderUserIds;
}

class AccountOwnershipResolver {
  const AccountOwnershipResolver();

  AccountOwnershipResolution resolve({
    required String rawValue,
    required Iterable<HouseholdMember> members,
  }) {
    final value = rawValue.trim();
    final memberList = members.toList(growable: false);
    if (value.isEmpty || _isHousehold(value)) {
      return AccountOwnershipResolution(
        ownershipType: AccountOwnershipType.household,
        holderUserIds: List.unmodifiable(memberList.map((member) => member.id)),
      );
    }
    final tokens = value.split('|').map((item) => item.trim()).toList();
    if (tokens.any((item) => item.isEmpty)) {
      throw StateError('Chaque titulaire doit être renseigné.');
    }
    final ids = <String>[];
    for (final token in tokens) {
      final matches = memberList.where(
        (member) =>
            member.id == token ||
            member.displayName.trim().toLowerCase() == token.toLowerCase(),
      );
      if (matches.isEmpty) {
        throw StateError("Le titulaire '$token' est inconnu dans ce foyer.");
      }
      if (matches.length > 1) {
        throw StateError("Le titulaire '$token' est ambigu dans ce foyer.");
      }
      final userId = matches.single.id;
      if (ids.contains(userId)) {
        throw StateError("Le titulaire '$token' est présent plusieurs fois.");
      }
      ids.add(userId);
    }
    return AccountOwnershipResolution(
      ownershipType: ids.length == 1
          ? AccountOwnershipType.individual
          : AccountOwnershipType.shared,
      holderUserIds: List.unmodifiable(ids),
    );
  }

  static bool _isHousehold(String value) => switch (value.toLowerCase()) {
    'commun' || 'household' || 'foyer' => true,
    _ => false,
  };
}
