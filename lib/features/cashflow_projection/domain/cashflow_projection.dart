import '../../../core/money/money.dart';
import '../../recurring_finance/domain/recurring_finance.dart';
import '../../wealth/domain/wealth_models.dart';
import '../../wealth/domain/home_auto_models.dart';
import '../../finance/application/providers/remote_debts_provider.dart';

enum ProjectionHorizon { endOfMonth, nextMonth, threeMonths, sixMonths, year }

enum ProjectionCertainty { certain, estimated, hypothetical }

enum ProjectionFlowKind { income, expense, internalTransfer, financing }

class ProjectionExplanation {
  const ProjectionExplanation({
    required this.rule,
    required this.sourceKind,
    required this.sourceId,
    required this.reason,
    this.period,
    this.parameters = const {},
  });
  final String rule, sourceKind, sourceId, reason;
  final String? period;
  final Map<String, Object?> parameters;
}

class ProjectionFlow {
  const ProjectionFlow({
    required this.id,
    required this.date,
    required this.label,
    required this.amount,
    required this.kind,
    required this.certainty,
    required this.source,
    this.sourceAccountId,
    this.destinationAccountId,
    this.envelopeId,
    this.memberId,
    this.explanation,
  });

  final String id, label, source;
  final DateTime date;
  final Money amount;
  final ProjectionFlowKind kind;
  final ProjectionCertainty certainty;
  final String? sourceAccountId, destinationAccountId, envelopeId, memberId;
  final ProjectionExplanation? explanation;

  int get householdDelta => switch (kind) {
    ProjectionFlowKind.income => amount.minorUnits,
    ProjectionFlowKind.expense ||
    ProjectionFlowKind.financing => -amount.minorUnits,
    ProjectionFlowKind.internalTransfer => 0,
  };
}

List<ProjectionFlow> adaptCanonicalExpectedSources({
  required DateTime asOf,
  required DateTime through,
  Iterable<RemoteDebtBalance> obligations = const [],
  Iterable<VehicleCostPlan> vehicleCosts = const [],
}) {
  final start = _day(asOf);
  final result = <ProjectionFlow>[];
  for (final obligation in obligations) {
    final due = obligation.dueAt;
    if (due == null ||
        obligation.remainingAmount.minorUnits <= 0 ||
        due.isBefore(start) ||
        due.isAfter(through)) {
      continue;
    }
    result.add(
      ProjectionFlow(
        id: 'obligation:${obligation.id}',
        date: due,
        label: obligation.description,
        amount: obligation.remainingAmount,
        kind: ProjectionFlowKind.expense,
        certainty: ProjectionCertainty.certain,
        source: 'Obligations — solde dérivé et échéance canonique',
        explanation: ProjectionExplanation(
          rule: 'obligation_due',
          sourceKind: 'obligation',
          sourceId: obligation.id,
          period: _key(due),
          reason: 'Échéance ouverte issue du solde canonique de l’obligation.',
        ),
      ),
    );
  }
  for (final plan in vehicleCosts) {
    if (plan.category == VehicleCostCategory.financing) continue;
    if (plan.dueDate.isBefore(start) || plan.dueDate.isAfter(through)) continue;
    result.add(
      ProjectionFlow(
        id: 'vehicle-cost:${plan.id}',
        date: plan.dueDate,
        label: plan.label,
        amount: plan.amount,
        kind: ProjectionFlowKind.expense,
        certainty: ProjectionCertainty.estimated,
        source: 'F6 — coût automobile planifié',
        explanation: ProjectionExplanation(
          rule: 'vehicle_cost_due',
          sourceKind: 'vehicle_cost',
          sourceId: plan.id,
          period: _key(plan.dueDate),
          reason: 'Coût planifié daté, sans écriture financière.',
          parameters: {'category': plan.category.name},
        ),
      ),
    );
  }
  return List.unmodifiable(result);
}

