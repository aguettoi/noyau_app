import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/presentation/imports_page.dart';

void main() {
  Future<void> mount(
    WidgetTester t, {
    Future<void> Function(CsvImportTemplateDefinition)? downloader,
    CsvFilePicker? pickCsvFile,
    CsvTextLoader? readCsvText,
    CsvTextParse? parseCsvText,
    ValueChanged<String>? onCsvFileSelected,
  }) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ImportsPage(
          downloader: downloader ?? (_) async {},
          pickCsvFile: pickCsvFile,
          readCsvText: readCsvText,
          parseCsvText: parseCsvText,
          onCsvFileSelected: onCsvFileSelected,
        ),
      ),
    ),
  );
  testWidgets('sept templates', (t) async {
    for (final x in csvImportTemplates) {
      CsvImportTemplateDefinition? got;
      var calls = 0;
      Future<void> fake(CsvImportTemplateDefinition v) async {
        calls++;
        got = v;
      }

      await mount(t, downloader: fake);
      await t.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<ImportTemplateType>);
      expect(dropdown, findsOneWidget, reason: x.type.name);
      if (x.type != ImportTemplateType.accounts) {
        await t.ensureVisible(dropdown);
        await t.tap(dropdown);
        await t.pumpAndSettle();
        final option = find.text(x.label).last;
        expect(option, findsOneWidget, reason: x.id);
        await t.tap(option);
        await t.pumpAndSettle();
      }
      final download = find.byIcon(Icons.download_outlined);
      expect(download, findsOneWidget, reason: x.id);
      await t.ensureVisible(download);
      await t.tap(download);
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(got, same(x));
      expect(got!.fileName, x.fileName);
      expect(got!.csvContent, x.csvContent);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    }
  });
  testWidgets('téléchargement asynchrone bloque puis réactive les contrôles', (
    t,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    Future<void> fake(CsvImportTemplateDefinition _) {
      calls++;
      return calls == 1 ? pending.future : Future.value();
    }

    await mount(t, downloader: fake);
    final dropdown = find.byType(DropdownButtonFormField<ImportTemplateType>);
    await t.ensureVisible(dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text(byType(ImportTemplateType.envelopes).label).last);
    await t.pumpAndSettle();
    final download = find.byIcon(Icons.download_outlined);
    await t.ensureVisible(download);
    await t.tap(download);
    await t.pump();
    expect(find.byKey(const Key('template-download-progress')), findsOneWidget);
    expect(calls, 1);
    expect(
      t.widget<DropdownButtonFormField<ImportTemplateType>>(dropdown).onChanged,
      isNull,
    );
    pending.complete();
    await t.pump();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('template-download-progress')), findsNothing);
    expect(
      t.widget<DropdownButtonFormField<ImportTemplateType>>(dropdown).onChanged,
      isNotNull,
    );
    await t.tap(download);
    await t.pump();
    expect(calls, 2);
  });
  testWidgets('sélection CSV affiche le nom et transmet le chemin', (t) async {
    const path = r'C:\imports\comptes.csv';
    var received = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportsPage(
            pickCsvFile: () async => FilePickerResult([
              PlatformFile(name: 'comptes.csv', path: path, size: 123),
            ]),
            onCsvFileSelected: received.add,
          ),
        ),
      ),
    );
    final select = find.byIcon(Icons.upload_file_outlined);
    expect(select, findsOneWidget);
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();
    expect(find.text('Fichier sélectionné : comptes.csv'), findsOneWidget);
    expect(received, [path]);
  });
  testWidgets('annulation CSV affiche le message sans callback', (t) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportsPage(
            pickCsvFile: () async => null,
            onCsvFileSelected: (_) => calls++,
          ),
        ),
      ),
    );
    final select = find.byIcon(Icons.upload_file_outlined);
    expect(select, findsOneWidget);
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();
    expect(find.text('Sélection annulée.'), findsOneWidget);
    expect(calls, 0);
  });
  test('configuration du sélecteur limite aux fichiers csv', () {
    expect(csvPickerConfiguration.type, FileType.custom);
    expect(csvPickerConfiguration.allowedExtensions, const ['csv']);
  });
  testWidgets('sélection CSV lit le fichier avec le chemin exact', (t) async {
    const path = r'C:\imports\comptes.csv';
    String? readPath;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportsPage(
            pickCsvFile: () async => FilePickerResult([
              PlatformFile(name: 'comptes.csv', path: path, size: 1),
            ]),
            readCsvText: (value) async {
              readPath = value;
              return 'nom,type\nCash,CASH';
            },
          ),
        ),
      ),
    );
    await t.tap(find.byIcon(Icons.upload_file_outlined));
    await t.pumpAndSettle();
    expect(readPath, path);
    expect(find.text('Fichier lu avec succès.'), findsOneWidget);
  });
  testWidgets('annulation CSV ne lit pas le fichier', (t) async {
    var reads = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportsPage(
            pickCsvFile: () async => null,
            readCsvText: (_) async {
              reads++;
              return '';
            },
          ),
        ),
      ),
    );
    await t.tap(find.byIcon(Icons.upload_file_outlined));
    await t.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('Sélection annulée.'), findsOneWidget);
  });
  testWidgets('erreur de lecture CSV affiche un message sans planter', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportsPage(
            pickCsvFile: () async => FilePickerResult([
              PlatformFile(name: 'comptes.csv', path: 'x.csv', size: 1),
            ]),
            readCsvText: (_) async => throw Exception('lecture impossible'),
          ),
        ),
      ),
    );
    await t.tap(find.byIcon(Icons.upload_file_outlined));
    await t.pumpAndSettle();
    expect(find.textContaining('Erreur de lecture :'), findsOneWidget);
    expect(find.byType(ImportsPage), findsOneWidget);
  });

  testWidgets('lecture réussie parse le contenu exact', (t) async {
    const path = r'C:\imports\comptes.csv';
    const csvText = 'nom,type\nCash,CASH';
    String? parsedText;

    await mount(
      t,
      pickCsvFile: () async => FilePickerResult([
        PlatformFile(name: 'comptes.csv', path: path, size: 1),
      ]),
      readCsvText: (_) async => csvText,
      parseCsvText: (text) {
        parsedText = text;
        return const [
          ['nom', 'type'],
          ['Cash', 'CASH'],
        ];
      },
    );

    final select = find.byIcon(Icons.upload_file_outlined);
    expect(select, findsOneWidget);
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();

    expect(parsedText, csvText);
    expect(find.text('Fichier lu avec succès.'), findsOneWidget);
    expect(find.text('CSV analysé avec succès.'), findsOneWidget);
  });

  testWidgets('annulation CSV ne lance pas le parsing', (t) async {
    var parserCalls = 0;

    await mount(
      t,
      pickCsvFile: () async => null,
      readCsvText: (_) async => '',
      parseCsvText: (_) {
        parserCalls++;
        return const [];
      },
    );

    final select = find.byIcon(Icons.upload_file_outlined);
    expect(select, findsOneWidget);
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();

    expect(parserCalls, 0);
    expect(find.text('Sélection annulée.'), findsOneWidget);
  });

  testWidgets('erreur de lecture CSV ne lance pas le parsing', (t) async {
    var parserCalls = 0;

    await mount(
      t,
      pickCsvFile: () async => FilePickerResult([
        PlatformFile(name: 'comptes.csv', path: 'comptes.csv', size: 1),
      ]),
      readCsvText: (_) async => throw Exception('lecture impossible'),
      parseCsvText: (_) {
        parserCalls++;
        return const [];
      },
    );

    final select = find.byIcon(Icons.upload_file_outlined);
    expect(select, findsOneWidget);
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();

    expect(parserCalls, 0);
    expect(find.textContaining('Erreur de lecture :'), findsOneWidget);
  });

  testWidgets('erreur de parsing CSV affiche un message sans planter', (
    t,
  ) async {
    await mount(
      t,
      pickCsvFile: () async => FilePickerResult([
        PlatformFile(name: 'comptes.csv', path: 'comptes.csv', size: 1),
      ]),
      readCsvText: (_) async => 'nom,type\nCash,CASH',
      parseCsvText: (_) => throw const FormatException('CSV invalide'),
    );

    final select = find.byIcon(Icons.upload_file_outlined);
    expect(select, findsOneWidget);
    await t.ensureVisible(select);
    await t.tap(select);
    await t.pumpAndSettle();

    expect(find.textContaining('Erreur de parsing :'), findsOneWidget);
    expect(find.byType(ImportsPage), findsOneWidget);
  });
}
