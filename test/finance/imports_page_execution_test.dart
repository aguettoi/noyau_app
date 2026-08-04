import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_validation_pipeline.dart';
import 'package:noyau_app/features/finance/application/import_execution/accounts_import_execution.dart';
import 'package:noyau_app/features/finance/application/import_execution/accounts_import_executor.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_plan.dart';
import 'package:noyau_app/features/finance/application/import_models/import_account.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/imports_page.dart';

void main() {
  const activeHousehold = ActiveHouseholdState(
    status: ActiveHouseholdStatus.singleHousehold,
    householdId: 'household-1',
    householdIds: ['household-1'],
  );

  FilePickerResult csvFile() => FilePickerResult([
    PlatformFile(name: 'comptes.csv', path: r'C:\imports\comptes.csv', size: 1),
  ]);

  CsvImportValidationResult validResult() => const CsvImportValidationResult(
    stage: CsvImportValidationStage.valid,
    isValid: true,
    errors: [],
    parsedRows: [
      ['nom', 'type'],
      ['Compte importe', 'bank'],
    ],
    accountsBusinessResult: AccountsCsvBusinessValidationResult(
      rows: [AccountsCsvRowValidationResult(lineNumber: 2, errors: [])],
      errors: [],
    ),
  );

  AccountsImportPlan plan({bool existing = false}) => AccountsImportPlan(
    decisions: [
      AccountImportDecision(
        account: const ImportAccount(
          name: 'Compte importe',
          type: FinancialAccountType.bank,
          openingBalanceCents: 0,
        ),
        action: existing
            ? AccountImportAction.alreadyExists
            : AccountImportAction.create,
      ),
    ],
  );

  Future<void> mount(
    WidgetTester tester, {
    required ActiveHouseholdState household,
    required AccountsImportExecutor executor,
    required AccountsImportPlan importPlan,
    required String Function() idGenerator,
  }) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ImportsPage(
              activeHousehold: household,
              importExecutor: executor,
              importExecutionIdGenerator: idGenerator,
              pickCsvFile: () async => csvFile(),
              readCsvText: (_) async => 'ignored',
              validateCsvImport: ({required csvText, required template}) =>
                  validResult(),
              buildAccountsImportPlan: (_) => importPlan,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectFileAndRevealImport(WidgetTester tester) async {
    final upload = find.byIcon(Icons.upload_file_outlined, skipOffstage: false);
    expect(upload, findsOneWidget);
    final scrollable = find.ancestor(
      of: upload,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, 10000));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pumpAndSettle();
    for (
      var index = 0;
      find.byKey(const Key('accounts-import-button')).evaluate().isEmpty &&
          index < 5;
      index++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    final button = find.byKey(const Key('accounts-import-button'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
  }

  testWidgets('bouton desactive sans foyer actif non ambigu', (tester) async {
    final transaction = _Transaction();
    await mount(
      tester,
      household: const ActiveHouseholdState(
        status: ActiveHouseholdStatus.multipleHouseholds,
        householdIds: ['household-1', 'household-2'],
      ),
      executor: _executor(transaction),
      importPlan: plan(),
      idGenerator: () => '11111111-1111-4111-8111-111111111111',
    );

    await selectFileAndRevealImport(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('accounts-import-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('Sélectionnez un foyer'), findsOneWidget);
  });

  testWidgets('import transmet plan et identifiant puis affiche le succes', (
    tester,
  ) async {
    final transaction = _Transaction();
    await mount(
      tester,
      household: activeHousehold,
      executor: _executor(transaction),
      importPlan: plan(),
      idGenerator: () => '11111111-1111-4111-8111-111111111111',
    );

    await selectFileAndRevealImport(tester);
    await tester.tap(find.byKey(const Key('accounts-import-button')));
    await tester.pumpAndSettle();

    expect(transaction.executionIds, ['11111111-1111-4111-8111-111111111111']);
    expect(transaction.created, ['Compte importe']);
    expect(find.textContaining('Import terminé dans Supabase'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('accounts-import-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('politique remplacer transmet le remplacement explicite zero', (
    tester,
  ) async {
    final transaction = _Transaction();
    await mount(
      tester,
      household: activeHousehold,
      executor: _executor(transaction),
      importPlan: plan(existing: true),
      idGenerator: () => '22222222-2222-4222-8222-222222222222',
    );

    await selectFileAndRevealImport(tester);
    final replace = find.byKey(const Key('opening-balance-replace-option'));
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accounts-import-button')));
    await tester.pumpAndSettle();

    expect(transaction.replaced, ['Compte importe:0']);
  });

  testWidgets('import bloque le double clic pendant execution', (tester) async {
    final pending = Completer<void>();
    final transaction = _Transaction(pending: pending);
    await mount(
      tester,
      household: activeHousehold,
      executor: _executor(transaction),
      importPlan: plan(),
      idGenerator: () => '33333333-3333-4333-8333-333333333333',
    );

    await selectFileAndRevealImport(tester);
    final button = find.byKey(const Key('accounts-import-button'));
    await tester.tap(button);
    await tester.pump();

    expect(find.byKey(const Key('accounts-import-progress')), findsOneWidget);
    expect(transaction.executionIds, hasLength(1));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('echec conserve identifiant et autorise un retry', (
    tester,
  ) async {
    final transaction = _Transaction(failFirst: true);
    await mount(
      tester,
      household: activeHousehold,
      executor: _executor(transaction),
      importPlan: plan(),
      idGenerator: () => '44444444-4444-4444-8444-444444444444',
    );

    await selectFileAndRevealImport(tester);
    final button = find.byKey(const Key('accounts-import-button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Erreur d’import'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(transaction.executionIds, [
      '44444444-4444-4444-8444-444444444444',
      '44444444-4444-4444-8444-444444444444',
    ]);
  });
}

AccountsImportExecutor _executor(_Transaction transaction) =>
    AccountsImportExecutor(
      runTransaction: ({required importExecutionId, required operation}) async {
        transaction.executionIds.add(importExecutionId);
        if (transaction.failFirst && transaction.executionIds.length == 1) {
          throw Exception('indisponible');
        }
        await transaction.waitIfNeeded();
        await operation(transaction);
        return const AccountsImportTransactionResult(
          AccountsImportTransactionStatus.executed,
        );
      },
    );

class _Transaction implements AccountsImportTransaction {
  _Transaction({this.pending, this.failFirst = false});

  final Completer<void>? pending;
  final bool failFirst;
  final List<String> executionIds = [];
  final List<String> created = [];
  final List<String> replaced = [];

  Future<void> waitIfNeeded() => pending?.future ?? Future.value();

  @override
  Future<void> createAccount(ImportAccount account) async {
    created.add(account.name);
  }

  @override
  Future<void> replaceOpeningBalance({
    required ImportAccount account,
    required int openingBalanceCents,
  }) async {
    replaced.add('${account.name}:$openingBalanceCents');
  }
}
