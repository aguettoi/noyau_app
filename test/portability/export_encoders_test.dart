import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/portability/application/portability_provider.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';

void main() {
  final data = <String, List<Map<String, Object?>>>{
    'accounts': [
      {'name': 'Compte spécial é', 'balance': 12.34},
    ],
    'budget': const [],
  };

  test('CSV and XLSX exports are readable', () {
    final csv = utf8.decode(encodeTransactionsCsv(const []));
    expect(csv, contains('date;type;description'));
    final xlsx = encodeHouseholdXlsx(data);
    final decoded = Excel.decodeBytes(xlsx);
    expect(decoded.tables.keys, contains('accounts'));
    expect(decoded.tables['accounts']!.rows.length, 2);
    final transactionXlsx = encodeTransactionsXlsx([
      TransactionHistoryItem(
        id: 'event-1',
        type: LedgerTransactionType.expense,
        occurredAt: DateTime(2026, 10, 9),
        description: 'Caractères spéciaux é',
        amount: Money.fromDirhams(12.34),
        createdAt: DateTime(2026, 10, 9),
      ),
    ]);
    expect(
      Excel.decodeBytes(transactionXlsx).tables['transactions']!.rows.length,
      2,
    );
  });

  test('PDF and household archive are valid and readable', () async {
    final pdf = await encodeHouseholdPdf(data);
    expect(ascii.decode(pdf.take(4).toList()), '%PDF');
    final zip = encodeHouseholdArchive(data, utf8.encode('header\n'));
    final archive = ZipDecoder().decodeBytes(zip);
    expect(
      archive.files.map((f) => f.name),
      containsAll(['README.txt', 'transactions.csv', 'accounts.json']),
    );
  });
}
