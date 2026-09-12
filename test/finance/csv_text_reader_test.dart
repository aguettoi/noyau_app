import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_text_reader.dart';

void main() {
  test('lit UTF-8 sans BOM', () async {
    final r = CsvTextReader(
      readBytes: (_) => Future.value(utf8.encode('nom\nÉpargne vacances\n')),
    );
    expect(await r.readCsvFileAsUtf8('x'), 'nom\nÉpargne vacances\n');
  });
  test('lit UTF-8 avec BOM', () async {
    final r = CsvTextReader(
      readBytes: (_) => Future.value(utf8.encode('\uFEFFÉpargne vacances')),
    );
    expect(await r.readCsvFileAsUtf8('x'), 'Épargne vacances');
  });
  test('lit les fins de ligne Windows', () async {
    final r = CsvTextReader(
      readBytes: (_) =>
          Future.value(utf8.encode('nom\r\nÉpargne vacances\r\n')),
    );
    expect(await r.readCsvFileAsUtf8('x'), 'nom\r\nÉpargne vacances\r\n');
  });
  test('lit fichier vide', () async {
    final r = CsvTextReader(readBytes: (_) => Future.value([]));
    expect(await r.readCsvFileAsUtf8('x'), '');
  });
  test('erreurs claires', () async {
    final missing = CsvTextReader(
      readBytes: (_) => Future.error(FileSystemException()),
    );
    await expectLater(missing.readCsvFileAsUtf8('x'), throwsFormatException);
    final invalid = CsvTextReader(readBytes: (_) => Future.value([0xff]));
    await expectLater(invalid.readCsvFileAsUtf8('x'), throwsFormatException);
  });
  test(
    'un CSV Windows-1252 est refusé avec une aide Excel explicite',
    () async {
      final reader = CsvTextReader(
        readBytes: (_) =>
            Future.value([0x6e, 0x6f, 0x6d, 0x0a, 0x43, 0x61, 0x66, 0xe9]),
      );

      await expectLater(
        reader.readCsvFileAsUtf8('x'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('CSV UTF-8'),
          ),
        ),
      );
    },
  );
}
