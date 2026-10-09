import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/remote_transactions_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../finance/domain/transaction_history_item.dart';
import '../domain/portability_models.dart';

abstract interface class GlobalSearchGateway {
  Future<List<GlobalSearchResult>> search(
    String query, {
    int page = 0,
    int size = 50,
  });
}

class SupabaseGlobalSearchGateway implements GlobalSearchGateway {
  SupabaseGlobalSearchGateway(this.ref);
  final Ref ref;

  @override
  Future<List<GlobalSearchResult>> search(
    String query, {
    int page = 0,
    int size = 50,
  }) async {
    if (query.trim().length < 2) return const [];
    final household = await ref.read(activeHouseholdProvider.future);
    final rows = await ref
        .read(supabaseClientProvider)
        .rpc(
          'search_household_global',
          params: {
            'p_household_id': household.householdId,
            'p_query': query.trim(),
            'p_limit': size,
            'p_offset': page * size,
          },
        );
    return [
      for (final raw in rows as List<dynamic>)
        _searchResult(Map<String, Object?>.from(raw as Map)),
    ];
  }
}

final globalSearchGatewayProvider = Provider<GlobalSearchGateway>(
  SupabaseGlobalSearchGateway.new,
);

final importHistoryProvider = FutureProvider<List<ImportHistoryEntry>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('import_sheet_runs')
      .select(
        'id,status,detected_records,preview,created_at,import_sessions!inner(source_file_name,household_id,created_by)',
      )
      .eq('import_sessions.household_id', household.householdId!)
      .order('created_at', ascending: false)
      .limit(100);
  return [
    for (final raw in rows as List<dynamic>)
      ImportHistoryEntry(
        id: (raw as Map)['id'].toString(),
        fileName: ((raw['import_sessions'] as Map)['source_file_name'])
            .toString(),
        status: raw['status'].toString(),
        createdAt: DateTime.parse(raw['created_at'].toString()),
        detectedRecords: (raw['detected_records'] as num?)?.toInt() ?? 0,
        actorId: (raw['import_sessions'] as Map)['created_by'].toString(),
        error: (raw['preview'] as Map?)?['error']?.toString(),
      ),
  ];
});

class HouseholdExportService {
  HouseholdExportService(this.ref);
  final Ref ref;

  Future<List<TransactionHistoryItem>> _transactions() async {
    final repository = ref.read(transactionsSupabaseRepositoryProvider);
    return repository.all(
      filter: const TransactionHistoryFilter(pageSize: 5000),
    );
  }

  String _stamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  Future<PortableFile> transactionsCsv() async {
    final rows = await _transactions();
    return PortableFile(
      'transactions_${_stamp()}.csv',
      'text/csv;charset=utf-8',
      encodeTransactionsCsv(rows),
    );
  }

  Future<PortableFile> transactionsXlsx() async {
    final rows = await _transactions();
    return PortableFile(
      'transactions_${_stamp()}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      encodeTransactionsXlsx(rows),
    );
  }

  Future<Map<String, List<Map<String, Object?>>>> _snapshot() async {
    final household = await ref.read(activeHouseholdProvider.future);
    final id = household.householdId!;
    final client = ref.read(supabaseClientProvider);
    Future<List<Map<String, Object?>>> rows(String table) async => [
      for (final raw
          in await client.from(table).select().eq('household_id', id)
              as List<dynamic>)
        Map<String, Object?>.from(raw as Map),
    ];
    return {
      'accounts': await rows('accounts'),
      'household_members': await rows('household_members'),
      'envelopes': await rows('envelopes'),
      'envelope_movements': await rows('envelope_movements'),
      'obligations': await rows('obligations'),
      'obligation_settlements': await rows('obligation_settlements'),
      'goals': await rows('budget_goals'),
      'shopping': await rows('shopping_items'),
      'priorities': await rows('priority_plans'),
      'tasks': await rows('household_tasks'),
      'assets': await rows('wealth_assets'),
      'investments': await rows('investment_products'),
      'financings': await rows('financing_profiles'),
      'budget_periods': await rows('budget_periods'),
      'budget_scenarios': await rows('budget_scenarios'),
      'budget_scenario_rules': await rows('budget_scenario_rules'),
      'budget_runs': await rows('budget_allocation_runs'),
      'budget_run_lines': await rows('budget_allocation_run_lines'),
      'budget_reporting': await rows('budget_envelope_reporting'),
      'attachments_metadata': await rows('financial_event_attachments'),
    };
  }

  Future<PortableFile> householdXlsx() async {
    final data = await _snapshot();
    return PortableFile(
      'foyer_${_stamp()}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      encodeHouseholdXlsx(data),
    );
  }

  Future<PortableFile> summaryPdf() async {
    final data = await _snapshot();
    return PortableFile(
      'synthese_foyer_${_stamp()}.pdf',
      'application/pdf',
      await encodeHouseholdPdf(data),
    );
  }

