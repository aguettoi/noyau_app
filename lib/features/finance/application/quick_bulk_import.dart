import 'dart:typed_data';

import 'package:excel/excel.dart';

enum QuickImportSeverity { blocking, warning, information }

enum QuickImportKind { expense, income }

class QuickImportIssue {
  const QuickImportIssue(this.severity, this.code, this.message, {this.row});
  final QuickImportSeverity severity;
  final String code;
  final String message;
  final int? row;
}

class QuickImportReferenceCatalog {
  const QuickImportReferenceCatalog({
    required this.members,
    required this.accounts,
    required this.envelopes,
  });
  final Set<String> members;
  final Set<String> accounts;
  final Set<String> envelopes;
}

class QuickImportRow {
  const QuickImportRow({
    required this.sourceRow,
    required this.kind,
    required this.date,
    required this.amount,
    required this.currency,
    required this.member,
    required this.account,
    required this.envelope,
    required this.category,
    required this.description,
    required this.reference,
    this.ignored = false,
  });
  final int sourceRow;
  final QuickImportKind kind;
  final DateTime date;
  final double amount;
  final String currency;
  final String member;
  final String account;
  final String envelope;
  final String category;
  final String description;
  final String reference;
  final bool ignored;

  String get fingerprint => [
    kind.name,
    date.toIso8601String().substring(0, 10),
    amount.toStringAsFixed(2),
    currency.toUpperCase(),
    member.toLowerCase(),
    account.toLowerCase(),
    envelope.toLowerCase(),
    description.toLowerCase(),
    reference.toLowerCase(),
  ].join('|');

  QuickImportRow copyWith({
    String? member,
    String? account,
    String? envelope,
    bool? ignored,
  }) => QuickImportRow(
    sourceRow: sourceRow,
    kind: kind,
    date: date,
    amount: amount,
    currency: currency,
    member: member ?? this.member,
    account: account ?? this.account,
    envelope: envelope ?? this.envelope,
    category: category,
    description: description,
    reference: reference,
    ignored: ignored ?? this.ignored,
  );
}

class QuickImportPreview {
  const QuickImportPreview({required this.rows, required this.issues});
  final List<QuickImportRow> rows;
  final List<QuickImportIssue> issues;
  bool get canConfirm =>
      issues.every((i) => i.severity != QuickImportSeverity.blocking) &&
      rows.any((r) => !r.ignored);
  int get blockingCount =>
      issues.where((i) => i.severity == QuickImportSeverity.blocking).length;
  int get warningCount =>
      issues.where((i) => i.severity == QuickImportSeverity.warning).length;
}

class QuickBulkImportParser {
  static const headers = <String>[
    'Type',
    'Date',
    'Montant',
    'Devise',
    'Membre',
    'Compte',
    'Enveloppe',
    'Catégorie',
    'Libellé',
    'Référence',
  ];

