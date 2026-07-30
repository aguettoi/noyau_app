import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/financial_account.dart';
import '../domain/financial_transaction.dart';
import '../domain/household_member.dart';
import 'source_envelope_import.dart';

final financeWorkspaceProvider =
    AsyncNotifierProvider<FinanceWorkspaceController, FinanceWorkspace>(
      FinanceWorkspaceController.new,
    );

class FinanceWorkspace {
  const FinanceWorkspace({
    required this.members,
    required this.accounts,
    required this.transactions,
    required this.importEnvelopeNames,
  });

  factory FinanceWorkspace.empty(List<String> importEnvelopeNames) =>
      FinanceWorkspace(
        members: const [],
        accounts: const [],
        transactions: const [],
        importEnvelopeNames: importEnvelopeNames,
      );

  final List<HouseholdMember> members;
  final List<FinancialAccount> accounts;
  final List<FinancialTransaction> transactions;
  final List<String> importEnvelopeNames;
}

class FinanceWorkspaceController extends AsyncNotifier<FinanceWorkspace> {
  @override
  Future<FinanceWorkspace> build() async =>
      FinanceWorkspace.empty(await SourceEnvelopeImport.loadEnvelopeNames());
}
