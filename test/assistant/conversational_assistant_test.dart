import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noyau_app/features/assistant/application/assistant_capabilities.dart';
import 'package:noyau_app/features/assistant/application/assistant_providers.dart';
import 'package:noyau_app/features/assistant/application/conversational_assistant.dart';
import 'package:noyau_app/features/assistant/domain/assistant_contract.dart';
import 'package:noyau_app/features/assistant/domain/conversation_contract.dart';
import 'package:noyau_app/features/assistant/infrastructure/edge_conversational_ai_provider.dart';

void main() {
  test('free question can compose several capabilities dynamically', () async {
    final capabilities = _Capabilities();
    final provider = _Provider(
      const AssistantConversationPlan(
        language: 'fr',
        capabilityIds: {
          'budget.summary',
          'wealth.explanation',
          'priorities.summary',
        },
        operationLevel: AssistantOperationLevel.recommend,
      ),
    );
    final answer =
        await AssistantConversationOrchestrator(
          provider: provider,
          capabilities: capabilities,
        ).answer(
          _request(
            'Puis-je acheter une voiture sans compromettre nos projets ?',
          ),
        );

    expect(capabilities.executed, {
      'budget.summary',
      'wealth.explanation',
      'priorities.summary',
    });
    expect(answer.capabilityIds, capabilities.executed);
    expect(answer.operationLevel, AssistantOperationLevel.recommend);
  });

  test('unknown capability from model is ignored before execution', () async {
    final capabilities = _Capabilities();
    final provider = _Provider(
      const AssistantConversationPlan(
        language: 'en',
        capabilityIds: {'budget.summary', 'read.every.private.account'},
        operationLevel: AssistantOperationLevel.read,
      ),
    );
    await AssistantConversationOrchestrator(
      provider: provider,
      capabilities: capabilities,
    ).answer(_request('What can I afford?'));
    expect(capabilities.executed, {'budget.summary'});
  });

  test(
    'capabilities are freshly executed on every conversational turn',
    () async {
      final capabilities = _Capabilities();
      final provider = _Provider(
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'budget.summary'},
          operationLevel: AssistantOperationLevel.read,
        ),
      );
      final orchestrator = AssistantConversationOrchestrator(
        provider: provider,
        capabilities: capabilities,
      );
      await orchestrator.answer(_request('Combien pouvons-nous épargner ?'));
      await orchestrator.answer(_request('Et avec 30 000 DH d’apport ?'));
      expect(capabilities.executionCount, 2);
    },
  );

  test('timeout fails closed and requests deterministic fallback', () async {
    final answer = await AssistantConversationOrchestrator(
      provider: _SlowProvider(),
      capabilities: _Capabilities(),
      timeout: const Duration(milliseconds: 5),
    ).answer(_request('Question libre'));
    expect(answer.status, AssistantConversationStatus.timeout);
    expect(answer.fallbackUsed, isTrue);
    expect(answer.text, isEmpty);
    expect(answer.failurePhase, AssistantFailurePhase.planning);
    expect(answer.failureCategory, AssistantProviderErrorCategory.timeout);
  });

  test(
    'provider failure matrix remains technical, never clarification',
    () async {
      for (final category in AssistantProviderErrorCategory.values) {
        final answer = await AssistantConversationOrchestrator(
          provider: _FailingProvider(
            phase: AssistantFailurePhase.planning,
            category: category,
          ),
          capabilities: _ScopedCapabilities(),
        ).answer(_request('Quel est mon budget global restant ?'));
        expect(answer.status, AssistantConversationStatus.providerUnavailable);
        expect(answer.text, isEmpty);
        expect(answer.failurePhase, AssistantFailurePhase.planning);
        expect(answer.failureCategory, category);
        expect(answer.capabilityIds, isEmpty);
      }
    },
  );

  test(
    'valid plan followed by synthesis failure is identified separately',
    () async {
      final answer = await AssistantConversationOrchestrator(
        provider: _FailingProvider(
          phase: AssistantFailurePhase.synthesis,
          category: AssistantProviderErrorCategory.serverError,
        ),
        capabilities: _ScopedCapabilities(),
      ).answer(_request('Quel est le budget global préparé ?'));
      expect(answer.status, AssistantConversationStatus.providerUnavailable);
      expect(answer.failurePhase, AssistantFailurePhase.synthesis);
      expect(
        answer.failureCategory,
        AssistantProviderErrorCategory.serverError,
      );
    },
  );

  test('mock provider retries empty content once then succeeds', () async {
    final provider = _RetryingScenarioProvider([
      const AssistantProviderException(
        phase: AssistantFailurePhase.planning,
        category: AssistantProviderErrorCategory.emptyContent,
      ),
      _explicitBudgetPlan,
    ]);
    final answer = await AssistantConversationOrchestrator(
      provider: provider,
      capabilities: _ScopedCapabilities(),
    ).answer(_request('Quel est le budget global préparé ?'));
    expect(provider.planAttempts, 2);
    expect(answer.status, AssistantConversationStatus.ready);
  });

  test('mock provider retries timeout once then succeeds', () async {
    final provider = _RetryingScenarioProvider([
      TimeoutException('provider timeout'),
      _explicitBudgetPlan,
    ]);
    final answer = await AssistantConversationOrchestrator(
      provider: provider,
      capabilities: _ScopedCapabilities(),
    ).answer(_request('Quel est le budget global préparé ?'));
    expect(provider.planAttempts, 2);
    expect(answer.status, AssistantConversationStatus.ready);
  });

  test('mock provider stops after two empty responses', () async {
    final provider = _RetryingScenarioProvider([
      const AssistantProviderException(
        phase: AssistantFailurePhase.planning,
        category: AssistantProviderErrorCategory.emptyContent,
      ),
      const AssistantProviderException(
        phase: AssistantFailurePhase.planning,
        category: AssistantProviderErrorCategory.emptyContent,
      ),
    ]);
    final answer = await AssistantConversationOrchestrator(
      provider: provider,
      capabilities: _ScopedCapabilities(),
    ).answer(_request('Quel est le budget global préparé ?'));
    expect(provider.planAttempts, 2);
    expect(answer.status, AssistantConversationStatus.providerUnavailable);
    expect(answer.failureCategory, AssistantProviderErrorCategory.emptyContent);
  });

  test('edge provider accepts multilingual and code-switched plans', () async {
    const samples = <String, String>{
      'wach n9der nchri tomobil had l3am?': 'ary-Latn',
      'Can I afford the car sans compromettre notre épargne?': 'mixed-en-fr',
      '¿Cuánto podemos ahorrar este mes?': 'es',
      'Wie viel können wir sparen?': 'de',
      'Quanto possiamo risparmiare?': 'it',
      'واش نقدر نشري طوموبيل؟': 'ary',
    };
    for (final entry in samples.entries) {
      final gateway = _Gateway([
        {
          'language': entry.value,
          'capability_ids': ['budget.summary'],
          'operation_level': 'read',
        },
      ]);
      final plan = await EdgeConversationalAIProvider(gateway).plan(
        request: _request(entry.key),
        availableCapabilities: _Capabilities().descriptors,
      );
      expect(plan.language, entry.value, reason: entry.key);
    }
  });

  test('edge planner exposes a clarification without selecting data', () async {
    final gateway = _Gateway([
      {
        'language': 'fr',
        'capability_ids': <String>[],
        'operation_level': 'read',
        'needs_clarification': true,
        'clarification_question': 'Quel périmètre souhaitez-vous consulter ?',
      },
    ]);
    final plan = await EdgeConversationalAIProvider(gateway).plan(
      request: _request('Combien puis-je dépenser ?'),
      availableCapabilities: _Capabilities().descriptors,
    );
    expect(plan.needsClarification, isTrue);
    expect(plan.capabilityIds, isEmpty);
    expect(plan.clarificationQuestion, contains('périmètre'));
  });

  test(
    'edge provider sends only user-authored history back to model',
    () async {
      final gateway = _Gateway([
        {
          'language': 'fr',
          'capability_ids': <String>[],
          'operation_level': 'read',
        },
      ]);
      await EdgeConversationalAIProvider(gateway).plan(
        request: AssistantConversationRequest(
          question: 'Et maintenant ?',
          userId: 'u',
          householdId: 'h',
          uiLocale: 'fr',
          history: [
            _message('user', 'Première question'),
            _message('assistant', 'Ancienne réponse avec un montant révoqué'),
          ],
        ),
        availableCapabilities: _Capabilities().descriptors,
      );
      final history = gateway.requests.single['history'] as List<dynamic>;
      expect(history, hasLength(1));
      expect((history.single as Map)['role'], 'user');
      expect('$history', isNot(contains('montant révoqué')));
    },
  );

  test(
    'edge provider accepts only allowlisted low-risk navigation proposals',
    () async {
      final gateway = _Gateway([
        {
          'text': 'Review the canonical workflow.',
          'language': 'en',
          'provider': 'fake',
          'model': 'fake-v1',
          'navigations': [
            {'type': 'financial_event', 'target': 'transfer'},
            {'type': 'navigate', 'target': 'budget'},
          ],
        },
      ]);
      final answer = await EdgeConversationalAIProvider(gateway).respond(
        request: _request('Move 2000 to savings'),
        plan: const AssistantConversationPlan(
          language: 'en',
          capabilityIds: {'budget.summary'},
          operationLevel: AssistantOperationLevel.execute,
        ),
        authorizedResults: const [],
      );
      expect(answer.navigations, hasLength(1));
      expect(answer.navigations.single.target, 'budget');
      expect(answer.proposals, isEmpty);
    },
  );

  test(
    'budget unavailable is explicit and never becomes numeric zero',
    () async {
      final container = ProviderContainer(
        overrides: [
          assistantContextBuilderProvider.overrideWithValue(
            const _ContextBuilder(visibleFacts: {}, budgetAvailable: false),
          ),
        ],
      );
      addTearDown(container.dispose);
      final result =
          (await container.read(assistantCapabilityExecutorProvider).execute({
            'budget.summary',
          })).single;
      expect(result.facts, isNot(contains('budget_remaining_minor')));
      expect(result.facts['availability'], 'unavailable');
      expect(result.unavailableReason, 'budget_not_prepared_or_unavailable');
    },
  );

  test('empty synthesis is a governed provider failure', () async {
    final provider = EdgeConversationalAIProvider(
      _Gateway([
        {
          'text': '   ',
          'language': 'fr',
          'provider': 'fake',
          'model': 'fake-v1',
        },
      ]),
    );
    await expectLater(
      provider.respond(
        request: _request('Question'),
        plan: _explicitBudgetPlan,
        authorizedResults: const [],
      ),
      throwsA(
        isA<AssistantProviderException>()
            .having(
              (error) => error.phase,
              'phase',
              AssistantFailurePhase.synthesis,
            )
            .having(
              (error) => error.category,
              'category',
              AssistantProviderErrorCategory.emptyContent,
            ),
      ),
    );
  });

  test('a real calculated zero remains an available zero', () async {
    final container = ProviderContainer(
      overrides: [
        assistantContextBuilderProvider.overrideWithValue(
          const _ContextBuilder(
            visibleFacts: {'budget_remaining_minor': 0},
            budgetAvailable: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final result =
        (await container.read(assistantCapabilityExecutorProvider).execute({
          'budget.summary',
        })).single;
    expect(result.facts['budget_remaining_minor'], 0);
    expect(result.facts['availability'], 'available');
    expect(result.unavailableReason, isNull);
  });

  test('generated output may state zero only when zero is canonical', () async {
    final answer = await _respondWith(
      text: 'Le restant canonique est à 0.',
      facts: const {'budget_remaining_minor': 0},
    );
    expect(answer.text, contains('0'));
  });

  test(
    'authorized amount and canonical currency pass output validation',
    () async {
      final answer = await _respondWith(
        text: 'Le montant disponible est de 125 USD.',
        facts: const {'budget_remaining_minor': 12500, 'currency_code': 'USD'},
      );
      expect(answer.text, contains('125 USD'));
    },
  );

  test('missing currency cannot be invented by generated output', () async {
    await expectLater(
      _respondWith(
        text: 'Le montant disponible est de 125 €.',
        facts: const {'budget_remaining_minor': 12500},
      ),
      throwsFormatException,
    );
  });

  test('a different currency cannot replace the canonical currency', () async {
    await expectLater(
      _respondWith(
        text: 'Le montant disponible est de 125 EUR.',
        facts: const {'budget_remaining_minor': 12500, 'currency_code': 'USD'},
      ),
      throwsFormatException,
    );
  });

  test('unavailable or private monetary data cannot become zero', () async {
    await expectLater(
      _respondWith(
        text: 'Le montant disponible est de 0 EUR.',
        facts: const {
          'availability': 'unavailable',
          'privacy_notice': 'hidden_financial_data_excluded',
        },
        unavailableReason: 'budget_not_prepared_or_unavailable',
      ),
      throwsFormatException,
    );
  });

  test('generated output cannot introduce an absent monetary amount', () async {
    await expectLater(
      _respondWith(
        text: 'Le montant disponible est de 500.',
        facts: const {'budget_remaining_minor': 12500},
      ),
      throwsFormatException,
    );
  });

  test('multi-capability counts cannot be repurposed as money', () async {
    final provider = EdgeConversationalAIProvider(
      _Gateway([
        {
          'text': 'Le budget disponible est de 3 MAD.',
          'language': 'fr',
          'provider': 'fake',
          'model': 'fake-v1',
        },
      ]),
    );
    await expectLater(
      provider.respond(
        request: _request('Résumé'),
        plan: const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'budget.summary', 'alerts.summary'},
          operationLevel: AssistantOperationLevel.read,
        ),
        authorizedResults: [
          AuthorizedCapabilityResult(
            capabilityId: 'budget.summary',
            generatedAt: DateTime.utc(2026, 11, 21),
            facts: const {
              'budget_remaining_minor': 10000,
              'currency_code': 'MAD',
            },
            sourceCategories: const {'budget_summary'},
          ),
          AuthorizedCapabilityResult(
            capabilityId: 'alerts.summary',
            generatedAt: DateTime.utc(2026, 11, 21),
            facts: const {'alert_count': 3},
            sourceCategories: const {'authorized_alerts'},
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test(
    'authorized Cycle date may be repeated exactly without intimate data',
    () async {
      final provider = EdgeConversationalAIProvider(
        _Gateway([
          {
            'text': 'La phase partagée commence le 2026-11-25.',
            'language': 'fr',
            'provider': 'fake',
            'model': 'fake-v1',
          },
        ]),
      );
      final answer = await provider.respond(
        request: _request('Quelle est la prochaine phase partagée ?'),
        plan: const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'cycle.authorized_projection'},
          operationLevel: AssistantOperationLevel.read,
        ),
        authorizedResults: [
          AuthorizedCapabilityResult(
            capabilityId: 'cycle.authorized_projection',
            generatedAt: DateTime.utc(2026, 11, 21),
            facts: const {
              'authorized_shared_events': [
                {'starts_on': '2026-11-25', 'phase': 'period'},
              ],
            },
            sourceCategories: const {'authorized_cycle_dates_phases'},
          ),
        ],
      );
      expect(answer.text, contains('2026-11-25'));
    },
  );

  test('unavailable monetary data cannot be phrased as textual zero', () async {
    await expectLater(
      _respondWith(
        text: 'Il ne reste plus de budget, le montant est zéro.',
        facts: const {'availability': 'unavailable'},
        unavailableReason: 'budget_not_prepared_or_unavailable',
      ),
      throwsFormatException,
    );
  });

  test('precise financial question executes its selected capability', () async {
    final capabilities = _Capabilities();
    final provider = _RecordingProvider([
      const AssistantConversationPlan(
        language: 'fr',
        capabilityIds: {'budget.summary'},
        operationLevel: AssistantOperationLevel.read,
        scopeBasis: AssistantScopeBasis.explicitContext,
        scopeEvidence: 'budget global préparé',
      ),
    ]);
    final answer = await AssistantConversationOrchestrator(
      provider: provider,
      capabilities: capabilities,
    ).answer(_request('Quel est le restant du budget global préparé ?'));
    expect(capabilities.executionCount, 1);
    expect(answer.text, 'Structured answer');
  });

  test(
    'ambiguous financial question clarifies before retrieving data',
    () async {
      final capabilities = _ScopedCapabilities();
      final provider = _RecordingProvider([
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'budget.summary'},
          operationLevel: AssistantOperationLevel.read,
        ),
      ]);
      final answer = await AssistantConversationOrchestrator(
        provider: provider,
        capabilities: capabilities,
      ).answer(_request('Combien puis-je encore dépenser ?'));
      expect(answer.text, contains('périmètre financier'));
      expect(capabilities.executionCount, 0);
      expect(provider.respondCount, 0);
    },
  );

  test('broad question may use a reliable canonical aggregate', () async {
    final capabilities = _ScopedCapabilities();
    final provider = _RecordingProvider([
      const AssistantConversationPlan(
        language: 'fr',
        capabilityIds: {'month.summary'},
        operationLevel: AssistantOperationLevel.read,
        scopeBasis: AssistantScopeBasis.canonicalGlobalAggregate,
      ),
    ]);
    await AssistantConversationOrchestrator(
      provider: provider,
      capabilities: capabilities,
    ).answer(_request('Donne-moi la situation budgétaire globale du mois.'));
    expect(capabilities.executed, {'month.summary'});
  });

  test('explicit multi-scope request composes several capabilities', () async {
    final capabilities = _ScopedCapabilities();
    final provider = _RecordingProvider([
      const AssistantConversationPlan(
        language: 'fr',
        capabilityIds: {'budget.summary', 'shopping.availability'},
        operationLevel: AssistantOperationLevel.recommend,
        scopeBasis: AssistantScopeBasis.explicitContext,
        scopeEvidence: 'budget global préparé et capacité d’achat',
      ),
    ]);
    final answer =
        await AssistantConversationOrchestrator(
          provider: provider,
          capabilities: capabilities,
        ).answer(
          _request(
            'Compare mon budget global préparé et capacité d’achat autorisée.',
          ),
        );
    expect(capabilities.executed, {'budget.summary', 'shopping.availability'});
    expect(answer.operationLevel, AssistantOperationLevel.recommend);
  });

  test(
    'incoherent global scope is clarified without capability execution',
    () async {
      final capabilities = _ScopedCapabilities();
      final provider = _RecordingProvider([
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'budget.summary'},
          operationLevel: AssistantOperationLevel.read,
          scopeBasis: AssistantScopeBasis.canonicalGlobalAggregate,
        ),
      ]);
      final answer = await AssistantConversationOrchestrator(
        provider: provider,
        capabilities: capabilities,
      ).answer(_request('Donne-moi une vue globale.'));
      expect(answer.text, contains('périmètre financier'));
      expect(capabilities.executionCount, 0);
      expect(provider.respondCount, 0);
    },
  );

  test(
    'clarification answer resumes original request and revalidates access',
    () async {
      final capabilities = _ScopedCapabilities();
      final provider = _RecordingProvider([
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {},
          operationLevel: AssistantOperationLevel.read,
          needsClarification: true,
          clarificationQuestion: 'Quel périmètre ?',
        ),
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'budget.summary'},
          operationLevel: AssistantOperationLevel.read,
          scopeBasis: AssistantScopeBasis.explicitContext,
          scopeEvidence: 'budget global',
        ),
      ]);
      final orchestrator = AssistantConversationOrchestrator(
        provider: provider,
        capabilities: capabilities,
      );
      await orchestrator.answer(_request('Combien puis-je dépenser ?'));
      expect(capabilities.executionCount, 0);
      await orchestrator.answer(
        AssistantConversationRequest(
          question: 'Le budget global.',
          userId: 'u',
          householdId: 'h',
          uiLocale: 'fr',
          history: [_message('user', 'Combien puis-je dépenser ?')],
        ),
      );
      expect(capabilities.executionCount, 1);
      expect(
        provider.planRequests.last.history.single.content,
        contains('Combien'),
      );
    },
  );

  test(
    'all unavailable capabilities return a safe answer without synthesis',
    () async {
      final provider = _RecordingProvider([
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {'budget.summary'},
          operationLevel: AssistantOperationLevel.read,
          scopeBasis: AssistantScopeBasis.explicitContext,
          scopeEvidence: 'montant disponible',
        ),
      ]);
      final answer = await AssistantConversationOrchestrator(
        provider: provider,
        capabilities: _UnavailableCapabilities(),
      ).answer(_request('Quel est le montant disponible ?'));
      expect(answer.text, contains('montant fiable'));
      expect(answer.text, isNot(contains('0')));
      expect(provider.respondCount, 0);
    },
  );

  test(
    'different materially ambiguous scopes also clarify generically',
    () async {
      for (final capabilities in const [
        {'priorities.summary', 'organization.tasks'},
        {'budget.summary', 'shopping.availability'},
        {'month.summary', 'alerts.summary'},
      ]) {
        final executor = _ScopedCapabilities();
        final provider = _RecordingProvider([
          AssistantConversationPlan(
            language: 'fr',
            capabilityIds: capabilities,
            operationLevel: AssistantOperationLevel.read,
          ),
        ]);
        final answer = await AssistantConversationOrchestrator(
          provider: provider,
          capabilities: executor,
        ).answer(_request('Donnez-moi une réponse sur ce sujet.'));
        expect(answer.text, contains('périmètre financier'));
        expect(executor.executionCount, 0);
      }
    },
  );

  test(
    'revoked permission is re-evaluated between conversational turns',
    () async {
      final capabilities = _RevocableCapabilities();
      final provider = _RecordingProvider([
        _explicitBudgetPlan,
        _explicitBudgetPlan,
      ]);
      final orchestrator = AssistantConversationOrchestrator(
        provider: provider,
        capabilities: capabilities,
      );
      final first = await orchestrator.answer(
        _request('Quel est le budget global préparé ?'),
      );
      expect(first.text, 'Structured answer');
      capabilities.authorized = false;
      final second = await orchestrator.answer(
        AssistantConversationRequest(
          question: 'Quel est le budget global préparé maintenant ?',
          userId: 'u',
          householdId: 'h',
          uiLocale: 'fr',
          history: [_message('user', 'Quel est le budget global préparé ?')],
        ),
      );
      expect(second.text, contains('montant fiable'));
      expect(provider.respondCount, 1);
      expect(capabilities.executionCount, 2);
    },
  );
}

