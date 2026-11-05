import 'dart:convert';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveQuickImportTemplate(Uint8List bytes, String fileName) async {
  final href =
      'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,${base64Encode(bytes)}';
  final anchor = web.HTMLAnchorElement()
    ..href = href
    ..download = fileName;
  anchor.click();
}
