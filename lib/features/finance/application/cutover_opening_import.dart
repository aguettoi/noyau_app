import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/active_household_provider.dart';
import 'providers/remote_household_members_provider.dart';
import 'providers/supabase_client_provider.dart';
import '../domain/account_ownership.dart';
import '../domain/household_member.dart';
import 'workbook_import.dart';

class CutoverOpeningAccount {
  const CutoverOpeningAccount({
    required this.sourceLabel,
    required this.name,
    required this.kind,
    required this.openingAmount,
    this.ownershipType,
    this.holderUserIds = const [],
    this.conflictDecision = 'create',
    this.matchedAccountId,
    this.referenceConflict,
  });

  final String sourceLabel;
  final String name;
  final String kind;
  final num openingAmount;
  final AccountOwnershipType? ownershipType;
  final List<String> holderUserIds;
  final String conflictDecision;
  final String? matchedAccountId;
  final String? referenceConflict;

  String? get ownershipValidationError {
    final ownership = ownershipType;
    if (ownership == null) return 'Titularité à confirmer.';
    final uniqueHolders = holderUserIds.toSet();
    if (uniqueHolders.length != holderUserIds.length) {
      return 'Un même titulaire ne peut être sélectionné deux fois.';
    }
    return switch (ownership) {
      AccountOwnershipType.individual when holderUserIds.length != 1 =>
        'Un compte individuel exige exactement un titulaire.',
      AccountOwnershipType.shared when holderUserIds.length < 2 =>
        'Un compte partagé exige au moins deux titulaires.',
      AccountOwnershipType.household when holderUserIds.isNotEmpty =>
        'Un compte foyer ne porte aucun titulaire individuel.',
      _ => null,
    };
  }

  bool get hasValidOwnership => ownershipValidationError == null;
  bool get hasReferenceConflict => referenceConflict != null;

  CutoverOpeningAccount copyWith({
    AccountOwnershipType? ownershipType,
    bool clearOwnershipType = false,
    List<String>? holderUserIds,
    String? conflictDecision,
    String? matchedAccountId,
    bool clearMatchedAccountId = false,
    String? referenceConflict,
    bool clearReferenceConflict = false,
  }) => CutoverOpeningAccount(
    sourceLabel: sourceLabel,
    name: name,
    kind: kind,
    openingAmount: openingAmount,
    ownershipType: clearOwnershipType
        ? null
        : ownershipType ?? this.ownershipType,
    holderUserIds: List.unmodifiable(holderUserIds ?? this.holderUserIds),
    conflictDecision: conflictDecision ?? this.conflictDecision,
    matchedAccountId: clearMatchedAccountId
        ? null
        : matchedAccountId ?? this.matchedAccountId,
    referenceConflict: clearReferenceConflict
        ? null
        : referenceConflict ?? this.referenceConflict,
  );

  Map<String, Object?> toJson() => {
    'source_label': sourceLabel,
    'name': name,
    'kind': kind,
    'opening_amount': openingAmount,
    'ownership_type': ownershipType?.name,
    'holder_user_ids': holderUserIds,
    'conflict_decision': conflictDecision,
    if (matchedAccountId != null) 'matched_account_id': matchedAccountId,
    if (referenceConflict != null) 'reference_conflict': referenceConflict,
  };
}

class CutoverOpeningEnvelope {
  const CutoverOpeningEnvelope({
    required this.sourceLabel,
    required this.name,
    required this.openingAmount,
    required this.isToAllocate,
    this.conflictDecision = 'create',
    this.matchedEnvelopeId,
    this.referenceConflict,
  });

  final String sourceLabel;
  final String name;
  final num openingAmount;
  final bool isToAllocate;
  final String conflictDecision;
  final String? matchedEnvelopeId;
  final String? referenceConflict;

  bool get hasReferenceConflict => referenceConflict != null;

