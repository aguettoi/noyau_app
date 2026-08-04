import '../../domain/financial_account.dart';
import '../../domain/account_ownership.dart';

class ImportAccount {
  const ImportAccount({
    required this.name,
    required this.type,
    required this.openingBalanceCents,
    this.ownershipType = AccountOwnershipType.household,
    this.holderUserIds = const [],
  });

  final String name;
  final FinancialAccountType type;

  /// null = aucun solde fourni.
  final int? openingBalanceCents;
  final AccountOwnershipType ownershipType;
  final List<String> holderUserIds;
}
