import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_text_reader.dart';

void main() {
  test('lit UTF-8 et BOM', () async {
    final r = CsvTextReader(
      readBytes: (_) => Future.value(utf8.encode('\uFEFFé')),
    );
    expect(await r.readCsvFileAsUtf8('x'), 'é');
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
}
