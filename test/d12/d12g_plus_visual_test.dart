import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/fp_universe_hub.dart';
import 'package:noyau_app/features/finance/application/quick_bulk_import.dart';
import 'package:noyau_app/features/finance/presentation/quick_bulk_import_page.dart';

void main() {
  const catalog = QuickImportReferenceCatalog(
    members: {'Sara'},
    accounts: {'Compte courant'},
    envelopes: {'Courses'},
  );

  testWidgets('D1.2-G Plus desktop', (tester) async {
    await _surface(tester, const Size(1440, 1000), _plusHub());
    await expectLater(
      find.byType(FpUniverseHub),
      matchesGoldenFile('runtime_goldens/d12g_01_plus_desktop.png'),
    );
  });

  testWidgets('D1.2-G Plus compact RTL', (tester) async {
    await _surface(
      tester,
      const Size(390, 844),
      _plusHub(),
      locale: const Locale('ar'),
    );
    await expectLater(
      find.byType(FpUniverseHub),
      matchesGoldenFile('runtime_goldens/d12g_02_plus_mobile_rtl.png'),
    );
  });

  testWidgets('D1.2-G quick import upload', (tester) async {
    await _surface(
      tester,
      const Size(1100, 900),
      const QuickBulkImportPage(referenceCatalog: catalog),
    );
    await expectLater(
      find.byType(QuickBulkImportPage),
      matchesGoldenFile('runtime_goldens/d12g_03_quick_import_upload.png'),
    );
  });

  testWidgets('D1.2-G quick import errors and correction', (tester) async {
    await _surface(
      tester,
      const Size(1100, 1000),
      QuickBulkImportPage(
        referenceCatalog: catalog,
        pickBytes: () async => _book([
          [
            'Dépense',
            '2026-11-01',
            '25',
            'MAD',
            'Inconnu',
            'Absent',
            'Absente',
            '',
            'Taxi',
            'R-1',
          ],
        ]),
      ),
    );
    await tester.tap(find.byKey(const Key('quick-import-file-picker')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(QuickBulkImportPage),
      matchesGoldenFile('runtime_goldens/d12g_04_quick_import_errors.png'),
    );
  });

  testWidgets('D1.2-G quick import preview', (tester) async {
    await _surface(
      tester,
      const Size(1100, 1000),
      QuickBulkImportPage(
        referenceCatalog: catalog,
        pickBytes: () async => _book([
          [
            'Dépense',
            '2026-11-01',
            '25',
            'MAD',
            'Sara',
            'Compte courant',
            'Courses',
            '',
            'Taxi',
            'R-2',
          ],
        ]),
        commit: (rows) async => rows.length,
      ),
    );
    await tester.tap(find.byKey(const Key('quick-import-file-picker')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(QuickBulkImportPage),
      matchesGoldenFile('runtime_goldens/d12g_05_quick_import_preview.png'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('quick-import-confirm')),
      250,
    );
    await tester.tap(find.byKey(const Key('quick-import-confirm')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile(
        'runtime_goldens/d12g_06_quick_import_confirmation.png',
      ),
    );
  });
}

Widget _plusHub() => Scaffold(
  body: FpUniverseHub(
    titleKey: 'more',
    subtitleKey: 'more.subtitle',
    destinations: [
      for (final item in const [
        ('assistant', Icons.auto_awesome_outlined, 'more.tools'),
        ('reports', Icons.assessment_outlined, 'more.tools'),
        ('imports', Icons.upload_file_outlined, 'more.tools'),
        ('portability', Icons.inventory_2_outlined, 'more.tools'),
        ('members', Icons.group_outlined, 'more.householdAccess'),
        ('settings', Icons.settings_outlined, 'more.application'),
        ('onboarding', Icons.route_outlined, 'more.application'),
        ('help', Icons.help_outline, 'more.application'),
      ])
        FpUniverseDestination(
          labelKey: item.$1,
          icon: item.$2,
          sectionKey: item.$3,
          open: _noop,
        ),
    ],
  ),
);

void _noop() {}

Future<void> _surface(
  WidgetTester tester,
  Size size,
  Widget child, {
  Locale locale = const Locale('fr'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
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
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Uint8List _book(List<List<String>> rows) {
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
