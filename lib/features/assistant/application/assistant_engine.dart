import '../domain/assistant_contract.dart';

class DeterministicAssistantProvider implements AssistantProvider {
  const DeterministicAssistantProvider({this.clock = DateTime.now});
  final DateTime Function() clock;

  @override
  String get mode => 'deterministic';

  @override
  Future<AssistantResponse> answer(AuthorizedAssistantContext context) async {
    final statements = <AssistantStatement>[];
    final proposals = <AssistantProposal>[];
    final facts = context.visibleFacts;
    final flags = context.flags;
    switch (context.useCase) {
      case AssistantUseCase.budget:
        if (!facts.containsKey('budget_remaining_minor')) {
          statements.add(
            const AssistantStatement(
              AssistantStatementKind.uncertainty,
              'assistant.insufficient',
            ),
          );
        } else if (facts['budget_remaining_minor']! < 0) {
          statements.add(
            const AssistantStatement(
              AssistantStatementKind.fact,
              'assistant.budget.tension',
            ),
          );
          statements.add(
            const AssistantStatement(
              AssistantStatementKind.rule,
              'assistant.budget.rule',
            ),
          );
          proposals.add(
            _navigate(
              'budget',
              'assistant.action.open_budget',
              'assistant.action.review_budget',
              clock(),
            ),
          );
        } else {
          statements.add(
            const AssistantStatement(
              AssistantStatementKind.fact,
              'assistant.budget.stable',
            ),
          );
        }
      case AssistantUseCase.monthlySummary:
        statements.add(
          AssistantStatement(
            AssistantStatementKind.fact,
            'assistant.summary',
            arguments: {
              'alerts': facts['alert_count']?.toInt() ?? 0,
              'goals': facts['goal_count']?.toInt() ?? 0,
            },
          ),
        );
        if (flags['has_hidden_financial_data'] == true) {
          statements.add(
            const AssistantStatement(
              AssistantStatementKind.uncertainty,
              'assistant.hidden_excluded',
            ),
          );
        }
      case AssistantUseCase.anomalies:
        statements.add(
          AssistantStatement(
            AssistantStatementKind.fact,
            facts['alert_count'] == 0
                ? 'assistant.anomaly.none'
                : 'assistant.anomaly.present',
          ),
        );
      case AssistantUseCase.priorities:
        statements.add(
          AssistantStatement(
            AssistantStatementKind.fact,
            flags['has_next_priority'] == true
                ? 'assistant.priorities.next'
                : 'assistant.priorities.none',
          ),
        );
        proposals.add(
          _navigate(
            'priorities',
            'assistant.action.open_priorities',
            'assistant.action.review_priorities',
            clock(),
          ),
        );
      case AssistantUseCase.organization:
        statements.add(
          AssistantStatement(
            AssistantStatementKind.fact,
            'assistant.organization.summary',
            arguments: {'tasks': facts['open_task_count']?.toInt() ?? 0},
          ),
        );
      case AssistantUseCase.shopping:
        statements.add(
          AssistantStatement(
            AssistantStatementKind.rule,
            flags['authorized_availability_ok'] == true
                ? 'assistant.shopping.compatible'
                : 'assistant.shopping.unknown',
          ),
        );
      case AssistantUseCase.wealth:
        statements.add(
          const AssistantStatement(
            AssistantStatementKind.rule,
            'assistant.wealth.explain_only',
          ),
        );
      case AssistantUseCase.productHelp:
        statements.add(
          const AssistantStatement(
            AssistantStatementKind.suggestion,
            'assistant.help',
          ),
        );
    }
    return AssistantResponse(statements: statements, proposals: proposals);
  }

  AssistantProposal _navigate(
    String target,
    String objective,
    String reason,
    DateTime now,
  ) => AssistantProposal(
    id: '${now.microsecondsSinceEpoch}-$target',
    type: 'navigate',
    objectiveKey: objective,
    justificationKey: reason,
    risk: AssistantRisk.low,
    createdAt: now,
    expiresAt: now.add(const Duration(minutes: 15)),
    parameters: {'target': target},
    sourceCategories: const {'authorized_summary'},
  );
}

class AssistantActionWorkflow {
  const AssistantActionWorkflow(this.executor, {this.clock = DateTime.now});
  final AssistantActionExecutor executor;
  final DateTime Function() clock;

  Future<AssistantProposal> reject(AssistantProposal proposal) async =>
      proposal.copyWith(state: AssistantActionState.rejected);

  Future<AssistantProposal> confirm(AssistantProposal proposal) async {
    if (proposal.state != AssistantActionState.proposed) return proposal;
    if (proposal.type != 'navigate') {
      return proposal.copyWith(state: AssistantActionState.failed);
    }
    if (!clock().isBefore(proposal.expiresAt)) {
      return proposal.copyWith(state: AssistantActionState.expired);
    }
    try {
      await executor.revalidate(proposal);
      await executor.execute(proposal);
      return proposal.copyWith(state: AssistantActionState.executed);
    } catch (_) {
      return proposal.copyWith(state: AssistantActionState.failed);
    }
  }
}

class UnavailableGenerativeProvider implements AssistantProvider {
  const UnavailableGenerativeProvider(this.fallback);
  final AssistantProvider fallback;
  @override
  String get mode => 'deterministic-fallback';
  @override
  Future<AssistantResponse> answer(AuthorizedAssistantContext context) =>
      fallback.answer(context);
}
