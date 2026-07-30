import 'dart:convert';

class CsvIssue {
  const CsvIssue(this.line, this.column, this.value, this.code, this.message);
  final int line;
  final String column, value, code, message;
}

class AccountCsvRow {
  const AccountCsvRow(this.line, this.values);
  final int line;
  final Map<String, String> values;
}

class AccountCsvAnalysis {
  const AccountCsvAnalysis({
    required this.valid,
    required this.issues,
    required this.total,
    required this.ignored,
    required this.elapsed,
  });
  final List<AccountCsvRow> valid;
  final List<CsvIssue> issues;
  final int total, ignored;
  final Duration elapsed;
}

class AccountsCsvParser {
  static const columns = [
    'external_id',
    'nom',
    'type',
    'titulaire',
    'statut',
    'solde_initial_centimes',
    'date_solde_initial',
  ];
  AccountCsvAnalysis parse(List<int> bytes) {
    final w = Stopwatch()..start();
    final issues = <CsvIssue>[];
    final valid = <AccountCsvRow>[];
    final text = utf8
        .decode(bytes, allowMalformed: false)
        .replaceFirst('\uFEFF', '');
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.every((x) => x.trim().isEmpty)) {
      return AccountCsvAnalysis(
        valid: valid,
        issues: [
          const CsvIssue(1, '', '', 'empty_file', 'Le fichier est vide.'),
        ],
        total: 0,
        ignored: 0,
        elapsed: w.elapsed,
      );
    }
    final header = lines.first.split(';').map((x) => x.trim()).toList();
    for (final c in columns) {
      if (!header.contains(c)) {
        issues.add(
          CsvIssue(
            1,
            c,
            '',
            'missing_required_column',
            'Colonne attendue absente : $c',
          ),
        );
      }
    }
    for (final c in header) {
      if (!columns.contains(c)) {
        issues.add(
          CsvIssue(1, c, '', 'unknown_column', 'Colonne inconnue : $c'),
        );
      }
    }
    var ignored = 0;
    final ids = <String>{}, logical = <String>{};
    for (var i = 1; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.trim().isEmpty) {
        ignored++;
        continue;
      }
      final v = raw.split(';');
      if (v.length != header.length) {
        issues.add(
          CsvIssue(
            i + 1,
            '',
            '',
            'wrong_column_count',
            'Nombre de colonnes incorrect.',
          ),
        );
        continue;
      }
      final m = {
        for (var j = 0; j < header.length; j++) header[j]: v[j].trim(),
      };
      final name = m['nom'] ?? '',
          type = m['type'] ?? '',
          status = (m['statut'] ?? '').isEmpty ? 'actif' : m['statut']!;
      var bad = false;
      void issue(String c, String code, String msg) {
        issues.add(CsvIssue(i + 1, c, m[c] ?? '', code, msg));
        bad = true;
      }

      if (name.isEmpty) {
        issue('nom', 'empty_required_value', 'Le nom est obligatoire.');
      }
      if (type.isEmpty) {
        issue('type', 'empty_required_value', 'Le type est obligatoire.');
      }
      if (status != 'actif' && status != 'archive') {
        issue('statut', 'invalid_status', 'Statut attendu : actif ou archive.');
      }
      m['statut'] = status;
      final amount = m['solde_initial_centimes'] ?? '';
      if (amount.isNotEmpty && int.tryParse(amount) == null) {
        issue(
          'solde_initial_centimes',
          'invalid_integer',
          'Montant entier en centimes attendu.',
        );
      }
      final date = m['date_solde_initial'] ?? '';
      if (date.isNotEmpty && !_isStrictDate(date)) {
        issue(
          'date_solde_initial',
          'invalid_date',
          'Date YYYY-MM-DD réelle attendue.',
        );
      }
      final id = m['external_id'] ?? '';
      if (id.isNotEmpty && !ids.add(id)) {
        issue(
          'external_id',
          'duplicate_external_id',
          'external_id déjà présent.',
        );
      }
      final key =
          '${name.toLowerCase()}|${(m['titulaire'] ?? '').toLowerCase()}';
      if (name.isNotEmpty && !logical.add(key)) {
        issue(
          'nom',
          'duplicate_logical_account',
          'Compte nom+titulaires déjà présent.',
        );
      }
      if (!bad) {
        valid.add(AccountCsvRow(i + 1, m));
      }
    }
    w.stop();
    return AccountCsvAnalysis(
      valid: valid,
      issues: issues,
      total: lines.length - 1,
      ignored: ignored,
      elapsed: w.elapsed,
    );
  }
}

bool _isStrictDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.year == year &&
      parsed.month == month &&
      parsed.day == day;
}
