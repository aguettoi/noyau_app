import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/application/csv_import_validation_pipeline.dart';
import 'package:noyau_app/features/finance/application/csv_text_parser.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_model_builder.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_plan.dart';
import 'package:noyau_app/features/finance/application/import_models/import_account.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/imports_page.dart';

void main() {
  final accounts = byType(ImportTemplateType.accounts);

  FilePickerResult csvFile(String path) => FilePickerResult([
    PlatformFile(name: 'comptes.csv', path: path, size: 1),
  ]);

  Future<void> mount(
    WidgetTester tester, {
    required CsvFilePicker picker,
    required CsvImportValidation validation,
    AccountsImportPlanBuilder? planBuilder,
  }) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserIdProvider.overrideWithValue(null)],
        child: MaterialApp(
          home: Scaffold(
            body: ImportsPage(
              pickCsvFile: picker,
              readCsvText: (_) async => 'ignored',
              validateCsvImport: validation,
              buildAccountsImportPlan: planBuilder,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectCsv(WidgetTester tester) async {
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
  }

  CsvImportValidationResult validationResult({
    required CsvImportValidationStage stage,
    required bool isValid,
    List<String> errors = const [],
    List<List<String>>? rows,
  }) => CsvImportValidationResult(
    stage: stage,
    isValid: isValid,
    errors: errors,
    parsedRows: rows,
    accountsBusinessResult: rows == null
        ? null
        : const AccountsCsvBusinessValidationResult(rows: [], errors: []),
  );

  test(
    'le template Comptes et la virgule decimale sont parses avec point-virgule',
    () {
      final rows = CsvTextParser().parse(
        '${accounts.header}\n;Compte courant;bank;;actif;44311,70;01/01/2026\n',
      );

      expect(rows.first, accounts.columns);
      expect(rows[1], [
        '',
        'Compte courant',
        'bank',
        '',
        'actif',
        '44311,70',
        '01/01/2026',
      ]);
    },
  );

  test('le pipeline reconnait un en-tete Comptes genere par le template', () {
    final result = CsvImportValidationPipeline().validate(
      csvText:
          '${accounts.header}\n;Compte courant;bank;;actif;44311,70;01/01/2026\n',
      template: accounts,
    );

    expect(result.isValid, isTrue);
    expect(result.stage, CsvImportValidationStage.valid);
  });

  test('le builder Comptes ne depend pas de external_id', () {
    final validationResult = CsvImportValidationResult(
      stage: CsvImportValidationStage.valid,
      isValid: true,
      errors: const [],
      parsedRows: const [
        [
          'nom',
          'type',
          'titulaire',
          'statut',
          'solde_initial_mad',
          'date_solde_initial',
        ],
        ['Compte courant', 'bank', '', 'actif', '', ''],
      ],
      accountsBusinessResult: const AccountsCsvBusinessValidationResult(
        rows: [AccountsCsvRowValidationResult(lineNumber: 2, errors: [])],
        errors: [],
      ),
    );

    final account = AccountsImportModelBuilder().build(validationResult).single;
    expect(account.name, 'Compte courant');
    expect(account.type, FinancialAccountType.bank);
  });

  testWidgets('Reinitialiser efface fichier, erreurs et apercu', (
    tester,
  ) async {
    await mount(
      tester,
      picker: () async => csvFile(r'C:\imports\comptes.csv'),
      validation: ({required csvText, required template}) => validationResult(
        stage: CsvImportValidationStage.businessInvalid,
        isValid: false,
        errors: const ['Erreur a effacer.'],
      ),
    );

    await selectCsv(tester);
    expect(find.text('Erreur a effacer.'), findsOneWidget);
    expect(find.textContaining('comptes.csv'), findsWidgets);

    final reset = find.byType(OutlinedButton, skipOffstage: false).last;
    final resetScrollable = find.ancestor(
      of: reset,
      matching: find.byType(Scrollable),
    );
    expect(resetScrollable, findsOneWidget);
    await tester.drag(resetScrollable, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();

    expect(find.text('Erreur a effacer.'), findsNothing);
    expect(find.textContaining('Fichier s'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Analyser'), findsNothing);
  });

  testWidgets(
    'Reinitialiser remet le choix du solde par defaut et accepte le meme fichier',
    (tester) async {
      var selections = 0;
      final conflictPlan = AccountsImportPlan(
        decisions: [
          AccountImportDecision(
            account: const ImportAccount(
              name: 'Existant',
              type: FinancialAccountType.bank,
              openingBalanceCents: null,
            ),
            action: AccountImportAction.alreadyExists,
          ),
        ],
      );
      await mount(
        tester,
        picker: () async {
          selections++;
          return csvFile(r'C:\imports\comptes.csv');
        },
        validation: ({required csvText, required template}) => validationResult(
          stage: CsvImportValidationStage.valid,
          isValid: true,
          rows: [accounts.columns],
        ),
        planBuilder: (_) => conflictPlan,
      );

      await selectCsv(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      final replace = find.byKey(const Key('opening-balance-replace-option'));
      expect(replace, findsOneWidget);
      await tester.ensureVisible(replace);
      await tester.tap(replace);
      await tester.pumpAndSettle();

      final reset = find.byType(OutlinedButton).last;
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('opening-balance-replace-option')),
        findsNothing,
      );

      await selectCsv(tester);
      expect(selections, 2);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      final radioGroup = find.byType(RadioGroup<OpeningBalanceConflictChoice>);
      expect(radioGroup, findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<OpeningBalanceConflictChoice>>(radioGroup)
            .groupValue,
        OpeningBalanceConflictChoice.ignoreFileBalance,
      );
    },
  );
}