  CutoverOpeningEnvelope copyWith({
    String? conflictDecision,
    String? matchedEnvelopeId,
    bool clearMatchedEnvelopeId = false,
    String? referenceConflict,
    bool clearReferenceConflict = false,
  }) => CutoverOpeningEnvelope(
    sourceLabel: sourceLabel,
    name: name,
    openingAmount: openingAmount,
    isToAllocate: isToAllocate,
    conflictDecision: conflictDecision ?? this.conflictDecision,
    matchedEnvelopeId: clearMatchedEnvelopeId
        ? null
        : matchedEnvelopeId ?? this.matchedEnvelopeId,
    referenceConflict: clearReferenceConflict
        ? null
        : referenceConflict ?? this.referenceConflict,
  );

  Map<String, Object?> toJson() => {
    'source_label': sourceLabel,
    'name': name,
    'opening_amount': openingAmount,
    'is_to_allocate': isToAllocate,
    'conflict_decision': isToAllocate ? 'match' : conflictDecision,
    if (matchedEnvelopeId != null) 'matched_envelope_id': matchedEnvelopeId,
    if (referenceConflict != null) 'reference_conflict': referenceConflict,
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
      blockingErrors.isEmpty &&
      accounts.isNotEmpty &&
      envelopes.isNotEmpty &&
      accounts.every(
        (account) => account.hasValidOwnership && !account.hasReferenceConflict,
      ) &&
      envelopes.every((envelope) => !envelope.hasReferenceConflict);

  List<String> ownershipErrorsForMemberIds(Set<String> memberIds) => accounts
      .where(
        (account) => account.holderUserIds.any(
          (holderId) => !memberIds.contains(holderId),
        ),
      )
      .map(
        (account) =>
            '${account.name} : un titulaire ne fait pas partie du household cible.',
      )
      .toList(growable: false);

  bool canConfirmForMemberIds(Set<String> memberIds) =>
      canConfirm && ownershipErrorsForMemberIds(memberIds).isEmpty;

  CutoverOpeningPlan updateAccount(int index, CutoverOpeningAccount account) =>
      CutoverOpeningPlan(
        cutoverId: cutoverId,
        householdId: householdId,
        sourceFingerprint: sourceFingerprint,
        effectiveDate: effectiveDate,
        accounts: List.unmodifiable([
          for (var current = 0; current < accounts.length; current++)
            current == index ? account : accounts[current],
        ]),
        envelopes: envelopes,
        blockingErrors: blockingErrors,
        warnings: warnings,
        confirmedAt: confirmedAt,
      );

  CutoverOpeningPlan resolveReferences({
    required List<CutoverExistingAccount> existingAccounts,
    required List<CutoverExistingEnvelope> existingEnvelopes,
  }) => CutoverOpeningPlan(
    cutoverId: cutoverId,
    householdId: householdId,
    sourceFingerprint: sourceFingerprint,
    effectiveDate: effectiveDate,
    accounts: List.unmodifiable(
      accounts.map((account) {
        final matches = existingAccounts
            .where(
              (existing) =>
                  existing.name.toLowerCase() == account.name.toLowerCase(),
            )
            .toList(growable: false);
        if (matches.isEmpty) {
          return account.copyWith(
            conflictDecision: 'create',
            clearMatchedAccountId: true,
            clearReferenceConflict: true,
          );
        }
        if (matches.length > 1) {
          return account.copyWith(
            conflictDecision: 'conflict',
            clearMatchedAccountId: true,
            referenceConflict:
                'Plusieurs comptes existants portent ce libellé. Le rattachement est ambigu.',
          );
        }
        final existing = matches.single;
        final holdersMatch =
            existing.holderUserIds.toSet().containsAll(account.holderUserIds) &&
            account.holderUserIds.toSet().containsAll(existing.holderUserIds);
        if (existing.archived ||
            existing.kind != account.kind ||
            existing.ownershipType != account.ownershipType ||
            !holdersMatch) {
          return account.copyWith(
            conflictDecision: 'conflict',
            matchedAccountId: existing.id,
            referenceConflict:
                'Compte existant incompatible : type, cycle de vie ou titularité.',
          );
        }
        return account.copyWith(
          conflictDecision: 'match',
          matchedAccountId: existing.id,
          clearReferenceConflict: true,
        );
      }),
    ),
    envelopes: List.unmodifiable(
      envelopes.map((envelope) {
        final matches = existingEnvelopes
            .where(
              (existing) => envelope.isToAllocate
                  ? existing.systemKey == 'to_allocate'
                  : !existing.isSystem &&
                        existing.name.toLowerCase() ==
                            envelope.name.toLowerCase(),
            )
            .toList(growable: false);
        if (matches.isEmpty) {
          if (envelope.isToAllocate) {
            return envelope.copyWith(
              conflictDecision: 'conflict',
              referenceConflict: 'Enveloppe système À répartir introuvable.',
            );
          }
          return envelope.copyWith(
            conflictDecision: 'create',
            clearMatchedEnvelopeId: true,
            clearReferenceConflict: true,
          );
        }
        if (matches.length > 1) {
          return envelope.copyWith(
            conflictDecision: 'conflict',
            clearMatchedEnvelopeId: true,
            referenceConflict:
                'Plusieurs enveloppes existantes correspondent. Le rattachement est ambigu.',
          );
        }
        final existing = matches.single;
        if (existing.archived) {
          return envelope.copyWith(
            conflictDecision: 'conflict',
            matchedEnvelopeId: existing.id,
            referenceConflict: 'Enveloppe existante archivée.',
          );
        }
        return envelope.copyWith(
          conflictDecision: 'match',
          matchedEnvelopeId: existing.id,
          clearReferenceConflict: true,
        );
      }),
    ),
    blockingErrors: blockingErrors,
    warnings: warnings,
    confirmedAt: confirmedAt,
  );

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
              ownershipType: _parseOwnershipType(
                value['ownership_type'] as String?,
              ),
              holderUserIds: List<String>.from(
                value['holder_user_ids'] as List? ?? const [],
              ),
              conflictDecision:
                  value['conflict_decision'] as String? ?? 'create',
              matchedAccountId: value['matched_account_id'] as String?,
              referenceConflict: value['reference_conflict'] as String?,
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
              matchedEnvelopeId: value['matched_envelope_id'] as String?,
              referenceConflict: value['reference_conflict'] as String?,
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

class CutoverExistingAccount {
  const CutoverExistingAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.ownershipType,
    required this.holderUserIds,
    required this.archived,
  });

