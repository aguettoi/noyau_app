import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/active_household_provider.dart';
import 'providers/supabase_client_provider.dart';
import 'workbook_import.dart';

class CutoverOpeningAccount {
  const CutoverOpeningAccount({
    required this.sourceLabel,
    required this.name,
    required this.kind,
    required this.openingAmount,
    this.conflictDecision = 'create',
  });

  final String sourceLabel;
  final String name;
  final String kind;
  final num openingAmount;
  final String conflictDecision;

  Map<String, Object?> toJson() => {
    'source_label': sourceLabel,
    'name': name,
    'kind': kind,
    'opening_amount': openingAmount,
    'conflict_decision': conflictDecision,
  };
}

class CutoverOpeningEnvelope {
  const CutoverOpeningEnvelope({
    required this.sourceLabel,
    required this.name,
    required this.openingAmount,
    required this.isToAllocate,
    this.conflictDecision = 'create',
  });

  final String sourceLabel;
  final String name;
  final num openingAmount;
  final bool isToAllocate;
  final String conflictDecision;

  Map<String, Object?> toJson() => {
    'source_label': sourceLabel,
    'name': name,
    'opening_amount': openingAmount,
    'is_to_allocate': isToAllocate,
    'conflict_decision': isToAllocate ? 'match' : conflictDecision,
  };
}

class CutoverOpeningPlan {
  const CutoverOpeningPlan({
    required this.cutoverId,
    required this.householdId,
    required this.sourceFingerprint,
    required this.effectiveDate,
    required this.accounts,
    required this.envelopes,
    this.blockingErrors = const [],
    this.warnings = const [],
    this.confirmedAt,
  });

  final String cutoverId;
  final String householdId;
  final String sourceFingerprint;
  final DateTime effectiveDate;
  final List<CutoverOpeningAccount> accounts;
  final List<CutoverOpeningEnvelope> envelopes;
  final List<String> blockingErrors;
  final List<String> warnings;
  final DateTime? confirmedAt;

  bool get canConfirm =>
      blockingErrors.isEmpty && accounts.isNotEmpty && envelopes.isNotEmpty;

  CutoverOpeningPlan confirm(DateTime now) => CutoverOpeningPlan(
    cutoverId: cutoverId,
    householdId: householdId,
    sourceFingerprint: sourceFingerprint,
    effectiveDate: effectiveDate,
    accounts: accounts,
    envelopes: envelopes,
    blockingErrors: blockingErrors,
    warnings: warnings,
    confirmedAt: now,
  );

  Map<String, Object?> toJson() => {
    'cutover_id': cutoverId,
    'household_id': householdId,
    'source_fingerprint': sourceFingerprint,
    'effective_date': formatDate(effectiveDate),
    'accounts': accounts.map((item) => item.toJson()).toList(),
    'envelopes': envelopes.map((item) => item.toJson()).toList(),
    'blocking_errors': blockingErrors,
    'warnings': warnings,
    if (confirmedAt != null) 'confirmed_at': confirmedAt!.toIso8601String(),
  };

  factory CutoverOpeningPlan.fromJson(Map<String, dynamic> json) {
    final accountRows = (json['accounts'] as List<dynamic>? ?? const []);
    final envelopeRows = (json['envelopes'] as List<dynamic>? ?? const []);
    return CutoverOpeningPlan(
      cutoverId: json['cutover_id'] as String,
      householdId: json['household_id'] as String,
      sourceFingerprint: json['source_fingerprint'] as String,
      effectiveDate: DateTime.parse(json['effective_date'] as String),
      accounts: accountRows
          .map((row) {
            final value = Map<String, dynamic>.from(row as Map);
            return CutoverOpeningAccount(
              sourceLabel: value['source_label'] as String? ?? '',
              name: value['name'] as String,
              kind: value['kind'] as String,
              openingAmount: value['opening_amount'] as num,
              conflictDecision:
                  value['conflict_decision'] as String? ?? 'create',
            );
          })
          .toList(growable: false),
      envelopes: envelopeRows
          .map((row) {
            final value = Map<String, dynamic>.from(row as Map);
            return CutoverOpeningEnvelope(
              sourceLabel: value['source_label'] as String? ?? '',
              name: value['name'] as String,
              openingAmount: value['opening_amount'] as num,
              isToAllocate: value['is_to_allocate'] as bool? ?? false,
              conflictDecision:
                  value['conflict_decision'] as String? ?? 'create',
            );
          })
          .toList(growable: false),
      blockingErrors: List<String>.from(
        json['blocking_errors'] as List? ?? const [],
      ),
      warnings: List<String>.from(json['warnings'] as List? ?? const []),
      confirmedAt: json['confirmed_at'] == null
          ? null
          : DateTime.parse(json['confirmed_at'] as String),
    );
  }

  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Extracts only the controlled B1 sheet.  Other workbook sheets remain
/// archived/optional and never become cutover inputs by accident.
class CutoverOpeningPlanBuilder {
  static const sourceSheetName = 'Positions ouverture';