const _explicitBudgetPlan = AssistantConversationPlan(
  language: 'fr',
  capabilityIds: {'budget.summary'},
  operationLevel: AssistantOperationLevel.read,
  scopeBasis: AssistantScopeBasis.explicitContext,
  scopeEvidence: 'budget global préparé',
);

Future<AssistantConversationAnswer> _respondWith({
  required String text,
  required Map<String, Object?> facts,
  String? unavailableReason,
}) =>
    EdgeConversationalAIProvider(
      _Gateway([
        {
          'text': text,
          'language': 'fr',
          'provider': 'fake',
          'model': 'fake-v1',
        },
      ]),
    ).respond(
      request: _request('Question neutre'),
      plan: const AssistantConversationPlan(
        language: 'fr',
        capabilityIds: {'budget.summary'},
        operationLevel: AssistantOperationLevel.read,
      ),
      authorizedResults: [
        AuthorizedCapabilityResult(
          capabilityId: 'budget.summary',
          generatedAt: DateTime.utc(2026, 11, 21),
          facts: facts,
          sourceCategories: const {'budget_summary'},
          unavailableReason: unavailableReason,
        ),
      ],
    );

AssistantConversationRequest _request(String question) =>
    AssistantConversationRequest(
      question: question,
      userId: 'u',
      householdId: 'h',
      uiLocale: 'fr',
      history: const [],
    );

