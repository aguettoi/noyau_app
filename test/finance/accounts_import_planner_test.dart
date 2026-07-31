import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_plan.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_planner.dart';
import 'package:noyau_app/features/finance/application/import_models/import_account.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  final planner = AccountsImportPlanner();

  ImportAccount imported(String name) => ImportAccount(
    name: name,
    type: FinancialAccountType.bank,
    openingBalanceCents: 0,
  );

  FinancialAccount existing(String name, {String id = 'id'}) =>
      FinancialAccount(
        id: id,
        name: name,
        type: FinancialAccountType.bank,
        openingBalance: const Money.fromMinorUnits(0),
      );

  test('aucun compte existant produit uniquement des créations', () {
    final plan = planner.plan(
      importedAccounts: [imported('Compte courant'), imported('Épargne')],
      existingAccounts: const [],
    );
    expect(plan.decisions.map((decision) => decision.action), [
      AccountImportAction.create,
      AccountImportAction.create,
    ]);
  });

  test('un compte existant produit alreadyExists', () {
    final plan = planner.plan(
      importedAccounts: [imported('Compte courant')],
      existingAccounts: [existing('Compte courant')],
    );
    expect(plan.decisions.single.action, AccountImportAction.alreadyExists);
  });

  test('plusieurs comptes existants sont reconnus', () {
    final plan = planner.plan(
      importedAccounts: [imported('Compte A'), imported('Compte B')],
      existingAccounts: [
        existing('Compte A', id: 'a'),
        existing('Compte B', id: 'b'),
      ],
    );
    expect(plan.alreadyExistsCount, 2);
  });

  test('la comparaison est insensible à la casse', () {
    final plan = planner.plan(
      importedAccounts: [imported('COMPTE COURANT')],
      existingAccounts: [existing('compte courant')],
    );
    expect(plan.decisions.single.action, AccountImportAction.alreadyExists);
  });

  test('la comparaison ignore les espaces après trim', () {
    final plan = planner.plan(
      importedAccounts: [imported('  Compte courant  ')],
      existingAccounts: [existing('Compte courant')],
    );
    expect(plan.decisions.single.action, AccountImportAction.alreadyExists);
  });

  test('ordre des comptes importés conservé', () {
    final plan = planner.plan(
      importedAccounts: [imported('Premier'), imported('Second')],
      existingAccounts: const [],
    );
    expect(plan.decisions.map((decision) => decision.account.name), [
      'Premier',
      'Second',
    ]);
  });

  test('createCount est correct', () {
    final plan = planner.plan(
      importedAccounts: [imported('Nouveau'), imported('Existant')],
      existingAccounts: [existing('Existant')],
    );
    expect(plan.createCount, 1);
  });

  test('alreadyExistsCount est correct', () {
    final plan = planner.plan(
      importedAccounts: [imported('Nouveau'), imported('Existant')],
      existingAccounts: [existing('Existant')],
    );
    expect(plan.alreadyExistsCount, 1);
  });

  test('hasConflicts est faux sans compte existant', () {
    final plan = planner.plan(
      importedAccounts: [imported('Nouveau')],
      existingAccounts: const [],
    );
    expect(plan.hasConflicts, isFalse);
  });

  test('hasConflicts est vrai avec un compte existant', () {
    final plan = planner.plan(
      importedAccounts: [imported('Existant')],
      existingAccounts: [existing('Existant')],
    );
    expect(plan.hasConflicts, isTrue);
  });

  test('liste vide produit un plan vide', () {
    final plan = planner.plan(
      importedAccounts: const [],
      existingAccounts: const [],
    );
    expect(plan.decisions, isEmpty);
    expect(plan.createCount, 0);
  });

  test('aucune modification des ImportAccount', () {
    final account = imported('Compte courant');
    planner.plan(
      importedAccounts: [account],
      existingAccounts: [existing('Compte courant')],
    );
    expect(account.name, 'Compte courant');
    expect(account.type, FinancialAccountType.bank);
    expect(account.openingBalanceCents, 0);
  });

  test('plusieurs doublons existants sont traités comme un conflit', () {
    final plan = planner.plan(
      importedAccounts: [imported('Compte courant')],
      existingAccounts: [
        existing('Compte courant', id: 'a'),
        existing('Compte courant', id: 'b'),
      ],
    );
    expect(plan.alreadyExistsCount, 1);
  });

  test('nom identique avec espaces est reconnu', () {
    final plan = planner.plan(
      importedAccounts: [imported('Compte courant')],
      existingAccounts: [existing(' Compte courant ')],
    );
    expect(plan.decisions.single.action, AccountImportAction.alreadyExists);
  });
}
