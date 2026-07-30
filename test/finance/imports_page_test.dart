import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/presentation/imports_page.dart';

void main() {
  Future<void> mount(
    WidgetTester t,
    Future<void> Function(CsvImportTemplateDefinition) d,
  ) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ImportsPage(downloader: d)),
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

      await mount(t, fake);
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

    await mount(t, fake);
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
}
