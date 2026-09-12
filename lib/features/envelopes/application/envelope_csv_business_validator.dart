import '../../finance/application/csv_import_templates.dart';

class EnvelopeImportCandidate {
  const EnvelopeImportCandidate({
    required this.name,
    required this.openingBalanceMad,
    required this.isActive,
    required this.notes,
    required this.lineNumber,
  });

  final String name;
  final String openingBalanceMad;
  final bool isActive;
  final String? notes;
  final int lineNumber;

  Map<String, Object?> toJson() => {
    'name': name,
    'opening_balance': openingBalanceMad,
    'status': isActive ? 'actif' : 'inactif',
    'notes': notes,
  };
}

class EnvelopeCsvBusinessValidationResult {
  const EnvelopeCsvBusinessValidationResult({
    required this.rows,
    required this.errors,
  });

  final List<EnvelopeImportCandidate> rows;
  final List<String> errors;
  bool get isValid => errors.isEmpty;
}

/// Validates initial-envelope values without duplicating ledger rules.
class EnvelopeCsvBusinessValidator {
  EnvelopeCsvBusinessValidationResult validate({
    required List<List<String>> rows,
    required CsvImportTemplateDefinition template,
  }) {
    if (template.type != ImportTemplateType.envelopes || rows.isEmpty) {
      return const EnvelopeCsvBusinessValidationResult(rows: [], errors: []);
    }
    final header = rows.first
        .map((value) => value.trim().toLowerCase())
        .toList(growable: false);
    final indexes = <String, int>{
      for (var index = 0; index < header.length; index++) header[index]: index,
    };
    final candidates = <EnvelopeImportCandidate>[];
    final errors = <String>[];
    final seen = <String>{};
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.trim().isEmpty)) {
        continue;
      }
      final line = rowIndex + 1;
      String value(String key) {
        final index = indexes[key];
        return index == null || index >= row.length ? '' : row[index].trim();
      }

      final name = value('nom');
      final normalizedName = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty) {
        errors.add('Ligne $line : le nom de l’enveloppe est obligatoire.');
        continue;
      }
      if (!seen.add(normalizedName)) {
        continue;
      }
      final amount = value('solde_initial');
      final normalizedAmount = amount.isEmpty
          ? '0.00'
          : amount.replaceAll(',', '.');
      if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalizedAmount)) {
        errors.add(
          'Ligne $line : le solde initial doit être un montant MAD positif ou nul.',
        );
        continue;
      }
      final status = value('statut').toLowerCase();
      if (status.isNotEmpty && status != 'actif' && status != 'inactif') {
        errors.add('Ligne $line : le statut doit être actif ou inactif.');
        continue;
      }
      final parts = normalizedAmount.split('.');
      final openingBalanceMad =
          '${int.parse(parts.first)}.${parts.length == 1 ? '00' : parts.last.padRight(2, '0')}';
      final notes = value('notes');
      candidates.add(
        EnvelopeImportCandidate(
          name: name.replaceAll(RegExp(r'\s+'), ' '),
          openingBalanceMad: openingBalanceMad,
          isActive: status != 'inactif',
          notes: notes.isEmpty ? null : notes,
          lineNumber: line,
        ),
      );
    }
    return EnvelopeCsvBusinessValidationResult(
      rows: List.unmodifiable(candidates),
      errors: List.unmodifiable(errors),
    );
  }
}
