import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const canonicalHouseholdArchiveVersion = 1;

const canonicalHouseholdDatasetOrder = <String>[
  'households',
  'household_members',
  'accounts',
  'account_holders',
  'account_privacy_settings',
  'envelopes',
  'budget_goals',
  'financial_events',
  'financial_transactions',
  'financial_transaction_lines',
  'envelope_movements',
  'obligations',
  'obligation_settlements',
  'wealth_assets',
  'wealth_asset_owners',
  'wealth_asset_valuations',
  'investment_products',
  'investment_valuations',
  'investment_operations',
  'financing_profiles',
  'account_balance_observations',
];

const _requiredDatasets = <String>{
  'households',
  'household_members',
  'accounts',
  'envelopes',
  'financial_events',
  'financial_transactions',
  'financial_transaction_lines',
  'envelope_movements',
  'obligations',
  'obligation_settlements',
};

class HouseholdArchiveException implements Exception {
  const HouseholdArchiveException(this.message);

  final String message;

  @override
  String toString() => 'HouseholdArchiveException: $message';
}

class CanonicalHouseholdArchive {
  const CanonicalHouseholdArchive({
    required this.sourceHouseholdId,
    required this.createdAt,
    required this.datasets,
    this.version = canonicalHouseholdArchiveVersion,
  });

  final int version;
  final String sourceHouseholdId;
  final DateTime createdAt;
  final Map<String, List<Map<String, Object?>>> datasets;
}

class HouseholdArchiveCodec {
  const HouseholdArchiveCodec();

  Uint8List encode(CanonicalHouseholdArchive value) {
    _validateShape(value);
    final files = <String, Uint8List>{};
    final datasetManifest = <String, Object?>{};
    for (final name in canonicalHouseholdDatasetOrder) {
      final rows = value.datasets[name] ?? const <Map<String, Object?>>[];
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(rows)),
      );
      files['data/$name.json'] = bytes;
      datasetManifest[name] = {
        'rows': rows.length,
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    final manifest = <String, Object?>{
      'format': 'financiel-pilote-household-archive',
      'version': value.version,
      'restore_eligible': true,
      'source_household_id': value.sourceHouseholdId,
      'created_at': value.createdAt.toUtc().toIso8601String(),
      'datasets': datasetManifest,
    };
    final manifestBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
    final zip = Archive()
      ..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );
    for (final entry in files.entries) {
      zip.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(zip)!);
  }

  CanonicalHouseholdArchive decode(List<int> bytes) {
    late Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes, verify: true);
    } on Object catch (error) {
      throw HouseholdArchiveException('Archive ZIP illisible: $error');
    }
    final files = {for (final file in zip.files) file.name: file};
    final manifestFile = files['manifest.json'];
    if (manifestFile == null) {
      throw const HouseholdArchiveException('manifest.json absent');
    }
    final manifest = _jsonObject(manifestFile.content as List<int>);
    if (manifest['format'] != 'financiel-pilote-household-archive' ||
        manifest['restore_eligible'] != true) {
      throw const HouseholdArchiveException(
        'Archive utilisateur ou format non restaurable',
      );
    }
    final version = (manifest['version'] as num?)?.toInt();
    if (version != canonicalHouseholdArchiveVersion) {
      throw HouseholdArchiveException(
        'Version incompatible: ${version ?? 'absente'}',
      );
    }
    final declared = manifest['datasets'];
    if (declared is! Map) {
      throw const HouseholdArchiveException('Manifeste de jeux invalide');
    }
    final datasets = <String, List<Map<String, Object?>>>{};
    for (final name in canonicalHouseholdDatasetOrder) {
      final metadata = declared[name];
      final file = files['data/$name.json'];
      if (metadata is! Map || file == null) {
        throw HouseholdArchiveException('Jeu déclaré absent: $name');
      }
      final content = Uint8List.fromList(file.content as List<int>);
      if (sha256.convert(content).toString() != metadata['sha256']) {
        throw HouseholdArchiveException('Empreinte invalide: $name');
      }
      final decoded = jsonDecode(utf8.decode(content));
      if (decoded is! List || decoded.length != metadata['rows']) {
        throw HouseholdArchiveException('Comptage invalide: $name');
      }
      datasets[name] = [
        for (final row in decoded)
          if (row is Map)
            Map<String, Object?>.from(row)
          else
            throw HouseholdArchiveException('Ligne invalide: $name'),
      ];
    }
    final archive = CanonicalHouseholdArchive(
      version: version!,
      sourceHouseholdId: manifest['source_household_id']?.toString() ?? '',
      createdAt: DateTime.parse(manifest['created_at'].toString()),
      datasets: datasets,
    );
    _validateShape(archive);
    return archive;
  }

  static Map<String, Object?> _jsonObject(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const HouseholdArchiveException('Manifeste invalide');
    }
    return Map<String, Object?>.from(decoded);
  }

  static void _validateShape(CanonicalHouseholdArchive archive) {
    if (archive.version != canonicalHouseholdArchiveVersion ||
        archive.sourceHouseholdId.isEmpty) {
      throw const HouseholdArchiveException('Archive incompatible');
    }
    if (!_requiredDatasets.every(archive.datasets.containsKey)) {
      throw const HouseholdArchiveException('Archive canonique incomplète');
    }
    final unknown = archive.datasets.keys.where(
      (name) => !canonicalHouseholdDatasetOrder.contains(name),
    );
    if (unknown.isNotEmpty) {
      throw HouseholdArchiveException(
        'Jeu non pris en charge: ${unknown.join(', ')}',
      );
    }
    final households = archive.datasets['households']!;
    if (households.length != 1 ||
        households.single['id'] != archive.sourceHouseholdId) {
      throw const HouseholdArchiveException('Foyer source incohérent');
    }
    for (final entry in archive.datasets.entries) {
      for (final row in entry.value) {
        if (entry.key != 'households' &&
            row['household_id'] != archive.sourceHouseholdId) {
          throw HouseholdArchiveException(
            'Ligne cross-household interdite: ${entry.key}',
          );
        }
      }
    }
  }
}

