import 'dart:convert';

import 'package:flutter/services.dart';

/// Read-only extract from the household workbook; it is not a database seed.
class SourceEnvelopeImport {
  static const _assetPath = 'assets/source/envelopes_from_excel.json';

  static Future<List<String>> loadEnvelopeNames() async {
    final raw = await rootBundle.loadString(_assetPath);
    final document = jsonDecode(raw) as Map<String, dynamic>;
    return List.unmodifiable(
      (document['envelopes'] as List<dynamic>).cast<String>(),
    );
  }
}