AssistantConversationMessage _message(String role, String content) =>
    AssistantConversationMessage(
      id: '$role-1',
      role: role,
      content: content,
      createdAt: DateTime.utc(2026, 11, 21),
    );

class _Capabilities implements AssistantCapabilityExecutor {
  Set<String> executed = {};
  var executionCount = 0;
  @override
  List<AssistantCapabilityDescriptor> get descriptors => const [
    AssistantCapabilityDescriptor(
      id: 'budget.summary',
      description: 'budget',
      operationLevel: AssistantOperationLevel.read,
    ),
    AssistantCapabilityDescriptor(
      id: 'wealth.explanation',
      description: 'wealth',
      operationLevel: AssistantOperationLevel.read,
    ),
    AssistantCapabilityDescriptor(
      id: 'priorities.summary',
      description: 'priorities',
      operationLevel: AssistantOperationLevel.read,
    ),
  ];

  @override
  Future<List<AuthorizedCapabilityResult>> execute(Set<String> ids) async {
    executionCount++;
    executed = ids;
    return [
      for (final id in ids)
        AuthorizedCapabilityResult(
          capabilityId: id,
          generatedAt: DateTime.utc(2026, 11, 21),
          facts: const {'available': true},
          sourceCategories: {id},
        ),
    ];
  }
}

