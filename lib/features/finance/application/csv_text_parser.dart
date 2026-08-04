class CsvTextParser {
  List<List<String>> parse(String text, {String separator = ';'}) {
    if (separator.length != 1) {
      throw ArgumentError.value(
        separator,
        'separator',
        'Le séparateur CSV doit contenir un seul caractère.',
      );
    }
    if (text.isEmpty) return const [];
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        if (field.isNotEmpty) {
          throw const FormatException('Guillemet inattendu dans un champ CSV.');
        }
        quoted = true;
      } else if (c == separator) {
        row.add(field.toString());
        field = StringBuffer();
      } else if (c == '\n') {
        if (field.isNotEmpty && field.toString().endsWith('\r')) {
          final v = field.toString();
          field = StringBuffer(v.substring(0, v.length - 1));
        }
        row.add(field.toString());
        rows.add(row);
        row = [];
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    if (quoted) {
      throw const FormatException('Champ CSV entre guillemets non fermé.');
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
