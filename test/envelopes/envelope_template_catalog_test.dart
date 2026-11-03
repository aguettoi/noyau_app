import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/envelopes/presentation/envelope_template_catalog.dart';
import 'package:noyau_app/features/envelopes/presentation/envelope_template_catalog_page.dart';

void main() {
  test('ENV-TPL is complete in four languages', () {
    final expected = EnvelopeTemplateWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(EnvelopeTemplateWords.keysFor(language), expected);
    }
    expect(envelopeTemplates.length, 21);
  });

  for (final locale in const [
    Locale('fr'),
    Locale('en'),
    Locale('ar'),
    Locale('ar', 'MA'),
  ]) {
    testWidgets(
      'ENV-TPL supports ${locale.toLanguageTag()}, search and multiple selection',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: const [
              Locale('fr'),
              Locale('en'),
              Locale('ar'),
              Locale('ar', 'MA'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const EnvelopeTemplateCatalogPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('envelope-template-groceries')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('envelope-template-groceries')));
        await tester.tap(find.byKey(const Key('envelope-template-transport')));
        await tester.enterText(
          find.byKey(const Key('envelope-template-search')),
          '___missing___',
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.search_off), findsOneWidget);
        expect(tester.takeException(), isNull);
        final direction = Directionality.of(
          tester.element(find.byType(Scaffold)),
        );
        expect(
          direction,
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      },
    );
  }
}