class _ScopedCapabilities extends _Capabilities {
  @override
  List<AssistantCapabilityDescriptor> get descriptors => const [
    AssistantCapabilityDescriptor(
      id: 'budget.summary',
      description: 'budget',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Prepared global monthly budget remainder only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'month.summary',
      description: 'month overview',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Global month overview.',
      allowsImplicitGlobalResolution: true,
    ),
    AssistantCapabilityDescriptor(
      id: 'alerts.summary',
      description: 'alerts',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Alerts only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'priorities.summary',
      description: 'priorities',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Priorities only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'organization.tasks',
      description: 'tasks',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Household tasks only.',
    ),
    AssistantCapabilityDescriptor(
      id: 'shopping.availability',
      description: 'affordability',
      operationLevel: AssistantOperationLevel.recommend,
      semanticScope: 'Purchase affordability only.',
    ),
  ];
}

class _Provider implements ConversationalAIProvider {
  _Provider(this.nextPlan);
  final AssistantConversationPlan nextPlan;
  @override
  String get providerId => 'fake';
  @override
  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  }) async => nextPlan;
  @override
  Future<AssistantConversationAnswer> respond({
    required AssistantConversationRequest request,
    required AssistantConversationPlan plan,
    required List<AuthorizedCapabilityResult> authorizedResults,
  }) async => AssistantConversationAnswer(
    text: 'Structured answer',
    language: plan.language,
    status: AssistantConversationStatus.ready,
    provider: providerId,
    model: 'fake-v1',
    capabilityIds: plan.capabilityIds,
    sourceCategories: {
      for (final result in authorizedResults) ...result.sourceCategories,
    },
    operationLevel: plan.operationLevel,
    duration: const Duration(milliseconds: 1),
  );
}

