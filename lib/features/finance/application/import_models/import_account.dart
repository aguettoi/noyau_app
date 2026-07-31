import '../../domain/financial_account.dart';

class ImportAccount {
  const ImportAccount({
    required this.name,
    required this.type,
    required this.openingBalanceCents,
  });

  final String name;
  final FinancialAccountType type;

  /// null = aucun solde fourni.
  final int? openingBalanceCents;
}