class ProjectionRisk {
  const ProjectionRisk({required this.date, required this.message});
  final DateTime date;
  final String message;
}

class CashflowProjection {
  const CashflowProjection({
    required this.asOf,
    required this.through,
    required this.currentHouseholdBalance,
    required this.projectedHouseholdBalance,
    required this.accountBalances,
    required this.projectedAccountBalances,
    required this.envelopeBalances,
    required this.projectedEnvelopeBalances,
    required this.memberDeltas,
    required this.flows,
    required this.risks,
    required this.unlocatedAmount,
    this.scenarioName,
  });

  final DateTime asOf, through;
  final Money currentHouseholdBalance, projectedHouseholdBalance;
  final Map<String, Money> accountBalances, projectedAccountBalances;
  final Map<String, Money> envelopeBalances, projectedEnvelopeBalances;
  final Map<String, Money> memberDeltas;
  final List<ProjectionFlow> flows;
  final List<ProjectionRisk> risks;
  final Money unlocatedAmount;
  final String? scenarioName;

  Money get income => Money.fromMinorUnits(
    flows
        .where((f) => f.kind == ProjectionFlowKind.income)
        .fold(0, (sum, f) => sum + f.amount.minorUnits),
  );
  Money get expenses => Money.fromMinorUnits(
    flows
        .where(
          (f) =>
              f.kind == ProjectionFlowKind.expense ||
              f.kind == ProjectionFlowKind.financing,
        )
        .fold(0, (sum, f) => sum + f.amount.minorUnits),
  );
  Money get transfers => Money.fromMinorUnits(
    flows
        .where((f) => f.kind == ProjectionFlowKind.internalTransfer)
        .fold(0, (sum, f) => sum + f.amount.minorUnits),
  );
}

DateTime projectionThrough(DateTime asOf, ProjectionHorizon horizon) =>
    switch (horizon) {
      ProjectionHorizon.endOfMonth => DateTime(asOf.year, asOf.month + 1, 0),
      ProjectionHorizon.nextMonth => DateTime(asOf.year, asOf.month + 2, 0),
      ProjectionHorizon.threeMonths => DateTime(asOf.year, asOf.month + 3, 0),
      ProjectionHorizon.sixMonths => DateTime(asOf.year, asOf.month + 6, 0),
      ProjectionHorizon.year => DateTime(asOf.year, asOf.month + 12, 0),
    };

List<ExpectedFinancialOccurrence> expandExpectedOccurrences({
  required DateTime asOf,
  required DateTime through,
  required List<RecurringFinancialIntention> intentions,
  required List<ExpectedFinancialOccurrence> persisted,
}) {
  final result = <ExpectedFinancialOccurrence>[
    ...persisted.where(
      (o) =>
          !o.expectedOn.isBefore(_day(asOf)) && !o.expectedOn.isAfter(through),
    ),
  ];
  final existing = {
    for (final o in persisted) '${o.intentionId}:${_key(o.expectedOn)}',
  };
  for (final intention in intentions) {
    if (intention.status != RecurringStatus.active) continue;
    var date = intention.nextOccurrenceOn;
    while (date.isBefore(_day(asOf))) {
      date = nextRecurringDate(
        date,
        intention.frequency,
        anchorDay: intention.startsOn.day,
      );
    }
    while (!date.isAfter(through) &&
        (intention.endsOn == null || !date.isAfter(intention.endsOn!))) {
      final key = '${intention.id}:${_key(date)}';
      if (!existing.contains(key)) {
        result.add(
          ExpectedFinancialOccurrence(
            id: 'projected:$key',
            intentionId: intention.id,
            expectedOn: date,
            type: intention.type,
            label: intention.label,
            expectedAmount: intention.amount,
            confirmedAmount: const Money.fromMinorUnits(0),
            status: ExpectedOccurrenceStatus.expected,
            sourceAccountId: intention.sourceAccountId,
            destinationAccountId: intention.destinationAccountId,
            envelopeId: intention.envelopeId,
            memberId: intention.memberId,
          ),
        );
      }
      date = nextRecurringDate(
        date,
        intention.frequency,
        anchorDay: intention.startsOn.day,
      );
    }
  }
  result.sort((a, b) => a.expectedOn.compareTo(b.expectedOn));
  return List.unmodifiable(result);
}

