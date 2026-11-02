import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/assistant/presentation/assistant_locale.dart';

void main() {
  test('assistant catalog is complete in four languages', () {
    final reference = AssistantWords.keysFor(AppLanguage.french);
    expect(reference, isNotEmpty);
    for (final language in AppLanguage.values) {
      final keys = AssistantWords.keysFor(language);
      expect(keys, reference, reason: language.name);
      for (final key in keys) {
        expect(AssistantWords(language).text(key).trim(), isNotEmpty);
      }
    }
  });

  test('assistant respects LTR and RTL rendering locales', () {
    expect(AppLanguage.french.locale.languageCode, 'fr');
    expect(AppLanguage.english.locale.languageCode, 'en');
    expect(AppLanguage.arabic.locale.languageCode, 'ar');
    expect(AppLanguage.darija.storageCode, 'ary');
    expect(AppLanguage.darija.locale, const Locale('ar', 'MA'));
  });
}
