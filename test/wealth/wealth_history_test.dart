import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/wealth/domain/wealth_history.dart';
import 'package:noyau_app/features/wealth/domain/wealth_models.dart';

Money mad(num value) => Money.fromDirhams(value);

void main() {
  group('historique patrimonial prouvé', () {
    test('ne fabrique pas une valeur nette historique incomplète', () {
      final points = buildWealthHistory(
        entries: [
          WealthHistoryEntry(
            sourceId: 'asset:home',
            label: 'Logement',
            date: DateTime(2025, 12, 31),
            value: mad(600000),
            kind: WealthEvidenceKind.entered,
          ),
        ],
        currentDate: DateTime(2026, 10, 24),
        currentSnapshot: WealthSnapshot(
          liquidity: mad(10000),
          investments: mad(5000),
          assets: mad(610000),
          liabilities: mad(400000),
        ),
      );
      expect(points, hasLength(2));
      expect(points.first.netWorth, isNull);
      expect(points.first.assets, mad(600000));
      expect(points.last.netWorth, mad(225000));
      expect(points.last.isComplete, isTrue);
    });

    test('compare N/N-1 uniquement lorsque les deux points sont complets', () {
      final comparison = compareAnnualWealth([
        WealthHistoryPoint(
          date: DateTime(2025, 12, 31),
          assets: mad(100),
          investments: mad(0),
          liquidity: mad(50),
          liabilities: mad(20),
          isComplete: true,
          explanations: const [],
        ),
        WealthHistoryPoint(
          date: DateTime(2026, 12, 31),
          assets: mad(110),
          investments: mad(0),
          liquidity: mad(60),
          liabilities: mad(10),
          isComplete: true,
          explanations: const [],
        ),
      ], 2026);
      expect(comparison.change, mad(30));
    });

    test('exporte les points et signale les lignes partielles', () {
      final csv = utf8.decode(
        encodeWealthHistoryCsv([
          WealthHistoryPoint(
            date: DateTime(2025, 2, 28),
            assets: mad(10),
            investments: mad(0),
            isComplete: false,
            explanations: const ['Historique incomplet'],
          ),
        ]),
      );
      expect(csv, contains('2025-02-28'));
      expect(csv, contains('"non"'));
      expect(csv, contains('Historique incomplet'));
    });
  });

  group('échéancier consolidé', () {
    ConsolidatedDue due(
      String identity,
      ConsolidatedDueKind kind, {
      int day = 31,
      int amount = 100,
      String source = 'source',
    }) => ConsolidatedDue(
      identity: identity,
      label: identity,
      date: DateTime(2026, 12, day),
      amount: mad(amount),
      kind: kind,
      state: kind == ConsolidatedDueKind.financing
          ? ConsolidatedDueState.projected
          : ConsolidatedDueState.expected,
      sourceId: source,
    );

    test('ne double pas une obligation représentée par son financement', () {
      final result = consolidateDues(
        obligations: [due('obligation:o1', ConsolidatedDueKind.obligation)],
        financings: [due('obligation:o1', ConsolidatedDueKind.financing)],
        expected: const [],
      );
      expect(result, hasLength(1));
      expect(result.single.kind, ConsolidatedDueKind.financing);
    });

    test('préserve les sources distinctes et trie les frontières', () {
      final result = consolidateDues(
        obligations: [
          due('obligation:o1', ConsolidatedDueKind.obligation, day: 31),
        ],
        financings: const [],
        expected: [due('expected:e1', ConsolidatedDueKind.expected, day: 1)],
      );
      expect(result.map((e) => e.date.day), [1, 31]);
    });

    test('déduplique les retries d’une même source économique', () {
      final item = due('expected:e1', ConsolidatedDueKind.expected);
      final result = consolidateDues(
        obligations: const [],
        financings: const [],
        expected: [item, item],
      );
      expect(result, hasLength(1));
    });
  });
}
