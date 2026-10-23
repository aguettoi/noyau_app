import '../../recurring_finance/domain/recurring_finance.dart';
import '../application/providers/remote_budget_provider.dart';

enum MonthlyQualityLevel { information, attention, blocker }

enum MonthlyResponsibility { household, member, unassigned }

class MonthlyQualityExplanation {
  const MonthlyQualityExplanation({
    required this.rule,
    required this.period,
    required this.source,
    required this.reason,
    required this.status,
    this.action,
  });

  final String rule, period, source, reason, status;
  final String? action;
}

class MonthlyEnvelopeQuality {
  const MonthlyEnvelopeQuality({
    required this.envelopeId,
    required this.plannedCents,
    required this.actualCents,
    required this.expectedCents,
  });

  final String envelopeId;
  final int plannedCents, actualCents, expectedCents;
  int get remainingCents => plannedCents - actualCents - expectedCents;
  bool get overCommitted => remainingCents < 0;
}

class MonthlyReconciliationQuality {
  const MonthlyReconciliationQuality({required this.open, required this.stale});
  final int open, stale;
}

class MonthlyReceiptQuality {
  const MonthlyReceiptQuality({
    required this.required,
    required this.attached,
    required this.missing,
  });
  final int required, attached, missing;
  double get coverage => required == 0 ? 1 : attached / required;
}

class MonthlyResponsibilityQuality {
  const MonthlyResponsibilityQuality({
    required this.household,
    required this.member,
    required this.unassigned,
  });
  final int household, member, unassigned;
}

enum MonthlyDecisionKind {
  preserveLiquidity,
  savings,
  priorities,
  variableIncome,
}

class MonthlyDecisionOption {
  const MonthlyDecisionOption({
    required this.kind,
    required this.title,
    required this.amountCents,
    required this.consequence,
    required this.explanation,
    this.requiresConfirmation = true,
  });

  final MonthlyDecisionKind kind;
  final String title, consequence;
  final int amountCents;
  final bool requiresConfirmation;
  final MonthlyQualityExplanation explanation;
}

class MonthlyQualityAnalysis {
  const MonthlyQualityAnalysis({
    required this.envelopes,
    required this.reconciliations,
    required this.receipts,
    required this.responsibilities,
    required this.unresolvedOccurrences,
    required this.options,
    required this.explanations,
  });

  final List<MonthlyEnvelopeQuality> envelopes;
  final MonthlyReconciliationQuality reconciliations;
  final MonthlyReceiptQuality receipts;
  final MonthlyResponsibilityQuality responsibilities;
  final int unresolvedOccurrences;
  final List<MonthlyDecisionOption> options;
  final List<MonthlyQualityExplanation> explanations;

  int get plannedCents =>
      envelopes.fold(0, (sum, row) => sum + row.plannedCents);
  int get actualCents => envelopes.fold(0, (sum, row) => sum + row.actualCents);
  int get expectedCents =>
      envelopes.fold(0, (sum, row) => sum + row.expectedCents);
  int get remainingCents =>
      envelopes.fold(0, (sum, row) => sum + row.remainingCents);
}

class MonthlyQualityEvent {
  const MonthlyQualityEvent({
    required this.id,
    required this.requiresReceipt,
    required this.hasReceipt,
    required this.responsibility,
  });
  final String id;
  final bool requiresReceipt, hasReceipt;
  final MonthlyResponsibility responsibility;
}

class MonthlyQualityReconciliation {
  const MonthlyQualityReconciliation({
    required this.open,
    required this.observedAt,
  });
  final bool open;
  final DateTime observedAt;
}