  CutoverOpeningPlan build({
    required WorkbookImportAnalysis analysis,
    required String householdId,
    required DateTime effectiveDate,
    String? cutoverId,
  }) {
    final snapshot = analysis.sourceSheets
        .where(
          (sheet) =>
              _normalise(sheet.sourceSheetName) == _normalise(sourceSheetName),
        )
        .firstOrNull;
    final errors = <String>[];
    final accounts = <CutoverOpeningAccount>[];
    final envelopes = <CutoverOpeningEnvelope>[];
    if (snapshot == null) {
      errors.add(
        'L’onglet « $sourceSheetName » est requis pour un cutover B1.',
      );
    } else {
      final rows = _rows(snapshot);
      final header = rows.isEmpty
          ? const <String>[]
          : rows.first.map(_normalise).toList();
      final typeIndex = header.indexOf('type');
      final nameIndex = header.indexOf('nom');
      final kindIndex = header.indexOf('kind');
      final amountIndex = header.indexOf('montant');
      if ([typeIndex, nameIndex, amountIndex].any((index) => index < 0)) {
        errors.add('L’onglet doit contenir les colonnes Type, Nom et Montant.');
      } else {
        for (var index = 1; index < rows.length; index++) {
          final row = rows[index];
          if (row.every((cell) => cell.trim().isEmpty)) continue;
          final type = _at(row, typeIndex).toLowerCase();
          final name = _at(row, nameIndex);
          final amount = num.tryParse(
            _at(row, amountIndex).replaceAll(',', '.'),
          );
          if (name.isEmpty || amount == null || amount <= 0) {
            errors.add('Ligne ${index + 1} : nom et montant positif requis.');
            continue;
          }
          if (type == 'compte') {
            final kind = _at(row, kindIndex).toLowerCase();
            if (!const {'bank', 'cash', 'savings', 'loan'}.contains(kind)) {
              errors.add('Ligne ${index + 1} : type de compte invalide.');
              continue;
            }
            accounts.add(
              CutoverOpeningAccount(
                sourceLabel: 'Ligne ${index + 1}',
                name: name,
                kind: kind,
                openingAmount: amount,
              ),
            );
          } else if (type == 'enveloppe') {
            final isToAllocate = _normalise(name) == 'a repartir';
            envelopes.add(
              CutoverOpeningEnvelope(
                sourceLabel: 'Ligne ${index + 1}',
                name: name,
                openingAmount: amount,
                isToAllocate: isToAllocate,
              ),
            );
          } else {
            errors.add(
              'Ligne ${index + 1} : Type doit être Compte ou Enveloppe.',
            );
          }
        }
      }
    }
    return CutoverOpeningPlan(
      cutoverId: cutoverId ?? _uuid(),
      householdId: householdId,
      sourceFingerprint: analysis.sourceFingerprint,
      effectiveDate: effectiveDate,
      accounts: List.unmodifiable(accounts),
      envelopes: List.unmodifiable(envelopes),
      blockingErrors: List.unmodifiable(errors),
    );
  }

  static List<List<String>> _rows(SourceSheetSnapshot snapshot) {
    final values = <int, Map<int, String>>{};
    for (final cell in snapshot.cells) {
      final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cell.coordinate);
      if (match == null) {
        continue;
      }
      final row = int.parse(match.group(2)!);
      var column = 0;
      for (final code in match.group(1)!.codeUnits) {
        column = column * 26 + code - 64;
      }
      values.putIfAbsent(row, () => {})[column - 1] = cell.value;
    }
    return values.entries.map((entry) {
      final columnCount = entry.value.keys.fold(0, max);
      return List<String>.generate(
        columnCount + 1,
        (index) => entry.value[index] ?? '',
      );
    }).toList();
  }

  static String _at(List<String> values, int index) =>
      index >= 0 && index < values.length ? values[index].trim() : '';
  static String _normalise(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll('à', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e');
  static String _uuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class CutoverOpeningImportRepository {
  const CutoverOpeningImportRepository(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> execute(CutoverOpeningPlan plan) async {
    final response = await _client.rpc(
      'execute_cutover_opening_import',
      params: {
        'p_household_id': plan.householdId,
        'p_cutover_id': plan.cutoverId,
        'p_source_fingerprint': plan.sourceFingerprint,
        'p_effective_date': CutoverOpeningPlan.formatDate(plan.effectiveDate),
        'p_plan': plan.toJson(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>?> findExisting({
    required String householdId,
    required String sourceFingerprint,
    required DateTime effectiveDate,
  }) async {
    final response = await _client.rpc(
      'get_cutover_opening_run',
      params: {
        'p_household_id': householdId,
        'p_source_fingerprint': sourceFingerprint,
        'p_effective_date': CutoverOpeningPlan.formatDate(effectiveDate),
      },
    );
    return response == null ? null : Map<String, dynamic>.from(response as Map);
  }
}

final cutoverOpeningImportRepositoryProvider = Provider(
  (ref) => CutoverOpeningImportRepository(ref.watch(supabaseClientProvider)),
);

final cutoverOpeningTargetHouseholdProvider = FutureProvider<String>((
  ref,
) async {
  final active = await ref.watch(activeHouseholdProvider.future);
  if (!active.hasActiveHousehold) {
    throw StateError('Un household opérationnel explicite est requis.');
  }
  return active.householdId!;
});