  QuickImportPreview parse(
    Uint8List bytes,
    QuickImportReferenceCatalog catalog,
  ) {
    final issues = <QuickImportIssue>[];
    final rows = <QuickImportRow>[];
    Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      return const QuickImportPreview(
        rows: [],
        issues: [
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'invalid_file',
            'Le fichier Excel est illisible.',
          ),
        ],
      );
    }
    if (workbook.tables.isEmpty) {
      return const QuickImportPreview(
        rows: [],
        issues: [
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'empty_workbook',
            'Le classeur ne contient aucune feuille.',
          ),
        ],
      );
    }
    final sheet = workbook.tables.values.first;
    if (sheet.rows.isEmpty) {
      return const QuickImportPreview(
        rows: [],
        issues: [
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'empty_sheet',
            'La feuille est vide.',
          ),
        ],
      );
    }
    final actual = sheet.rows.first.map((c) => _text(c?.value)).toList();
    final missing = headers.where((h) => !actual.contains(h)).toList();
    final unknown = actual
        .where((h) => h.isNotEmpty && !headers.contains(h))
        .toList();
    if (missing.isNotEmpty) {
      issues.add(
        QuickImportIssue(
          QuickImportSeverity.blocking,
          'missing_columns',
          'Colonnes obligatoires manquantes : ${missing.join(', ')}.',
        ),
      );
    }
    if (unknown.isNotEmpty) {
      issues.add(
        QuickImportIssue(
          QuickImportSeverity.blocking,
          'unknown_columns',
          'Colonnes inconnues : ${unknown.join(', ')}.',
        ),
      );
    }
    if (missing.isNotEmpty || unknown.isNotEmpty) {
      return QuickImportPreview(rows: rows, issues: issues);
    }
    final index = {for (var i = 0; i < actual.length; i++) actual[i]: i};
    final seen = <String>{};
    for (var i = 1; i < sheet.rows.length; i++) {
      final cells = sheet.rows[i];
      String value(String name) => index[name]! < cells.length
          ? _text(cells[index[name]!]?.value).trim()
          : '';
      if (cells.every((c) => _text(c?.value).trim().isEmpty)) continue;
      final line = i + 1;
      final kindRaw = value('Type').toLowerCase();
      final kind = switch (kindRaw) {
        'dépense' || 'depense' || 'expense' => QuickImportKind.expense,
        'revenu' || 'income' => QuickImportKind.income,
        _ => null,
      };
      final date = _date(value('Date'));
      final amount = double.tryParse(
        value('Montant').replaceAll(' ', '').replaceAll(',', '.'),
      );
      final currency = value('Devise').toUpperCase();
      final member = value('Membre');
      final account = value('Compte');
      final envelope = value('Enveloppe');
      final description = value('Libellé');
      void block(String code, String message) => issues.add(
        QuickImportIssue(
          QuickImportSeverity.blocking,
          code,
          message,
          row: line,
        ),
      );
      if (kind == null) {
        block('invalid_type', 'Type inconnu. Utilisez Dépense ou Revenu.');
      }
      if (date == null) {
        block('invalid_date', 'Date invalide. Format attendu : AAAA-MM-JJ.');
      }
      if (amount == null || amount <= 0) {
        block('invalid_amount', 'Le montant doit être strictement positif.');
      }
      if (currency.isEmpty) {
        block('missing_currency', 'La devise est obligatoire.');
      }
      if (member.isEmpty || !_contains(catalog.members, member)) {
        block('unknown_member', 'Membre inconnu : $member.');
      }
      if (account.isEmpty || !_contains(catalog.accounts, account)) {
        block('unknown_account', 'Compte inconnu : $account.');
      }
      if (envelope.isNotEmpty && !_contains(catalog.envelopes, envelope)) {
        block('unknown_envelope', 'Enveloppe inconnue : $envelope.');
      }
      if (description.isEmpty) {
        block('missing_description', 'Le libellé est obligatoire.');
      }
      if (kind == null || date == null || amount == null || amount <= 0) {
        continue;
      }
      final row = QuickImportRow(
        sourceRow: line,
        kind: kind,
        date: date,
        amount: amount,
        currency: currency,
        member: member,
        account: account,
        envelope: envelope,
        category: value('Catégorie'),
        description: description,
        reference: value('Référence'),
      );
      if (!seen.add(row.fingerprint)) {
        issues.add(
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'duplicate_in_file',
            'Doublon détecté dans le fichier.',
            row: line,
          ),
        );
      }
      rows.add(row);
    }
    if (rows.isEmpty && issues.isEmpty) {
      issues.add(
        const QuickImportIssue(
          QuickImportSeverity.blocking,
          'no_rows',
          'Aucune opération à importer.',
        ),
      );
    }
    return QuickImportPreview(
      rows: List.unmodifiable(rows),
      issues: List.unmodifiable(issues),
    );
  }

  QuickImportPreview applyBulkCorrection(
    QuickImportPreview preview,
    QuickImportReferenceCatalog catalog, {
    String? member,
    String? account,
    String? envelope,
  }) {
    final rows = [
      for (final row in preview.rows)
        row.copyWith(member: member, account: account, envelope: envelope),
    ];
    final issues = preview.issues
        .where(
          (issue) => !const {
            'unknown_member',
            'unknown_account',
            'unknown_envelope',
          }.contains(issue.code),
        )
        .toList();
    for (final row in rows) {
      if (!_contains(catalog.members, row.member)) {
        issues.add(
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'unknown_member',
            'Membre inconnu : ${row.member}.',
            row: row.sourceRow,
          ),
        );
      }
      if (!_contains(catalog.accounts, row.account)) {
        issues.add(
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'unknown_account',
            'Compte inconnu : ${row.account}.',
            row: row.sourceRow,
          ),
        );
      }
      if (row.envelope.isNotEmpty &&
          !_contains(catalog.envelopes, row.envelope)) {
        issues.add(
          QuickImportIssue(
            QuickImportSeverity.blocking,
            'unknown_envelope',
            'Enveloppe inconnue : ${row.envelope}.',
            row: row.sourceRow,
          ),
        );
      }
    }
    return QuickImportPreview(
      rows: List.unmodifiable(rows),
      issues: List.unmodifiable(issues),
    );
  }

  static bool _contains(Set<String> values, String value) =>
      values.any((v) => v.trim().toLowerCase() == value.trim().toLowerCase());
  static String _text(dynamic value) => value?.toString() ?? '';
  static DateTime? _date(String value) {
    final iso = DateTime.tryParse(value);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    final date = DateTime(y, m, d);
    return date.day == d && date.month == m && date.year == y ? date : null;
  }
}

Uint8List buildQuickImportTemplate() {
  final excel = Excel.createExcel();
  final sheet = excel['Opérations'];
  excel.delete('Sheet1');
  sheet.appendRow(
    QuickBulkImportParser.headers.map(TextCellValue.new).toList(),
  );
  sheet.appendRow(<CellValue>[
    TextCellValue('Dépense'),
    TextCellValue('2026-01-31'),
    DoubleCellValue(125.50),
    TextCellValue('MAD'),
    TextCellValue('Nom du membre'),
    TextCellValue('Nom du compte'),
    TextCellValue('Nom de l’enveloppe'),
    TextCellValue('Courses'),
    TextCellValue('Exemple à supprimer'),
    TextCellValue('EXEMPLE-001'),
  ]);
  final info = excel['Instructions'];
  info.appendRow([TextCellValue('FINANCIEL PILOTE — Import rapide')]);
  info.appendRow([
    TextCellValue(
      'Une ligne = une dépense ou un revenu. Aucun identifiant technique n’est demandé.',
    ),
  ]);
  info.appendRow([
    TextCellValue(
      'Date : AAAA-MM-JJ. Montant positif. Type : Dépense ou Revenu.',
    ),
  ]);
  info.appendRow([
    TextCellValue(
      'Utilisez exactement les noms affichés dans l’application pour le membre, le compte et l’enveloppe.',
    ),
  ]);
  info.appendRow([
    TextCellValue('Supprimez la ligne d’exemple avant l’import.'),
  ]);
  return Uint8List.fromList(excel.encode()!);
}