MonthlyQualityAnalysis analyzeMonthlyQuality({
  required DateTime periodStart,
  required DateTime periodEnd,
  required List<RemoteBudgetReportRow> budget,
  required List<ExpectedFinancialOccurrence> occurrences,
  required List<MonthlyQualityEvent> events,
  required List<MonthlyQualityReconciliation> reconciliations,
  bool availabilityComplete = true,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  bool inPeriod(DateTime value) =>
      !value.isBefore(periodStart) && !value.isAfter(periodEnd);
  final unresolved = occurrences.where(
    (item) =>
        inPeriod(item.expectedOn) &&
        item.status != ExpectedOccurrenceStatus.realized &&
        item.status != ExpectedOccurrenceStatus.ignored,
  );
  final expectedByEnvelope = <String, int>{};
  var variableIncome = 0;
  for (final item in unresolved) {
    if (item.type == RecurringEconomicType.expense && item.envelopeId != null) {
      expectedByEnvelope.update(
        item.envelopeId!,
        (value) => value + item.remaining.minorUnits,
        ifAbsent: () => item.remaining.minorUnits,
      );
    } else if (item.type == RecurringEconomicType.income) {
      variableIncome += item.remaining.minorUnits;
    }
  }
  final envelopes = [
    for (final row in budget)
      MonthlyEnvelopeQuality(
        envelopeId: row.envelopeId,
        plannedCents: row.plannedCents,
        actualCents: row.actualCents,
        expectedCents: expectedByEnvelope[row.envelopeId] ?? 0,
      ),
  ];
  final required = events.where((event) => event.requiresReceipt).toList();
  final attached = required.where((event) => event.hasReceipt).length;
  final openReconciliations = reconciliations
      .where((item) => item.open)
      .toList();
  final responsibility = MonthlyResponsibilityQuality(
    household: events
        .where((e) => e.responsibility == MonthlyResponsibility.household)
        .length,
    member: events
        .where((e) => e.responsibility == MonthlyResponsibility.member)
        .length,
    unassigned: events
        .where((e) => e.responsibility == MonthlyResponsibility.unassigned)
        .length,
  );
  final period =
      '${periodStart.year}-${periodStart.month.toString().padLeft(2, '0')}';
  final remaining = envelopes.fold<int>(
    0,
    (sum, row) => sum + row.remainingCents,
  );
  final explanations = <MonthlyQualityExplanation>[
    if (openReconciliations.isNotEmpty)
      MonthlyQualityExplanation(
        rule: 'Rapprochements ouverts',
        period: period,
        source: 'account_reconciliation_cases',
        reason:
            '${openReconciliations.length} rapprochement(s) restent à traiter.',
        status: 'attention',
        action: 'Ouvrir les comptes concernés.',
      ),
    if (required.length - attached > 0)
      MonthlyQualityExplanation(
        rule: 'Justificatifs requis',
        period: period,
        source: 'financial_event_attachments',
        reason:
            '${required.length - attached} opération(s) éligible(s) sans justificatif.',
        status: 'attention',
        action: 'Compléter les justificatifs depuis les transactions.',
      ),
    if (responsibility.unassigned > 0)
      MonthlyQualityExplanation(
        rule: 'Responsabilité explicite',
        period: period,
        source: 'financial_events.created_by',
        reason:
            '${responsibility.unassigned} opération(s) restent non attribuées.',
        status: 'information',
        action:
            'Conserver Foyer / non attribué si aucune preuve ne permet mieux.',
      ),
  ];
  final options = <MonthlyDecisionOption>[
    if (remaining > 0)
      MonthlyDecisionOption(
        kind: MonthlyDecisionKind.preserveLiquidity,
        title: 'Conserver le reliquat disponible',
        amountCents: remaining,
        consequence:
            'La marge reste disponible; aucun mouvement bancaire ou d’enveloppe n’est créé.',
        explanation: MonthlyQualityExplanation(
          rule: 'Reliquat mensuel',
          period: period,
          source: 'Budget prévu − réalisé − attendu',
          reason:
              'Le budget conserve une marge positive après les opérations encore attendues.',
          status: 'simulation',
        ),
      ),
    if (remaining > 0 && !availabilityComplete)
      MonthlyDecisionOption(
        kind: MonthlyDecisionKind.priorities,
        title: 'Capacité à confirmer avant arbitrage',
        amountCents: remaining,
        consequence:
            'FinancialAvailability ne dispose pas de toutes les données autorisées; aucune recommandation de financement n’est formulée.',
        explanation: MonthlyQualityExplanation(
          rule: 'Arbitrage transversal',
          period: period,
          source: 'FinancialAvailability',
          reason:
              'La capacité financière est incomplète; le moteur refuse de déduire un solde ou une capacité privée.',
          status: 'données insuffisantes',
          action: 'Compléter les données autorisées avant de décider.',
        ),
      ),
    if (remaining > 0)
      MonthlyDecisionOption(
        kind: MonthlyDecisionKind.savings,
        title: 'Étudier une affectation à Épargne',
        amountCents: remaining,
        consequence:
            'Option simulée uniquement; le sweep canonique mensuel reste distinct et doit être confirmé.',
        explanation: MonthlyQualityExplanation(
          rule: 'Épargne permanente',
          period: period,
          source: 'Règles Budget Intelligence et sweep R2',
          reason:
              'Le reliquat peut être comparé aux sources historiquement éligibles sans inventer de transfert bancaire.',
          status: 'à confirmer',
          action:
              'Vérifier les enveloppes éligibles dans la clôture mensuelle.',
        ),
      ),
    if (remaining > 0 && availabilityComplete)
      MonthlyDecisionOption(
        kind: MonthlyDecisionKind.priorities,
        title: 'Comparer avec les objectifs et PRIOS',
        amountCents: remaining,
        consequence:
            'FinancialAvailability décide seulement de la capacité; aucune priorité n’est financée automatiquement.',
        explanation: MonthlyQualityExplanation(
          rule: 'Arbitrage transversal',
          period: period,
          source: 'FinancialAvailability / PRIOS',
          reason:
              'Une marge peut être comparée aux besoins planifiés sans modifier le réel.',
          status: 'simulation',
          action: 'Ouvrir PRIOS pour choisir explicitement.',
        ),
      ),
    if (variableIncome > 0)
      MonthlyDecisionOption(
        kind: MonthlyDecisionKind.variableIncome,
        title: 'Prime ou revenu variable attendu',
        amountCents: variableIncome,
        consequence:
            'L’origine membre/compte reste attachée à l’occurrence; le montant n’entre pas dans le budget récurrent.',
        explanation: MonthlyQualityExplanation(
          rule: 'Revenu variable hors budget récurrent',
          period: period,
          source: 'Occurrences R3.1 autorisées',
          reason:
              'Un revenu attendu n’est ni encaissé ni affecté tant qu’il n’est pas réalisé.',
          status: 'attendu',
        ),
      ),
  ];
  return MonthlyQualityAnalysis(
    envelopes: List.unmodifiable(envelopes),
    reconciliations: MonthlyReconciliationQuality(
      open: openReconciliations.length,
      stale: openReconciliations
          .where((item) => clock.difference(item.observedAt).inDays > 30)
          .length,
    ),
    receipts: MonthlyReceiptQuality(
      required: required.length,
      attached: attached,
      missing: required.length - attached,
    ),
    responsibilities: responsibility,
    unresolvedOccurrences: unresolved.length,
    options: List.unmodifiable(options),
    explanations: List.unmodifiable(explanations),
  );
}
