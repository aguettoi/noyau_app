import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import 'envelope_csv_business_validator.dart';

class EnvelopeBusinessImportResult {
  const EnvelopeBusinessImportResult({
    required this.created,
    required this.existing,
    required this.ignored,
    this.initializedExisting = 0,
    this.importSessionId,
    this.errors = const [],
  });

  final int created;
  final int existing;
  final int ignored;
  final int initializedExisting;
  final String? importSessionId;
  final List<String> errors;
}

List<String> normalizeEnvelopeImportNames(Iterable<String> names) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in names) {
    final name = raw.trim();
    final comparison = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isNotEmpty && seen.add(comparison)) {
      result.add(name);
    }
  }
  return List.unmodifiable(result);
}

final importHouseholdEnvelopesProvider =
    Provider<
      Future<EnvelopeBusinessImportResult> Function({
        required Iterable<String> names,
        Iterable<EnvelopeImportCandidate>? candidates,
        String? importSessionId,
      })
    >((ref) {
      return ({
        required Iterable<String> names,
        Iterable<EnvelopeImportCandidate>? candidates,
        String? importSessionId,
      }) async {
        final household = await ref.read(activeHouseholdProvider.future);
        final householdId = household.householdId;
        if (!household.hasActiveHousehold || householdId == null) {
          throw StateError('Aucun foyer actif sans ambiguïté.');
        }
        final normalized = normalizeEnvelopeImportNames(names);
        final entries = candidates
            ?.map((candidate) => candidate.toJson())
            .toList(growable: false);
        final raw = await ref
            .read(supabaseClientProvider)
            .rpc(
              'import_household_envelopes',
              params: {
                'p_household_id': householdId,
                'p_names': entries ?? normalized,
                'p_import_session_id': importSessionId,
              },
            );
        final result = Map<String, dynamic>.from(raw as Map);
        return EnvelopeBusinessImportResult(
          created: result['created'] as int? ?? 0,
          existing: result['existing'] as int? ?? 0,
          ignored: result['ignored'] as int? ?? 0,
          initializedExisting: result['initialized_existing'] as int? ?? 0,
          importSessionId: result['import_session_id'] as String?,
          errors: (result['errors'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
        );
      };
    });
