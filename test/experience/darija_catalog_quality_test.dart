import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/core/localization/dashboard_v2_locale.dart';
import 'package:noyau_app/core/localization/household_locale.dart';
import 'package:noyau_app/core/localization/monthly_close_locale.dart';

void main() {
  test(
    'all source catalogs preserve four-language parity and placeholders',
    () {
      final localeFiles = Directory('lib/core/localization')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('_locale.dart'));

      var catalogCount = 0;
      var darijaEntryCount = 0;
      for (final file in localeFiles) {
        final source = file.readAsStringSync();
        if (!source.contains('AppLanguage.french:')) continue;
        catalogCount++;

        final catalogs = <String, Map<String, String>>{
          for (final language in const [
            'french',
            'english',
            'arabic',
            'darija',
          ])
            language: _catalog(source, language, file.path),
        };
        final referenceKeys = catalogs['french']!.keys.toSet();
        for (final entry in catalogs.entries) {
          expect(
            entry.value.keys.toSet(),
            referenceKeys,
            reason: '${file.path}: ${entry.key} keys must match French',
          );
          for (final key in referenceKeys) {
            final value = entry.value[key]!;
            expect(
              value.trim(),
              isNotEmpty,
              reason: '${file.path}: ${entry.key}.$key must not be empty',
            );
            expect(
              _placeholders(value),
              _placeholders(catalogs['french']![key]!),
              reason:
                  '${file.path}: ${entry.key}.$key must preserve placeholders',
            );
          }
        }
        darijaEntryCount += catalogs['darija']!.length;
      }

      expect(catalogCount, greaterThanOrEqualTo(25));
      expect(darijaEntryCount, greaterThanOrEqualTo(2400));
    },
  );

  test('Darija catalog rejects known false friends', () {
    final sources = Directory('lib/core/localization')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_locale.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    final darijaValues = RegExp(
      r'AppLanguage\.darija:\s*\{([\s\S]*?)(?=\n\s*\},?\s*\n\s*(?:AppLanguage\.|\};))',
    ).allMatches(sources).map((match) => match.group(1)!).join('\n');
    expect(darijaValues, isNot(contains('الشريان')));
    expect(darijaValues, isNot(contains('الموالين')));
    expect(darijaValues, isNot(contains('المهام والتقويم')));
    expect(darijaValues, isNot(contains('الحياة اليومية')));
    expect(darijaValues, isNot(contains('العمليات المتكررة')));
    expect(darijaValues, isNot(contains('نظرة على الحسابات')));
    expect(darijaValues, isNot(contains('المساعد الحتمي')));
  });

  test('Darija uses Moroccan grocery vocabulary', () {
    final words = HouseholdWords(AppLanguage.darija);
    expect(words.text('daily.groceries'), 'التقضية');
    expect(words.text('today.groceries'), 'التقضية ديال الدار');
    expect(words.text('grocery.empty'), 'ليستة التقضية خاوية.');
  });

  test('Darija analytics localizes periods and reconciliation alerts', () {
    final words = DashboardV2Words(AppLanguage.darija);
    expect(words.text('period.currentMonth'), 'هاد الشهر');
    expect(words.text('alert.account_to_reconcile'), 'حساب خاصو المطابقة');
    expect(
      words.format('alert.no_observation_detail', {'account': 'AWB Ibrahim'}),
      'AWB Ibrahim: ما كاينة حتى معاينة.',
    );
  });

  test('Darija monthly close uses natural Moroccan guidance', () {
    final words = MonthlyCloseWords(AppLanguage.darija);
    expect(
      words.format('checklist', {'month': '11/2026'}),
      'مراحل واضحة باش تسالي الشهر • 11/2026',
    );
    expect(words.text('entry_reliability'), 'واش التسجيلات موثوقين');
    expect(words.text('guided_path'), 'المراحل الموجهة');
    expect(words.text('month_health'), 'حالة الشهر');
    expect(words.text('regularizations'), 'تصحيح الفروقات');
    expect(words.text('final_control'), 'آخر مراجعة');
  });

  test('numeric units stay unambiguous in LTR and RTL', () {
    expect(localizedPercent(AppLanguage.french, 86), '86 %');
    expect(localizedPercent(AppLanguage.english, 100), '100%');
    expect(localizedPercent(AppLanguage.arabic, 86), '\u200E86٪\u200E');
    expect(localizedPercent(AppLanguage.darija, 100), '\u200E100٪\u200E');
    expect(localizedMad(-125.50), '\u2066-125.5 MAD\u2069');
  });

  test('Arabic percentage keeps digits before U+066A in an RTL paragraph', () {
    final value = localizedPercent(AppLanguage.darija, 86);
    final text = 'الحالة: $value';
    final numberStart = text.indexOf('86');
    final percentStart = text.indexOf('٪');
    final painter = TextPainter(
      text: TextSpan(text: text),
      textDirection: TextDirection.rtl,
    )..layout();

    final numberBox = painter.getBoxesForSelection(
      TextSelection(baseOffset: numberStart, extentOffset: numberStart + 2),
    );
    final percentBox = painter.getBoxesForSelection(
      TextSelection(baseOffset: percentStart, extentOffset: percentStart + 1),
    );
    expect(numberBox, isNotEmpty);
    expect(percentBox, isNotEmpty);
    expect(numberBox.first.left, lessThan(percentBox.first.left));
  });

  testWidgets('RTL percentage renders as one isolated numeric unit', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Text(localizedPercent(AppLanguage.darija, 86)),
      ),
    );
    expect(find.text('\u200E86٪\u200E'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, String> _catalog(String source, String language, String path) {
  final block = RegExp(
    'AppLanguage\\.$language:\\s*\\{([\\s\\S]*?)'
    r'(?=\n\s*\},?\s*\n\s*(?:AppLanguage\.|\};))',
  ).firstMatch(source);
  expect(block, isNotNull, reason: '$path must contain $language');

  final result = <String, String>{};
  final entryPattern = RegExp(
    r'''^\s*'([^']+)'\s*:\s*((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+),''',
    multiLine: true,
    dotAll: true,
  );
  final literalPattern = RegExp(r'''(?:'((?:\\.|[^'])*)'|"((?:\\.|[^"])*)")''');
  for (final match in entryPattern.allMatches(block!.group(1)!)) {
    result[match.group(1)!] = literalPattern
        .allMatches(match.group(2)!)
        .map((literal) => literal.group(1) ?? literal.group(2)!)
        .join();
  }
  return result;
}

Set<String> _placeholders(String value) => RegExp(
  r'\{[A-Za-z0-9_]+\}',
).allMatches(value).map((match) => match.group(0)!).toSet();
