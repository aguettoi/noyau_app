enum AccountOwnershipType { household, individual, shared }

class AccountHolder {
  const AccountHolder({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
}