class IsolatedHouseholdStore {
  final Map<String, List<Map<String, Object?>>> tables = {};
  final Set<String> restoredArchiveDigests = {};

  bool get isEmpty => tables.values.every((rows) => rows.isEmpty);
}

class HouseholdRestorationResult {
  const HouseholdRestorationResult({
    required this.targetHouseholdId,
    required this.archiveDigest,
    required this.rowsRestored,
    required this.alreadyRestored,
    required this.idMap,
  });

  final String targetHouseholdId;
  final String archiveDigest;
  final int rowsRestored;
  final bool alreadyRestored;
  final Map<String, String> idMap;
}

class IsolatedHouseholdRestorer {
  const IsolatedHouseholdRestorer();

  static const _references = <String, Map<String, String>>{
    'household_members': {'user_id': 'members'},
    'account_holders': {'account_id': 'accounts', 'user_id': 'members'},
    'account_privacy_settings': {
      'account_id': 'accounts',
      'changed_by': 'members',
    },
    'envelopes': {
      'recommended_account_id': 'accounts',
      'owner_user_id': 'members',
    },
    'budget_goals': {
      'funding_envelope_id': 'envelopes',
      'created_by': 'members',
    },
    'financial_events': {'created_by': 'members'},
    'financial_transactions': {
      'event_id': 'financial_events',
      'source_account_id': 'accounts',
      'destination_account_id': 'accounts',
      'created_by': 'members',
    },
    'financial_transaction_lines': {
      'transaction_id': 'financial_transactions',
      'account_id': 'accounts',
      'envelope_id': 'envelopes',
    },
    'envelope_movements': {
      'envelope_id': 'envelopes',
      'financial_transaction_id': 'financial_transactions',
      'event_id': 'financial_events',
      'reversal_of': 'envelope_movements',
      'created_by': 'members',
    },
    'obligations': {
      'origin_event_id': 'financial_events',
      'origin_transaction_id': 'financial_transactions',
      'origin_envelope_id': 'envelopes',
      'created_by': 'members',
    },
    'obligation_settlements': {
      'obligation_id': 'obligations',
      'event_id': 'financial_events',
      'financial_transaction_id': 'financial_transactions',
      'created_by': 'members',
    },
    'wealth_assets': {'created_by': 'members', 'updated_by': 'members'},
    'wealth_asset_owners': {'asset_id': 'wealth_assets', 'user_id': 'members'},
    'wealth_asset_valuations': {
      'asset_id': 'wealth_assets',
      'created_by': 'members',
    },
    'investment_products': {
      'backing_account_id': 'accounts',
      'owner_user_id': 'members',
      'created_by': 'members',
    },
    'investment_valuations': {
      'investment_id': 'investment_products',
      'created_by': 'members',
    },
    'investment_operations': {
      'investment_id': 'investment_products',
      'financial_event_id': 'financial_events',
      'created_by': 'members',
    },
    'financing_profiles': {
      'asset_id': 'wealth_assets',
      'obligation_id': 'obligations',
      'created_by': 'members',
    },
    'account_balance_observations': {
      'account_id': 'accounts',
      'created_by': 'members',
    },
  };

