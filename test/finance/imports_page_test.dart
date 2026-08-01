import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/application/csv_import_validation_pipeline.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_plan.dart';
import 'package:noyau_app/features/finance/application/import_models/import_account.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/presentation/imports_page.dart';

void main() {
  final accounts = byType(ImportTemplateType.accounts);

  Future<void> mount(
    WidgetTester tester, {
    Future<void> Function(CsvImportTemplateDefinition)? downloader,
    CsvFilePicker? pickCsvFile,
    CsvTextLoader? readCsvText,
    CsvImportValidation? validateCsvImport,
    AccountsImportPlanBuilder? buildAccountsImportPlan,
    ValueChanged<String>? onCsvFileSelected,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ImportsPage(
          downloader: downloader ?? (_) async {},
          pickCsvFile: pickCsvFile,
          readCsvText: readCsvText,
          validateCsvImport: validateCsvImport,
          buildAccountsImportPlan:
              buildAccountsImportPlan ??
              (_) => AccountsImportPlan(decisions: []),
          onCsvFileSelected: onCsvFileSelected,
        ),
      ),
    ),
  );

  FilePickerResult csvFile(String path) => FilePickerResult([
    PlatformFile(name: path.split(RegExp(r'[\\/]')).last, path: path, size: 1),
  ]);

  CsvImportValidationResult result(
    CsvImportValidationStage stage, {
    bool isValid = false,
    List<String> errors = const [],
    List<List<String>>? parsedRows,
    AccountsCsvBusinessValidationResult? accountsBusinessResult,
  }) => CsvImportValidationResult(
    stage: stage,
    isValid: isValid,
    errors: errors,
    parsedRows: parsedRows,
    accountsBusinessResult: accountsBusinessResult,
  );

  CsvImportValidationResult validAccountsResult({
    required List<List<String>> rows,
    required List<int?> balances,
  }) => result(
    CsvImportValidationStage.valid,
    isValid: true,
    parsedRows: rows,
    accountsBusinessResult: AccountsCsvBusinessValidationResult(
      rows: List.generate(
        balances.length,
        (index) => AccountsCsvRowValidationResult(
          lineNumber: index + 2,
          errors: const [],
          initialBalanceCents: balances[index],
        ),
      ),
      errors: const [],
    ),
  );

  AccountsImportPlan importPlan(List<AccountImportDecision> decisions) =>
      AccountsImportPlan(decisions: decisions);

  AccountImportDecision decision(String name, AccountImportAction action) =>
      AccountImportDecision(
        account: ImportAccount(
          name: name,
          type: FinancialAccountType.bank,
          openingBalanceCents: null,
        ),
        action: action,
      );

  Future<void> selectTemplate(
    WidgetTester tester,
    CsvImportTemplateDefinition template,
  ) async {
    if (template.type == ImportTemplateType.accounts) {
      return;
    }
    final dropdown = find.byType(DropdownButtonFormField<ImportTemplateType>);
    expect(dropdown, findsOneWidget);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final option = find.text(template.label).last;
    expect(option, findsOneWidget);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final importsList = find.byType(ListView);
    expect(importsList, findsOneWidget);
    final importsScrollable = find.descendant(
      of: importsList,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            widget.physics is AlwaysScrollableScrollPhysics,
      ),
    );
    expect(importsScrollable, findsOneWidget);
    await tester.scrollUntilVisible(target, 200, scrollable: importsScrollable);
    await tester.ensureVisible(target);
    expect(target, findsOneWidget);
  }

  Future<void> selectCsv(WidgetTester tester) async {
    final button = find.byIcon(Icons.upload_file_outlined);
    await reveal(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> mountWithPlan(WidgetTester tester, AccountsImportPlan plan) =>
      mount(
        tester,
        pickCsvFile: () async => csvFile('comptes.csv'),
        readCsvText: (_) async => 'x',
        validateCsvImport: ({required csvText, required template}) =>
            result(CsvImportValidationStage.valid, isValid: true),
        buildAccountsImportPlan: (_) => plan,
      );

  testWidgets('sept templates', (tester) async {
    for (final template in csvImportTemplates) {
      CsvImportTemplateDefinition? received;
      var calls = 0;
      await mount(
        tester,
        downloader: (value) async {
          calls++;
          received = value;
        },
      );
      await tester.pumpAndSettle();
      await selectTemplate(tester, template);
      final download = find.byIcon(Icons.download_outlined);
      expect(download, findsOneWidget, reason: template.id);
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(calls, 1, reason: template.id);
      expect(received, same(template));
      expect(received!.fileName, template.fileName);
      expect(received!.csvContent, template.csvContent);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('téléchargement asynchrone bloque puis réactive les contrôles', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await mount(
      tester,
      downloader: (_) {
        calls++;
        return calls == 1 ? pending.future : Future.value();
      },
    );
    await selectTemplate(tester, byType(ImportTemplateType.envelopes));
    final download = find.byIcon(Icons.download_outlined);
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pump();
    expect(find.byKey(const Key('template-download-progress')), findsOneWidget);
    expect(calls, 1);
    final dropdown = find.byType(DropdownButtonFormField<ImportTemplateType>);
    expect(
      tester
          .widget<DropdownButtonFormField<ImportTemplateType>>(dropdown)
          .onChanged,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-download-progress')), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<ImportTemplateType>>(dropdown)
          .onChanged,
      isNotNull,
    );
    await tester.tap(download);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('sélection CSV affiche le nom et transmet le chemin', (
    tester,
  ) async {
    const path = r'C:\imports\comptes.csv';
    final selected = <String>[];
    await mount(
      tester,
      pickCsvFile: () async => csvFile(path),
      onCsvFileSelected: selected.add,
    );
    await selectCsv(tester);
    expect(find.text('Fichier sélectionné : comptes.csv'), findsOneWidget);
    expect(selected, [path]);
  });

  testWidgets('annulation CSV affiche le message sans callback', (
    tester,
  ) async {
    var callbacks = 0;
    await mount(
      tester,
      pickCsvFile: () async => null,
      onCsvFileSelected: (_) => callbacks++,
    );
    await selectCsv(tester);
    expect(find.text('Sélection annulée.'), findsOneWidget);
    expect(callbacks, 0);
  });

  test('configuration du sélecteur limite aux fichiers csv', () {
    expect(csvPickerConfiguration.type, FileType.custom);
    expect(csvPickerConfiguration.allowedExtensions, const ['csv']);
  });

  testWidgets('sélection CSV lit le fichier avec le chemin exact', (
    tester,
  ) async {
    const path = r'C:\imports\comptes.csv';
    String? readPath;
    await mount(
      tester,
      pickCsvFile: () async => csvFile(path),
      readCsvText: (value) async {
        readPath = value;
        return 'nom,type\nCompte courant,bank';
      },
      validateCsvImport: ({required csvText, required template}) =>
          result(CsvImportValidationStage.valid, isValid: true),
    );
    await selectCsv(tester);
    expect(readPath, path);
    expect(find.text('Fichier lu avec succès.'), findsOneWidget);
  });

  testWidgets('annulation CSV ne lit pas le fichier', (tester) async {
    var reads = 0;
    await mount(
      tester,
      pickCsvFile: () async => null,
      readCsvText: (_) async {
        reads++;
        return '';
      },
    );
    await selectCsv(tester);
    expect(reads, 0);
  });

  testWidgets('erreur de lecture CSV affiche un message sans planter', (
    tester,
  ) async {
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => throw Exception('lecture impossible'),
    );
    await selectCsv(tester);
    expect(find.textContaining('Erreur de lecture :'), findsOneWidget);
    expect(find.byType(ImportsPage), findsOneWidget);
  });

  testWidgets(
    'ImportsPage transmet le texte et le template exacts au pipeline',
    (tester) async {
      String? receivedText;
      CsvImportTemplateDefinition? receivedTemplate;
      await mount(
        tester,
        pickCsvFile: () async => csvFile('comptes.csv'),
        readCsvText: (_) async => 'texte CSV exact',
        validateCsvImport: ({required csvText, required template}) {
          receivedText = csvText;
          receivedTemplate = template;
          return result(CsvImportValidationStage.valid, isValid: true);
        },
      );
      await selectCsv(tester);
      expect(receivedText, 'texte CSV exact');
      expect(receivedTemplate, same(accounts));
    },
  );

  testWidgets('pipeline valide affiche Données métier valides', (tester) async {
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          result(CsvImportValidationStage.valid, isValid: true),
    );
    await selectCsv(tester);
    expect(find.text('Données métier valides.'), findsOneWidget);
  });

  testWidgets('parsing échoué affiche les erreurs de parsing', (tester) async {
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) => result(
        CsvImportValidationStage.parsingFailed,
        errors: ['Erreur de parsing : CSV non fermé'],
      ),
    );
    await selectCsv(tester);
    expect(find.text('Erreur de parsing :'), findsOneWidget);
    expect(find.text('CSV non fermé'), findsOneWidget);
  });

  testWidgets('structure invalide affiche toutes les erreurs structurelles', (
    tester,
  ) async {
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) => result(
        CsvImportValidationStage.structureInvalid,
        errors: ['Colonne Nom absente.', 'Ligne 3 incorrecte.'],
      ),
    );
    await selectCsv(tester);
    expect(find.text('Erreurs de structure :'), findsOneWidget);
    expect(find.text('Colonne Nom absente.'), findsOneWidget);
    expect(find.text('Ligne 3 incorrecte.'), findsOneWidget);
  });

  testWidgets('données métier invalides affiche toutes les erreurs métier', (
    tester,
  ) async {
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) => result(
        CsvImportValidationStage.businessInvalid,
        errors: ['Nom obligatoire.', 'Type invalide.'],
      ),
    );
    await selectCsv(tester);
    expect(find.text('Erreurs métier :'), findsOneWidget);
    expect(find.text('Nom obligatoire.'), findsOneWidget);
    expect(find.text('Type invalide.'), findsOneWidget);
  });

  testWidgets(
    'template non pris en charge affiche Validation métier indisponible',
    (tester) async {
      await mount(
        tester,
        pickCsvFile: () async => csvFile('enveloppes.csv'),
        readCsvText: (_) async => 'x',
        validateCsvImport: ({required csvText, required template}) => result(
          CsvImportValidationStage.unsupportedTemplate,
          errors: ['Validation absente.'],
        ),
      );
      await selectTemplate(tester, byType(ImportTemplateType.envelopes));
      await selectCsv(tester);
      expect(find.text('Validation métier indisponible.'), findsOneWidget);
      expect(find.text('Validation absente.'), findsOneWidget);
    },
  );

  testWidgets('annulation ne lance pas le pipeline', (tester) async {
    var calls = 0;
    await mount(
      tester,
      pickCsvFile: () async => null,
      validateCsvImport: ({required csvText, required template}) {
        calls++;
        return result(CsvImportValidationStage.valid, isValid: true);
      },
    );
    await selectCsv(tester);
    expect(calls, 0);
  });

  testWidgets('erreur de lecture ne lance pas le pipeline', (tester) async {
    var calls = 0;
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => throw Exception('lecture impossible'),
      validateCsvImport: ({required csvText, required template}) {
        calls++;
        return result(CsvImportValidationStage.valid, isValid: true);
      },
    );
    await selectCsv(tester);
    expect(calls, 0);
  });

  testWidgets(
    'exception du pipeline affiche Erreur de validation sans planter',
    (tester) async {
      await mount(
        tester,
        pickCsvFile: () async => csvFile('comptes.csv'),
        readCsvText: (_) async => 'x',
        validateCsvImport: ({required csvText, required template}) =>
            throw StateError('indisponible'),
      );
      await selectCsv(tester);
      expect(find.textContaining('Erreur de validation :'), findsOneWidget);
      expect(find.byType(ImportsPage), findsOneWidget);
    },
  );

  testWidgets('nouvelle sélection remplace l’ancien résultat', (tester) async {
    var attempts = 0;
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) {
        attempts++;
        return attempts == 1
            ? result(
                CsvImportValidationStage.businessInvalid,
                errors: ['Ancienne erreur.'],
              )
            : result(CsvImportValidationStage.valid, isValid: true);
      },
    );
    await selectCsv(tester);
    expect(find.text('Ancienne erreur.'), findsOneWidget);
    await selectCsv(tester);
    expect(find.text('Ancienne erreur.'), findsNothing);
    expect(find.text('Données métier valides.'), findsOneWidget);
  });

  testWidgets("validation réussie affiche le titre Aperçu de l'import", (
    tester,
  ) async {
    final rows = [
      accounts.columns,
      ['', 'Compte courant', 'bank', '', 'actif', '0', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          validAccountsResult(rows: rows, balances: [0]),
    );
    await selectCsv(tester);
    expect(find.text("Aperçu de l'import"), findsOneWidget);
  });

  testWidgets("l'aperçu affiche le nombre exact de comptes", (tester) async {
    final rows = [
      accounts.columns,
      ['', 'Compte courant', 'bank', '', 'actif', '0', ''],
      ['', 'Épargne', 'savings', '', 'actif', '2500', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          validAccountsResult(rows: rows, balances: [0, 250000]),
    );
    await selectCsv(tester);
    expect(find.text('Nombre de comptes : 2'), findsOneWidget);
  });

  testWidgets("l'aperçu affiche tous les comptes validés", (tester) async {
    final rows = [
      accounts.columns,
      ['', 'Compte courant', 'bank', '', 'actif', '0', ''],
      ['', 'Épargne', 'savings', '', 'actif', '2500', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          validAccountsResult(rows: rows, balances: [0, 250000]),
    );
    await selectCsv(tester);
    expect(find.text('Compte courant'), findsOneWidget);
    expect(find.text('Épargne'), findsOneWidget);
  });

  testWidgets("l'aperçu affiche le type de chaque compte", (tester) async {
    final rows = [
      accounts.columns,
      ['', 'Compte courant', 'bank', '', 'actif', '0', ''],
      ['', 'Épargne', 'savings', '', 'actif', '2500', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          validAccountsResult(rows: rows, balances: [0, 250000]),
    );
    await selectCsv(tester);
    expect(find.text('BANK'), findsOneWidget);
    expect(find.text('SAVINGS'), findsOneWidget);
  });

  testWidgets("l'aperçu affiche le solde interprété", (tester) async {
    final rows = [
      accounts.columns,
      ['', 'Épargne', 'savings', '', 'actif', '2500', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          validAccountsResult(rows: rows, balances: [250000]),
    );
    await selectCsv(tester);
    expect(find.text('2 500,00 MAD'), findsOneWidget);
  });

  testWidgets("l'aperçu affiche — lorsque le solde est absent", (tester) async {
    final rows = [
      accounts.columns,
      ['', 'Compte courant', 'bank', '', 'actif', '', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          validAccountsResult(rows: rows, balances: [null]),
    );
    await selectCsv(tester);
    expect(find.text('—'), findsOneWidget);
  });

  for (final stage in [
    CsvImportValidationStage.parsingFailed,
    CsvImportValidationStage.structureInvalid,
    CsvImportValidationStage.businessInvalid,
  ]) {
    testWidgets("l'aperçu est absent lorsque $stage", (tester) async {
      await mount(
        tester,
        pickCsvFile: () async => csvFile('comptes.csv'),
        readCsvText: (_) async => 'x',
        validateCsvImport: ({required csvText, required template}) =>
            result(stage, errors: ['Erreur']),
      );
      await selectCsv(tester);
      expect(find.text("Aperçu de l'import"), findsNothing);
    });
  }

  testWidgets("un nouveau fichier remplace complètement l'ancien aperçu", (
    tester,
  ) async {
    var attempts = 0;
    final firstRows = [
      accounts.columns,
      ['', 'Ancien compte', 'bank', '', 'actif', '0', ''],
    ];
    final secondRows = [
      accounts.columns,
      ['', 'Nouveau compte', 'cash', '', 'actif', '0', ''],
    ];
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) {
        attempts++;
        return attempts == 1
            ? validAccountsResult(rows: firstRows, balances: [0])
            : validAccountsResult(rows: secondRows, balances: [0]);
      },
    );
    await selectCsv(tester);
    expect(find.text('Ancien compte'), findsOneWidget);
    await selectCsv(tester);
    expect(find.text('Ancien compte'), findsNothing);
    expect(find.text('Nouveau compte'), findsOneWidget);
  });

  testWidgets("plan valide affiché", (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Compte courant', AccountImportAction.create)]),
    );
    await selectCsv(tester);
    expect(find.text("Plan d'import"), findsOneWidget);
  });

  testWidgets('nombre de créations affiché', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Nouveau', AccountImportAction.create)]),
    );
    await selectCsv(tester);
    expect(find.text('Comptes à créer : 1'), findsOneWidget);
  });

  testWidgets('nombre de comptes existants affiché', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Existant', AccountImportAction.alreadyExists)]),
    );
    await selectCsv(tester);
    expect(find.text('Comptes déjà existants : 1'), findsOneWidget);
  });

  testWidgets('total affiché', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([
        decision('Nouveau', AccountImportAction.create),
        decision('Existant', AccountImportAction.alreadyExists),
      ]),
    );
    await selectCsv(tester);
    expect(find.text('Total : 2'), findsOneWidget);
  });

  testWidgets('aucun conflit affiché', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Nouveau', AccountImportAction.create)]),
    );
    await selectCsv(tester);
    expect(find.text('Aucun conflit détecté.'), findsOneWidget);
  });

  testWidgets('conflit affiché', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Existant', AccountImportAction.alreadyExists)]),
    );
    await selectCsv(tester);
    expect(find.text('Des comptes existent déjà.'), findsOneWidget);
  });

  testWidgets('liste des décisions affichée', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([
        decision('Nouveau', AccountImportAction.create),
        decision('Existant', AccountImportAction.alreadyExists),
      ]),
    );
    await selectCsv(tester);
    expect(find.text('Nouveau'), findsOneWidget);
    expect(find.text('Existant'), findsOneWidget);
    expect(find.text('À créer'), findsOneWidget);
    expect(find.text('Existe déjà'), findsOneWidget);
  });

  testWidgets('ordre des décisions conservé', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([
        decision('Premier', AccountImportAction.create),
        decision('Second', AccountImportAction.create),
      ]),
    );
    await selectCsv(tester);
    final planList = find.byKey(const Key('accounts-import-plan-list'));
    expect(planList, findsOneWidget);
    await tester.ensureVisible(planList);
    final names = find.descendant(
      of: planList,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Premier' || widget.data == 'Second'),
      ),
    );
    expect(names, findsNWidgets(2));
    expect(tester.widgetList<Text>(names).map((widget) => widget.data), [
      'Premier',
      'Second',
    ]);
  });

  testWidgets('radio Ignorer sélectionnée par défaut', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Existant', AccountImportAction.alreadyExists)]),
    );
    await selectCsv(tester);
    final ignore = find.byKey(const Key('opening-balance-ignore-option'));
    await reveal(tester, ignore);
    final radioGroup = find.byType(RadioGroup<OpeningBalanceConflictChoice>);
    expect(radioGroup, findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<OpeningBalanceConflictChoice>>(radioGroup)
          .groupValue,
      OpeningBalanceConflictChoice.ignoreFileBalance,
    );
  });

  testWidgets('sélection de Remplacer fonctionne', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Existant', AccountImportAction.alreadyExists)]),
    );
    await selectCsv(tester);
    final replace = find.byKey(const Key('opening-balance-replace-option'));
    await reveal(tester, replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    final radioGroup = find.byType(RadioGroup<OpeningBalanceConflictChoice>);
    expect(radioGroup, findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<OpeningBalanceConflictChoice>>(radioGroup)
          .groupValue,
      OpeningBalanceConflictChoice.replaceOpeningBalance,
    );
  });

  testWidgets('bouton Importer présent', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Nouveau', AccountImportAction.create)]),
    );
    await selectCsv(tester);
    final importer = find.byKey(const Key('accounts-import-button'));
    await reveal(tester, importer);
  });

  testWidgets('bouton Importer désactivé', (tester) async {
    await mountWithPlan(
      tester,
      importPlan([decision('Nouveau', AccountImportAction.create)]),
    );
    await selectCsv(tester);
    final importer = find.byKey(const Key('accounts-import-button'));
    await reveal(tester, importer);
    final button = tester.widget<FilledButton>(importer);
    expect(button.onPressed, isNull);
  });

  testWidgets('aucun plan affiché si validation échoue', (tester) async {
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          result(CsvImportValidationStage.businessInvalid, errors: ['Erreur']),
    );
    await selectCsv(tester);
    expect(find.text("Plan d'import"), findsNothing);
    expect(find.byKey(const Key('accounts-import-button')), findsNothing);
  });

  testWidgets('nouveau fichier réinitialise le plan et le choix utilisateur', (
    tester,
  ) async {
    var attempts = 0;
    final conflictPlan = importPlan([
      decision('Existant', AccountImportAction.alreadyExists),
    ]);
    final cleanPlan = importPlan([
      decision('Nouveau', AccountImportAction.create),
    ]);
    await mount(
      tester,
      pickCsvFile: () async => csvFile('comptes.csv'),
      readCsvText: (_) async => 'x',
      validateCsvImport: ({required csvText, required template}) =>
          result(CsvImportValidationStage.valid, isValid: true),
      buildAccountsImportPlan: (_) {
        attempts++;
        return attempts == 1 ? conflictPlan : cleanPlan;
      },
    );
    await selectCsv(tester);
    final replace = find.byKey(const Key('opening-balance-replace-option'));
    await reveal(tester, replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    final importsScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          widget.physics is AlwaysScrollableScrollPhysics,
    );
    expect(importsScrollable, findsOneWidget);
    await tester.drag(importsScrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await selectCsv(tester);
    expect(find.text('Existant'), findsNothing);
    expect(find.text('Nouveau'), findsOneWidget);
    expect(
      find.byKey(const Key('opening-balance-ignore-option')),
      findsNothing,
    );
  });
}