class _SlowProvider extends _Provider {
  _SlowProvider()
    : super(
        const AssistantConversationPlan(
          language: 'fr',
          capabilityIds: {},
          operationLevel: AssistantOperationLevel.read,
        ),
      );
  @override
  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  }) => Completer<AssistantConversationPlan>().future;
}

class _FailingProvider extends _Provider {
  _FailingProvider({required this.phase, required this.category})
    : super(_explicitBudgetPlan);

  final AssistantFailurePhase phase;
  final AssistantProviderErrorCategory category;

  @override
  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  }) async {
    if (phase == AssistantFailurePhase.planning) {
      throw AssistantProviderException(phase: phase, category: category);
    }
    return _explicitBudgetPlan;
  }

  @override
  Future<AssistantConversationAnswer> respond({
    required AssistantConversationRequest request,
    required AssistantConversationPlan plan,
    required List<AuthorizedCapabilityResult> authorizedResults,
  }) async =>
      throw AssistantProviderException(phase: phase, category: category);
}

class _RetryingScenarioProvider extends _Provider {
  _RetryingScenarioProvider(this.outcomes) : super(_explicitBudgetPlan);

  final List<Object> outcomes;
  var planAttempts = 0;

  @override
  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  }) async {
    Object? lastFailure;
    for (var attempt = 0; attempt < 2; attempt++) {
      planAttempts++;
      final outcome = outcomes.removeAt(0);
      if (outcome is AssistantConversationPlan) return outcome;
      lastFailure = outcome;
      if (outcome is! AssistantProviderException &&
          outcome is! TimeoutException) {
        throw outcome;
      }
    }
    if (lastFailure is AssistantProviderException) throw lastFailure;
    if (lastFailure is TimeoutException) throw lastFailure;
    throw StateError('unexpected scenario');
  }
}

