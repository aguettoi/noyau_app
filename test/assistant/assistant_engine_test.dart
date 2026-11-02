import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/assistant/application/assistant_engine.dart';
import 'package:noyau_app/features/assistant/application/assistant_providers.dart';
import 'package:noyau_app/features/assistant/domain/assistant_contract.dart';
import 'package:noyau_app/features/experience/application/experience_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const engine = DeterministicAssistantProvider();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('authorized context is minimal and contains no raw private data', () {
    final context = _context(
      AssistantUseCase.monthlySummary,
      flags: const {'has_hidden_financial_data': true},
    );
    expect(context.containsRawPrivateData, isFalse);
    expect(context.visibleFacts.keys, isNot(contains('account_balance')));
    expect(context.visibleFacts.keys, isNot(contains('cycle_notes')));
    expect(context.sourceCategories, {'authorized_summary'});
  });

  test(
    'budget uses canonical summary and distinguishes fact and rule',
    () async {
      final response = await engine.answer(
        _context(
          AssistantUseCase.budget,
          facts: const {'budget_remaining_minor': -1},
        ),
      );
      expect(
        response.statements.map((item) => item.kind),
        containsAll([AssistantStatementKind.fact, AssistantStatementKind.rule]),
      );
      expect(response.proposals.single.state, AssistantActionState.proposed);
    },
  );

  test('all V1 use cases return structured deterministic responses', () async {
    for (final useCase in AssistantUseCase.values) {
      final response = await engine.answer(
        _context(
          useCase,
          facts: const {
            'budget_remaining_minor': 10,
            'alert_count': 1,
            'goal_count': 2,
            'open_task_count': 3,
          },
        ),
      );
      expect(response.statements, isNotEmpty, reason: useCase.name);
    }
  });

  test('hidden data is excluded and never reconstructed', () async {
    final response = await engine.answer(
      _context(
        AssistantUseCase.monthlySummary,
        flags: const {'has_hidden_financial_data': true},
      ),
    );
    expect(
      response.statements.map((item) => item.messageKey),
      contains('assistant.hidden_excluded'),
    );
    expect(
      response.statements.expand((item) => item.arguments.keys),
      isNot(contains('hidden_balance')),
    );
  });

  test('untrusted user content cannot become instructions', () async {
    final context = _context(AssistantUseCase.productHelp);
    expect(context.visibleFacts, isEmpty);
    final response = await engine.answer(context);
    expect(response.statements.single.messageKey, 'assistant.help');
  });

  test('provider absence keeps deterministic mode available', () async {
    final provider = UnavailableGenerativeProvider(engine);
    final response = await provider.answer(
      _context(AssistantUseCase.anomalies),
    );
    expect(provider.mode, 'deterministic-fallback');
    expect(response.statements, isNotEmpty);
  });

  test(
    'proposal requires confirmation and revalidation before execution',
    () async {
      final executor = _Executor();
      final workflow = AssistantActionWorkflow(
        executor,
        clock: () => DateTime.utc(2026, 11, 2, 12),
      );
      final proposal = _proposal(expiresAt: DateTime.utc(2026, 11, 2, 13));
      expect(executor.executions, 0);
      final result = await workflow.confirm(proposal);
      expect(executor.revalidations, 1);
      expect(executor.executions, 1);
      expect(result.state, AssistantActionState.executed);
    },
  );

  test('proposal can be rejected, expires, and fails closed', () async {
    final executor = _Executor(fail: true);
    final workflow = AssistantActionWorkflow(
      executor,
      clock: () => DateTime.utc(2026, 11, 2, 14),
    );
    expect(
      (await workflow.reject(_proposal())).state,
      AssistantActionState.rejected,
    );
    expect(
      (await workflow.confirm(
        _proposal(expiresAt: DateTime.utc(2026, 11, 2, 13)),
      )).state,
      AssistantActionState.expired,
    );
    expect(
      (await workflow.confirm(
        _proposal(expiresAt: DateTime.utc(2026, 11, 2, 15)),
      )).state,
      AssistantActionState.failed,
    );
  });

  test(
    'financial mutation proposal cannot execute through L5 workflow',
    () async {
      final executor = _Executor();
      final workflow = AssistantActionWorkflow(
        executor,
        clock: () => DateTime.utc(2026, 11, 2, 12),
      );
      final financial = AssistantProposal(
        id: 'financial',
        type: 'financial_event',
        objectiveKey: 'objective',
        justificationKey: 'reason',
        risk: AssistantRisk.high,
        createdAt: DateTime.utc(2026, 11, 2, 12),
        expiresAt: DateTime.utc(2026, 11, 2, 13),
      );
      final result = await workflow.confirm(financial);
      expect(result.state, AssistantActionState.failed);
      expect(executor.revalidations, 0);
      expect(executor.executions, 0);
    },
  );

  test('audit persists metadata without raw private context', () async {
    final store = AssistantAuditStore();
    await store.append(
      AssistantAuditEvent(
        userId: 'user-a',
        householdId: 'household-a',
        useCase: AssistantUseCase.budget,
        timestamp: DateTime.utc(2026, 11, 2),
        mode: 'deterministic',
        sourceCategories: const {'budget_summary'},
      ),
    );
    final rows = await store.readMinimizedEvents();
    expect(rows, hasLength(1));
    expect(rows.single, contains('budget_summary'));
    expect(rows.single, isNot(contains('cycle')));
    expect(rows.single, isNot(contains('hidden_balance')));
    await ExperienceStore().purgePrivateState();
    expect(await store.readMinimizedEvents(), isEmpty);
  });
}

AuthorizedAssistantContext _context(
  AssistantUseCase useCase, {
  Map<String, num> facts = const {},
  Map<String, bool> flags = const {},
}) => AuthorizedAssistantContext(
  userId: 'user-a',
  householdId: 'household-a',
  useCase: useCase,
  generatedAt: DateTime.utc(2026, 11, 2),
  visibleFacts: facts,
  flags: flags,
  sourceCategories: const {'authorized_summary'},
);

AssistantProposal _proposal({DateTime? expiresAt}) => AssistantProposal(
  id: 'proposal-1',
  type: 'navigate',
  objectiveKey: 'objective',
  justificationKey: 'reason',
  risk: AssistantRisk.low,
  createdAt: DateTime.utc(2026, 11, 2, 12),
  expiresAt: expiresAt ?? DateTime.utc(2026, 11, 2, 13),
);

class _Executor implements AssistantActionExecutor {
  _Executor({this.fail = false});
  final bool fail;
  var revalidations = 0;
  var executions = 0;
  @override
  Future<void> revalidate(AssistantProposal proposal) async {
    revalidations++;
    if (fail) throw StateError('stale or forbidden');
  }

  @override
  Future<void> execute(AssistantProposal proposal) async => executions++;
}