  final String id;
  final String name;
  final String kind;
  final AccountOwnershipType ownershipType;
  final List<String> holderUserIds;
  final bool archived;
}

class CutoverExistingEnvelope {
  const CutoverExistingEnvelope({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.systemKey,
    required this.archived,
  });

  final String id;
  final String name;
  final bool isSystem;
  final String? systemKey;
  final bool archived;
}

AccountOwnershipType? _parseOwnershipType(String? value) => switch (value) {
  'individual' => AccountOwnershipType.individual,
  'shared' => AccountOwnershipType.shared,
  'household' => AccountOwnershipType.household,
  _ => null,
};

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
      final ownershipIndex = _firstHeaderIndex(header, const [
        'ownership type',
        'ownership_type',
      ]);
      final holdersIndex = _firstHeaderIndex(header, const [
        'holder user ids',
        'holder_user_ids',
      ]);
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
            final ownershipType = _parseOwnershipType(
              _at(row, ownershipIndex).toLowerCase().replaceAll(' ', '_'),
            );
            final holderUserIds = _at(row, holdersIndex)
                .split(RegExp(r'[,;]'))
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false);
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
                ownershipType: ownershipType,
                holderUserIds: List.unmodifiable(holderUserIds),
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
  static int _firstHeaderIndex(List<String> headers, List<String> names) {
    for (final name in names) {
      final index = headers.indexOf(name);
      if (index >= 0) return index;
    }
    return -1;
  }

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

  Future<CutoverOpeningPlan> resolveReferences(CutoverOpeningPlan plan) async {
    final accountRows = await _client
        .from('accounts')
        .select(
          'id,name,kind,ownership_type,archived_at,account_holders(user_id)',
        )
        .eq('household_id', plan.householdId)
        .eq('is_system', false);
    final envelopeRows = await _client
        .from('envelopes')
        .select('id,name,is_system,system_code,archived_at')
        .eq('household_id', plan.householdId);
    return plan.resolveReferences(
      existingAccounts: (accountRows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => CutoverExistingAccount(
              id: row['id'] as String,
              name: row['name'] as String,
              kind: row['kind'] as String,
              ownershipType: _parseOwnershipType(
                row['ownership_type'] as String?,
              )!,
              holderUserIds:
                  (row['account_holders'] as List<dynamic>? ?? const [])
                      .map((item) => Map<String, dynamic>.from(item as Map))
                      .map((item) => item['user_id'] as String)
                      .toList(growable: false),
              archived: row['archived_at'] != null,
            ),
          )
          .toList(growable: false),
      existingEnvelopes: (envelopeRows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => CutoverExistingEnvelope(
              id: row['id'] as String,
              name: row['name'] as String,
              isSystem: row['is_system'] as bool? ?? false,
              systemKey: row['system_code'] as String?,
              archived: row['archived_at'] != null,
            ),
          )
          .toList(growable: false),
    );
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

/// An explicit import target. This is deliberately separate from the global
/// operational household resolver: a Cutover plan may be certified in a
/// technical household without making that household operational elsewhere.
class CutoverEligibleHousehold {
  const CutoverEligibleHousehold({
    required this.id,
    required this.name,
    required this.classification,
  });

  final String id;
  final String name;
  final HouseholdClassification classification;

  bool get isTechnical => classification == HouseholdClassification.technical;

  bool get isOperational =>
      classification == HouseholdClassification.operational;

  String get classificationLabel => switch (classification) {
    HouseholdClassification.operational => 'OPÉRATIONNEL',
    HouseholdClassification.technical => 'TECHNIQUE',
    HouseholdClassification.archived => 'ARCHIVÉ',
  };
}

abstract interface class CutoverEligibleHouseholdsGateway {
  Future<List<CutoverEligibleHousehold>> householdsForUser(String userId);
}

class SupabaseCutoverEligibleHouseholdsGateway
    implements CutoverEligibleHouseholdsGateway {
  SupabaseCutoverEligibleHouseholdsGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CutoverEligibleHousehold>> householdsForUser(
    String userId,
  ) async {
    final response = await _client
        .from('household_members')
        .select('household_id, households!inner(name, classification)')
        .eq('user_id', userId);
    final households = (response as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((item) {
          final household = Map<String, dynamic>.from(
            item['households'] as Map,
          );
          final classification = household['classification'] as String;
          if (classification != 'operational' &&
              classification != 'technical' &&
              classification != 'archived') {
            throw StateError('Classification de foyer invalide.');
          }
          return CutoverEligibleHousehold(
            id: item['household_id'] as String,
            name: household['name'] as String,
            classification: switch (classification) {
              'technical' => HouseholdClassification.technical,
              'archived' => HouseholdClassification.archived,
              _ => HouseholdClassification.operational,
            },
          );
        })
        .toList(growable: false);
    households.sort((left, right) => left.name.compareTo(right.name));
    return households;
  }
}

final cutoverEligibleHouseholdsGatewayProvider =
    Provider<CutoverEligibleHouseholdsGateway>(
      (ref) => SupabaseCutoverEligibleHouseholdsGateway(
        ref.watch(supabaseClientProvider),
      ),
    );

final cutoverEligibleHouseholdsProvider =
    FutureProvider<List<CutoverEligibleHousehold>>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const [];
      return ref
          .watch(cutoverEligibleHouseholdsGatewayProvider)
          .householdsForUser(userId);
    });

final cutoverOpeningImportRepositoryProvider = Provider(
  (ref) => CutoverOpeningImportRepository(ref.watch(supabaseClientProvider)),
);

final cutoverHouseholdMembersProvider =
    FutureProvider.family<List<HouseholdMember>, String>((ref, householdId) {
      return ref
          .watch(householdMembersGatewayProvider)
          .fetchMembers(householdId);
    });

final cutoverOpeningTargetHouseholdProvider = FutureProvider<String>((
  ref,
) async {
  final active = await ref.watch(activeHouseholdProvider.future);
  if (!active.hasActiveHousehold) {
    throw StateError('Un household opérationnel explicite est requis.');
  }
  return active.householdId!;
});