class _RecordingProvider implements ConversationalAIProvider {
  _RecordingProvider(this.plans);
  final List<AssistantConversationPlan> plans;
  final planRequests = <AssistantConversationRequest>[];
  var respondCount = 0;

  @override
  String get providerId => 'recording';

  @override
  Future<AssistantConversationPlan> plan({
    required AssistantConversationRequest request,
    required List<AssistantCapabilityDescriptor> availableCapabilities,
  }) async {
    planRequests.add(request);
    return plans.removeAt(0);
  }

  @override
  Future<AssistantConversationAnswer> respond({
    required AssistantConversationRequest request,
    required AssistantConversationPlan plan,
    required List<AuthorizedCapabilityResult> authorizedResults,
  }) async {
    respondCount++;
    return AssistantConversationAnswer(
      text: 'Structured answer',
      language: plan.language,
      status: AssistantConversationStatus.ready,
      provider: providerId,
      model: 'fake-v1',
      capabilityIds: plan.capabilityIds,
      sourceCategories: {
        for (final result in authorizedResults) ...result.sourceCategories,
      },
      operationLevel: plan.operationLevel,
      duration: const Duration(milliseconds: 1),
    );
  }
}

class _UnavailableCapabilities implements AssistantCapabilityExecutor {
  @override
  List<AssistantCapabilityDescriptor> get descriptors => const [
    AssistantCapabilityDescriptor(
      id: 'budget.summary',
      description: 'budget',
      operationLevel: AssistantOperationLevel.read,
      semanticScope: 'Prepared global monthly budget remainder only.',
    ),
  ];