  HouseholdRestorationResult restore({
    required List<int> archiveBytes,
    required IsolatedHouseholdStore target,
    required String targetHouseholdId,
    required Map<String, String> memberIdentityMap,
  }) {
    final digest = sha256.convert(archiveBytes).toString();
    if (target.restoredArchiveDigests.contains(digest)) {
      return HouseholdRestorationResult(
        targetHouseholdId: targetHouseholdId,
        archiveDigest: digest,
        rowsRestored: 0,
        alreadyRestored: true,
        idMap: const {},
      );
    }
    if (!target.isEmpty) {
      throw const HouseholdArchiveException(
        'La cible isolée doit être vide pour une première restauration',
      );
    }
    final decoded = const HouseholdArchiveCodec().decode(archiveBytes);
    final staged = <String, List<Map<String, Object?>>>{};
    final idMap = <String, String>{
      decoded.sourceHouseholdId: targetHouseholdId,
      ...memberIdentityMap,
    };
    var sequence = 0;
    for (final table in canonicalHouseholdDatasetOrder) {
      for (final row in decoded.datasets[table] ?? const []) {
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty && !idMap.containsKey(id)) {
          idMap[id] = 'restored-${sequence++}-${_slug(table)}';
        }
      }
    }
    for (final table in canonicalHouseholdDatasetOrder) {
      final output = <Map<String, Object?>>[];
      for (final source in decoded.datasets[table] ?? const []) {
        final row = Map<String, Object?>.from(source);
        if (table == 'households') {
          row['id'] = targetHouseholdId;
        } else {
          row['household_id'] = targetHouseholdId;
          if (row['id'] != null) row['id'] = idMap[row['id'].toString()];
        }
        for (final reference in _references[table]?.keys ?? const <String>[]) {
          final old = row[reference]?.toString();
          if (old == null) continue;
          final mapped = idMap[old];
          if (mapped == null) {
            throw HouseholdArchiveException(
              'Référence orpheline: $table.$reference=$old',
            );
          }
          row[reference] = mapped;
        }
        output.add(row);
      }
      staged[table] = output;
    }
    _validateLedger(staged);
    _validateObligations(staged);
    target.tables.addAll(staged);
    target.restoredArchiveDigests.add(digest);
    return HouseholdRestorationResult(
      targetHouseholdId: targetHouseholdId,
      archiveDigest: digest,
      rowsRestored: staged.values.fold(0, (sum, rows) => sum + rows.length),
      alreadyRestored: false,
      idMap: Map.unmodifiable(idMap),
    );
  }

  static void _validateLedger(Map<String, List<Map<String, Object?>>> tables) {
    final totals = <String, (num, num)>{};
    for (final line in tables['financial_transaction_lines'] ?? const []) {
      final transaction = line['transaction_id'].toString();
      final current = totals[transaction] ?? (0, 0);
      totals[transaction] = (
        current.$1 + (line['debit'] as num? ?? 0),
        current.$2 + (line['credit'] as num? ?? 0),
      );
    }
    for (final transaction in tables['financial_transactions'] ?? const []) {
      final total = totals[transaction['id'].toString()];
      if (total == null || (total.$1 - total.$2).abs() > 0.0001) {
        throw HouseholdArchiveException(
          'Transaction GL déséquilibrée: ${transaction['id']}',
        );
      }
    }
  }

  static void _validateObligations(
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    final initial = {
      for (final row in tables['obligations'] ?? const [])
        row['id'].toString(): row['initial_amount'] as num,
    };
    final settled = <String, num>{};
    for (final row in tables['obligation_settlements'] ?? const []) {
      final id = row['obligation_id'].toString();
      settled[id] = (settled[id] ?? 0) + (row['amount'] as num);
    }
    for (final entry in settled.entries) {
      if (!initial.containsKey(entry.key) ||
          entry.value > initial[entry.key]!) {
        throw HouseholdArchiveException(
          'Règlement obligation incohérent: ${entry.key}',
        );
      }
    }
  }

  static String _slug(String value) => value.replaceAll('_', '-');
}
