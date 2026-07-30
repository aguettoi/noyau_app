import 'dart:convert';
import 'dart:io';

typedef CsvBytesReader = Future<List<int>> Function(String path);

class CsvTextReader {
  CsvTextReader({CsvBytesReader? readBytes})
    : _readBytes = readBytes ?? _fromFile;
  final CsvBytesReader _readBytes;
  Future<String> readCsvFileAsUtf8(String path) async {
    try {
      final text = utf8.decode(await _readBytes(path), allowMalformed: false);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FileSystemException {
      throw const FormatException('Fichier CSV introuvable ou inaccessible.');
    } on FormatException {
      throw const FormatException(
        'Le fichier CSV doit être encodé en UTF-8 valide.',
      );
    } catch (_) {
      throw const FormatException('Lecture du fichier CSV impossible.');
    }
  }

  static Future<List<int>> _fromFile(String path) => File(path).readAsBytes();
}
