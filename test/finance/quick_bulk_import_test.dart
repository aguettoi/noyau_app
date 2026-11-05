import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:noyau_app/features/finance/application/quick_bulk_import.dart';
import 'package:noyau_app/features/finance/presentation/quick_bulk_import_page.dart';

void main() {
  const catalog = QuickImportReferenceCatalog(
    members: {'Sara', 'Adam'},
    accounts: {'Compte courant'},
    envelopes: {'Courses'},
  );

  test('official template contains business columns and no technical id', () {
    final workbook = Excel.decodeBytes(buildQuickImportTemplate());
    final headers = workbook['Opérations'].rows.first
        .map((cell) => cell?.value.toString())
        .toList();
    expect(headers, QuickBulkImportParser.headers);
    expect(headers.join(' ').toLowerCase(), isNot(contains('uuid')));
    expect(headers.join(' ').toLowerCase(), isNot(contains('supabase')));
  });

  test('valid workbook is previewable without mutation', () {
    final preview = QuickBulkImportParser().parse(
      _workbook([
        [
          'Dépense',
          '2026-11-01',
          '125.50',
          'MAD',
          'Sara',
          'Compte courant',
          'Courses',
          'Alimentation',
          'Marché',
          'REF-1',
        ],
      ]),
      catalog,
    );
    expect(preview.canConfirm, isTrue);
    expect(preview.rows, hasLength(1));
    expect(preview.issues, isEmpty);
  });

  test('missing and unknown columns are blocking', () {
    final excel = Excel.createExcel();
    final sheet = excel['Opérations'];
    excel.delete('Sheet1');
    sheet.appendRow([TextCellValue('Type'), TextCellValue('UUID')]);
    final preview = QuickBulkImportParser().parse(
      Uint8List.fromList(excel.encode()!),
      catalog,
    );
    expect(preview.canConfirm, isFalse);
    expect(
      preview.issues.map((i) => i.code),
      containsAll(['missing_columns', 'unknown_columns']),
    );
  });

  test('invalid references, values and duplicates are blocking', () {
    final preview = QuickBulkImportParser().parse(
      _workbook([
        [
          'Dépense',
          '2026-11-01',
          '50',
          'MAD',
          'Inconnu',
          'Compte courant',
          'Courses',
          '',
          'Taxi',
          'DUP',
        ],
        [
          'Dépense',
          '2026-11-01',
          '50',
          'MAD',
          'Inconnu',
          'Compte courant',
          'Courses',
          '',
          'Taxi',
          'DUP',
        ],
        [
          'Autre',
          '31-99-2026',
          '-1',
          '',
          'Sara',
          'Absent',
          'Absente',
          '',
          '',
          '',
        ],
      ]),
      catalog,
    );
    expect(preview.canConfirm, isFalse);
    expect(
      preview.issues.map((i) => i.code),
      containsAll([
        'unknown_member',
        'duplicate_in_file',
        'invalid_type',
        'invalid_date',
        'invalid_amount',
        'missing_currency',
        'unknown_account',
        'unknown_envelope',
        'missing_description',
      ]),
    );
  });

  test('bulk correction explicitly resolves business references', () {
    final initial = QuickBulkImportParser().parse(
      _workbook([
        [
          'Revenu',
          '2026-11-02',
          '500',
          'MAD',
          'Inconnu',
          'Absent',
          '',
          '',
          'Prime',
          'REF-3',
        ],
      ]),
      catalog,
    );
    final corrected = QuickBulkImportParser().applyBulkCorrection(
      initial,
      catalog,
      member: 'Adam',
      account: 'Compte courant',
    );
    expect(corrected.canConfirm, isTrue);
    expect(corrected.rows.single.member, 'Adam');
  });

  testWidgets('never commits before the explicit confirmation', (tester) async {
    var commits = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('fr'),
          home: QuickBulkImportPage(
            referenceCatalog: catalog,
            pickBytes: () async => _workbook([
              [
                'Dépense',
                '2026-11-01',
                '25',
                'MAD',
                'Sara',
                'Compte courant',
                'Courses',
                '',
                'Pain',
                'REF-2',
              ],
            ]),
            commit: (rows) async {
              commits++;
              return rows.length;
            },
          ),
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('quick-import-file-picker')),
    );
    await tester.tap(find.byKey(const Key('quick-import-file-picker')));
    await tester.pumpAndSettle();
    expect(commits, 0);
    await tester.scrollUntilVisible(
      find.byKey(const Key('quick-import-confirm')),
      300,
    );
    await tester.tap(find.byKey(const Key('quick-import-confirm')));
    await tester.pumpAndSettle();
    expect(commits, 0);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(commits, 1);
  });

  for (final locale in const [
    Locale('fr'),
    Locale('en'),
    Locale('ar'),
    Locale('ar', 'MA'),
  ]) {
    testWidgets(
      'quick import renders ${locale.toLanguageTag()} with direction',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: locale,
              supportedLocales: const [
                Locale('fr'),
                Locale('en'),
                Locale('ar'),
                Locale('ar', 'MA'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const QuickBulkImportPage(referenceCatalog: catalog),
            ),
          ),
        );
        await tester.pump();
        final direction = tester
            .widget<Directionality>(find.byType(Directionality).first)
            .textDirection;
        expect(
          direction,
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(find.byType(Scaffold), findsOneWidget);
      },
    );
  }
}

Uint8List _workbook(List<List<String>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel['Opérations'];
  excel.delete('Sheet1');
  sheet.appendRow(
    QuickBulkImportParser.headers.map(TextCellValue.new).toList(),
  );
  for (final row in rows) {
    sheet.appendRow(row.map(TextCellValue.new).toList());
  }
  return Uint8List.fromList(excel.encode()!);
}