  @override
  Future<List<AuthorizedCapabilityResult>> execute(Set<String> ids) async => [
    AuthorizedCapabilityResult(
      capabilityId: 'budget.summary',
      generatedAt: DateTime.utc(2026, 11, 21),
      facts: const {'availability': 'unavailable'},
      sourceCategories: const {'budget_summary'},
      unavailableReason: 'budget_not_prepared_or_unavailable',
    ),
  ];
}

class _RevocableCapabilities extends _ScopedCapabilities {
  bool authorized = true;

  @override
  Future<List<AuthorizedCapabilityResult>> execute(Set<String> ids) async {
    executionCount++;
    executed = ids;
    return [
      AuthorizedCapabilityResult(
        capabilityId: 'budget.summary',
        generatedAt: DateTime.utc(2026, 11, 21),
        facts: authorized
            ? const {
                'availability': 'available',
                'budget_remaining_minor': 100,
                'currency_code': 'MAD',
              }
            : const {'availability': 'unauthorized'},
        sourceCategories: const {'budget_summary'},
        unavailableReason: authorized ? null : 'authorization_revoked',
      ),
    ];
  }
}

class _ContextBuilder implements AssistantContextBuilder {
  const _ContextBuilder({
    required this.visibleFacts,
    required this.budgetAvailable,
  });

  final Map<String, num> visibleFacts;
  final bool budgetAvailable;

  @override
  Future<AuthorizedAssistantContext> build(AssistantUseCase useCase) async =>
      AuthorizedAssistantContext(
        userId: 'u',
        householdId: 'h',
        useCase: useCase,
        generatedAt: DateTime.utc(2026, 11, 21),
        visibleFacts: visibleFacts,
        flags: {'budget_summary_available': budgetAvailable},
        sourceCategories: const {'budget_summary'},
      );
}

class _Gateway implements AssistantFunctionGateway {
  _Gateway(this.responses);
  final List<Map<String, Object?>> responses;
  final requests = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> body) async {
    requests.add(body);
    return responses.removeAt(0);
  }
}