  Future<PortableFile> householdArchive() async {
    final data = await _snapshot();
    final transactions = await transactionsCsv();
    return PortableFile(
      'export_foyer_${_stamp()}.zip',
      'application/zip',
      encodeHouseholdArchive(data, transactions.bytes),
    );
  }
}

List<int> encodeTransactionsCsv(List<TransactionHistoryItem> rows) {
  final out = StringBuffer(
    '\uFEFFdate;type;description;montant;compte_source;compte_destination;enveloppes;moyen_paiement;acteur;reversal\n',
  );
  for (final row in rows) {
    out.writeln(
      [
        DateFormat('yyyy-MM-dd').format(row.occurredAt),
        row.type.name,
        row.description,
        row.amount.dirhams.toStringAsFixed(2),
        row.sourceAccountName ?? '',
        row.destinationAccountName ?? '',
        row.envelopes.map((e) => e.name).join(', '),
        row.paymentMethodName ?? '',
        row.actorId ?? '',
        row.isReversed || row.isReversal ? 'oui' : 'non',
      ].map(_csv).join(';'),
    );
  }
  return utf8.encode(out.toString());
}

List<int> encodeTransactionsXlsx(List<TransactionHistoryItem> rows) {
  final book = Excel.createExcel()..rename('Sheet1', 'transactions');
  final sheet = book['transactions'];
  sheet.appendRow(
    const [
      'date',
      'type',
      'description',
      'montant',
      'compte_source',
      'compte_destination',
      'enveloppes',
      'moyen_paiement',
      'acteur',
      'reversal',
    ].map(TextCellValue.new).toList(),
  );
  for (final row in rows) {
    sheet.appendRow([
      TextCellValue(DateFormat('yyyy-MM-dd').format(row.occurredAt)),
      TextCellValue(row.type.name),
      TextCellValue(row.description),
      DoubleCellValue(row.amount.dirhams),
      TextCellValue(row.sourceAccountName ?? ''),
      TextCellValue(row.destinationAccountName ?? ''),
      TextCellValue(row.envelopes.map((e) => e.name).join(', ')),
      TextCellValue(row.paymentMethodName ?? ''),
      TextCellValue(row.actorId ?? ''),
      TextCellValue(row.isReversed || row.isReversal ? 'oui' : 'non'),
    ]);
  }
  return book.encode()!;
}

List<int> encodeHouseholdXlsx(Map<String, List<Map<String, Object?>>> data) {
  final book = Excel.createExcel()..delete('Sheet1');
  for (final entry in data.entries) {
    final sheet = book[entry.key];
    final keys = entry.value.expand((e) => e.keys).toSet().toList();
    sheet.appendRow(keys.map(TextCellValue.new).toList());
    for (final row in entry.value) {
      sheet.appendRow(
        keys.map((key) => TextCellValue('${row[key] ?? ''}')).toList(),
      );
    }
  }
  return book.encode()!;
}

Future<List<int>> encodeHouseholdPdf(
  Map<String, List<Map<String, Object?>>> data,
) async {
  final pdf = pw.Document()
    ..addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(
            level: 0,
            child: pw.Text('FINANCIEL PILOTE - export foyer'),
          ),
          for (final entry in data.entries)
            pw.Text('${entry.key}: ${entry.value.length} element(s)'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Les justificatifs restent prives. Le rapport inclut uniquement leurs metadonnees.',
          ),
        ],
      ),
    );
  return pdf.save();
}

List<int> encodeHouseholdArchive(
  Map<String, List<Map<String, Object?>>> data,
  List<int> transactionsCsv,
) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'README.txt',
        'Export lisible FINANCIEL PILOTE. Justificatifs privés: métadonnées uniquement.',
      ),
    )
    ..addFile(
      ArchiveFile('transactions.csv', transactionsCsv.length, transactionsCsv),
    );
  for (final entry in data.entries) {
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(entry.value),
    );
    archive.addFile(ArchiveFile('${entry.key}.json', bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

String _csv(Object? value) => '"${value.toString().replaceAll('"', '""')}"';

final householdExportServiceProvider = Provider(HouseholdExportService.new);

GlobalSearchResult _searchResult(Map<String, Object?> row) =>
    GlobalSearchResult(
      type: SearchResultType.values.byName(
        (row['result_type'] as String).replaceAll(
          'financial_event',
          'financialEvent',
        ),
      ),
      id: row['source_id'].toString(),
      title: row['title'].toString(),
      subtitle: row['subtitle']?.toString() ?? '',
      date: row['occurred_on'] == null
          ? null
          : DateTime.parse(row['occurred_on'].toString()),
      amount: row['amount'] == null
          ? null
          : double.parse(row['amount'].toString()),
    );
