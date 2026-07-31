import 'import_account.dart';

enum AccountImportAction { create, alreadyExists }

class AccountImportDecision {
  const AccountImportDecision({required this.account, required this.action});

  final ImportAccount account;
  final AccountImportAction action;
}

class AccountsImportPlan {
  AccountsImportPlan({required List<AccountImportDecision> decisions})
    : decisions = List.unmodifiable(decisions);

  final List<AccountImportDecision> decisions;

  bool get hasConflicts => alreadyExistsCount > 0;

  int get createCount => decisions
      .where((decision) => decision.action == AccountImportAction.create)
      .length;

  int get alreadyExistsCount => decisions
      .where((decision) => decision.action == AccountImportAction.alreadyExists)
      .length;
}
