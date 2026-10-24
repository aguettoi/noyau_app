import 'dart:convert';

import '../../../core/money/money.dart';
import 'wealth_models.dart';

enum WealthEvidenceKind { observed, entered, calculated, projected }

class WealthHistoryEntry {
  const WealthHistoryEntry({
    required this.sourceId,
    required this.label,
    required this.date,
    required this.value,
    required this.kind,
  });

  final String sourceId;
  final String label;
  final DateTime date;
  final Money value;
  final WealthEvidenceKind kind;
}

class WealthHistoryPoint {
  const WealthHistoryPoint({
    required this.date,
    required this.assets,
    required this.investments,
    required this.isComplete,
    required this.explanations,
    this.liquidity,
    this.liabilities,
  });

  final DateTime date;
  final Money assets;
  final Money investments;
  final Money? liquidity;
  final Money? liabilities;
  final bool isComplete;
  final List<String> explanations;

  Money? get netWorth =>
      isComplete ? assets + investments + liquidity! - liabilities! : null;
}

/// Builds only dated, evidenced points. Asset and investment values may be
/// carried forward after their first observation; missing account/liability
/// history is never replaced with today's value.
List<WealthHistoryPoint> buildWealthHistory({
  required Iterable<WealthHistoryEntry> entries,
  required DateTime currentDate,
  required WealthSnapshot currentSnapshot,
}) {
  final ordered = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  final dates = <DateTime>{
    for (final item in ordered)
      DateTime(item.date.year, item.date.month, item.date.day),
    DateTime(currentDate.year, currentDate.month, currentDate.day),
  }.toList()..sort();
  final latest = <String, WealthHistoryEntry>{};
  final result = <WealthHistoryPoint>[];
  for (final date in dates) {
    for (final item in ordered.where((e) => !e.date.isAfter(date))) {
      latest[item.sourceId] = item;
    }
    final assetValues = latest.values.where(
      (e) => e.sourceId.startsWith('asset:'),
    );
    final investmentValues = latest.values.where(
      (e) => e.sourceId.startsWith('investment:'),
    );
    Money sum(Iterable<WealthHistoryEntry> values) => Money.fromMinorUnits(
      values.fold(0, (total, item) => total + item.value.minorUnits),
    );
    final isCurrent = date == dates.last;
    result.add(
      WealthHistoryPoint(
        date: date,
        assets: isCurrent ? currentSnapshot.assets : sum(assetValues),
        investments: isCurrent
            ? currentSnapshot.investments
            : sum(investmentValues),
        liquidity: isCurrent ? currentSnapshot.liquidity : null,
        liabilities: isCurrent ? currentSnapshot.liabilities : null,
        isComplete: isCurrent,
        explanations: List.unmodifiable([
          if (assetValues.isNotEmpty)
            '${assetValues.length} valorisation(s) d’actifs prouvée(s)',
          if (investmentValues.isNotEmpty)
            '${investmentValues.length} valorisation(s) d’investissements prouvée(s)',
          if (!isCurrent)
            'Liquidités et passifs historiques non figés : valeur nette non calculée',
          if (isCurrent)
            'Situation actuelle issue des lectures canoniques autorisées',
        ]),
      ),
    );
  }
  return List.unmodifiable(result);
}

class AnnualWealthComparison {
  const AnnualWealthComparison({required this.previous, required this.current});
  final WealthHistoryPoint? previous;
  final WealthHistoryPoint? current;
  Money? get change => previous?.netWorth == null || current?.netWorth == null
      ? null
      : current!.netWorth! - previous!.netWorth!;
}

AnnualWealthComparison compareAnnualWealth(
  Iterable<WealthHistoryPoint> points,
  int year,
) {
  WealthHistoryPoint? lastIn(int target) {
    final matches = points.where((p) => p.date.year == target).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return matches.isEmpty ? null : matches.last;
  }

  return AnnualWealthComparison(
    previous: lastIn(year - 1),
    current: lastIn(year),
  );
}

enum ConsolidatedDueKind { obligation, financing, expected }

enum ConsolidatedDueState { observed, expected, projected }

class ConsolidatedDue {
  const ConsolidatedDue({
    required this.identity,
    required this.label,
    required this.date,
    required this.amount,
    required this.kind,
    required this.state,
    required this.sourceId,
  });
  final String identity;
  final String label;
  final DateTime date;
  final Money amount;
  final ConsolidatedDueKind kind;
  final ConsolidatedDueState state;
  final String sourceId;
}

List<ConsolidatedDue> consolidateDues({
  required Iterable<ConsolidatedDue> obligations,
  required Iterable<ConsolidatedDue> financings,
  required Iterable<ConsolidatedDue> expected,
}) {
  final financedObligations = financings
      .map((e) => e.identity)
      .where((e) => e.startsWith('obligation:'))
      .toSet();
  final all = <ConsolidatedDue>[
    ...obligations.where((e) => !financedObligations.contains(e.identity)),
    ...financings,
    ...expected,
  ];
  final unique = <String, ConsolidatedDue>{};
  for (final item in all) {
    final key = '${item.identity}|${_day(item.date)}|${item.amount.minorUnits}';
    unique.putIfAbsent(key, () => item);
  }
  final result = unique.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return List.unmodifiable(result);
}

List<int> encodeWealthHistoryCsv(Iterable<WealthHistoryPoint> points) {
  final out = StringBuffer(
    '\uFEFFdate;actifs;investissements;liquidites;passifs;valeur_nette;complet;explication\n',
  );
  for (final point in points) {
    String money(Money? value) => value?.dirhams.toStringAsFixed(2) ?? '';
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    out.writeln(
      [
        _day(point.date),
        money(point.assets),
        money(point.investments),
        money(point.liquidity),
        money(point.liabilities),
        money(point.netWorth),
        point.isComplete ? 'oui' : 'non',
        point.explanations.join(' · '),
      ].map(cell).join(';'),
    );
  }
  return utf8.encode(out.toString());
}

String _day(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