CashflowProjection buildCashflowProjection({
  required DateTime asOf,
  required DateTime through,
  required Map<String, Money> accountBalances,
  required Map<String, Money> envelopeBalances,
  required List<ExpectedFinancialOccurrence> occurrences,
  List<FinancingProfile> financings = const [],
  Map<String, ProjectionCertainty> certaintyByIntention = const {},
  List<ProjectionFlow> canonicalExpectedFlows = const [],
  List<ProjectionFlow> hypotheticalFlows = const [],
  String? scenarioName,
}) {
  final flows = <ProjectionFlow>[];
  for (final occurrence in occurrences) {
    if (occurrence.status == ExpectedOccurrenceStatus.realized ||
        occurrence.status == ExpectedOccurrenceStatus.ignored ||
        occurrence.remaining.minorUnits <= 0 ||
        occurrence.expectedOn.isBefore(_day(asOf)) ||
        occurrence.expectedOn.isAfter(through)) {
      continue;
    }
    flows.add(
      ProjectionFlow(
        id: occurrence.id,
        date: occurrence.expectedOn,
        label: occurrence.label,
        amount: occurrence.remaining,
        kind: switch (occurrence.type) {
          RecurringEconomicType.income => ProjectionFlowKind.income,
          RecurringEconomicType.expense => ProjectionFlowKind.expense,
          RecurringEconomicType.accountTransfer =>
            ProjectionFlowKind.internalTransfer,
        },
        certainty:
            certaintyByIntention[occurrence.intentionId] ??
            ProjectionCertainty.certain,
        source: 'R3.1 — opération attendue',
        sourceAccountId: occurrence.sourceAccountId,
        destinationAccountId: occurrence.destinationAccountId,
        envelopeId: occurrence.envelopeId,
        memberId: occurrence.memberId,
        explanation: ProjectionExplanation(
          rule: 'recurring_occurrence',
          sourceKind: 'recurring_intention',
          sourceId: occurrence.intentionId,
          period: _key(occurrence.expectedOn),
          reason: 'Occurrence attendue restante, non réalisée et non ignorée.',
        ),
      ),
    );
  }
  for (final financing in financings) {
    for (final line in buildFinancingSchedule(financing)) {
      if (line.date.isBefore(_day(asOf)) || line.date.isAfter(through)) {
        continue;
      }
      final duplicate = flows.any(
        (flow) =>
            flow.kind == ProjectionFlowKind.expense &&
            (flow.date.difference(line.date).inDays).abs() <= 3 &&
            flow.amount.minorUnits == line.payment.minorUnits &&
            _labelsOverlap(flow.label, financing.label),
      );
      if (!duplicate) {
        flows.add(
          ProjectionFlow(
            id: 'financing:${financing.id}:${line.number}',
            date: line.date,
            label: financing.label,
            amount: line.payment,
            kind: ProjectionFlowKind.financing,
            certainty: ProjectionCertainty.certain,
            source: 'F5 — échéancier de financement',
          ),
        );
      }
    }
  }
  final existingIds = flows.map((flow) => flow.id).toSet();
  for (final flow in [...canonicalExpectedFlows, ...hypotheticalFlows]) {
    if (flow.date.isBefore(_day(asOf)) || flow.date.isAfter(through)) continue;
    if (existingIds.add(flow.id)) flows.add(flow);
  }
  flows.sort((a, b) => a.date.compareTo(b.date));

  final accounts = {
    for (final e in accountBalances.entries) e.key: e.value.minorUnits,
  };
  final envelopes = {
    for (final e in envelopeBalances.entries) e.key: e.value.minorUnits,
  };
  final members = <String, int>{};
  final risks = <ProjectionRisk>[];
  var household = accounts.values.fold<int>(0, (a, b) => a + b);
  var unlocated = 0;
  for (final flow in flows) {
    household += flow.householdDelta;
    if (flow.memberId != null) {
      members.update(
        flow.memberId!,
        (v) => v + flow.householdDelta,
        ifAbsent: () => flow.householdDelta,
      );
    }
    if (flow.kind == ProjectionFlowKind.income) {
      if (flow.destinationAccountId == null ||
          !accounts.containsKey(flow.destinationAccountId)) {
        unlocated += flow.amount.minorUnits;
      } else {
        accounts.update(
          flow.destinationAccountId!,
          (v) => v + flow.amount.minorUnits,
        );
      }
      if (flow.envelopeId != null && envelopes.containsKey(flow.envelopeId)) {
        envelopes.update(flow.envelopeId!, (v) => v + flow.amount.minorUnits);
      }
    } else if (flow.kind == ProjectionFlowKind.internalTransfer) {
      if (accounts.containsKey(flow.sourceAccountId) &&
          accounts.containsKey(flow.destinationAccountId)) {
        accounts.update(
          flow.sourceAccountId!,
          (v) => v - flow.amount.minorUnits,
        );
        accounts.update(
          flow.destinationAccountId!,
          (v) => v + flow.amount.minorUnits,
        );
      } else {
        unlocated += flow.amount.minorUnits;
      }
    } else {
      if (flow.sourceAccountId == null ||
          !accounts.containsKey(flow.sourceAccountId)) {
        unlocated += flow.amount.minorUnits;
      } else {
        accounts.update(
          flow.sourceAccountId!,
          (v) => v - flow.amount.minorUnits,
        );
        if (accounts[flow.sourceAccountId]! < 0) {
          risks.add(
            ProjectionRisk(
              date: flow.date,
              message:
                  'Un compte pourrait devenir négatif après « ${flow.label} ».',
            ),
          );
        }
      }
      if (flow.envelopeId != null && envelopes.containsKey(flow.envelopeId)) {
        envelopes.update(flow.envelopeId!, (v) => v - flow.amount.minorUnits);
      }
    }
    if (household < 0) {
      risks.add(
        ProjectionRisk(
          date: flow.date,
          message:
              'La trésorerie du foyer pourrait devenir négative après « ${flow.label} ».',
        ),
      );
    }
  }
  return CashflowProjection(
    asOf: _day(asOf),
    through: through,
    currentHouseholdBalance: Money.fromMinorUnits(
      accountBalances.values.fold(0, (a, b) => a + b.minorUnits),
    ),
    projectedHouseholdBalance: Money.fromMinorUnits(household),
    accountBalances: Map.unmodifiable(accountBalances),
    projectedAccountBalances: Map.unmodifiable(
      accounts.map((k, v) => MapEntry(k, Money.fromMinorUnits(v))),
    ),
    envelopeBalances: Map.unmodifiable(envelopeBalances),
    projectedEnvelopeBalances: Map.unmodifiable(
      envelopes.map((k, v) => MapEntry(k, Money.fromMinorUnits(v))),
    ),
    memberDeltas: Map.unmodifiable(
      members.map((k, v) => MapEntry(k, Money.fromMinorUnits(v))),
    ),
    flows: List.unmodifiable(flows),
    risks: List.unmodifiable(risks),
    unlocatedAmount: Money.fromMinorUnits(unlocated),
    scenarioName: scenarioName,
  );
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
String _key(DateTime value) => '${value.year}-${value.month}-${value.day}';

bool _labelsOverlap(String left, String right) {
  Set<String> tokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zà-ÿ0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.length > 2)
      .toSet();
  final a = tokens(left), b = tokens(right);
  return a.isNotEmpty && b.isNotEmpty && a.intersection(b).isNotEmpty;
}
