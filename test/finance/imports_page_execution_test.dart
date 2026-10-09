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

  testWidgets('la matérialisation CSV legacy reste neutralisée', (
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
    expect(
      find.textContaining('Matérialisation CSV legacy désactivée'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('accounts-import-button')))
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const Key('opening-balance-replace-option')),
      findsNothing,
    );
    expect(transaction.executionIds, isEmpty);
    expect(transaction.created, isEmpty);
    expect(transaction.replaced, isEmpty);
  });
}

AccountsImportExecutor _executor(_Transaction transaction) =>
    AccountsImportExecutor(
      runTransaction: ({required importExecutionId, required operation}) async {
        transaction.executionIds.add(importExecutionId);
        await transaction.waitIfNeeded();
        await operation(transaction);
        return const AccountsImportTransactionResult(
          AccountsImportTransactionStatus.executed,
        );
      },
    );

class _Transaction implements AccountsImportTransaction {
  final List<String> executionIds = [];
  final List<String> created = [];
  final List<String> replaced = [];

  Future<void> waitIfNeeded() => Future.value();

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
